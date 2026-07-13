import XCTest
@testable import DraftBar

@MainActor
final class MarkdownEditorContractTests: XCTestCase {
    func testBindingRoundTripAndMarkedTextProtection() {
        let adapter = MarkdownTextBindingAdapter(text: "initial")
        var modelText = "initial"

        adapter.receiveEditorText("edited") { modelText = $0 }
        XCTAssertEqual(modelText, "edited")
        XCTAssertEqual(adapter.editorText, "edited")

        adapter.receiveExternalText("external")
        XCTAssertEqual(adapter.editorText, "external")

        adapter.setMarkedTextActive(true)
        adapter.receiveExternalText("must not replace composition")
        XCTAssertEqual(adapter.editorText, "external")
    }

    func testImageURLResolutionStaysLocal() {
        let baseURL = URL(fileURLWithPath: "/tmp/draftbar-note", isDirectory: true)

        XCTAssertEqual(
            MarkdownImageURLResolver.localURL(for: "images/example.png", relativeTo: baseURL)?.path,
            "/tmp/draftbar-note/images/example.png"
        )
        XCTAssertNil(
            MarkdownImageURLResolver.localURL(for: "https://example.com/image.png", relativeTo: baseURL)
        )
    }
}
