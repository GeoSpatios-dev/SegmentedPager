//
//  StickyMathTests.swift
//  SegmentedPagerTests
//

import CoreGraphics
import SegmentedPagerCore
import Testing

struct StickyMathTests {
    private let math = StickyMath(headerHeight: 120, barHeight: 44)

    @Test func totalTopInsetSumsHeaderAndBar() {
        #expect(math.totalTopInset == 164)
    }

    @Test func normalizedOffsetIsZeroAtFullyExpandedRest() {
        #expect(math.normalizedOffset(contentOffsetY: -164, adjustedTopInset: 164) == 0)
    }

    @Test func collapseClampsBelowZero() {
        // Pull-down bounce never over-expands the header.
        #expect(math.collapse(forNormalizedOffset: -50) == 0)
    }

    @Test func collapseTracksOffsetWithinTravel() {
        #expect(math.collapse(forNormalizedOffset: 60) == 60)
    }

    @Test func collapseClampsToHeaderHeight() {
        #expect(math.collapse(forNormalizedOffset: 500) == 120)
    }

    @Test func chromeFramesFollowCollapse() {
        #expect(math.headerOriginY(collapse: 0) == 0)
        #expect(math.headerOriginY(collapse: 80) == -80)
        #expect(math.barOriginY(collapse: 0) == 120)
        #expect(math.barOriginY(collapse: 120) == 0)
    }

    @Test func pinProgressSpansZeroToOne() {
        #expect(math.pinProgress(collapse: 0) == 0)
        #expect(math.pinProgress(collapse: 60) == 0.5)
        #expect(math.pinProgress(collapse: 120) == 1)
    }

    @Test func zeroHeightHeaderIsAlwaysPinned() {
        let fixed = StickyMath(headerHeight: 0, barHeight: 44)
        #expect(fixed.pinProgress(collapse: 0) == 1)
        #expect(fixed.collapse(forNormalizedOffset: 300) == 0)
    }
}
