//
//  OffsetSyncRule.swift
//  SegmentedPager
//
//  Created by yousanflics on 7/1/26.
//
//  Cross-page offset synchronization for sticky header continuity when a
//  horizontal transition settles.
//
//  - Header not pinned: every "shallow" page shares the current collapse
//    depth so the header never jumps. The destination's own shallow
//    offset is overwritten to preserve the shared header position.
//  - Header pinned: the destination keeps its own deep position; a
//    shallow destination is clamped to the pin point so the header does
//    not pop back open on landing.
//

import CoreGraphics

public enum OffsetSyncRule {
    /// Normalized offset the destination page must adopt when a
    /// horizontal transition settles on it.
    ///
    /// All values are in normalized space (0 == fully expanded, see
    /// `StickyMath.normalizedOffset`).
    public static func targetNormalizedOffset(
        currentCollapse: CGFloat,
        headerHeight: CGFloat,
        destinationSavedNormalizedOffset: CGFloat
    ) -> CGFloat {
        if currentCollapse < headerHeight {
            return currentCollapse
        }

        return max(destinationSavedNormalizedOffset, headerHeight)
    }
}
