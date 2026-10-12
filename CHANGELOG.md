# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.0.2] - 2026-10-12

### Changed
- Sources grouped by responsibility (`Container`, `Lifecycle`, `Sticky`, `Geometry`; `Bar`, `Page`, `Configuration`). No API change.
- Tests split into `SegmentedPagerCoreTests` and `SegmentedPagerUITests`, one per module.
- The DEBUG-only demo moved out of the `SegmentedPagerUI` module into the `Examples` package.

### Added
- DocC catalog: Getting Started, Configuration, Architecture and Performance articles.
- Swift Package Index configuration, contributing guide, issue and pull request templates.

## [1.0.1] - 2026-10-12

### Changed
- CI runs on macOS 26 (Xcode 26) for both the macOS and the iOS simulator jobs.
- A test harness is explicitly main-actor isolated so the package also compiles with Xcode 16.4.

Library sources are unchanged from 1.0.0.

## [1.0.0] - 2026-10-11

First standalone release, extracted from the Ascent iOS app with its history.

### Added
- `pagerContentKey(_:)`: opt-in cheap updates for pages that observe their own inputs.
- `PagerPageLifecycleTracker.preloadAroundSelection()`: neighbour pages are built after a transition rests.

### Changed
- `PagerBarContext.progress` is a lazy read of the pager's progress, so only its readers re-render per frame.
- A tap or a settle creates only the selected page; `.neighbors` preloading runs on the next run-loop turn.

[Unreleased]: https://github.com/GeoSpatios-dev/SegmentedPager/compare/1.0.2...HEAD
[1.0.2]: https://github.com/GeoSpatios-dev/SegmentedPager/compare/1.0.1...1.0.2
[1.0.1]: https://github.com/GeoSpatios-dev/SegmentedPager/compare/1.0.0...1.0.1
[1.0.0]: https://github.com/GeoSpatios-dev/SegmentedPager/releases/tag/1.0.0
