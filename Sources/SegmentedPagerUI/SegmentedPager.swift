//
//  SegmentedPager.swift
//  SegmentedPager
//
//  Created by yousanflics on 7/1/26.
//
//  Public SwiftUI entry point. Wraps the UIKit PagerContainerViewController
//  and hosts each page in its own UIHostingController, so pages stay
//  alive across tab switches (scroll positions and @State survive, .task
//  runs once) and gesture arbitration is native nested-scroll behavior.
//
//  Bar modes:
//  - .fixed  — header and bar are ordinary SwiftUI siblings above the
//              paging area.
//  - .pinned — header and bar are UIKit-hosted chrome coordinated by
//              PagerStickyCoordinator: the header scrolls away with the
//              active page (it is reparented INTO the page's scroll view
//              while scrolling vertically) and the bar pins at the top.
//
//  Environment bridging: pages, header and bar live in separate
//  hosting controllers, so SwiftUI Environment does NOT flow into them
//  automatically. The pager captures the full `EnvironmentValues` at its
//  own position in the hierarchy and re-injects it into every hosted
//  root (with pager-scoped keys layered on top).
//
//  Body invalidation is deliberately decoupled: per-frame progress ticks
//  flow through the observable host model and re-evaluate only the views
//  that read `PagerBarContext.progress`, never the pager body or the page
//  roots. With `.pagerContentKey`, a re-run of the pager body (a selection
//  write, a store update the pages observe themselves) refreshes the
//  closures and the bridged environment without notifying the hosted
//  roots; only `tabs`, `selection`, the key and a change of the
//  environment's observable traits do. Without a key every update still
//  re-evaluates the roots, since a closure may have captured a changed
//  input the pager cannot see.
//

#if canImport(UIKit)
import SegmentedPagerCore
import SwiftUI
import UIKit

public struct SegmentedPager<Tab: Hashable, Header: View, Bar: View, Page: View>: View {
    private let tabs: [Tab]
    @Binding private var selection: Tab
    private let header: () -> Header
    private let bar: (PagerBarContext<Tab>) -> Bar
    private let page: (Tab) -> Page

    @State private var model = PagerHostModel<Tab, Header, Bar, Page>()
    @Environment(\.self) private var environmentValues
    @Environment(\.pagerBarMode) private var barMode
    @Environment(\.pagerPreloadPolicy) private var preloadPolicy
    @Environment(\.pagerSwipeEnabled) private var isSwipeEnabled
    @Environment(\.pagerBarBackground) private var barBackground
    @Environment(\.pagerPinProgressAction) private var pinProgressAction
    @Environment(\.pagerContentKey) private var contentKey

    public init(
        tabs: [Tab],
        selection: Binding<Tab>,
        @ViewBuilder header: @escaping () -> Header,
        @ViewBuilder bar: @escaping (PagerBarContext<Tab>) -> Bar,
        @ViewBuilder page: @escaping (Tab) -> Page
    ) {
        self.tabs = tabs
        _selection = selection
        self.header = header
        self.bar = bar
        self.page = page
    }

    public var body: some View {
        switch barMode {
        case .fixed:
            VStack(spacing: 0) {
                header()

                PagerFixedBarHost(
                    model: model,
                    tabs: tabs,
                    selection: selection,
                    bar: bar,
                    select: { tab in
                        if let select = model.select {
                            select(tab)
                        } else {
                            selection = tab
                        }
                    }
                )
                    .background {
                        if let barBackground {
                            Rectangle()
                                .fill(barBackground)
                                .ignoresSafeArea(edges: .horizontal)
                        }
                    }

                representable(usesChrome: false)
            }
        case .pinned:
            representable(usesChrome: true)
        }
    }

    private func representable(usesChrome: Bool) -> some View {
        PagerRepresentable(
            tabs: tabs,
            selection: $selection,
            model: model,
            header: header,
            bar: bar,
            page: page,
            environment: environmentValues,
            preloadPolicy: preloadPolicy,
            isSwipeEnabled: isSwipeEnabled,
            barBackground: barBackground,
            contentKey: contentKey,
            usesChrome: usesChrome,
            pinProgressAction: pinProgressAction
        )
    }
}

// MARK: - Convenience initializers

