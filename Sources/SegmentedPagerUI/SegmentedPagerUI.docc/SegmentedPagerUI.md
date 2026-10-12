# ``SegmentedPagerUI``

Keep-alive segmented paging for SwiftUI on iOS.

## Overview

`SegmentedPager` hosts every page in its own `UIHostingController` inside a paging `UIScrollView`. Pages stay alive across tab switches: scroll position and `@State` survive, and `.task` runs once. Horizontal paging and vertical scrolling are arbitrated by UIKit's native nested-scroll behaviour instead of competing SwiftUI gestures.

```swift
SegmentedPager(
    tabs: Tab.allCases,
    selection: $selection,
    title: { $0.title },
    page: { tab in
        PagerPageScroll { TabContent(tab) }
    }
)
```

## Topics

### Essentials

- <doc:GettingStarted>
- ``SegmentedPager``
- ``PagerPageScroll``

### Tab bars

- ``PagerBarContext``
- ``DefaultPagerBar``

### Configuration

- <doc:Configuration>

### Understanding the pager

- <doc:Architecture>
- <doc:Performance>
