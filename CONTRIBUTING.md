# Contributing

Thanks for helping improve SegmentedPager.

## Before you open a pull request

1. Open an issue first for anything larger than a bug fix, so the approach can be agreed before you write it.
2. Keep pull requests focused: one behaviour change per pull request, with tests.
3. Add an entry under **Unreleased** in `CHANGELOG.md`.

## Running the tests

Pure logic (lifecycle, progress, sticky geometry) runs on macOS:

```bash
swift test
```

The UIKit and SwiftUI suites need an iOS simulator:

```bash
xcodebuild test \
  -scheme SegmentedPager-Package \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

CI runs both, and builds the `Examples` package for the simulator.

## Conventions

- Swift 6 language mode with strict concurrency; UIKit-dependent code is gated behind `#if canImport(UIKit)` so the core still builds on macOS.
- Tests use Swift Testing (`@Test`, `#expect`). Put a test in the target of the module it exercises.
- Comments explain why, not what. Public API gets a documentation comment.
- Never read observable state from `updateUIViewController`: it runs under SwiftUI's access tracking, and a read followed by a write there causes an update loop.

## Releasing

Maintainers tag `MAJOR.MINOR.PATCH` on `main` after CI is green, move the **Unreleased** notes into a dated section, and publish a GitHub release with the same notes.
