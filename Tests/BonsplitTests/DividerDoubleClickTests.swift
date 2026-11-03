import AppKit
import Testing
@testable import Bonsplit

/// A divider double-click released without dragging is offered to the host
/// (`splitTabBar(_:didDoubleClickDivider:)`); every other press keeps AppKit's
/// native divider tracking. Adapted from upstream manaflow-ai/bonsplit
/// 5925806a + 58b73fde onto this fork's closure seam.
@Suite("Divider double click", .serialized)
@MainActor
struct DividerDoubleClickTests {
    private final class Delegate: BonsplitDelegate {
        var splitIds: [UUID] = []
        var handled = true
        var onDoubleClick: (() -> Void)?

        func splitTabBar(_ controller: BonsplitController, didDoubleClickDivider splitId: UUID) -> Bool {
            splitIds.append(splitId)
            onDoubleClick?()
            return handled
        }
    }

    /// Replays a scripted follow-up event and records what the split view did.
    private final class PointerSplitView: ThemedSplitView {
        var pointerEvent: NSEvent?
        var nativeTrackingCount = 0
        var consumedCount = 0
        var dequeueWindows: [NSWindow?] = []

        override func trackDivider(with event: NSEvent) { nativeTrackingCount += 1 }
        override func nextDividerEvent(in window: NSWindow?, dequeue: Bool) -> NSEvent? {
            if dequeue {
                consumedCount += 1
                dequeueWindows.append(window)
            }
            return pointerEvent
        }
    }

    @Test(arguments: [SplitOrientation.horizontal, .vertical])
    func releasedDoubleClickIsOfferedToTheHostOnce(orientation: SplitOrientation) throws {
        try exercise(orientation: orientation, clickCount: 2, drag: false, handled: true)
    }

    @Test(arguments: [1, 3])
    func otherClickCountsKeepNativeTracking(clickCount: Int) throws {
        try exercise(orientation: .horizontal, clickCount: clickCount, drag: false, handled: true)
    }

    @Test func doubleClickThatTurnsIntoADragResizesNormally() throws {
        try exercise(orientation: .horizontal, clickCount: 2, drag: true, handled: true)
    }

    @Test func unhandledDoubleClickKeepsNativeTracking() throws {
        try exercise(orientation: .horizontal, clickCount: 2, drag: false, handled: false)
    }

    @Test func releaseIsDequeuedFromTheCapturedWindowWhenTheHostDetachesTheView() throws {
        // Arrange
        let (controller, delegate, splitId) = try makeSplit(orientation: .horizontal)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        let splitView = PointerSplitView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        splitView.addArrangedSubview(NSView())
        splitView.addArrangedSubview(NSView())
        splitView.onDividerDoubleClick = Self.handler(controller, splitId)
        window.contentView?.addSubview(splitView)
        // Equalizing can rebuild the split hierarchy; model that as the view leaving its window.
        delegate.onDoubleClick = { [weak splitView] in splitView?.removeFromSuperview() }
        let down = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: .zero,
            modifierFlags: [], timestamp: 1, windowNumber: window.windowNumber, context: nil,
            eventNumber: 1, clickCount: 2, pressure: 1))
        splitView.pointerEvent = try #require(NSEvent.mouseEvent(with: .leftMouseUp, location: .zero,
            modifierFlags: [], timestamp: 1.1, windowNumber: window.windowNumber, context: nil,
            eventNumber: 2, clickCount: 2, pressure: 0))

        // Act
        splitView.mouseDown(with: down)

        // Assert
        #expect(splitView.window == nil)
        #expect(splitView.consumedCount == 1)
        #expect(splitView.dequeueWindows.count == 1)
        #expect(splitView.dequeueWindows.first.map { $0 === window } == true)
    }

    @Test func withoutAHostHandlerEveryPressKeepsNativeTracking() throws {
        let splitView = PointerSplitView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        splitView.addArrangedSubview(NSView())
        splitView.addArrangedSubview(NSView())
        let down = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: .zero,
            modifierFlags: [], timestamp: 1, windowNumber: 0, context: nil,
            eventNumber: 1, clickCount: 2, pressure: 1))

        splitView.mouseDown(with: down)

        #expect(splitView.nativeTrackingCount == 1)
        #expect(splitView.consumedCount == 0)
    }

    // MARK: - Helpers

    /// The same closure `SplitContainerView` installs.
    private static func handler(_ controller: BonsplitController, _ splitId: UUID) -> () -> Bool {
        { controller.delegate?.splitTabBar(controller, didDoubleClickDivider: splitId) == true }
    }

    private func makeSplit(orientation: SplitOrientation) throws -> (BonsplitController, Delegate, UUID) {
        let controller = BonsplitController()
        let delegate = Delegate()
        controller.delegate = delegate
        let pane = try #require(controller.focusedPaneId)
        _ = try #require(controller.splitPane(pane, orientation: orientation))
        guard case .split(let state) = controller.internalController.rootNode else {
            Issue.record("Expected a split")
            throw CancellationError()
        }
        return (controller, delegate, state.id)
    }

    private func exercise(orientation: SplitOrientation, clickCount: Int, drag: Bool, handled: Bool) throws {
        // Arrange
        let (controller, delegate, splitId) = try makeSplit(orientation: orientation)
        delegate.handled = handled
        let splitView = PointerSplitView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        splitView.isVertical = orientation == .horizontal
        splitView.addArrangedSubview(NSView())
        splitView.addArrangedSubview(NSView())
        splitView.onDividerDoubleClick = Self.handler(controller, splitId)
        let down = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: .zero,
            modifierFlags: [], timestamp: 1, windowNumber: 0, context: nil,
            eventNumber: 1, clickCount: clickCount, pressure: 1))
        splitView.pointerEvent = try #require(NSEvent.mouseEvent(
            with: drag ? .leftMouseDragged : .leftMouseUp, location: .zero,
            modifierFlags: [], timestamp: 1.1, windowNumber: 0, context: nil,
            eventNumber: 2, clickCount: clickCount, pressure: 0))

        // Act
        splitView.mouseDown(with: down)

        // Assert
        let offered = clickCount == 2 && !drag
        #expect(delegate.splitIds == (offered ? [splitId] : []))
        #expect(splitView.nativeTrackingCount == (offered && handled ? 0 : 1))
        #expect(splitView.consumedCount == (offered && handled ? 1 : 0))
        #expect(controller.allPaneIds.count == 2)
    }
}
