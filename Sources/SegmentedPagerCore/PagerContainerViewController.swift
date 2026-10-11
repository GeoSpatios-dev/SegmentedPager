//
//  PagerContainerViewController.swift
//  SegmentedPager
//
//  Created by yousanflics on 7/1/26.
//
//  Container view controller owning the horizontal paging scroll view
//  and page view controllers via standard containment (addChild /
//  didMove), so pages that need real appearance callbacks (PDF viewers
//  etc.) behave correctly.
//
//  Responsibilities: lazy page creation (driven by
//  PagerPageLifecycleTracker), progress reporting for bar indicator
//  interpolation, programmatic selection, page realignment on size
//  changes, and — in pinned mode — chrome hosting plus sticky
//  coordination timing (freeze during horizontal transitions, synchronize
//  the destination offset, then attach the header and resume observation).
//  Tab semantics live in the SwiftUI layer; Core uses integer page indices.
//

#if canImport(UIKit)
import OSLog
import UIKit

private let pageInitSignposter = OSSignposter(
    logger: Logger(subsystem: "SegmentedPager", category: "PageInit")
)

@MainActor
public protocol PagerPageProviding: AnyObject {
    func makePageViewController(at index: Int) -> UIViewController
}

/// Pinned-mode chrome: plain view controllers (the SwiftUI layer passes
/// hosting controllers; Core stays SwiftUI-free).
@MainActor
public struct PagerChrome {
    public let headerViewController: UIViewController?
    public let barViewController: UIViewController

    public init(headerViewController: UIViewController?, barViewController: UIViewController) {
        self.headerViewController = headerViewController
        self.barViewController = barViewController
    }
}

@MainActor
public final class PagerContainerViewController: UIViewController {
    public let scrollView = PagerHorizontalScrollView(frame: .zero)

    /// Continuous transition progress, emitted on every scroll tick
    /// (user drags and programmatic animations alike).
    public var onProgressChange: ((PageProgress) -> Void)?
    /// The pager came to rest on a page (after a drag, a programmatic
    /// animation, or an instant selection).
    public var onSelectionSettled: ((Int) -> Void)?
    /// Per-page lifecycle, in emission order. `initialize` has already
    /// been executed (the page exists) by the time this fires.
    public var onPageEvent: ((PagerPageEvent) -> Void)?
    /// Chrome heights changed → pages must update their top margins.
    public var onTopInsetChange: ((CGFloat) -> Void)? {
        didSet { sticky?.onTopInsetChange = onTopInsetChange }
    }

    /// Header pin progress (0 expanded … 1 pinned), pinned mode only.
    public var onPinProgressChange: ((CGFloat) -> Void)? {
        didSet { sticky?.onPinProgressChange = onPinProgressChange }
    }

    public var isSwipeEnabled: Bool {
        get { scrollView.isScrollEnabled }
        set { scrollView.isScrollEnabled = newValue }
    }

    public var selectedIndex: Int { tracker.selectedIndex }
    public var pageCount: Int { tracker.pageCount }

    public func pageViewController(at index: Int) -> UIViewController? {
        pages[index]
    }

    private let tracker: PagerPageLifecycleTracker
    private weak var dataSource: PagerPageProviding?
    private let chrome: PagerChrome?
    private var sticky: PagerStickyCoordinator?
    private var chromeOverlay: PagerChromeOverlay?

    private var pages: [Int: UIViewController] = [:]

    private struct WeakScrollView {
        weak var value: UIScrollView?
    }

    private var pageScrollViews: [Int: WeakScrollView] = [:]
    private var lastLayoutWidth: CGFloat = 0
    /// Suppresses tracker feeding while an offset change is ours (initial
    /// placement, size-change realignment, programmatic selection).
    private var isAdjustingOffsetInternally = false
    private var programmaticTargetIndex: Int?
    /// Selection requested before the first layout; applied once the
    /// tracker has started.
    private var deferredSelectionIndex: Int?

