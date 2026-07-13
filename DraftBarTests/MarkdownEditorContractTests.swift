import XCTest
import MarkdownEngine
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

    func testFormulaBackgroundPreservesBaselineWithPadding() throws {
        let renderer = ContrastLatexRenderer(
            base: StubLatexRenderer(),
            lightBackground: .white,
            darkBackground: .black,
            horizontalPadding: 4,
            verticalPadding: 3
        )

        let result = try XCTUnwrap(renderer.render(latex: "x", fontSize: 17, theme: .default))
        XCTAssertEqual(result.size, CGSize(width: 18, height: 12))
        XCTAssertEqual(result.baselineOffset, 5)
    }
}

private struct StubLatexRenderer: LatexRenderer {
    func render(latex: String, fontSize: CGFloat, theme: MarkdownEditorTheme) -> LatexRenderResult? {
        LatexRenderResult(
            image: NSImage(size: CGSize(width: 10, height: 6)),
            size: CGSize(width: 10, height: 6),
            baselineOffset: 2
        )
    }
}