extension SegmentedPager where Header == EmptyView {
    public init(
        tabs: [Tab],
        selection: Binding<Tab>,
        @ViewBuilder bar: @escaping (PagerBarContext<Tab>) -> Bar,
        @ViewBuilder page: @escaping (Tab) -> Page
    ) {
        self.init(
            tabs: tabs,
            selection: selection,
            header: { EmptyView() },
            bar: bar,
            page: page
        )
    }
}

extension SegmentedPager where Bar == DefaultPagerBar<Tab> {
    public init(
        tabs: [Tab],
        selection: Binding<Tab>,
        title: @escaping (Tab) -> String,
        @ViewBuilder header: @escaping () -> Header,
        @ViewBuilder page: @escaping (Tab) -> Page
    ) {
        self.init(
            tabs: tabs,
            selection: selection,
            header: header,
            bar: { context in DefaultPagerBar(context: context, title: title) },
            page: page
        )
    }
}

extension SegmentedPager where Header == EmptyView, Bar == DefaultPagerBar<Tab> {
    public init(
        tabs: [Tab],
        selection: Binding<Tab>,
        title: @escaping (Tab) -> String,
        @ViewBuilder page: @escaping (Tab) -> Page
    ) {
        self.init(
            tabs: tabs,
            selection: selection,
            title: title,
            header: { EmptyView() },
            page: page
        )
    }
}

// MARK: - Host model

/// Observable state shared between the SwiftUI shell and every hosted
/// root (pages, header, bar). Fine-grained observation keeps
/// invalidation scoped: the bar host reads `tabs`/`selection`, the
/// indicator reads `progress`; page roots read `tabs`, `chromeTopInset`
/// and `contentVersion`.
///
/// The closures, the bridged environment and the bar background are
/// deliberately NOT observed. None of them is comparable, so observing
/// them meant every `updateUIViewController` (every selection write,
/// every store update the host re-ran for) re-evaluated and laid out all
/// live page hosting controllers plus the chrome: five to seven
/// `UIHostingController` passes per tab tap in the airport detail. They
/// are refreshed on every push; `contentVersion` decides when the roots
/// re-evaluate (see `update(environment:contentKey:)`).
@MainActor
@Observable
final class PagerHostModel<Tab: Hashable, Header: View, Bar: View, Page: View> {
    var tabs: [Tab] = []
    var selection: Tab?
    var progress = PageProgress.resting(at: 0)
    var chromeTopInset: CGFloat = 0
    /// Bumped on every push unless the host supplies a content key, and
    /// with one only when that key or the bridged environment's observable
    /// traits (colour scheme, dynamic type, size classes, locale,
    /// accessibility settings, …) change. Every hosted root reads it.
    private(set) var contentVersion = 0

    @ObservationIgnored var page: ((Tab) -> Page)?
    @ObservationIgnored var header: (() -> Header)?
    @ObservationIgnored var bar: ((PagerBarContext<Tab>) -> Bar)?
    @ObservationIgnored private(set) var environment = EnvironmentValues()
    @ObservationIgnored var barBackground: AnyShapeStyle?
    @ObservationIgnored private var environmentSignature: PagerEnvironmentSignature?
    @ObservationIgnored private var contentKey: AnyHashable?
    @ObservationIgnored var handles: [Int: PagerPageHandle] = [:]
    @ObservationIgnored var select: ((Tab) -> Void)?

    // Shadow copies for the push path. `updateUIViewController` runs under
    // SwiftUI's access tracking, so READING an observable property there
    // (even to compare it) subscribes the host hierarchy to it, and the
    // write that follows re-runs the host, which pushes again: an infinite
    // layout loop. The push path only ever writes observable state and
    // compares against these.
    @ObservationIgnored private var pushedTabs: [Tab] = []
    @ObservationIgnored private var pushedSelection: Tab?
    @ObservationIgnored private var pushedVersion = 0

    func push(tabs: [Tab], selection: Tab) {
        if pushedTabs != tabs {
            pushedTabs = tabs
            self.tabs = tabs
        }
        if pushedSelection != selection {
            pushedSelection = selection
            self.selection = selection
        }
    }

    func settle(selectionAt index: Int) {
        guard pushedTabs.indices.contains(index) else { return }
        let settled = pushedTabs[index]
        guard pushedSelection != settled else { return }
        pushedSelection = settled
        selection = settled
    }

