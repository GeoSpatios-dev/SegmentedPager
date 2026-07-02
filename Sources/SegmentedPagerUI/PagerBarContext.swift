//
//  PagerBarContext.swift
//  SegmentedPager
//
//  Everything a tab bar skin needs: the tabs, the settled selection, the
//  continuous transition progress (for finger-tracking indicator
//  interpolation), and a select callback that routes through the pager's
//  animated page transition.
//
//  Any SwiftUI view can act as a bar by taking this context — the app
//  injects its own skin (e.g. a PillSegmentedControl-styled bar) without
//  the package knowing about app theming.
//

import SegmentedPagerCore

public struct PagerBarContext<Tab: Hashable> {
    public let tabs: [Tab]
    /// The settled selection. During a drag this remains the page the
    /// drag started from; use `progress` for continuous rendering.
    public let selection: Tab
    /// Continuous transition progress in logical page indices.
    public let progress: PageProgress
    /// Selects a tab, animating the page transition.
    public let select: (Tab) -> Void

    public init(
        tabs: [Tab],
        selection: Tab,
        progress: PageProgress,
        select: @escaping (Tab) -> Void
    ) {
        self.tabs = tabs
        self.selection = selection
        self.progress = progress
        self.select = select
    }

    public var selectedIndex: Int {
        tabs.firstIndex(of: selection) ?? 0
    }
}