    public init(
        pageCount: Int,
        initialIndex: Int,
        preloadPolicy: PagerPreloadPolicy,
        dataSource: PagerPageProviding,
        chrome: PagerChrome? = nil
    ) {
        tracker = PagerPageLifecycleTracker(
            pageCount: pageCount,
            selectedIndex: initialIndex,
            preloadPolicy: preloadPolicy
        )
        self.dataSource = dataSource
        self.chrome = chrome
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override public func viewDidLoad() {
        super.viewDidLoad()
        scrollView.delegate = self
        view.addSubview(scrollView)
        installChromeIfNeeded()
    }

    override public func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        scrollView.frame = view.bounds
        chromeOverlay?.frame = view.bounds

        let width = view.bounds.width
        guard width > 0 else { return }

        let widthChanged = abs(width - lastLayoutWidth) > 0.5
        lastLayoutWidth = width

        scrollView.contentSize = CGSize(
            width: width * CGFloat(tracker.pageCount),
            height: view.bounds.height
        )
        for (index, page) in pages {
            page.view.frame = pageFrame(at: index)
        }

        if widthChanged {
            // Keep the current page aligned through rotations / split
            // view resizes; realign by index, not by pixel offset.
            isAdjustingOffsetInternally = true
            scrollView.setContentOffset(restingOffset(for: tracker.selectedIndex), animated: false)
            isAdjustingOffsetInternally = false

            // The instant realign kills any in-flight programmatic
            // animation WITHOUT its didEndScrollingAnimation callback —
            // complete the settle here or the chrome stays frozen and
            // the selection binding never reconciles.
            if let target = programmaticTargetIndex {
                programmaticTargetIndex = nil
                stickySettle(at: target)
                updateScrollsToTop(activeIndex: target)
                onProgressChange?(.resting(at: target))
                onSelectionSettled?(target)
            }
        }

        sticky?.overlayLayoutChanged()
        startTrackerIfNeeded()

        if let deferred = deferredSelectionIndex, !pages.isEmpty {
            deferredSelectionIndex = nil
            setSelectedIndex(deferred, animated: false)
        }
    }

    // MARK: - Public API

    /// Programmatic selection (bar tap, external binding write).
    public func setSelectedIndex(_ index: Int, animated: Bool) {
        guard index != tracker.selectedIndex,
              (0 ..< tracker.pageCount).contains(index)
        else { return }

        // Before the first layout the tracker hasn't started — freezing
        // or feeding it here would silently drop the selection and wedge
        // the chrome. Defer to the first layout pass instead.
        guard lastLayoutWidth > 0 else {
            deferredSelectionIndex = index
            return
        }

        // Chrome freezes for the whole transition, exactly like a drag.
        sticky?.freezeForHorizontalTransition()
        if animated {
            programmaticTargetIndex = index
        }

        apply(events: tracker.selectProgrammatically(index))

        if animated {
            scrollView.setContentOffset(restingOffset(for: index), animated: true)
        } else {
            // An earlier animated transition may still be in flight —
            // this instant jump supersedes it.
            programmaticTargetIndex = nil
            isAdjustingOffsetInternally = true
            scrollView.setContentOffset(restingOffset(for: index), animated: false)
            isAdjustingOffsetInternally = false
            stickySettle(at: index)
            updateScrollsToTop(activeIndex: index)
            onProgressChange?(.resting(at: index))
            onSelectionSettled?(index)
            schedulePreloadAroundSelection()
        }
    }

