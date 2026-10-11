//
//  PagerPageLifecycleTracker.swift
//  SegmentedPager
//
//  Created by yousanflics on 7/1/26.
//
//  Pure state machine translating pager motion (drags, settles,
//  programmatic selection) into per-page lifecycle events, with the same
//  semantics as JXSegmentedListContainerView's list lifecycle:
//  initialize / willAppear / didAppear / willDisappear / didDisappear.
//
//  Owns lazy-creation policy decisions (when a page must be initialized)
//  and deduplication (rapid back-and-forth drags never emit duplicate
//  will/did pairs). No UIKit — fully unit-testable; the container feeds
//  it scroll state and executes the returned events in order.
//

import CoreGraphics

public enum PagerPageEvent: Equatable, Sendable {
    /// Create the page's view controller. Always precedes the page's
    /// first `willAppear`.
    case initialize(Int)
    case willAppear(Int)
    case didAppear(Int)
    case willDisappear(Int)
    case didDisappear(Int)
}

public final class PagerPageLifecycleTracker {
    private enum AppearanceState {
        case disappeared
        case appearing // willAppear emitted
        case appeared // didAppear emitted
        case disappearing // willDisappear emitted
    }

    public let pageCount: Int
    public let preloadPolicy: PagerPreloadPolicy
    public private(set) var selectedIndex: Int

    private var initialized: Set<Int> = []
    private var states: [AppearanceState]
    private var started = false

    public init(pageCount: Int, selectedIndex: Int, preloadPolicy: PagerPreloadPolicy) {
        self.pageCount = max(pageCount, 0)
        self.selectedIndex = min(max(selectedIndex, 0), max(pageCount - 1, 0))
        self.preloadPolicy = preloadPolicy
        states = Array(repeating: .disappeared, count: max(pageCount, 0))
    }

    public func isInitialized(_ index: Int) -> Bool {
        initialized.contains(index)
    }

    /// Initial events once the container has laid out: create pages per
    /// policy and bring the selected page fully on screen.
    public func start() -> [PagerPageEvent] {
        guard !started, pageCount > 0 else { return [] }
        started = true

        var events: [PagerPageEvent] = []
        initializeIfNeeded(selectedIndex, into: &events)
        preloadPerPolicy(around: selectedIndex, into: &events)
        transition(selectedIndex, to: .appeared, into: &events)
        return events
    }

    /// Feed on every user-driven horizontal scroll tick.
    public func dragUpdated(_ progress: PageProgress) -> [PagerPageEvent] {
        guard started, pageCount > 1 else { return [] }

        var events: [PagerPageEvent] = []
        let incoming = incomingPage(for: progress)

        // A previously peeked page that is no longer part of the
        // transition goes away immediately (rapid direction reversal).
        for index in states.indices
        where index != selectedIndex && index != incoming?.index && !isResting(index) {
            transition(index, to: .disappeared, into: &events)
        }

        if let incoming {
            if !initialized.contains(incoming.index) {
                guard incoming.visibleRatio >= preloadPolicy.initVisibleRatio else { return events }
                initializeIfNeeded(incoming.index, into: &events)
            }
            transition(incoming.index, to: .appearing, into: &events)
            transition(selectedIndex, to: .disappearing, into: &events)
        } else if case .disappearing = states[selectedIndex] {
            // Drag returned to rest on the current page: recover it.
            transition(selectedIndex, to: .appeared, into: &events)
        }

        return events
    }

    /// The pager came to rest on `index` after a user drag (deceleration
    /// ended, or the drag ended without deceleration).
    public func settle(at index: Int) -> [PagerPageEvent] {
        guard started, states.indices.contains(index) else { return [] }

        var events: [PagerPageEvent] = []
        initializeIfNeeded(index, into: &events)

        for other in states.indices where other != index && !isResting(other) {
            transition(other, to: .disappeared, into: &events)
        }
        transition(index, to: .appeared, into: &events)

        selectedIndex = index
        return events
    }

    /// Selection changed without a user drag (bar tap, external binding
    /// write). The container animates the offset; lifecycle events are
    /// emitted up front in will/did order.
    ///
    /// Only the target page is created here. Neighbor preloading is a
    /// separate step (`preloadAroundSelection`) so that a tap builds one
    /// page in its own frame, not up to three.
    public func selectProgrammatically(_ index: Int) -> [PagerPageEvent] {
        guard started, states.indices.contains(index), index != selectedIndex else { return [] }

        var events: [PagerPageEvent] = []
        initializeIfNeeded(index, into: &events)

        for other in states.indices where other != index && !isResting(other) {
            transition(other, to: .disappeared, into: &events)
        }
        transition(index, to: .appeared, into: &events)

        selectedIndex = index
        return events
    }

