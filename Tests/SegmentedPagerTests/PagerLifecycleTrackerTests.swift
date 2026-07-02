//
//  PagerLifecycleTrackerTests.swift
//  SegmentedPagerTests
//

import CoreGraphics
import SegmentedPagerCore
import Testing

struct PagerLifecycleTrackerTests {
    private func makeTracker(
        pageCount: Int = 3,
        selectedIndex: Int = 0,
        policy: PagerPreloadPolicy = .lazy(visibleRatio: 0.5)
    ) -> PagerPageLifecycleTracker {
        PagerPageLifecycleTracker(
            pageCount: pageCount,
            selectedIndex: selectedIndex,
            preloadPolicy: policy
        )
    }

    // MARK: - start()

    @Test func lazyStartInitializesOnlySelectedPage() {
        let tracker = makeTracker(selectedIndex: 1)
        let events = tracker.start()
        #expect(events == [.initialize(1), .willAppear(1), .didAppear(1)])
        #expect(tracker.isInitialized(0) == false)
        #expect(tracker.isInitialized(2) == false)
    }

    @Test func eagerStartInitializesAllPagesButShowsOnlySelected() {
        let tracker = makeTracker(selectedIndex: 1, policy: .eager)
        let events = tracker.start()
        #expect(events == [
            .initialize(1), .initialize(0), .initialize(2),
            .willAppear(1), .didAppear(1),
        ])
    }

    @Test func neighborsStartInitializesValidAdjacentPages() {
        let tracker = makeTracker(selectedIndex: 0, policy: .neighbors)
        let events = tracker.start()
        #expect(events == [.initialize(0), .initialize(1), .willAppear(0), .didAppear(0)])
    }

    @Test func startIsIdempotent() {
        let tracker = makeTracker()
        _ = tracker.start()
        #expect(tracker.start().isEmpty)
    }

    // MARK: - dragUpdated()

    @Test func dragBelowVisibleRatioDoesNotInitializeIncomingPage() {
        let tracker = makeTracker()
        _ = tracker.start()
        let events = tracker.dragUpdated(
            PageProgress(fromIndex: 0, toIndex: 1, fraction: 0.3)
        )
        #expect(events.isEmpty)
        #expect(tracker.isInitialized(1) == false)
    }

    @Test func dragCrossingVisibleRatioInitializesAndAppearsIncomingPage() {
        let tracker = makeTracker()
        _ = tracker.start()
        let events = tracker.dragUpdated(
            PageProgress(fromIndex: 0, toIndex: 1, fraction: 0.6)
        )
        #expect(events == [.initialize(1), .willAppear(1), .willDisappear(0)])
    }

    @Test func repeatedDragTicksEmitNoDuplicates() {
        let tracker = makeTracker()
        _ = tracker.start()
        _ = tracker.dragUpdated(PageProgress(fromIndex: 0, toIndex: 1, fraction: 0.6))
        let events = tracker.dragUpdated(
            PageProgress(fromIndex: 0, toIndex: 1, fraction: 0.8)
        )
        #expect(events.isEmpty)
    }

    @Test func dragReturningToRestRecoversCurrentAndCancelsIncoming() {
        let tracker = makeTracker()
        _ = tracker.start()
        _ = tracker.dragUpdated(PageProgress(fromIndex: 0, toIndex: 1, fraction: 0.6))
        let events = tracker.dragUpdated(.resting(at: 0))
        #expect(events == [
            .willDisappear(1), .didDisappear(1),
            .willAppear(0), .didAppear(0),
        ])
    }

    @Test func dragReversalToOtherNeighborCancelsPreviousIncoming() {
        let tracker = makeTracker(selectedIndex: 1)
        _ = tracker.start()
        _ = tracker.dragUpdated(PageProgress(fromIndex: 1, toIndex: 2, fraction: 0.6))
        // Reverse: now revealing page 0 (selected is the `to` side).
        let events = tracker.dragUpdated(
            PageProgress(fromIndex: 0, toIndex: 1, fraction: 0.4)
        )
        #expect(events == [
            .willDisappear(2), .didDisappear(2),
            .initialize(0), .willAppear(0),
        ])
    }

    // MARK: - settle()

    @Test func settlingOnIncomingPageCompletesTheSwitch() {
        let tracker = makeTracker()
        _ = tracker.start()
        _ = tracker.dragUpdated(PageProgress(fromIndex: 0, toIndex: 1, fraction: 0.6))
        let events = tracker.settle(at: 1)
        #expect(events == [.didDisappear(0), .didAppear(1)])
        #expect(tracker.selectedIndex == 1)
    }

    @Test func settlingBackOnCurrentPageCancelsCleanly() {
        let tracker = makeTracker()
        _ = tracker.start()
        _ = tracker.dragUpdated(PageProgress(fromIndex: 0, toIndex: 1, fraction: 0.6))
        let events = tracker.settle(at: 0)
        #expect(events == [
            .willDisappear(1), .didDisappear(1),
            .willAppear(0), .didAppear(0),
        ])
        #expect(tracker.selectedIndex == 0)
    }

    @Test func settleInitializesFastFlingTargetThatSkippedTheThreshold() {
        let tracker = makeTracker()
        _ = tracker.start()
        let events = tracker.settle(at: 1)
        #expect(events == [
            .initialize(1),
            .willDisappear(0), .didDisappear(0),
            .willAppear(1), .didAppear(1),
        ])
    }

    @Test func neighborsPolicyPreloadsNewNeighborsAfterSettle() {
        let tracker = makeTracker(policy: .neighbors)
        _ = tracker.start()
        let events = tracker.settle(at: 1)
        #expect(events.contains(.initialize(2)))
        #expect(tracker.isInitialized(2))
    }

    // MARK: - selectProgrammatically()

    @Test func programmaticSelectionEmitsFullLifecycleUpFront() {
        let tracker = makeTracker(pageCount: 4)
        _ = tracker.start()
        let events = tracker.selectProgrammatically(3)
        #expect(events == [
            .initialize(3),
            .willDisappear(0), .didDisappear(0),
            .willAppear(3), .didAppear(3),
        ])
        #expect(tracker.selectedIndex == 3)
    }

    @Test func programmaticSelectionOfCurrentPageIsANoOp() {
        let tracker = makeTracker()
        _ = tracker.start()
        #expect(tracker.selectProgrammatically(0).isEmpty)
    }

    @Test func programmaticSelectionCancelsInFlightDrag() {
        let tracker = makeTracker(pageCount: 4)
        _ = tracker.start()
        _ = tracker.dragUpdated(PageProgress(fromIndex: 0, toIndex: 1, fraction: 0.6))
        let events = tracker.selectProgrammatically(3)
        // Page 0 already received willDisappear during the drag; only the
        // matching didDisappear remains due.
        #expect(events == [
            .initialize(3),
            .didDisappear(0),
            .willDisappear(1), .didDisappear(1),
            .willAppear(3), .didAppear(3),
        ])
    }
}
