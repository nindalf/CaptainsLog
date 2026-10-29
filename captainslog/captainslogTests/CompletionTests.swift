import Foundation
import Testing
import CaptainsLogKit

// Pure string logic, no SwiftData, so parallel execution is fine.
struct MentionQueryTests {
    /// Caret at the end of `text`, which is where typing leaves it.
    private func query(_ text: String) -> CompletionQuery? {
        completionQuery(in: text, caretOffset: text.count)
    }

    @Test func triggerIsReportedAsPerson() {
        #expect(query("@ali")?.trigger == .person)
    }

    @Test func bareAtSignOpensWithAnEmptyPrefix() {
        let result = query("paired with @")
        #expect(result?.prefix == "")
        #expect(result?.start == 12)
        #expect(result?.end == 13)
    }

    @Test func prefixIsWhatFollowsTheAtSign() {
        #expect(query("paired with @ali")?.prefix == "ali")
    }

    @Test func prefixMaySpanASpaceSoSurnamesMatch() {
        // "@Alice Sm" has to be able to reach "Alice Smith".
        #expect(query("@Alice Sm")?.prefix == "Alice Sm")
    }

    @Test func aPrefixEndingInWhitespaceIsNotInProgress() {
        // How an accepted mention is told apart from one being typed. Without this the list
        // reopens the instant a name is inserted, still offering the person just chosen.
        #expect(query("@Alice Smith ") == nil)
        #expect(query("@ali ") == nil)
        #expect(query("@ali\t") == nil)
        // Still mid-name, so still a mention.
        #expect(query("@Alice Sm") != nil)
    }

    @Test func acceptedMentionFollowedByProseShowsNoSuggestions() {
        #expect(query("paired with @Alice Smith ") == nil)
        // Typing on past a completed mention does keep a query alive, since the prefix no longer
        // ends in whitespace. Nothing matches it, so the list stays empty either way.
        let continued = query("paired with @Alice Smith on the backfill")
        #expect(continued != nil)
        #expect(mentionMatchScore(prefix: continued?.prefix ?? "", name: "Alice Smith") == nil)
    }

    @Test func noMentionWithoutAnAtSign() {
        #expect(query("no mention here") == nil)
        #expect(query("") == nil)
    }

    @Test func atSignMustStartAWord() {
        // Email addresses are the case this protects.
        #expect(query("mail james.kirk@larder.co.uk") == nil)
        #expect(query("a@b") == nil)
    }

    @Test func openingBracketsCountAsABoundary() {
        #expect(query("(@ali")?.prefix == "ali")
        #expect(query("[@ali")?.prefix == "ali")
    }

    @Test func mentionCannotSpanLines() {
        #expect(query("@alice\nsecond line") == nil)
    }

    @Test func startOfTextIsABoundary() {
        #expect(query("@ali")?.start == 0)
    }

    @Test func longPrefixesGiveUp() {
        // Past the cap the user is writing prose, not completing a name.
        #expect(query("@\(String(repeating: "x", count: 32))") != nil)
        #expect(query("@\(String(repeating: "x", count: 33))") == nil)
    }

    @Test func caretBeforeTheAtSignIsNotInsideTheMention() {
        #expect(completionQuery(in: "hello @alice", caretOffset: 3) == nil)
    }

    @Test func caretInTheMiddleOfAMentionUsesTextUpToTheCaret() {
        // "@alice" with the caret after "al": complete on "al", not "alice".
        let result = completionQuery(in: "@alice", caretOffset: 3)
        #expect(result?.prefix == "al")
        #expect(result?.end == 3)
    }

    @Test func outOfRangeCaretIsRejected() {
        #expect(completionQuery(in: "@ali", caretOffset: 99) == nil)
        #expect(completionQuery(in: "@ali", caretOffset: -1) == nil)
    }

    @Test func nearestAtSignWins() {
        #expect(query("@bob and @ali")?.prefix == "ali")
    }

    @Test func multiByteTextKeepsOffsetsAligned() {
        // Offsets are character counts, so an emoji must not shift the mention start.
        let result = query("🎉 shipped @ali")
        #expect(result?.prefix == "ali")
        #expect(result?.start == 10)
    }
}

struct MentionMatchScoreTests {
    @Test func emptyPrefixMatchesEveryone() {
        #expect(mentionMatchScore(prefix: "", name: "Alice Smith") == 0)
    }

    @Test func namePrefixOutranksSurnamePrefix() {
        let first = mentionMatchScore(prefix: "al", name: "Alice Smith")
        let surname = mentionMatchScore(prefix: "smi", name: "Alice Smith")
        #expect(first != nil)
        #expect(surname != nil)
        #expect(first! < surname!)
    }

    @Test func surnamePrefixOutranksHandle() {
        let surname = mentionMatchScore(prefix: "smi", name: "Alice Smith")
        let handle = mentionMatchScore(prefix: "asmith", name: "Alice Smith", handles: ["asmith"])
        #expect(surname! < handle!)
    }

