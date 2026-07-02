//
//  OffsetSyncRuleTests.swift
//  SegmentedPagerTests
//
//  Four quadrants of the settle rule (design doc §5.3):
//  (header pinned / not pinned) × (destination saved deep / shallow).
//

import CoreGraphics
import SegmentedPagerCore
import Testing

struct OffsetSyncRuleTests {
    private let headerHeight: CGFloat = 120

    @Test func headerVisibleSyncsShallowDestinationToCurrentCollapse() {
        let target = OffsetSyncRule.targetNormalizedOffset(
            currentCollapse: 40,
            headerHeight: headerHeight,
            destinationSavedNormalizedOffset: 10
        )
        #expect(target == 40)
    }

    @Test func headerVisibleOverridesDeepDestinationForContinuity() {
        // Header visibly expanded: the destination adopts the shared
        // collapse depth even if it was previously deep — the header
        // must not jump on landing (JXPagingSmoothView convention).
        let target = OffsetSyncRule.targetNormalizedOffset(
            currentCollapse: 40,
            headerHeight: headerHeight,
            destinationSavedNormalizedOffset: 800
        )
        #expect(target == 40)
    }

    @Test func headerPinnedKeepsDeepDestinationPosition() {
        let target = OffsetSyncRule.targetNormalizedOffset(
            currentCollapse: headerHeight,
            headerHeight: headerHeight,
            destinationSavedNormalizedOffset: 800
        )
        #expect(target == 800)
    }

    @Test func headerPinnedClampsShallowDestinationToPinPoint() {
        // Header stays pinned on landing; a shallow destination is
        // pulled down to the pin point instead of popping it open.
        let target = OffsetSyncRule.targetNormalizedOffset(
            currentCollapse: headerHeight,
            headerHeight: headerHeight,
            destinationSavedNormalizedOffset: 30
        )
        #expect(target == headerHeight)
    }

    @Test func fullyExpandedSyncsEverythingToTop() {
        let target = OffsetSyncRule.targetNormalizedOffset(
            currentCollapse: 0,
            headerHeight: headerHeight,
            destinationSavedNormalizedOffset: 65
        )
        #expect(target == 0)
    }
}