    /// Without a key the pager cannot tell whether a closure captured a
    /// changed input, so every push re-evaluates the roots as it always
    /// did. With a key the host vouches that its pages observe their own
    /// inputs, and the roots re-evaluate only when the key or an
    /// observable environment trait changes.
    func update(environment: EnvironmentValues, contentKey: AnyHashable?) {
        self.environment = environment
        let signature = PagerEnvironmentSignature(environment)
        let environmentChanged = signature != environmentSignature
        environmentSignature = signature
        let keyChanged = contentKey != self.contentKey
        self.contentKey = contentKey
        guard contentKey == nil || keyChanged || environmentChanged else { return }
        pushedVersion &+= 1
        contentVersion = pushedVersion
    }

    func pageContent(at index: Int) -> Page? {
        guard tabs.indices.contains(index), let page else { return nil }
        return page(tabs[index])
    }

    func barContext() -> PagerBarContext<Tab>? {
        guard let selection, !tabs.isEmpty else { return nil }
        let select = select
        return PagerBarContext(
            tabs: tabs,
            selection: selection,
            progressProvider: { [weak self] in self?.progress ?? .resting(at: 0) },
            select: { tab in select?(tab) }
        )
    }
}

/// The environment traits whose change must re-evaluate the hosted
/// roots. `EnvironmentValues` itself is not comparable; this is the
/// comparable projection the host model keys `contentVersion` on.
struct PagerEnvironmentSignature: Equatable {
    let colorScheme: ColorScheme
    let colorSchemeContrast: ColorSchemeContrast
    let dynamicTypeSize: DynamicTypeSize
    let horizontalSizeClass: UserInterfaceSizeClass?
    let verticalSizeClass: UserInterfaceSizeClass?
    let layoutDirection: LayoutDirection
    let locale: Locale
    let calendar: Calendar
    let timeZone: TimeZone
    let isEnabled: Bool
    let controlSize: ControlSize
    let displayScale: CGFloat
    let legibilityWeight: LegibilityWeight?
    let accessibilityReduceMotion: Bool
    let accessibilityReduceTransparency: Bool
    let accessibilityDifferentiateWithoutColor: Bool
    let accessibilityInvertColors: Bool
    let accessibilityEnabled: Bool
    let redactionReasons: RedactionReasons
    let isLuminanceReduced: Bool
    let scenePhase: ScenePhase

    init(_ environment: EnvironmentValues) {
        colorScheme = environment.colorScheme
        colorSchemeContrast = environment.colorSchemeContrast
        dynamicTypeSize = environment.dynamicTypeSize
        horizontalSizeClass = environment.horizontalSizeClass
        verticalSizeClass = environment.verticalSizeClass
        layoutDirection = environment.layoutDirection
        locale = environment.locale
        calendar = environment.calendar
        timeZone = environment.timeZone
        isEnabled = environment.isEnabled
        controlSize = environment.controlSize
        displayScale = environment.displayScale
        legibilityWeight = environment.legibilityWeight
        accessibilityReduceMotion = environment.accessibilityReduceMotion
        accessibilityReduceTransparency = environment.accessibilityReduceTransparency
        accessibilityDifferentiateWithoutColor = environment.accessibilityDifferentiateWithoutColor
        accessibilityInvertColors = environment.accessibilityInvertColors
        accessibilityEnabled = environment.accessibilityEnabled
        redactionReasons = environment.redactionReasons
        isLuminanceReduced = environment.isLuminanceReduced
        scenePhase = environment.scenePhase
    }
}

// MARK: - Bar hosts

/// Fixed mode: tabs/selection/bar come straight from the pager body (so
/// the bar renders on the very first frame); the per-frame `progress` is
/// read from the model lazily, by whichever bar subview reads it.
struct PagerFixedBarHost<Tab: Hashable, Header: View, Bar: View, Page: View>: View {
    let model: PagerHostModel<Tab, Header, Bar, Page>
    let tabs: [Tab]
    let selection: Tab
    let bar: (PagerBarContext<Tab>) -> Bar
    let select: (Tab) -> Void

    var body: some View {
        bar(
            PagerBarContext(
                tabs: tabs,
                selection: selection,
                progressProvider: { [model] in model.progress },
                select: select
            )
        )
    }
}

/// Pinned chrome: everything comes from the observable model, since the
/// hosted bar has no SwiftUI parent pushing values in.
struct PagerBarHost<Tab: Hashable, Header: View, Bar: View, Page: View>: View {
    let model: PagerHostModel<Tab, Header, Bar, Page>