    /// Pages report their vertical scroll views here (via the SwiftUI
    /// probe). Core owns scrollsToTop uniqueness and sticky attachment.
    public func registerPageScrollView(_ scrollView: UIScrollView, at index: Int) {
        pageScrollViews[index] = WeakScrollView(value: scrollView)
        // Status-bar-tap scroll-to-top must have exactly one taker.
        scrollView.scrollsToTop = index == tracker.selectedIndex

        // Registration happens exactly once per page, right as it is
        // created — align the fresh page with the chrome BEFORE it
        // becomes visible mid-transition.
        sticky?.prepareIncomingPage(scrollView)
        Task { @MainActor [weak self, weak scrollView] in
            await Task.yield()
            guard let self, let scrollView else { return }
            sticky?.prepareIncomingPage(scrollView)
            settleRegisteredScrollViewIfCurrent(scrollView, at: index)
        }

        // The settled page's scroll view arriving late (page created
        // during this settle, probe resolved on a later layout pass)
        // completes the sticky attach here.
        settleRegisteredScrollViewIfCurrent(scrollView, at: index)
    }

    /// Sticky-settle from a registration path — only when the pager is
    /// actually at rest on this page. A frozen chrome means a horizontal
    /// transition is in flight and its own settle path (drag settle,
    /// animation end, or the explicit stickySettle after an instant
    /// jump) completes the attach; settling from here mid-swipe would
    /// unfreeze and drag the header sideways with the outgoing page.
    private func settleRegisteredScrollViewIfCurrent(_ scrollView: UIScrollView, at index: Int) {
        guard index == tracker.selectedIndex,
              programmaticTargetIndex == nil,
              sticky?.isFrozen != true
        else { return }
        sticky?.settle(on: scrollView)
    }

    public func pageScrollView(at index: Int) -> UIScrollView? {
        pageScrollViews[index]?.value
    }

    public func setHeaderHeight(_ height: CGFloat) {
        sticky?.setHeaderHeight(height)
    }

    public func setBarHeight(_ height: CGFloat) {
        sticky?.setBarHeight(height)
    }

    // MARK: - Internals

    private func installChromeIfNeeded() {
        guard let chrome else { return }

        if let headerVC = chrome.headerViewController {
            addChild(headerVC)
            headerVC.view.backgroundColor = .clear
        }
        addChild(chrome.barViewController)
        chrome.barViewController.view.backgroundColor = .clear

        let overlay = PagerChromeOverlay(frame: .zero)
        view.addSubview(overlay)
        chromeOverlay = overlay

        let sticky = PagerStickyCoordinator(
            overlay: overlay,
            headerView: chrome.headerViewController?.view,
            barView: chrome.barViewController.view
        )
        sticky.onTopInsetChange = onTopInsetChange
        sticky.onPinProgressChange = onPinProgressChange
        self.sticky = sticky

        chrome.headerViewController?.didMove(toParent: self)
        chrome.barViewController.didMove(toParent: self)
    }

    private func startTrackerIfNeeded() {
        guard pages.isEmpty else { return }

        isAdjustingOffsetInternally = true
        scrollView.setContentOffset(restingOffset(for: tracker.selectedIndex), animated: false)
        isAdjustingOffsetInternally = false

        apply(events: tracker.start())
    }

    private func restingOffset(for index: Int) -> CGPoint {
        CGPoint(x: CGFloat(index) * lastLayoutWidth, y: 0)
    }

    private func pageFrame(at index: Int) -> CGRect {
        CGRect(
            x: CGFloat(index) * lastLayoutWidth,
            y: 0,
            width: lastLayoutWidth,
            height: view.bounds.height
        )
    }

    private func apply(events: [PagerPageEvent]) {
        for event in events {
            if case .initialize(let index) = event {
                installPage(at: index)
            }
            onPageEvent?(event)
        }
    }

