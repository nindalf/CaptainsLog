import Testing
import CaptainsLogKit

struct MarkdownPreviewTests {
    @Test func inlineMarkersAreDropped() {
        #expect(markdownPreview("Met **Alice**, _agreed_ on `v2` and ~~v1~~") == "Met Alice, agreed on v2 and v1")
    }

    @Test func linksKeepTheirText() {
        #expect(markdownPreview("See [the RFC](https://example.com/rfc) first") == "See the RFC first")
    }

    @Test func blocksJoinOnOneLine() {
        let source = "# Handover\n\nSystems:\n- Screening (Tom)\n- Alerts\n\n> keep it short"
        #expect(markdownPreview(source) == "Handover Systems: Screening (Tom) Alerts keep it short")
    }

    @Test func mentionsAndPlainTextSurvive() {
        #expect(markdownPreview("Ask @priya about #412") == "Ask @priya about #412")
        #expect(markdownPreview("") == "")
    }
}
