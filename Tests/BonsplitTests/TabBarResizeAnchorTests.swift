import AppKit
@testable import Bonsplit
import SwiftUI
import XCTest

@MainActor
final class TabBarResizeAnchorTests: XCTestCase {
    func testViewportResizeKeepsLeadingAnchoredWhenTabStripWasLeadingAligned() throws {
        let harness = try makeTabBarHarness(
            initialSize: NSSize(width: 900, height: TabBarMetrics.barHeight),
            tabCount: 8,
            selectedIndex: 2
        )
        defer { harness.window.orderOut(nil) }

        let scrollView = try XCTUnwrap(firstDescendant(ofType: NSScrollView.self, in: harness.hostingView))
        XCTAssertEqual(scrollView.contentView.bounds.origin.x, 0, accuracy: 0.5)

        harness.window.setContentSize(NSSize(width: 240, height: TabBarMetrics.barHeight))
        harness.hostingView.frame = harness.window.contentView?.bounds ?? harness.hostingView.frame
        settleLayout(in: harness.window, hostingView: harness.hostingView)

        XCTAssertEqual(
            scrollView.contentView.bounds.origin.x,
            0,
            accuracy: 0.5,
            "A pure pane/window resize must preserve the leading tab-strip anchor instead of recentering the selected tab and shifting icons."
        )
    }

    private struct TabBarHarness {
        let window: NSWindow
        let hostingView: NSView
    }

    private func makeTabBarHarness(
        initialSize: NSSize,
        tabCount: Int,
        selectedIndex: Int
    ) throws -> TabBarHarness {
        let controller = BonsplitController(configuration: BonsplitConfiguration(appearance: .default))
        controller.tabShortcutHintsEnabled = false
        let pane = try XCTUnwrap(controller.internalController.rootNode.allPanes.first)

        let tabs = (0..<tabCount).map { index in
            TabItem(title: "Terminal \(index + 1)", icon: "terminal.fill", kind: "terminal")
        }
        pane.tabs = tabs
        pane.selectedTabId = tabs[selectedIndex].id

        let hostingView = NSHostingView(
            rootView: TabBarView(pane: pane, isFocused: true, showSplitButtons: false)
                .environment(controller)
                .environment(controller.internalController)
        )
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        let contentView = try XCTUnwrap(window.contentView)
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.frame = NSRect(origin: .zero, size: initialSize)
        hostingView.autoresizingMask = [.width, .height]
        contentView.addSubview(hostingView)

        window.makeKeyAndOrderFront(nil)
        settleLayout(in: window, hostingView: hostingView)

        return TabBarHarness(window: window, hostingView: hostingView)
    }

    private func settleLayout(in window: NSWindow, hostingView: NSView) {
        window.contentView?.layoutSubtreeIfNeeded()
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        window.contentView?.layoutSubtreeIfNeeded()
        hostingView.layoutSubtreeIfNeeded()
    }

    private func firstDescendant<T: NSView>(ofType type: T.Type, in root: NSView) -> T? {
        if let match = root as? T {
            return match
        }
        for subview in root.subviews {
            if let match = firstDescendant(ofType: type, in: subview) {
                return match
            }
        }
        return nil
    }
}