    private func installPage(at index: Int) {
        guard pages[index] == nil, let dataSource else { return }

        // Expose page creation cost to Instruments to identify expensive
        // content construction during paging.
        let signpostState = pageInitSignposter.beginInterval("PageInit", id: pageInitSignposter.makeSignpostID())
        defer { pageInitSignposter.endInterval("PageInit", signpostState) }

        let page = dataSource.makePageViewController(at: index)
        pages[index] = page

        addChild(page)
        page.view.frame = pageFrame(at: index)
        page.view.autoresizingMask = []
        scrollView.addSubview(page.view)
        page.didMove(toParent: self)

        // Chrome must stay above pages regardless of insertion order.
        if let chromeOverlay {
            view.bringSubviewToFront(chromeOverlay)
        }
        // Force the hosted SwiftUI content to build now so the page's
        // scroll view registers synchronously in the common case (an
        // async registration is handled by registerPageScrollView).
        page.view.layoutIfNeeded()
    }

    /// Page settling: runs before appearance callbacks reach SwiftUI so the
    /// unfreeze frame is consistent. Safe no-op when the page's scroll
    /// view has not registered yet — registration completes it.
    private func stickySettle(at index: Int) {
        guard let sticky else { return }
        if let target = pageScrollViews[index]?.value {
            sticky.settle(on: target)
        }
    }

    private func currentProgress() -> PageProgress {
        PageProgress.from(
            offsetX: scrollView.contentOffset.x,
            pageWidth: lastLayoutWidth,
            pageCount: tracker.pageCount
        )
    }

    private func settle() {
        guard lastLayoutWidth > 0, tracker.pageCount > 0 else { return }
        let index = min(
            max(Int((scrollView.contentOffset.x / lastLayoutWidth).rounded()), 0),
            tracker.pageCount - 1
        )

        let events = tracker.settle(at: index)
        // Create any missing page first, then run the sticky settle, then
        // surface lifecycle to SwiftUI — all within this runloop turn.
        for event in events {
            if case .initialize(let pageIndex) = event {
                installPage(at: pageIndex)
            }
        }
        stickySettle(at: index)
        for event in events {
            onPageEvent?(event)
        }

        updateScrollsToTop(activeIndex: index)
        onProgressChange?(.resting(at: index))
        onSelectionSettled?(index)
        schedulePreloadAroundSelection()
    }

    /// Neighbor pages per the preload policy are built on the next runloop
    /// turn after a transition rests, so the frame that lands the selected
    /// page is presented before any other page is constructed. Building
    /// them inside the tap or the settle put two hosting-controller
    /// layouts in the transition frame (airport detail: 10.6% slow frames
    /// in this container). Skipped when a new transition has started
    /// meanwhile; the tracker only emits pages that still do not exist.
    private func schedulePreloadAroundSelection() {
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  programmaticTargetIndex == nil,
                  !scrollView.isDragging, !scrollView.isDecelerating
            else { return }
            apply(events: tracker.preloadAroundSelection())
        }
    }

    private func updateScrollsToTop(activeIndex: Int) {
        for (index, box) in pageScrollViews {
            box.value?.scrollsToTop = index == activeIndex
        }
    }
}

// MARK: - UIScrollViewDelegate

extension PagerContainerViewController: UIScrollViewDelegate {
    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        // A grab mid-programmatic-animation interrupts it and
        // scrollViewDidEndScrollingAnimation never fires; hand control
        // back to the drag pipeline.
        programmaticTargetIndex = nil
        sticky?.freezeForHorizontalTransition()
    }

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !isAdjustingOffsetInternally, lastLayoutWidth > 0 else { return }

        let progress = currentProgress()
        onProgressChange?(progress)

        // Programmatic animations already emitted their lifecycle events
        // up front; only user drags feed the tracker incrementally.
        if programmaticTargetIndex == nil,
           scrollView.isDragging || scrollView.isDecelerating {
            apply(events: tracker.dragUpdated(progress))
        }
    }

    public func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard !decelerate else { return }
        settle()
    }

    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        settle()
    }

    public func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        let target = programmaticTargetIndex
        programmaticTargetIndex = nil
        if let target {
            stickySettle(at: target)
            updateScrollsToTop(activeIndex: target)
            onProgressChange?(.resting(at: target))
            onSelectionSettled?(target)
            schedulePreloadAroundSelection()
        }
    }
}
#endif
