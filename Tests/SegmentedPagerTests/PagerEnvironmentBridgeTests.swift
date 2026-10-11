//
//  PagerEnvironmentBridgeTests.swift
//  SegmentedPagerTests
//
//  Created by yousanflics on 7/1/26.
//
//  Asserts that SwiftUI Environment values set on the host hierarchy
//  cross the UIHostingController boundary into page content.
//

#if canImport(UIKit)
import SegmentedPagerUI
import SwiftUI
import Testing
import UIKit

private struct BridgeProbeKey: EnvironmentKey {
    static let defaultValue = "unbridged"
}

extension EnvironmentValues {
    fileprivate var bridgeProbe: String {
        get { self[BridgeProbeKey.self] }
        set { self[BridgeProbeKey.self] = newValue }
    }
}

@MainActor
private final class BridgeCapture {
    var value = ""
    var isActiveValues: [Bool] = []
    var colorSchemes: [ColorScheme] = []
    var capturedValues: [String] = []
}

@MainActor
@Observable
private final class BridgeDriver {
    var colorScheme: ColorScheme = .light
    var captured = "first"
}

/// A page that renders a value the host captured by value in the page
/// closure (not observed inside the page).
private struct BridgeCapturedPage: View {
    let value: String
    let capture: BridgeCapture

    var body: some View {
        Color.clear
            .onAppear { capture.capturedValues.append(value) }
            .onChange(of: value) { _, newValue in capture.capturedValues.append(newValue) }
    }
}

private struct BridgeCapturedHost: View {
    let driver: BridgeDriver
    let capture: BridgeCapture
    /// `nil`: default behaviour. Otherwise the key the host vouches with.
    let contentKey: (BridgeDriver) -> AnyHashable?

    var body: some View {
        let captured = driver.captured
        SegmentedPager(
            tabs: [0, 1],
            selection: .constant(0),
            title: { "\($0)" },
            page: { _ in BridgeCapturedPage(value: captured, capture: capture) }
        )
        .pagerContentKey(contentKey(driver))
    }
}

private struct BridgeSchemeProbePage: View {
    @Environment(\.colorScheme) private var colorScheme
    let capture: BridgeCapture

    var body: some View {
        Color.clear
            .onAppear { capture.colorSchemes.append(colorScheme) }
            .onChange(of: colorScheme) { _, newValue in capture.colorSchemes.append(newValue) }
    }
}

/// Hosts the pager under a driver-controlled colour scheme.
private struct BridgeSchemeHost: View {
    let driver: BridgeDriver
    let capture: BridgeCapture

    var body: some View {
        SegmentedPager(
            tabs: [0, 1],
            selection: .constant(0),
            title: { "\($0)" },
            page: { _ in BridgeSchemeProbePage(capture: capture) }
        )
        .environment(\.colorScheme, driver.colorScheme)
    }
}

private struct BridgeProbePage: View {
    @Environment(\.bridgeProbe) private var bridgeProbe
    @Environment(\.pagerPageIsActive) private var isActive
    let capture: BridgeCapture

    var body: some View {
        Color.clear
            .onAppear {
                capture.value = bridgeProbe
                capture.isActiveValues.append(isActive)
            }
            .onChange(of: isActive) { _, newValue in
                capture.isActiveValues.append(newValue)
            }
    }
}

@MainActor
struct PagerEnvironmentBridgeTests {
    @Test func customEnvironmentValueReachesPageContent() {
        let capture = BridgeCapture()
        let pager = SegmentedPager(
            tabs: [0, 1],
            selection: .constant(0),
            title: { "\($0)" },
            page: { _ in BridgeProbePage(capture: capture) }
        )
        .environment(\.bridgeProbe, "bridged")

        let hosting = UIHostingController(rootView: pager)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        window.rootViewController = hosting
        window.isHidden = false
        window.layoutIfNeeded()

        // Page hosting controllers render on the next run loop turns.
        let deadline = Date().addingTimeInterval(2)
        while capture.value.isEmpty, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            window.layoutIfNeeded()
        }

