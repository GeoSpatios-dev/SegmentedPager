//
//  PagerChromeOverlay.swift
//  SegmentedPager
//
//  Created by yousanflics on 7/1/26.
//
//  Full-bleed overlay above the horizontal paging scroll view hosting
//  the pinned chrome: the bar always, the header only while a
//  horizontal transition is in flight. During vertical scrolling the
//  header lives inside the active page's scroll view so dragging the
//  header also scrolls the list.
//
//  Touch policy: only touches that land on hosted chrome subviews are
//  claimed; everything else falls through to the pages underneath.
//

#if canImport(UIKit)
import UIKit

@MainActor
public final class PagerChromeOverlay: UIView {
    override public init(frame: CGRect) {
        super.init(frame: frame)
        // Collapsed chrome slides above the container's top edge and
        // must clip there, not float over host content.
        clipsToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override public func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let view = super.hitTest(point, with: event)
        return view === self ? nil : view
    }
}
#endif
