# Architecture

How the pager is put together, and which module owns what.

## Two modules

- **SegmentedPagerCore** owns the UIKit container (`PagerContainerViewController`), the page lifecycle state machine (`PagerPageLifecycleTracker`), the sticky-chrome coordinator and the geometry. It does not import SwiftUI. The pure logic (lifecycle, progress, sticky math, offset sync) builds and tests on macOS.
- **SegmentedPagerUI** is the SwiftUI adapter: the `SegmentedPager` view, `PagerPageScroll`, the bar context and the configuration modifiers.

## One hosting controller per page

Each page is a `UIHostingController` added as a child of the container and laid out side by side in a paging `UIScrollView`. Pages are never evicted, so their SwiftUI state, scroll position and running tasks survive tab switches.

## Lifecycle

The tracker turns drags, settles and programmatic selections into `initialize`, `willAppear`, `didAppear`, `willDisappear` and `didDisappear` events, deduplicated so a back-and-forth drag never emits a pair twice. Creation policy lives here too: a tap or a settle creates only the page being selected; the policy's neighbours are created by a separate `preloadAroundSelection()` step that the container runs on the next run-loop turn once the transition has rested.

## Pinned chrome

In `.pinned` mode the header and the bar are hosted outside the pages. While the user scrolls vertically the header is reparented into the active page's scroll view, so it scrolls with the content; during a horizontal transition it is frozen in the overlay, so it does not slide sideways with the outgoing page. `OffsetSyncRule` aligns an incoming page's offset with the chrome before it becomes visible.

## Environment bridging

Pages, header and bar live in separate hosting controllers, so SwiftUI's environment does not flow into them on its own. The pager captures the environment at its own position and re-injects it into every hosted root, with pager-scoped values layered on top.
