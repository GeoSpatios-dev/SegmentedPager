//
//  PagerStickyCoordinator.swift
//  SegmentedPager
//
//  Smooth-mode sticky coordination (design doc §5.3). Single
//  responsibility: keep the chrome (header + bar) consistent with the
//  active page's vertical offset, across page switches.
//
//  Mechanics:
//  - The bar always lives in the chrome overlay; its y is a pure
//    function of the active page's collapse, driven per-frame by KVO on
//    contentOffset (plain frame writes, no SwiftUI involvement).
//  - The header is NOT a pure floating layer: during vertical scrolling
//    it is a subview of the active page's scroll view at content y = 0,
//    so dragging the header IS dragging the list (zero gesture
//    forwarding) and it scrolls away without per-frame driving. During
//    horizontal transitions it moves to the overlay, frozen at the
//    transition's starting collapse.
//  - Settle order (§5.3): ① sync the destination's offset via
//    OffsetSyncRule → ② reparent the header into the destination →
//    ③ switch KVO to the destination and unfreeze. All in one runloop
//    so the unfreeze frame shows exactly the frozen collapse.
//

#if canImport(UIKit)
import UIKit

@MainActor
public final class PagerStickyCoordinator {
    /// Chrome heights change → the UI layer updates each page's top
    /// content margin.
    public var onTopInsetChange: ((CGFloat) -> Void)?
    /// Continuous pin progress (0 expanded … 1 pinned), emitted on change.
    public var onPinProgressChange: ((CGFloat) -> Void)?

    public private(set) var math: StickyMath

    private let overlay: PagerChromeOverlay
    private let headerView: UIView?
    private let barView: UIView

    private weak var activeScrollView: UIScrollView?
    private var offsetObservation: NSKeyValueObservation?
    /// Non-nil while a horizontal transition is in flight; chrome renders
    /// this collapse regardless of vertical offsets.
    private var frozenCollapse: CGFloat?
    /// Top anchor of the chrome inside the overlay (the container's safe
    /// area top), matching the pages' adjusted content inset origin.
    private var chromeTopAnchor: CGFloat = 0
    private var lastReportedPinProgress: CGFloat = -1

    public init(
        overlay: PagerChromeOverlay,
        headerView: UIView?,
        barView: UIView,
        math: StickyMath = StickyMath(headerHeight: 0, barHeight: 0)
    ) {
        self.overlay = overlay
        self.headerView = headerView
        self.barView = barView
        self.math = math

        if let headerView {
            overlay.addSubview(headerView)
        }
        overlay.addSubview(barView)
    }

    // MARK: - Inputs from the container

    public var currentCollapse: CGFloat {
        if let frozenCollapse { return frozenCollapse }
        guard let activeScrollView else { return 0 }
        return collapse(of: activeScrollView)
    }

    /// A horizontal transition (user drag or programmatic animation) is
    /// starting: freeze the chrome at the current collapse and float the
    /// header so it stays visually static while pages slide.
    public func freezeForHorizontalTransition() {
        guard frozenCollapse == nil else { return }
        let collapse = currentCollapse
        frozenCollapse = collapse
        moveHeaderToOverlay()
        applyChromeFrames(collapse: collapse)
    }

    /// The pager settled on a page (§5.3 order: sync offset → reparent →
    /// observe + unfreeze). Also serves as the initial attach. Idempotent.
    public func settle(on scrollView: UIScrollView) {
        let collapse = currentCollapse

        // ① Destination offset per OffsetSyncRule.
        let saved = normalizedOffset(of: scrollView)
        let target = OffsetSyncRule.targetNormalizedOffset(
            currentCollapse: collapse,
            headerHeight: math.headerHeight,
            destinationSavedNormalizedOffset: saved
        )
        if abs(target - saved) > 0.5 {
            scrollView.contentOffset.y += target - saved
        }

        // ② Header rides inside the destination's scroll content.
        moveHeader(into: scrollView)

        // ③ Chrome now follows the destination.
        frozenCollapse = nil
        observe(scrollView)
        applyChromeFrames(collapse: self.collapse(of: scrollView))
    }

    /// Container laid out (size change, safe area change): re-anchor and
    /// re-apply chrome frames.
    public func overlayLayoutChanged() {
        chromeTopAnchor = overlay.safeAreaInsets.top
        updateHeaderWidth()
        applyChromeFrames(collapse: currentCollapse)
    }