    @Test func handleOutranksMidWordSubstring() {
        let handle = mentionMatchScore(prefix: "asm", name: "Alice Smith", handles: ["asmith"])
        let substring = mentionMatchScore(prefix: "lice", name: "Alice Smith")
        #expect(handle! < substring!)
    }

    @Test func matchingIsCaseInsensitive() {
        #expect(mentionMatchScore(prefix: "ALI", name: "Alice Smith") == 0)
        #expect(mentionMatchScore(prefix: "ali", name: "ALICE SMITH") == 0)
    }

    @Test func nonMatchScoresNil() {
        #expect(mentionMatchScore(prefix: "zzz", name: "Alice Smith") == nil)
    }

    @Test func nilHandlesAreSkipped() {
        #expect(mentionMatchScore(prefix: "asm", name: "Alice Smith", handles: [nil, nil]) == nil)
        #expect(mentionMatchScore(prefix: "asm", name: "Alice Smith", handles: [nil, "asmith"]) == 2)
    }

    @Test func surroundingWhitespaceInThePrefixIsIgnored() {
        // Defensive only: `completionQuery` will not hand out a prefix with edge whitespace.
        #expect(mentionMatchScore(prefix: "Alice ", name: "Alice Smith") == 0)
    }
}

// MARK: - Pull requests

struct PullRequestQueryTests {
    private func query(_ text: String) -> CompletionQuery? {
        completionQuery(in: text, caretOffset: text.count)
    }

    @Test func hashOpensAPullRequestCompletion() {
        let result = query("caused by #45")
        #expect(result?.trigger == .pullRequest)
        #expect(result?.prefix == "45")
        #expect(result?.start == 10)
    }

    @Test func bareHashOpensWithAnEmptyPrefix() {
        #expect(query("caused by #")?.prefix == "")
    }

    @Test func hashAtTheStartOfTextIsAPullRequest() {
        // `#4521` is not a valid ATX heading (no space after the hash), so it is unambiguous.
        #expect(query("#4521")?.trigger == .pullRequest)
    }

    // MARK: markdown headings must stay inert

    @Test func atxHeadingsDoNotOpenAList() {
        // The prefix would start with whitespace, which is not a completion in progress.
        #expect(query("# Heading editing works") == nil)
        #expect(query("# ") == nil)
    }

    @Test func multiHashHeadingsDoNotOpenAList() {
        // The nearest hash is preceded by another hash, so it does not start a word.
        #expect(query("## Key themes") == nil)
        #expect(query("### Deeper") == nil)
        #expect(query("##") == nil)
    }

    @Test func headingsMidNoteStayInert() {
        #expect(query("intro\n\n## Key themes") == nil)
    }

    @Test func aPullRequestInsideAHeadingStillCompletes() {
        // The hash before 4521 is preceded by a space, so it is a word start.
        let result = query("## Follow-up to #4521")
        #expect(result?.trigger == .pullRequest)
        #expect(result?.prefix == "4521")
    }

    @Test func trailingSpaceClosesAnAcceptedPullRequest() {
        #expect(query("caused by #4521 ") == nil)
    }

    @Test func bothTriggersCoexistAndTheNearestWins() {
        #expect(query("@ali reviewed #45")?.trigger == .pullRequest)
        #expect(query("#45 reviewed by @ali")?.trigger == .person)
    }
}

struct PullRequestMatchScoreTests {
    @Test func emptyPrefixMatchesEverything() {
        #expect(pullRequestMatchScore(prefix: "", number: 4521, title: "Add backfill") == 0)
    }

    @Test func numericPrefixMatchesTheNumber() {
        #expect(pullRequestMatchScore(prefix: "45", number: 4521, title: "Add backfill") == 0)
        #expect(pullRequestMatchScore(prefix: "4521", number: 4521, title: "Add backfill") == 0)
        #expect(pullRequestMatchScore(prefix: "99", number: 4521, title: "Add backfill") == nil)
    }

    @Test func numberOutranksTitle() {
        let byNumber = pullRequestMatchScore(prefix: "45", number: 4521, title: "Add backfill")
        let byTitle = pullRequestMatchScore(prefix: "add", number: 4521, title: "Add backfill")
        #expect(byNumber! < byTitle!)
    }

    @Test func titlePrefixOutranksWordAndSubstring() {
        let leading = pullRequestMatchScore(prefix: "add", number: 1, title: "Add multibuy backfill")
        let word = pullRequestMatchScore(prefix: "multi", number: 1, title: "Add multibuy backfill")
        let substring = pullRequestMatchScore(prefix: "buy", number: 1, title: "Add multibuy backfill")
        #expect(leading! < word!)
        #expect(word! < substring!)
    }

    @Test func repoIsSearchable() {
        let score = pullRequestMatchScore(
            prefix: "ledger", number: 1, title: "Add backfill", repo: "larder/ledger")
        #expect(score != nil)
    }

    @Test func matchingIsCaseInsensitive() {
        #expect(pullRequestMatchScore(prefix: "ADD", number: 1, title: "Add backfill") == 1)
    }

    @Test func nonMatchScoresNil() {
        #expect(pullRequestMatchScore(prefix: "zzz", number: 4521, title: "Add backfill") == nil)
    }
}

