//
//  SegmentedPager.swift
//  SegmentedPager
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
//  Environment bridging (§6.5): pages, header and bar live in separate
//  hosting controllers, so SwiftUI Environment does NOT flow into them
//  automatically. The pager captures the full `EnvironmentValues` at its
//  own position in the hierarchy and re-injects it into every hosted
//  root (with pager-scoped keys layered on top).
//
//  Body invalidation is deliberately decoupled: per-frame progress ticks
//  flow through the observable host model and re-evaluate only the bar
//  host, never the pager body or the page roots.
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
/// invalidation scoped: the bar host reads `progress`/`selection`; page
/// roots read `tabs`, `page`, `environment` and `chromeTopInset`.
@MainActor
@Observable
final class PagerHostModel<Tab: Hashable, Header: View, Bar: View, Page: View> {
    var tabs: [Tab] = []
    var selection: Tab?
    var page: ((Tab) -> Page)?
    var header: (() -> Header)?
    var bar: ((PagerBarContext<Tab>) -> Bar)?
    var environment = EnvironmentValues()
    var progress = PageProgress.resting(at: 0)
    var chromeTopInset: CGFloat = 0
    var barBackground: AnyShapeStyle?

    @ObservationIgnored var handles: [Int: PagerPageHandle] = [:]
    @ObservationIgnored var select: ((Tab) -> Void)?

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
            progress: progress,
            select: { tab in select?(tab) }
        )
    }
}

// MARK: - Bar hosts

/// Fixed mode: tabs/selection/bar come straight from the pager body (so
/// the bar renders on the very first frame); only the per-frame
/// `progress` is read from the model, isolating drag-tick invalidation
/// to this small subtree.
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
                progress: model.progress,
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
        model.tabs = tabs
        model.selection = selection
        model.page = page
        model.header = header
        model.bar = bar
        model.environment = environment
        model.barBackground = barBackground

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
        if model.tabs.indices.contains(index) {
            model.selection = model.tabs[index]
        }
        applySelection?(index)
    }
}
#endif
