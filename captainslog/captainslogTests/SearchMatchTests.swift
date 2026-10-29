import Testing
import CaptainsLogKit

struct SearchMatchTests {
    @Test func reportsTheFirstFieldInOrderThatMatches() {
        let match = SearchMatch.first("runbook", in: [("title", "Handover"), ("notes", nil), ("summary", "Send the runbook"), ("transcript", "runbook")])
        #expect(match == SearchMatch(field: "summary", snippet: "Send the runbook"))
    }

    @Test func ignoresCaseAndDiacritics() {
        #expect(SearchMatch.first("CAFE", in: [("notes", "Met at the café")])?.field == "notes")
    }

    @Test func noFieldMatchingIsNil() {
        #expect(SearchMatch.first("absent", in: [("title", "Handover"), ("notes", nil)]) == nil)
    }

    @Test func aMatchDeepInLongTextIsInTheSnippetWithEllipsesAtBothCuts() {
        let text = String(repeating: "a ", count: 200) + "needle" + String(repeating: " b", count: 200)
        let snippet = SearchMatch.first("needle", in: [("notes", text)], length: 40)!.snippet
        #expect(snippet.hasPrefix("…"))
        #expect(snippet.hasSuffix("…"))
        #expect(snippet.contains("needle"))
    }

    @Test func collapsesWhitespaceAndLeavesShortTextUncut() {
        #expect(SearchMatch.first("two", in: [("notes", "one\n\ntwo   three")])?.snippet == "one two three")
    }

    @Test func matchesOnlyAtTheStartOfAWord() {
        #expect(SearchMatch.first("tom", in: [("notes", "No customer impact")]) == nil)
        #expect(SearchMatch.first("tom", in: [("notes", "Paired with Tom")])?.snippet == "Paired with Tom")
        #expect(SearchMatch.first("861", in: [("number", "#861")]) != nil)
    }

    @Test func everyWordMustAppearButNotInTheSameField() {
        let fields: [(name: String, text: String?)] = [("title", "Handover"), ("notes", "Send the runbook")]
        #expect(SearchMatch.first("handover runbook", in: fields)?.field == "title")
        #expect(SearchMatch.first("handover vendor", in: fields) == nil)
    }

    @Test func reportsTheFieldHoldingTheMostWords() {
        let fields: [(name: String, text: String?)] = [("title", "Screening sync"), ("notes", "Tom walked through screening")]
        #expect(SearchMatch.first("screening tom", in: fields)?.field == "notes")
    }

    @Test func aMatchNearTheEndOfShortTextDoesNotCutTheStart() {
        let text = "Knowledge transfer: screening service walkthrough with Tom"
        #expect(SearchMatch.first("tom", in: [("title", text)], length: 200)?.snippet == text)
    }

    @Test func termsSplitOnWhitespaceAndDropRepeats() {
        #expect(SearchMatch.terms(of: "  Tom  tom\tTÓM runbook ") == ["Tom", "runbook"])
    }

    @Test func highlightsEveryWordStartAndMergesOverlaps() {
        let text = "Tom and Tomas, not customer"
        let ranges = SearchMatch.wordStarts(of: ["tom", "toma"], in: text)
        #expect(ranges.map { String(text[$0]) } == ["Tom", "Toma"])
    }

    @Test func cutsFallBetweenWords() {
        let text = "alpha bravo charlie delta echo foxtrot golf hotel india juliet"
        let snippet = SearchMatch.first("golf", in: [("notes", text)], length: 24)!.snippet
        #expect(snippet == "…golf hotel india…")
    }
}