        #expect(capture.value == "bridged")
    }

    /// The host model no longer observes the bridged environment wholesale
    /// (that re-evaluated every page on every pager update); a change of an
    /// observable trait must still reach a mounted page.
    @Test func colorSchemeChangeAfterMountReachesPageContent() {
        let capture = BridgeCapture()
        let driver = BridgeDriver()
        let hosting = UIHostingController(rootView: BridgeSchemeHost(driver: driver, capture: capture))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        window.rootViewController = hosting
        window.isHidden = false
        window.layoutIfNeeded()

        let deadline = Date().addingTimeInterval(2)
        while capture.colorSchemes.isEmpty, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            window.layoutIfNeeded()
        }
        #expect(capture.colorSchemes.last == .light)

        driver.colorScheme = .dark
        let deadline2 = Date().addingTimeInterval(2)
        while capture.colorSchemes.last != .dark, Date() < deadline2 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            window.layoutIfNeeded()
        }
        #expect(capture.colorSchemes.last == .dark)
    }

    /// Without a content key every pager update re-evaluates the pages, so
    /// a value captured by the page closure reaches a mounted page.
    @Test func capturedInputReachesMountedPageWithoutContentKey() {
        let capture = BridgeCapture()
        let driver = BridgeDriver()
        let window = mount(BridgeCapturedHost(driver: driver, capture: capture, contentKey: { _ in nil }))
        waitUntil(window) { !capture.capturedValues.isEmpty }
        #expect(capture.capturedValues.last == "first")

        driver.captured = "second"
        waitUntil(window) { capture.capturedValues.last == "second" }
        #expect(capture.capturedValues.last == "second")
    }

    /// With a content key the pages re-evaluate when the key changes …
    @Test func capturedInputReachesMountedPageWhenContentKeyChanges() {
        let capture = BridgeCapture()
        let driver = BridgeDriver()
        let window = mount(BridgeCapturedHost(driver: driver, capture: capture, contentKey: { $0.captured }))
        waitUntil(window) { !capture.capturedValues.isEmpty }

        driver.captured = "second"
        waitUntil(window) { capture.capturedValues.last == "second" }
        #expect(capture.capturedValues.last == "second")
    }

    /// … and not otherwise: that is the trade-off the key documents.
    @Test func constantContentKeyKeepsMountedPageUntouched() {
        let capture = BridgeCapture()
        let driver = BridgeDriver()
        let window = mount(BridgeCapturedHost(driver: driver, capture: capture, contentKey: { _ in "constant" }))
        waitUntil(window) { !capture.capturedValues.isEmpty }

        driver.captured = "second"
        waitUntil(window, timeout: 0.5) { capture.capturedValues.last == "second" }
        #expect(capture.capturedValues.last == "first")
    }

    private func mount(_ root: some View) -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        window.rootViewController = UIHostingController(rootView: root)
        window.isHidden = false
        window.layoutIfNeeded()
        return window
    }

    private func waitUntil(_ window: UIWindow, timeout: TimeInterval = 2, _ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            window.layoutIfNeeded()
        }
    }

    @Test func activePageSeesPagerPageIsActive() {
        let capture = BridgeCapture()
        let pager = SegmentedPager(
            tabs: [0, 1],
            selection: .constant(0),
            title: { "\($0)" },
            page: { _ in BridgeProbePage(capture: capture) }
        )

        let hosting = UIHostingController(rootView: pager)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        window.rootViewController = hosting
        window.isHidden = false
        window.layoutIfNeeded()

        let deadline = Date().addingTimeInterval(2)
        while capture.isActiveValues.isEmpty, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            window.layoutIfNeeded()
        }

        // The selected page is active by the time it first renders (its
        // didAppear fires during container setup, before SwiftUI's first
        // render commit) or immediately after; either way the value must
        // be observable as true once rendered.
        let deadline2 = Date().addingTimeInterval(2)
        while capture.isActiveValues.last != true, Date() < deadline2 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        #expect(capture.isActiveValues.last == true)
    }
}
#endif
