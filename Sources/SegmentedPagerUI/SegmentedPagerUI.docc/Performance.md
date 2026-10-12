# Performance

What the pager does per frame and per update, and how to keep tab switches cheap.

## Per-frame work during a transition

The continuous transition progress lives in the pager's observable model. ``PagerBarContext/progress`` is a lazy read of it, so only the views that read it re-render on each frame. Keep that read in the moving indicator and in fading labels, not in the bar's outer `body`, or the whole bar is rebuilt every frame.

## Page creation

Building a page means creating a `UIHostingController` and laying it out. The pager never does that inside a drag tick. With `.neighbors`, a tap or a settle builds only the selected page; the neighbours are built on the next run-loop turn after the transition rests.

## Pager updates and `pagerContentKey`

The page, header and bar closures you pass are not comparable, so by default every update of the pager (a selection write, a parent re-render) re-evaluates every hosted root in case a closure captured a changed value.

When your pages read their inputs through an `@Observable` model themselves, pass a content key containing everything the closures capture by value. The roots then re-evaluate only when the key, the tabs, the selection or an observable environment trait (colour scheme, dynamic type, size class, locale, accessibility) changes:

```swift
SegmentedPager(tabs: tabs, selection: $tab, title: \.title) { tab in
    PagerPageScroll { DetailPage(model: model, tab: tab, showsMap: showsMap) }
}
.pagerContentKey(showsMap) // `model` is observed inside the pages
```

A value captured by a closure but missing from the key reaches a mounted page only on that page's next own update. Leave the key `nil` if you are unsure.
