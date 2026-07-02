//
//  PageProgressTests.swift
//  SegmentedPagerTests
//

import CoreGraphics
import SegmentedPagerCore
import Testing

struct PageProgressTests {
    @Test func restingProgressHasZeroFraction() {
        let progress = PageProgress.resting(at: 2)
        #expect(progress.fromIndex == 2)
        #expect(progress.toIndex == 2)
        #expect(progress.fraction == 0)
        #expect(progress.position == 2)
    }

    @Test func zeroPageWidthFallsBackToFirstPage() {
        let progress = PageProgress.from(offsetX: 100, pageWidth: 0, pageCount: 3)
        #expect(progress == .resting(at: 0))
    }

    @Test func zeroPageCountFallsBackToFirstPage() {
        let progress = PageProgress.from(offsetX: 100, pageWidth: 390, pageCount: 0)
        #expect(progress == .resting(at: 0))
    }

    @Test func offsetOnBoundaryRests() {
        let progress = PageProgress.from(offsetX: 390, pageWidth: 390, pageCount: 3)
        #expect(progress == .resting(at: 1))
    }

    @Test func midTransitionReportsBothPagesAndFraction() {
        let progress = PageProgress.from(offsetX: 195, pageWidth: 390, pageCount: 3)
        #expect(progress.fromIndex == 0)
        #expect(progress.toIndex == 1)
        #expect(progress.fraction == 0.5)
        #expect(progress.position == 0.5)
    }

    @Test func negativeOffsetClampsToFirstPage() {
        let progress = PageProgress.from(offsetX: -80, pageWidth: 390, pageCount: 3)
        #expect(progress == .resting(at: 0))
    }

    @Test func overshootOffsetClampsToLastPage() {
        let progress = PageProgress.from(offsetX: 390 * 2.5, pageWidth: 390, pageCount: 3)
        #expect(progress == .resting(at: 2))
    }

    @Test func transitionIntoLastPageClampsToIndex() {
        let progress = PageProgress.from(offsetX: 390 * 1.25, pageWidth: 390, pageCount: 3)
        #expect(progress.fromIndex == 1)
        #expect(progress.toIndex == 2)
        #expect(abs(progress.fraction - 0.25) < 0.0001)
    }
}