struct PullRequestOrderTests {
    /// Sort a set of (score, number) rows the way the suggestion list does.
    private func ordered(_ rows: [(score: Int, number: Int)]) -> [Int] {
        rows.sorted(by: pullRequestSuggestionPrecedes).map(\.number)
    }

    @Test func equalScoresSortByNumberDescending() {
        // The bare `#` case: every row scores 0, so this is the whole ordering.
        #expect(ordered([(0, 45), (0, 4521), (0, 900)]) == [4521, 900, 45])
    }

    @Test func betterMatchesStillLeadRegardlessOfNumber() {
        // A number-prefix match beats a title match even when the title match is newer.
        #expect(ordered([(4, 9999), (0, 45)]) == [45, 9999])
    }

    @Test func tiersGroupFirstAndNumbersDescendWithinEach() {
        // Tier 0 descending (30, 7), then tier 1 descending (4521, 10).
        #expect(ordered([(1, 10), (1, 4521), (0, 30), (0, 7)]) == [30, 7, 4521, 10])
    }
}

struct CompletionInsertionTests {
    @Test func mentionInsertsTheSlackHandle() {
        #expect(mentionInsertion(name: "Alice Smith", slackHandle: "asmith") == "@asmith ")
        #expect(mentionInsertion(name: "Alice Smith", slackHandle: "@asmith") == "@asmith ")
    }

    @Test func mentionFallsBackToTheNameWithoutAHandle() {
        #expect(mentionInsertion(name: "Alice Smith", slackHandle: nil) == "@Alice Smith ")
        #expect(mentionInsertion(name: "Alice Smith", slackHandle: " ") == "@Alice Smith ")
    }

    @Test func pullRequestInsertsTheBareNumber() {
        #expect(pullRequestInsertion(number: 4521) == "#4521 ")
    }
}

struct PossessiveJoinTests {
    private func joined(_ text: String) -> String? {
        guard let join = possessiveJoin(in: text, caretOffset: text.count) else { return nil }
        var characters = Array(text)
        characters.replaceSubrange(join.start..<(join.start + 2), with: Array(join.replacement))
        return String(characters)
    }

    @Test func possessiveSAttachesToTheTag() {
        #expect(joined("paired with @asmith 's") == "paired with @asmith's")
        #expect(joined("#4521 's") == "#4521's")
    }

    @Test func bareApostropheAttachesOnceTheSpaceIsTyped() {
        #expect(joined("@james ' ") == "@james' ")
        #expect(joined("@james '") == nil)
    }

    @Test func aNameWithSpacesCountsAsATag() {
        #expect(joined("@Alice Smith 's") == "@Alice Smith's")
    }

    @Test func curlyApostrophesBecomeClosingOnes() {
        #expect(joined("@asmith \u{2018}s") == "@asmith\u{2019}s")
        #expect(joined("@asmith \u{2019}s") == "@asmith\u{2019}s")
    }

    @Test func onlyAfterATag() {
        #expect(joined("the cat 's") == nil)
        #expect(joined("james.kirk@larder.co.uk 's") == nil)
        #expect(joined("@ 's") == nil)
        #expect(joined("# Heading 's") == nil)
        #expect(joined("@asmith  's") == nil)
    }

    @Test func onlyWhenTheCaretIsRightAfterIt() {
        #expect(possessiveJoin(in: "@asmith 's", caretOffset: 9) == nil)
        #expect(possessiveJoin(in: "@asmith 's here", caretOffset: 10)?.start == 7)
    }
}

struct PunctuationJoinTests {
    private func joined(_ text: String) -> String? {
        guard let space = punctuationJoin(in: text, caretOffset: text.count) else { return nil }
        var characters = Array(text)
        characters.remove(at: space)
        return String(characters)
    }

    @Test func punctuationAttachesToTheTag() {
        #expect(joined("@Picard ?") == "@Picard?")
        #expect(joined("thanks @asmith ,") == "thanks @asmith,")
        #expect(joined("@Alice Smith .") == "@Alice Smith.")
        #expect(joined("@asmith !") == "@asmith!")
        #expect(joined("@asmith ;") == "@asmith;")
        #expect(joined("#4521 .") == "#4521.")
    }

    @Test func onlyThePunctuationThatClosesASentenceOrClause() {
        #expect(joined("@asmith :") == nil)
        #expect(joined("@asmith )") == nil)
        #expect(joined("@asmith -") == nil)
    }

    @Test func onlyAfterATag() {
        #expect(joined("the cat ?") == nil)
        #expect(joined("james.kirk@larder.co.uk .") == nil)
        #expect(joined("@ ?") == nil)
        #expect(joined("# Heading .") == nil)
        #expect(joined("@asmith  ?") == nil)
        #expect(joined("@asmith?") == nil)
    }

    @Test func onlyWhenTheCaretIsRightAfterIt() {
        #expect(punctuationJoin(in: "@asmith ?", caretOffset: 8) == nil)
        #expect(punctuationJoin(in: "@asmith ? here", caretOffset: 9) == 7)
    }
}
