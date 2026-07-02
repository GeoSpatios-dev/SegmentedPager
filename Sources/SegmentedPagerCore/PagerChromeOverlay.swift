//
//  PagerChromeOverlay.swift
//  SegmentedPager
//
//  Full-bleed overlay above the horizontal paging scroll view hosting
//  the pinned chrome: the bar always, the header only while a
//  horizontal transition is in flight (design doc §5.3 — during
//  vertical scrolling the header lives inside the active page's scroll
//  view so drags on it are drags on the list).
//
//  Touch policy: only touches that land on hosted chrome subviews are
//  claimed; everything else falls through to the pages underneath.
//

#if canImport(UIKit)
import UIKit

@MainActor
public final class PagerChromeOverlay: UIView {
    public override init(frame: CGRect) {
        super.init(frame: frame)
        // Collapsed chrome slides above the container's top edge and
        // must clip there, not float over host content.
        clipsToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let view = super.hitTest(point, with: event)
        return view === self ? nil : view
    }
}
#endif