    var body: some View {
        if let bar = model.bar, let context = model.barContext() {
            bar(context)
        }
    }
}

// MARK: - Chrome roots (pinned mode)

/// Root of the header hosting controller: natural-height content that
/// reports its measured height so the sticky coordinator can size the
/// chrome and the pages' top margins.
private struct PagerChromeHeaderRoot<Tab: Hashable, Header: View, Bar: View, Page: View>: View {
    let model: PagerHostModel<Tab, Header, Bar, Page>
    let onHeightChange: @MainActor @Sendable (CGFloat) -> Void

    var body: some View {
        // swiftlint:disable:next redundant_discardable_let
        let _ = model.contentVersion
        if let header = model.header {
            header()
                .fixedSize(horizontal: false, vertical: true)
                // Measure the natural content height BEFORE the frame
                // expands to the host view's bounds — measuring outside
                // reports max(hostBounds, content) and can only ratchet
                // upward, since hostBounds is itself the last report.
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }, action: onHeightChange)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .environment(\.self, model.environment)
        }
    }
}

private struct PagerChromeBarRoot<Tab: Hashable, Header: View, Bar: View, Page: View>: View {
    let model: PagerHostModel<Tab, Header, Bar, Page>
    let onHeightChange: @MainActor @Sendable (CGFloat) -> Void

    var body: some View {
        // swiftlint:disable:next redundant_discardable_let
        let _ = model.contentVersion
        PagerBarHost(model: model)
            .background {
                if let barBackground = model.barBackground {
                    Rectangle()
                        .fill(barBackground)
                        .ignoresSafeArea(edges: .horizontal)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            // Same measure-inside-the-frame rule as the header root.
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }, action: onHeightChange)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .environment(\.self, model.environment)
    }
}

// MARK: - Page root

/// Root view of each page's hosting controller: re-injects the bridged
/// environment (outermost) and layers page-scoped values on top.
private struct PagerPageRoot<Tab: Hashable, Header: View, Bar: View, Page: View>: View {
    let index: Int
    let model: PagerHostModel<Tab, Header, Bar, Page>
    let handle: PagerPageHandle
    let registrar: PagerScrollViewRegistrar

    var body: some View {
        // swiftlint:disable:next redundant_discardable_let
        let _ = model.contentVersion
        if let content = model.pageContent(at: index) {
            content
                .environment(\.pagerPageIsActive, handle.isActive)
                .environment(\.pagerScrollViewRegistrar, registrar)
                .environment(\.pagerChromeTopInset, model.chromeTopInset)
                // Wholesale environment replacement bridges the host
                // hierarchy's environment across the UIKit boundary;
                // the page-scoped keys above override it for this subtree.
                .environment(\.self, model.environment)
        }
    }
}

// MARK: - Representable

private struct PagerRepresentable<Tab: Hashable, Header: View, Bar: View, Page: View>: UIViewControllerRepresentable {
    let tabs: [Tab]
    @Binding var selection: Tab
    let model: PagerHostModel<Tab, Header, Bar, Page>
    let header: () -> Header
    let bar: (PagerBarContext<Tab>) -> Bar
    let page: (Tab) -> Page
    let environment: EnvironmentValues
    let preloadPolicy: PagerPreloadPolicy
    let isSwipeEnabled: Bool
    let barBackground: AnyShapeStyle?
    let contentKey: AnyHashable?
    let usesChrome: Bool
    let pinProgressAction: (@MainActor @Sendable (CGFloat) -> Void)?

    func makeCoordinator() -> PagerCoordinator<Tab, Header, Bar, Page> {
        PagerCoordinator(model: model)
    }

    func makeUIViewController(context: Context) -> PagerContainerViewController {
        let coordinator = context.coordinator
        pushState(to: coordinator)

        let initialIndex = tabs.firstIndex(of: selection) ?? 0
        model.progress = .resting(at: initialIndex)

        let chrome: PagerChrome? = usesChrome
            ? coordinator.makeChrome(includesHeader: Header.self != EmptyView.self)
            : nil

        let container = PagerContainerViewController(
            pageCount: tabs.count,
            initialIndex: initialIndex,
            preloadPolicy: preloadPolicy,
            dataSource: coordinator,
            chrome: chrome
        )
        coordinator.container = container

        container.onProgressChange = { [weak coordinator] progress in
            coordinator?.model.progress = progress
        }
        container.onSelectionSettled = { [weak coordinator] index in
            coordinator?.selectionSettled(at: index)
        }
        container.onPageEvent = { [weak coordinator] event in
            coordinator?.handlePageEvent(event)
        }
        container.onTopInsetChange = { [weak coordinator] inset in
            coordinator?.model.chromeTopInset = inset
        }
        container.onPinProgressChange = { [weak coordinator] progress in
            coordinator?.pinProgressAction?(progress)
        }
        container.isSwipeEnabled = isSwipeEnabled
        return container
    }

