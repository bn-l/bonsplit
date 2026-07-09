import XCTest
@testable import Bonsplit

@MainActor
final class EmbeddedConfigurationTests: XCTestCase {
    func testEmbeddedBehaviorControlsAreOptIn() {
        let configuration = BonsplitConfiguration()

        XCTAssertTrue(configuration.allowsTabContextMenu)
        XCTAssertEqual(configuration.dividerPositionRange, 0.1...0.9)
    }

    func testConfiguredDividerRangeAllowsNarrowProgrammaticLayouts() throws {
        let configuration = BonsplitConfiguration(
            allowsTabContextMenu: false,
            dividerPositionRange: 0...1
        )
        let controller = BonsplitController(configuration: configuration)
        let rootPane = try XCTUnwrap(controller.allPaneIds.first)
        XCTAssertNotNil(controller.splitPane(rootPane, orientation: .horizontal))
        guard case .split(let split) = controller.treeSnapshot() else {
            XCTFail("Expected split root")
            return
        }
        let splitID = try XCTUnwrap(UUID(uuidString: split.id))

        XCTAssertTrue(controller.setDividerPosition(0.02, forSplit: splitID))
        guard case .split(let updated) = controller.treeSnapshot() else {
            XCTFail("Expected split root")
            return
        }
        XCTAssertEqual(updated.dividerPosition, 0.02, accuracy: 0.0001)
    }
}
