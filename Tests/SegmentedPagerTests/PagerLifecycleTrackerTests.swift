//
//  PagerLifecycleTrackerTests.swift
//  SegmentedPagerTests
//
//  Created by yousanflics on 7/1/26.
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

    @Test func dragRestingExactlyOnNeighborBoundaryKeepsItIncoming() {
        // A still-active drag can pass through offset == pageWidth
        // exactly (fraction 0 at the NEIGHBOR's index). That is a fully
        // revealed incoming page — not a return to rest — and must not
        // invert appearance between the visible and hidden pages.
        let tracker = makeTracker()
        _ = tracker.start()
        _ = tracker.dragUpdated(PageProgress(fromIndex: 0, toIndex: 1, fraction: 0.6))
        let events = tracker.dragUpdated(.resting(at: 1))
        #expect(events.isEmpty)
        #expect(tracker.selectedIndex == 0) // not settled yet
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

    /// The settle creates only the page it lands on; the neighbor the
    /// policy wants comes from the separate preload step the container
    /// runs once the settled frame is up.
    @Test func neighborsPolicySettleCreatesOnlyTheLandedPage() {
        let tracker = makeTracker(policy: .neighbors)
        _ = tracker.start()
        let events = tracker.settle(at: 1)
        #expect(!events.contains(.initialize(2)))
        #expect(!tracker.isInitialized(2))

        let preload = tracker.preloadAroundSelection()
        #expect(preload == [.initialize(2)])
        #expect(tracker.isInitialized(2))
        #expect(tracker.preloadAroundSelection().isEmpty)
    }

    /// Airport detail: Info → Chart used to build Chart and Runway in the
    /// tap. The tap now builds Chart alone; Runway follows in the preload.
    @Test func neighborsPolicyProgrammaticSelectionBuildsOnlyTheTarget() {
        let tracker = makeTracker(pageCount: 5, policy: .neighbors)
        _ = tracker.start()
        let events = tracker.selectProgrammatically(4)
        #expect(events.filter { if case .initialize = $0 { return true } else { return false } } == [.initialize(4)])
        #expect(!tracker.isInitialized(3))

        #expect(tracker.preloadAroundSelection() == [.initialize(3)])
    }

    @Test func lazyPolicyPreloadAroundSelectionIsEmpty() {
        let tracker = makeTracker(pageCount: 5)
        _ = tracker.start()
        _ = tracker.selectProgrammatically(2)
        #expect(tracker.preloadAroundSelection().isEmpty)
    }

    @Test func neighborPreloadingMovesAllAdjacentPageCreationOutOfDragTicks() {
        // Five pages match Airport Detail. Compare the old lazy path against
        // preloading through a full forward/backward visit, including a
        // canceled swipe before the first settle.
        for policy in [PagerPreloadPolicy.default, .neighbors] {
            let tracker = makeTracker(pageCount: 5, policy: policy)
            _ = tracker.start()
            var initializedDuringDrag: [Int] = []
            let destinations = [1, 2, 3, 4, 3, 2, 1, 0]

            for destination in destinations {
                let origin = tracker.selectedIndex
                for fraction in [CGFloat(0.1), 0.5, 0.9] {
                    let events = tracker.dragUpdated(PageProgress(
                        fromIndex: min(origin, destination),
                        toIndex: max(origin, destination),
                        fraction: origin < destination ? fraction : 1 - fraction
                    ))
                    for case .initialize(let index) in events {
                        initializedDuringDrag.append(index)
                    }
                }
                if origin == 0, destination == 1 {
                    _ = tracker.dragUpdated(.resting(at: origin))
                    #expect(tracker.selectedIndex == origin)
                    _ = tracker.dragUpdated(PageProgress(fromIndex: 0, toIndex: 1, fraction: 0.9))
                }
                _ = tracker.settle(at: destination)
                #expect(tracker.selectedIndex == destination)
                // The container runs this on the runloop turn after the
                // settle; the drag ticks above never see neighbor creation.
                _ = tracker.preloadAroundSelection()
            }

            #expect(initializedDuringDrag == (policy == .neighbors ? [] : [1, 2, 3, 4]))
            #expect(tracker.selectedIndex == 0)
        }
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
