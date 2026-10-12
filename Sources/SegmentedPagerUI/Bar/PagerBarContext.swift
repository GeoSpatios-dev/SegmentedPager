//
//  PagerBarContext.swift
//  SegmentedPager
//
//  Created by yousanflics on 7/1/26.
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
    /// Selects a tab, animating the page transition.
    public let select: (Tab) -> Void
    private let readProgress: () -> PageProgress

    /// Continuous transition progress in logical page indices.
    ///
    /// Read lazily: when the pager supplies the context, this reads the
    /// pager's observable progress at the point of use, so only the view
    /// whose `body` reads it (the moving indicator, the fading selected
    /// label) re-evaluates on each frame of a transition. A bar skin
    /// that reads it in its outer `body` is rebuilt per frame instead.
    public var progress: PageProgress { readProgress() }

    public init(
        tabs: [Tab],
        selection: Tab,
        progress: PageProgress,
        select: @escaping (Tab) -> Void
    ) {
        self.init(tabs: tabs, selection: selection, progressProvider: { progress }, select: select)
    }

    public init(
        tabs: [Tab],
        selection: Tab,
        progressProvider: @escaping () -> PageProgress,
        select: @escaping (Tab) -> Void
    ) {
        self.tabs = tabs
        self.selection = selection
        readProgress = progressProvider
        self.select = select
    }

    public var selectedIndex: Int {
        tabs.firstIndex(of: selection) ?? 0
    }
}