    func updateUIViewController(_ container: PagerContainerViewController, context: Context) {
        assert(
            tabs.count == container.pageCount,
            "SegmentedPager does not support changing the tab count yet (planned for M3)"
        )

        pushState(to: context.coordinator)
        container.isSwipeEnabled = isSwipeEnabled
        // Keep the UIKit trait environment in step with the bridged
        // SwiftUI colorScheme so chrome and pages flip in the same frame.
        container.view.overrideUserInterfaceStyle =
            environment.colorScheme == .dark ? .dark : .light

        // The tracker adopts the target index up front in
        // setSelectedIndex, so an in-flight bar-tap transition reads as
        // selectedIndex == target here and re-entrant updates no-op.
        // A genuinely different external write (deep link, reset) lands
        // as a redirect of the running animation instead of being
        // swallowed.
        if let index = tabs.firstIndex(of: selection), index != container.selectedIndex {
            container.setSelectedIndex(index, animated: true)
        }
    }

    private func pushState(to coordinator: PagerCoordinator<Tab, Header, Bar, Page>) {
        // Observable fields only when they actually changed: `@Observable`
        // notifies on every write, and an equal write here reached every
        // bar and page root.
        model.push(tabs: tabs, selection: selection)
        model.page = page
        model.header = header
        model.bar = bar
        model.barBackground = barBackground
        model.update(environment: environment, contentKey: contentKey)

        coordinator.pinProgressAction = pinProgressAction

        let tabs = tabs
        coordinator.applySelection = { index in
            guard tabs.indices.contains(index) else { return }
            selection = tabs[index]
        }
        // Bar taps write the binding immediately (the host's
        // selection-gated UI must react on tap, not at animation end);
        // updateUIViewController turns the write into the animated
        // transition.
        model.select = { tab in
            selection = tab
        }
    }
}

// MARK: - Coordinator

@MainActor
final class PagerCoordinator<Tab: Hashable, Header: View, Bar: View, Page: View>: NSObject, PagerPageProviding {
    let model: PagerHostModel<Tab, Header, Bar, Page>
    weak var container: PagerContainerViewController?
    var applySelection: ((Int) -> Void)?
    var pinProgressAction: (@MainActor @Sendable (CGFloat) -> Void)?

    init(model: PagerHostModel<Tab, Header, Bar, Page>) {
        self.model = model
    }

    func makeChrome(includesHeader: Bool) -> PagerChrome {
        let headerVC: UIViewController?
        if includesHeader {
            let root = PagerChromeHeaderRoot(model: model) { [weak self] height in
                self?.container?.setHeaderHeight(height)
            }
            headerVC = UIHostingController(rootView: root)
        } else {
            headerVC = nil
        }

        let barRoot = PagerChromeBarRoot(model: model) { [weak self] height in
            self?.container?.setBarHeight(height)
        }
        let barVC = UIHostingController(rootView: barRoot)

        return PagerChrome(headerViewController: headerVC, barViewController: barVC)
    }

    func makePageViewController(at index: Int) -> UIViewController {
        let handle = PagerPageHandle()
        model.handles[index] = handle

        let registrar = PagerScrollViewRegistrar { [weak self] scrollView in
            self?.container?.registerPageScrollView(scrollView, at: index)
        }
        let root = PagerPageRoot(index: index, model: model, handle: handle, registrar: registrar)
        let hosting = UIHostingController(rootView: root)
        hosting.view.backgroundColor = .clear
        return hosting
    }

    func handlePageEvent(_ event: PagerPageEvent) {
        switch event {
        case .didAppear(let index):
            model.handles[index]?.isActive = true
        case .didDisappear(let index):
            model.handles[index]?.isActive = false
        case .initialize, .willAppear, .willDisappear:
            break
        }
    }

    func selectionSettled(at index: Int) {
        model.settle(selectionAt: index)
        applySelection?(index)
    }
}
#endif
