//
//  PagerEnvironment.swift
//  SegmentedPager
//
//  Environment keys carrying pager configuration from the host down to
//  `SegmentedPager`, and page-scoped values (`pagerPageIsActive`) that
//  the pager injects into each page's hosting controller.
//

import SegmentedPagerCore
import SwiftUI

private struct PagerBarModeKey: EnvironmentKey {
    static let defaultValue = PagerBarMode.pinned
}

private struct PagerPreloadPolicyKey: EnvironmentKey {
    static let defaultValue = PagerPreloadPolicy.default
}

private struct PagerSwipeEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

private struct PagerBarBackgroundKey: EnvironmentKey {
    static let defaultValue: AnyShapeStyle? = nil
}

private struct PagerContentBottomPaddingKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

private struct PagerPageIsActiveKey: EnvironmentKey {
    static let defaultValue = false
}

private struct PagerChromeTopInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

private struct PagerPinProgressActionKey: EnvironmentKey {
    static let defaultValue: (@MainActor @Sendable (CGFloat) -> Void)? = nil
}

extension EnvironmentValues {
    var pagerBarMode: PagerBarMode {
        get { self[PagerBarModeKey.self] }
        set { self[PagerBarModeKey.self] = newValue }
    }

    var pagerPreloadPolicy: PagerPreloadPolicy {
        get { self[PagerPreloadPolicyKey.self] }
        set { self[PagerPreloadPolicyKey.self] = newValue }
    }

    var pagerSwipeEnabled: Bool {
        get { self[PagerSwipeEnabledKey.self] }
        set { self[PagerSwipeEnabledKey.self] = newValue }
    }

    var pagerBarBackground: AnyShapeStyle? {
        get { self[PagerBarBackgroundKey.self] }
        set { self[PagerBarBackgroundKey.self] = newValue }
    }

    var pagerContentBottomPadding: CGFloat {
        get { self[PagerContentBottomPaddingKey.self] }
        set { self[PagerContentBottomPaddingKey.self] = newValue }
    }

    /// Whether the page containing this view is the pager's settled,
    /// visible page. `false` outside of a `SegmentedPager` page.
    public internal(set) var pagerPageIsActive: Bool {
        get { self[PagerPageIsActiveKey.self] }
        set { self[PagerPageIsActiveKey.self] = newValue }
    }

    /// Top space each page reserves for the pinned chrome (header + bar).
    /// Injected per page; consumed by `PagerPageScroll`.
    var pagerChromeTopInset: CGFloat {
        get { self[PagerChromeTopInsetKey.self] }
        set { self[PagerChromeTopInsetKey.self] = newValue }
    }

    var pagerPinProgressAction: (@MainActor @Sendable (CGFloat) -> Void)? {
        get { self[PagerPinProgressActionKey.self] }
        set { self[PagerPinProgressActionKey.self] = newValue }
    }
}
