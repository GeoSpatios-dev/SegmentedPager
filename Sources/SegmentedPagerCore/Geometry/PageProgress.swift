//
//  PageProgress.swift
//  SegmentedPager
//
//  Continuous horizontal transition progress between two adjacent pages,
//  normalized from the paging scroll view's content offset. Drives bar
//  indicator interpolation so the indicator tracks the finger instead of
//  animating after the fact.
//
//  Indices are always in logical order (index 0 = first tab) regardless
//  of layout direction; the UI layer owns any RTL mapping.
//

import CoreGraphics

public struct PageProgress: Equatable, Sendable {
    /// Lower page of the transition (the page whose leading edge is at or
    /// left of the viewport).
    public let fromIndex: Int
    /// Upper page of the transition. Equals `fromIndex` when the pager is
    /// resting exactly on a page boundary.
    public let toIndex: Int
    /// How far the transition has travelled from `fromIndex` toward
    /// `toIndex`, in `0...1`. `0` when resting.
    public let fraction: CGFloat

    public init(fromIndex: Int, toIndex: Int, fraction: CGFloat) {
        self.fromIndex = fromIndex
        self.toIndex = toIndex
        self.fraction = fraction
    }

    /// Continuous page position (`fromIndex + fraction`), convenient for
    /// interpolating indicator frames.
    public var position: CGFloat {
        CGFloat(fromIndex) + fraction
    }

    public static func resting(at index: Int) -> PageProgress {
        PageProgress(fromIndex: index, toIndex: index, fraction: 0)
    }

    /// Normalizes a horizontal content offset into a transition progress.
    /// Offsets outside the scrollable range (rubber-banding) clamp to the
    /// first/last page.
    public static func from(offsetX: CGFloat, pageWidth: CGFloat, pageCount: Int) -> PageProgress {
        guard pageWidth > 0, pageCount > 0 else { return .resting(at: 0) }

        let maxPosition = CGFloat(pageCount - 1)
        let position = min(max(offsetX / pageWidth, 0), maxPosition)
        let lower = min(CGFloat(Int(position.rounded(.down))), maxPosition)
        let fraction = position - lower

        let fromIndex = Int(lower)
        guard fraction > 0 else { return .resting(at: fromIndex) }

        return PageProgress(
            fromIndex: fromIndex,
            toIndex: min(fromIndex + 1, pageCount - 1),
            fraction: fraction
        )
    }
}
