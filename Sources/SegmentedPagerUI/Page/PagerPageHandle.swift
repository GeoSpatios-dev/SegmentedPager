//
//  PagerPageHandle.swift
//  SegmentedPager
//
//  Created by yousanflics on 7/1/26.
//
//  Per-page observable handle. The pager flips `isActive` on the page's
//  didAppear/didDisappear lifecycle events; page roots republish it as
//  the `pagerPageIsActive` environment value, which in turn drives the
//  `onPagerPageAppear` / `onPagerPageDisappear` modifiers.
//

import Observation

@MainActor
@Observable
final class PagerPageHandle {
    var isActive = false
}
