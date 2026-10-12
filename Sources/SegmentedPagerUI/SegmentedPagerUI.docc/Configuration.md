# Configuration

Every option is an environment-carried modifier. Apply it to the pager or to any ancestor.

| Modifier | Default | Effect |
|---|---|---|
| `pagerBarMode(_:)` | `.pinned` | `.pinned`: the header scrolls away with the active page and the bar pins below it. `.fixed`: the bar sits above the pages. |
| `pagerPreloadPolicy(_:)` | `.lazy(visibleRatio: 0.5)` | When pages are created. `.lazy` creates a page once a swipe reveals the given ratio, `.neighbors` builds the adjacent pages on the run-loop turn after a transition rests, `.eager` creates every page up front. Read once at setup. |
| `pagerSwipeEnabled(_:)` | `true` | Disables horizontal swipe paging; bar taps still switch pages. |
| `pagerBarBackground(_:)` | none | Opaque background behind the bar row. |
| `pagerContentBottomPadding(_:)` | `0` | Extra scrollable space below each page for host chrome that overlaps the bottom edge. |
| `pagerContentKey(_:)` | `nil` | Opt-in cheap updates. See <doc:Performance>. |
| `onPagerPinProgress(_:)` | none | Continuous header pin progress, 0 expanded to 1 pinned. Pinned mode only. |

Inside page content:

| Modifier | Effect |
|---|---|
| `onPagerPageAppear(_:)` / `onPagerPageDisappear(_:)` | Run when the containing page becomes, or stops being, the active page. |
| `pagerSwipeExclusion()` | Marks a region (a horizontal carousel) where horizontal drags must not page. |
| `@Environment(\.pagerPageIsActive)` | Whether the containing page is the settled, visible page. |