    /// Pages the policy wants created around the current selection that
    /// do not exist yet. The container runs this once a transition has
    /// come to rest and its frame has been presented, so neighbor
    /// construction never lands in the tap, the settle or a drag tick.
    /// Idempotent: pages already created emit nothing.
    public func preloadAroundSelection() -> [PagerPageEvent] {
        guard started else { return [] }
        var events: [PagerPageEvent] = []
        preloadPerPolicy(around: selectedIndex, into: &events)
        return events
    }

    // MARK: - Internals

    private func isResting(_ index: Int) -> Bool {
        if case .disappeared = states[index] { return true }
        return false
    }

    private struct IncomingPage {
        let index: Int
        let visibleRatio: CGFloat
    }

    /// The non-selected page revealed by the current transition, if any.
    private func incomingPage(for progress: PageProgress) -> IncomingPage? {
        guard progress.fraction > 0 else {
            // A still-active drag can momentarily rest exactly on a
            // neighbor's boundary (fraction == 0 at a non-selected
            // index): that neighbor is a fully revealed incoming page,
            // not a return to rest — treating it as rest would invert
            // appearance between the visible and hidden pages.
            if progress.fromIndex != selectedIndex, states.indices.contains(progress.fromIndex) {
                return IncomingPage(index: progress.fromIndex, visibleRatio: 1)
            }
            return nil
        }

        if progress.fromIndex == selectedIndex, progress.toIndex != selectedIndex {
            return IncomingPage(index: progress.toIndex, visibleRatio: progress.fraction)
        }

        if progress.toIndex == selectedIndex, progress.fromIndex != selectedIndex {
            return IncomingPage(index: progress.fromIndex, visibleRatio: 1 - progress.fraction)
        }

        guard progress.fromIndex != selectedIndex else { return nil }

        // Transition no longer touches the selected page (e.g. a fast
        // fling reported late): surface the dominant page.
        let dominant = progress.fraction >= 0.5 ? progress.toIndex : progress.fromIndex
        let ratio = progress.fraction >= 0.5 ? progress.fraction : 1 - progress.fraction
        return IncomingPage(index: dominant, visibleRatio: ratio)
    }

    private func initializeIfNeeded(_ index: Int, into events: inout [PagerPageEvent]) {
        guard states.indices.contains(index), !initialized.contains(index) else { return }
        initialized.insert(index)
        events.append(.initialize(index))
    }

    private func preloadPerPolicy(around index: Int, into events: inout [PagerPageEvent]) {
        switch preloadPolicy {
        case .lazy:
            break
        case .neighbors:
            initializeIfNeeded(index - 1, into: &events)
            initializeIfNeeded(index + 1, into: &events)
        case .eager:
            for page in 0 ..< pageCount {
                initializeIfNeeded(page, into: &events)
            }
        }
    }

    /// Moves a page to a target appearance state, emitting exactly the
    /// events required to get there. Redundant transitions are no-ops,
    /// which is what deduplicates rapid back-and-forth drags.
    private func transition(
        _ index: Int,
        to target: AppearanceState,
        into events: inout [PagerPageEvent]
    ) {
        guard states.indices.contains(index) else { return }
        let current = states[index]

        switch target {
        case .appearing:
            switch current {
            case .disappeared, .disappearing:
                events.append(.willAppear(index))
                states[index] = .appearing
            case .appearing, .appeared:
                break
            }

        case .appeared:
            switch current {
            case .disappeared, .disappearing:
                events.append(.willAppear(index))
                events.append(.didAppear(index))
                states[index] = .appeared
            case .appearing:
                events.append(.didAppear(index))
                states[index] = .appeared
            case .appeared:
                break
            }

        case .disappearing:
            switch current {
            case .appeared, .appearing:
                events.append(.willDisappear(index))
                states[index] = .disappearing
            case .disappearing, .disappeared:
                break
            }

        case .disappeared:
            switch current {
            case .appeared, .appearing:
                events.append(.willDisappear(index))
                events.append(.didDisappear(index))
                states[index] = .disappeared
            case .disappearing:
                events.append(.didDisappear(index))
                states[index] = .disappeared
            case .disappeared:
                break
            }
        }
    }
}