    public func setHeaderHeight(_ height: CGFloat) {
        guard abs(height - math.headerHeight) > 0.5 else { return }

        // Preserve the pin ratio through the height change so the header
        // neither jumps nor pops (a header growing from 0 — its first
        // measurement — appears expanded).
        let oldHeight = math.headerHeight
        let oldCollapse = currentCollapse
        let progress = oldHeight > 0 ? math.pinProgress(collapse: oldCollapse) : 0
        math.headerHeight = height
        let targetCollapse = progress * height

        if frozenCollapse != nil {
            frozenCollapse = targetCollapse
        } else if let activeScrollView {
            let delta = targetCollapse - oldCollapse
            if abs(delta) > 0.5 {
                activeScrollView.contentOffset.y += delta
            }
        }

        onTopInsetChange?(math.totalTopInset)
        updateHeaderWidth()
        applyChromeFrames(collapse: currentCollapse)
    }

    public func setBarHeight(_ height: CGFloat) {
        guard abs(height - math.barHeight) > 0.5 else { return }
        math.barHeight = height
        onTopInsetChange?(math.totalTopInset)
        applyChromeFrames(collapse: currentCollapse)
    }

    // MARK: - Geometry

    private func normalizedOffset(of scrollView: UIScrollView) -> CGFloat {
        math.normalizedOffset(
            contentOffsetY: scrollView.contentOffset.y,
            adjustedTopInset: scrollView.adjustedContentInset.top
        )
    }

    private func collapse(of scrollView: UIScrollView) -> CGFloat {
        math.collapse(forNormalizedOffset: normalizedOffset(of: scrollView))
    }

    private func applyChromeFrames(collapse: CGFloat) {
        let width = overlay.bounds.width

        barView.frame = CGRect(
            x: 0,
            y: chromeTopAnchor + math.barOriginY(collapse: collapse),
            width: width,
            height: math.barHeight
        )

        if let headerView, headerView.superview === overlay {
            headerView.frame = CGRect(
                x: 0,
                y: chromeTopAnchor + math.headerOriginY(collapse: collapse),
                width: width,
                height: math.headerHeight
            )
        }

        let pinProgress = math.pinProgress(collapse: collapse)
        if abs(pinProgress - lastReportedPinProgress) > 0.001 {
            lastReportedPinProgress = pinProgress
            onPinProgressChange?(pinProgress)
        }
    }

    // MARK: - Header reparenting

    private func moveHeaderToOverlay() {
        guard let headerView, headerView.superview !== overlay else { return }
        assertNoFirstResponder(in: headerView)
        overlay.addSubview(headerView)
        overlay.bringSubviewToFront(barView)
    }

    private func moveHeader(into scrollView: UIScrollView) {
        guard let headerView else { return }
        guard headerView.superview !== scrollView else {
            updateHeaderWidth()
            return
        }
        assertNoFirstResponder(in: headerView)
        scrollView.addSubview(headerView)
        // Content y = 0 is the top of the page's chrome margin, which sits
        // at the viewport top when the page rests fully expanded.
        headerView.frame = CGRect(
            x: 0,
            y: 0,
            width: scrollView.bounds.width,
            height: math.headerHeight
        )
    }

    private func updateHeaderWidth() {
        guard let headerView else { return }
        if let scrollView = headerView.superview as? UIScrollView {
            headerView.frame = CGRect(
                x: 0,
                y: 0,
                width: scrollView.bounds.width,
                height: math.headerHeight
            )
        }
        // Overlay-hosted frames are owned by applyChromeFrames.
    }

    /// §5.3 contract: no text input inside the header — reparenting would
    /// tear down first responder mid-scroll.
    private func assertNoFirstResponder(in view: UIView) {
        #if DEBUG
        assert(
            !containsFirstResponder(view),
            "SegmentedPager header must not contain the first responder (no text input in headers)"
        )
        #endif
    }

    private func containsFirstResponder(_ view: UIView) -> Bool {
        if view.isFirstResponder { return true }
        return view.subviews.contains { containsFirstResponder($0) }
    }

    // MARK: - Offset observation

    private func observe(_ scrollView: UIScrollView) {
        activeScrollView = scrollView
        offsetObservation = scrollView.observe(\.contentOffset, options: [.new]) { [weak self] scrollView, _ in
            // UIScrollView offsets mutate on the main thread; the KVO
            // callback arrives there synchronously.
            MainActor.assumeIsolated {
                guard let self, self.frozenCollapse == nil,
                      scrollView === self.activeScrollView
                else { return }
                self.applyChromeFrames(collapse: self.collapse(of: scrollView))
            }
        }
    }
}
#endif
