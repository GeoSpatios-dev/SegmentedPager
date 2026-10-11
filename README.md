# SegmentedPager

Keep-alive segmented pager for SwiftUI apps on iOS 18+.

- Each page is its own `UIHostingController` inside a paging `UIScrollView`: pages stay alive across tab switches (scroll positions and `@State` survive, `.task` runs once), and horizontal paging vs. vertical scrolling is arbitrated by UIKit's native nested-scroll behaviour.
- Pinned chrome: a collapsing header that scrolls away with the active page and a bar that pins below it (`.pagerBarMode(.pinned)`), or a fixed bar above the pages (`.fixed`).
- Continuous transition progress for finger-tracking indicators (`PagerBarContext.progress`), read lazily so only the indicator re-renders per frame.
- Explicit page lifecycle (`initialize` / `willAppear` / `didAppear` / `willDisappear` / `didDisappear`) and preload policies (`.lazy(visibleRatio:)`, `.neighbors`, `.eager`); neighbor pages are built after a transition rests, never in the tap or drag.
- Environment bridging across the hosting-controller boundary, with `.pagerContentKey` to opt into cheap updates when pages observe their own inputs.

## Products

| Product | Contents |
|---|---|
| `SegmentedPagerCore` | UIKit container, lifecycle tracker, sticky-chrome coordinator, geometry. No SwiftUI. Pure logic builds and tests on macOS. |
| `SegmentedPagerUI` | `SegmentedPager` view, `PagerPageScroll`, bar context and modifiers. |

## Usage

```swift
import SegmentedPagerUI

SegmentedPager(
    tabs: Tab.allCases,
    selection: $selection,
    header: { SummaryHeader() },
    bar: { context in MyPillBar(context: context) },
    page: { tab in PagerPageScroll { TabContent(tab) } }
)
.pagerBarMode(.pinned)
.pagerPreloadPolicy(.neighbors)
.pagerContentKey(contentKey) // optional: see `pagerContentKey` docs
```

## Requirements

iOS 18+, Swift 6. `swift test` on macOS runs the pure-logic suites; the UIKit suites run on an iOS simulator (`xcodebuild test -scheme SegmentedPager-Package -destination 'platform=iOS Simulator,name=iPhone 16'`).
