# Getting Started

Add a pager, give each page a vertical scroll container, and choose how the bar behaves.

## Add the package

```swift
dependencies: [
    .package(url: "https://github.com/GeoSpatios-dev/SegmentedPager.git", from: "1.0.0"),
],
targets: [
    .target(name: "MyFeature", dependencies: [
        .product(name: "SegmentedPagerUI", package: "SegmentedPager"),
    ]),
]
```

## Build a pager

Wrap each page's content in ``PagerPageScroll``. It reports the page's `UIScrollView` to the container, which is what makes the sticky header, the bar pinning and status-bar scroll-to-top work.

```swift
import SegmentedPagerUI

struct AirportDetail: View {
    @State private var tab: DetailTab = .info

    var body: some View {
        SegmentedPager(
            tabs: DetailTab.allCases,
            selection: $tab,
            title: { $0.title },
            header: { SummaryCard() },
            page: { tab in
                PagerPageScroll {
                    LazyVStack(alignment: .leading) { content(for: tab) }
                }
            }
        )
        .pagerBarMode(.pinned)
        .pagerPreloadPolicy(.neighbors)
    }
}
```

## Bring your own bar

Any view that takes a ``PagerBarContext`` can be the bar. Read `context.progress` only in the view that moves with the transition (the indicator, a fading label): it is a lazy read of the pager's per-frame progress, so only that view re-renders while the user swipes.

```swift
bar: { context in
    MyPillBar(
        tabs: context.tabs,
        selection: context.selection,
        indicator: { Indicator(position: context.progress.position) },
        select: context.select
    )
}
```

## React to page visibility

Pages are created once and then kept. Use the lifecycle modifiers instead of `onAppear` to start and stop work when a page becomes the visible one.

```swift
List(items) { ItemRow($0) }
    .onPagerPageAppear { model.resumePolling() }
    .onPagerPageDisappear { model.pausePolling() }
```
