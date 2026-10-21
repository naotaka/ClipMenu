import XCTest

final class ClipMenuUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSelectingClipFromPopupAutoPastesIntoFocusedField() throws {
        throw XCTSkip("Native popup interaction is covered by the dedicated AX smoke runner in Resources/scripts/run_preview_ax_smoke.sh.")
    }

    @MainActor
    func testStatusPopupPreviewIsVisibleAndDoesNotOverlapPopup() throws {
        throw XCTSkip("Preview geometry is covered by the dedicated AX smoke runner in Resources/scripts/run_preview_ax_smoke.sh.")
    }

    @MainActor
    func testKeyboardPopupPreviewIsVisibleAndDoesNotOverlapPopup() throws {
        throw XCTSkip("Preview geometry is covered by the dedicated AX smoke runner in Resources/scripts/run_preview_ax_smoke.sh.")
    }

    @MainActor
    func testSubmenuPreviewIsVisibleAndDoesNotOverlapMenus() throws {
        throw XCTSkip("Preview geometry is covered by the dedicated AX smoke runner in Resources/scripts/run_preview_ax_smoke.sh.")
    }
}
