//
//  PagerEnvironmentBridgeTests.swift
//  SegmentedPagerTests
//
//  Asserts that SwiftUI Environment values set on the host hierarchy
//  cross the UIHostingController boundary into page content (design doc
//  §6.5) — the classic failure mode of hosted-page architectures.
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
