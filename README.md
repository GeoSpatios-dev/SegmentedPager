<h1 align="center">SegmentedPager</h1>

<p align="center">
  Keep-alive segmented paging for SwiftUI on iOS: UIKit-paged pages, a pinning tab bar,<br>
  and transitions that stay smooth on heavy content.
</p>

<p align="center">
  <a href="https://github.com/GeoSpatios-dev/SegmentedPager/actions/workflows/ci.yml"><img src="https://github.com/GeoSpatios-dev/SegmentedPager/actions/workflows/ci.yml/badge.svg?branch=main" alt="CI"></a>
  <img src="https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white" alt="Swift 6.0">
  <img src="https://img.shields.io/badge/platforms-iOS%2018%2B-0A84FF" alt="iOS 18+">
  <img src="https://img.shields.io/badge/SPM-compatible-34C759" alt="Swift Package Manager">
  <a href="https://github.com/GeoSpatios-dev/SegmentedPager/releases"><img src="https://img.shields.io/github/v/release/GeoSpatios-dev/SegmentedPager?sort=semver" alt="Release"></a>
</p>

---

- [Why SegmentedPager](#why-segmentedpager)
- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quick start](#quick-start)
- [Usage](#usage)
- [Configuration](#configuration)
- [Performance](#performance)
- [Architecture](#architecture)
- [Examples](#examples)
- [Contributing](#contributing)

## Why SegmentedPager

A `TabView(.page)` or a horizontal `ScrollView` of pages recreates or re-lays-out page content as you switch, drops scroll position, and fights nested vertical scrolling for the same gesture. Detail screens with a collapsing header, a pinned tab row and five heavy tabs feel that immediately.

SegmentedPager puts each page in its own `UIHostingController` inside a paging `UIScrollView`. Pages are created once and kept: `@State`, scroll position and `.task` survive every switch, and UIKit's nested-scroll arbitration decides between paging and scrolling.

## Features

- **Keep-alive pages.** One hosting controller per page; nothing is torn down on a tab switch.
- **Pinned or fixed chrome.** A collapsing header that scrolls with the active page and a bar that pins below it, or a bar fixed above the pages.
- **Finger-tracking bars.** Continuous transition progress for indicators, read lazily so only the indicator re-renders per frame. Bring your own bar or use the default one.
- **Explicit page lifecycle.** `onPagerPageAppear` / `onPagerPageDisappear`, `pagerPageIsActive`, and a deduplicated `initialize → willAppear → didAppear` event stream.
- **Preload policies.** `.lazy`, `.neighbors` or `.eager`; page construction never runs inside a drag tick.
- **Gesture arbitration.** Native nested scrolling, plus `pagerSwipeExclusion()` for horizontal carousels inside a page.
- **Environment bridging.** The host's SwiftUI environment reaches pages, header and bar across the hosting-controller boundary.
- **Testable core.** Lifecycle, progress and sticky geometry are pure Swift and run on macOS.

## Requirements

| | Minimum |
|---|---|
| iOS | 18.0 |
| Swift | 6.0 |
| Xcode | 16.0 (CI runs Xcode 26) |

## Installation

### Swift Package Manager

In Xcode: **File → Add Package Dependencies…**, enter `https://github.com/GeoSpatios-dev/SegmentedPager.git`, and add **SegmentedPagerUI** to your target.

Or in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/GeoSpatios-dev/SegmentedPager.git", from: "1.0.0"),
],
targets: [
    .target(
        name: "MyFeature",
        dependencies: [.product(name: "SegmentedPagerUI", package: "SegmentedPager")]
    ),
]
```

| Product | Use it for |
|---|---|
| `SegmentedPagerUI` | The SwiftUI `SegmentedPager` view. This is what apps import. |
| `SegmentedPagerCore` | The UIKit container and the lifecycle / geometry primitives, for UIKit hosts or custom adapters. |

## Quick start

```swift
import SegmentedPagerUI

struct ProfileView: View {
    enum Tab: String, CaseIterable { case posts = "Posts", media = "Media", likes = "Likes" }
    @State private var tab: Tab = .posts

    var body: some View {
        SegmentedPager(
            tabs: Tab.allCases,
            selection: $tab,
            title: { $0.rawValue },
            header: { ProfileHeader() },
            page: { tab in
                PagerPageScroll {
                    LazyVStack { FeedSection(tab) }
                }
            }
        )
        .pagerBarMode(.pinned)
    }
}
```

## Usage

### Custom bar

Any view that takes a `PagerBarContext` can be the bar. Read `context.progress` only in the part that moves with the swipe.

```swift
SegmentedPager(tabs: tabs, selection: $tab, header: { Header() }, bar: { context in
    HStack {
        ForEach(context.tabs, id: \.self) { tab in
            Button(tab.title) { context.select(tab) }
        }
    }
    .overlay(alignment: .bottomLeading) {
        Indicator(position: context.progress.position, count: context.tabs.count)
    }
}, page: { tab in
    PagerPageScroll { Content(tab) }
})
```

### Page lifecycle

```swift
TimelineList(model: model)
    .onPagerPageAppear { model.resume() }
    .onPagerPageDisappear { model.pause() }
```

### Horizontal content inside a page

```swift
ScrollView(.horizontal) { Carousel() }
    .pagerSwipeExclusion()
```

## Configuration

| Modifier | Default | Effect |
|---|---|---|
| `pagerBarMode(_:)` | `.pinned` | `.pinned`: header scrolls away, bar pins. `.fixed`: bar above the pages. |
| `pagerPreloadPolicy(_:)` | `.lazy(visibleRatio: 0.5)` | When pages are created: on reveal, neighbours after each transition, or all up front. |
| `pagerSwipeEnabled(_:)` | `true` | Disable swipe paging; bar taps still switch. |
| `pagerBarBackground(_:)` | none | Opaque background behind the bar row. |
| `pagerContentBottomPadding(_:)` | `0` | Scrollable space below each page for overlapping host chrome. |
| `pagerContentKey(_:)` | `nil` | Opt-in cheap updates; see [Performance](#performance). |
| `onPagerPinProgress(_:)` | none | Header pin progress, 0 → 1, for scroll-linked effects. |

## Performance

- Transition progress is read lazily from an observable model: only the views that read it re-render per frame.
- No page is created inside a drag tick. With `.neighbors`, a tap or a settle builds only the selected page; the neighbours are built on the run-loop turn after the transition rests.
- Every pager update re-evaluates the hosted pages by default, because the closures you pass are not comparable. If your pages observe their own inputs, pass `.pagerContentKey(...)` with the values the closures capture by value, and pages re-render only when that key, the tabs, the selection or an observable environment trait changes.

The [Performance article](Sources/SegmentedPagerUI/SegmentedPagerUI.docc/Performance.md) has the details.

## Architecture

```
SegmentedPagerUI                    SegmentedPagerCore
┌──────────────────────────┐       ┌────────────────────────────────────────┐
│ SegmentedPager (View)    │──────▶│ PagerContainerViewController           │
│  PagerRepresentable      │       │  paging UIScrollView, 1 hosting VC/page │
│  PagerHostModel (@Obs.)  │       │ PagerPageLifecycleTracker (pure)        │
│ PagerPageScroll          │       │ PagerStickyCoordinator + OffsetSyncRule │
│ PagerBarContext / bars   │       │ PageProgress, StickyMath (pure)         │
│ Configuration modifiers  │       └────────────────────────────────────────┘
└──────────────────────────┘
```

```
Sources/
├── SegmentedPagerCore/
│   ├── Container/      PagerContainerViewController, PagerHorizontalScrollView
│   ├── Lifecycle/      PagerPageLifecycleTracker, PagerConfig
│   ├── Sticky/         PagerStickyCoordinator, PagerChromeOverlay
│   └── Geometry/       PageProgress, StickyMath, OffsetSyncRule
└── SegmentedPagerUI/
    ├── SegmentedPager.swift
    ├── Bar/            PagerBarContext, DefaultPagerBar
    ├── Page/           PagerPageScroll, PagerPageHandle, ScrollViewProbe
    ├── Configuration/  PagerModifiers, PagerEnvironment
    └── SegmentedPagerUI.docc/
Tests/
├── SegmentedPagerCoreTests/   pure logic (macOS) + UIKit container (simulator)
└── SegmentedPagerUITests/     SwiftUI bridging and pinned geometry (simulator)
Examples/                      demo views and previews (separate package)
```

Read the [Architecture article](Sources/SegmentedPagerUI/SegmentedPagerUI.docc/Architecture.md) for the lifecycle and pinned-chrome mechanics.

## Examples

`Examples/` is a separate package with two demo screens and Xcode previews: a fixed bar with a heavy feed, nested horizontal scrollers, long text and a keep-alive proof page, and a pinned header with scroll-linked pin progress. Open the `Examples` folder in Xcode and run the previews.

## Contributing

Bug reports and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for the test commands and the conventions the CI enforces, and [CHANGELOG.md](CHANGELOG.md) for release notes.
