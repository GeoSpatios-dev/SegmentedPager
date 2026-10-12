//
//  PagerContainerTests.swift
//  SegmentedPagerTests
//
//  Created by yousanflics on 7/1/26.
//
//  Headless-UIWindow tests for the UIKit container: lazy page creation,
//  containment correctness, programmatic selection, and page alignment
//  through size changes. Simulator-only (gated on UIKit).
//

#if canImport(UIKit)
import SegmentedPagerCore
import Testing
import UIKit

@MainActor
private final class StubPageProvider: PagerPageProviding {
    private(set) var createdIndices: [Int] = []

    func makePageViewController(at index: Int) -> UIViewController {
        createdIndices.append(index)
        return UIViewController()
    }
}

@MainActor
struct PagerContainerTests {
    private static let pageWidth: CGFloat = 390

    private func makeHostedContainer(
        pageCount: Int = 3,
        initialIndex: Int = 0,
        policy: PagerPreloadPolicy = .lazy(visibleRatio: 0.5)
    ) -> (container: PagerContainerViewController, provider: StubPageProvider, window: UIWindow) {
        let provider = StubPageProvider()
        let container = PagerContainerViewController(
            pageCount: pageCount,
            initialIndex: initialIndex,
            preloadPolicy: policy,
            dataSource: provider
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: Self.pageWidth, height: 700))
        window.rootViewController = container
        window.isHidden = false
        window.layoutIfNeeded()
        return (container, provider, window)
    }

    @Test func lazyPolicyCreatesOnlyTheSelectedPage() {
        let (container, provider, _) = makeHostedContainer(initialIndex: 1)
        #expect(provider.createdIndices == [1])
        #expect(container.selectedIndex == 1)
        #expect(container.scrollView.contentOffset.x == Self.pageWidth)
    }

    @Test func eagerPolicyCreatesEveryPage() {
        let (_, provider, _) = makeHostedContainer(initialIndex: 1, policy: .eager)
        #expect(provider.createdIndices == [1, 0, 2])
    }

    @Test func neighborsPolicyCreatesAdjacentPages() {
        let (_, provider, _) = makeHostedContainer(initialIndex: 0, policy: .neighbors)
        #expect(provider.createdIndices == [0, 1])
    }

    @Test func pagesAreProperChildViewControllers() {
        let (container, _, _) = makeHostedContainer(initialIndex: 0)
        let page = container.pageViewController(at: 0)
        #expect(page != nil)
        #expect(page?.parent === container)
        #expect(page?.view.superview === container.scrollView)
        #expect(page?.view.frame == CGRect(x: 0, y: 0, width: Self.pageWidth, height: 700))
    }

    @Test func instantProgrammaticSelectionCreatesTargetAndSettles() {
        let (container, provider, _) = makeHostedContainer(initialIndex: 0)
        var settled: [Int] = []
        var events: [PagerPageEvent] = []
        container.onSelectionSettled = { settled.append($0) }
        container.onPageEvent = { events.append($0) }

        container.setSelectedIndex(2, animated: false)

        #expect(provider.createdIndices == [0, 2])
        #expect(container.selectedIndex == 2)
        #expect(container.scrollView.contentOffset.x == Self.pageWidth * 2)
        #expect(settled == [2])
        #expect(events == [
            .initialize(2),
            .willDisappear(0), .didDisappear(0),
            .willAppear(2), .didAppear(2),
        ])
    }

    @Test func selectingTheCurrentIndexIsANoOp() {
        let (container, provider, _) = makeHostedContainer(initialIndex: 0)
        var settled: [Int] = []
        container.onSelectionSettled = { settled.append($0) }

        container.setSelectedIndex(0, animated: false)

        #expect(provider.createdIndices == [0])
        #expect(settled.isEmpty)
    }

    @Test func outOfRangeSelectionIsIgnored() {
        let (container, _, _) = makeHostedContainer(initialIndex: 0)
        container.setSelectedIndex(9, animated: false)
        #expect(container.selectedIndex == 0)
    }

    @Test func widthChangeRealignsToTheSelectedPage() {
        // Bind the provider: the container's dataSource is weak, and page 1
        // is created after this line.
        let (container, provider, window) = makeHostedContainer(initialIndex: 0)
        container.setSelectedIndex(1, animated: false)
        #expect(provider.createdIndices == [0, 1])

        window.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        window.layoutIfNeeded()

        #expect(container.scrollView.contentOffset.x == 800)
        #expect(container.scrollView.contentSize.width == 2400)
        #expect(container.pageViewController(at: 1)?.view.frame.origin.x == 800)
        #expect(container.selectedIndex == 1)
    }

    @Test func swipeEnabledTogglesScrollability() {
        let (container, _, _) = makeHostedContainer()
        #expect(container.scrollView.isScrollEnabled)
        container.isSwipeEnabled = false
        #expect(container.scrollView.isScrollEnabled == false)
    }
}
#endif
