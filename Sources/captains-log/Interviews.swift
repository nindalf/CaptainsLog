import ArgumentParser
import CaptainsLogKit
import Foundation
import SwiftData

struct Interviews: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Manage interviews",
        subcommands: [List.self, Add.self, Edit.self],
        defaultSubcommand: List.self
    )

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List interviews"
        )

        @Option(name: .long, help: "Start date (ISO 8601, e.g. 2026-04-01)")
        var from: String?

        @Option(name: .long, help: "End date, inclusive (ISO 8601, e.g. 2026-05-02)")
        var to: String?

        @Option(name: .long, help: "Filter by candidate name")
        var candidate: String?

        @Option(name: .long, help: "Filter by recommendation: yes, no, strongYes, definitelyNot")
        var recommendation: String?

        @Flag(name: .long, help: "Pretty-print JSON output")
        var pretty: Bool = false

        mutating func run() async throws {
            if let recommendation, Recommendation(rawValue: recommendation) == nil {
                throw ValidationError("Invalid recommendation '\(recommendation)'. Use: yes, no, strongYes, definitelyNot")
            }

            let container = try Store.makeContainer()
            let context = ModelContext(container)

            let range = try CLIDate.range(from: from, to: to, defaultFrom: .distantPast, defaultTo: .distantFuture)
            let start = range.lowerBound
            let end = range.upperBound

            let descriptor = FetchDescriptor<Interview>(
                predicate: #Predicate { $0.date >= start && $0.date < end },
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
            var interviews = try context.fetch(descriptor)

            if let candidate {
                interviews = interviews.filter {
                    $0.candidateName.localizedCaseInsensitiveContains(candidate)
                }
            }
            if let recommendation {
                interviews = interviews.filter {
                    $0.recommendation?.rawValue == recommendation
                }
            }

            try printJSON(interviews.map(InterviewDTO.from), pretty: pretty)
        }
    }

    struct Add: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Add an interview, as the app's New Interview form does"
        )

        @Argument(help: "Candidate name")
        var candidate: String

        @Option(name: .long, help: "Role")
        var role: String?

        @Option(name: .long, help: "Date (ISO 8601, e.g. 2026-05-05). Defaults to now")
        var date: String?

        @Option(name: .long, help: "Problem name")
        var problem: String?

        @Flag(name: .long, help: "Pretty-print JSON output")
        var pretty: Bool = false

        func validate() throws {
            if candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ValidationError("Candidate name can't be empty")
            }
        }

        mutating func run() async throws {
            let date = try date.map(CLIDate.day) ?? .now
            let context = ModelContext(try Store.makeContainer())
            let interview = Interview(
                date: date,
                candidateName: candidate.trimmingCharacters(in: .whitespacesAndNewlines),
                role: role.flatMap(TextInput.field)
            )
            interview.problemName = problem.flatMap(TextInput.field)
            context.insert(interview)
            try context.save()

            try printJSON(InterviewDetail.from(interview, todos: (interview.todos ?? []).filter { !$0.isTrashed }.sorted { $0.sortOrder < $1.sortOrder }), pretty: pretty)
        }
    }

    struct Edit: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Change any section of an interview",
            discussion: "An empty value clears a field, as emptying it in the app does. Pass - to read one value from stdin."
        )

        @Argument(help: "Interview UUID")
        var id: String

        @Option(name: .long, help: "Candidate name")
        var candidate: String?

        @Option(name: .long, help: "Role")
        var role: String?

        @Option(name: .long, help: "Date (ISO 8601, e.g. 2026-05-05)")
        var date: String?

        @Option(name: .long, help: "Problem name")
        var problem: String?

        @Option(name: .long, help: "Whiteboard link")
        var whiteboard: String?

        @Option(name: .long, help: "Raw notes (markdown)")
        var rawNotes: String?

        @Option(name: .long, help: "Upsides (markdown)")
        var upsides: String?

        @Option(name: .long, help: "Risk factors (markdown)")
        var riskFactors: String?

        @Option(name: .long, help: "Level assessment")
        var level: String?

        @Option(name: .long, help: "Recommendation: yes, no, strongYes, definitelyNot. Empty clears it")
        var recommendation: String?

        @Option(name: .long, help: "Conclusion (markdown)")
        var conclusion: String?

        @Option(name: .long, help: "Debrief date (ISO 8601). Empty clears it")
        var debriefDate: String?

        @Option(name: .long, help: "Debrief notes (markdown)")
        var debriefNotes: String?

        @Flag(name: .customLong("private"), inversion: .prefixedNo, help: "Make it private, or not, as the app's lock does")
        var isPrivate: Bool?

        @Flag(name: .long, help: "Pretty-print JSON output")
        var pretty: Bool = false

        func validate() throws {
            if let candidate, candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ValidationError("Candidate name can't be empty")
            }
            if let recommendation, !recommendation.isEmpty, Recommendation(rawValue: recommendation) == nil {
                throw ValidationError("Invalid recommendation '\(recommendation)'. Use: yes, no, strongYes, definitelyNot")
            }
            let options = [candidate, role, date, problem, whiteboard, rawNotes, upsides, riskFactors, level, recommendation, conclusion, debriefDate, debriefNotes]
            if options.allSatisfy({ $0 == nil }) && isPrivate == nil {
                throw ValidationError("Nothing to change")
            }
        }

        mutating func run() async throws {
            let texts = try TextInput.resolve([rawNotes, upsides, riskFactors, conclusion, debriefNotes])
            let date = try date.map(CLIDate.day)
            let debriefDate = try debriefDate.map { $0.isEmpty ? nil : try CLIDate.day($0) }

            let context = ModelContext(try Store.makeContainer())
            let interview = try Interviews.interview(id: id, in: context)

            if let candidate { interview.candidateName = candidate.trimmingCharacters(in: .whitespacesAndNewlines) }
            if let role { interview.role = TextInput.field(role) }
            if let date { interview.date = date }
            if let problem { interview.problemName = TextInput.field(problem) }
            if let whiteboard { interview.whiteboardLink = TextInput.field(whiteboard) }
            if let text = texts[0] { interview.rawNotes = TextInput.field(text) }
            if let text = texts[1] { interview.upsides = TextInput.field(text) }
            if let text = texts[2] { interview.riskFactors = TextInput.field(text) }
            if let level { interview.levelAssessment = TextInput.field(level) }
            if let recommendation { interview.recommendation = Recommendation(rawValue: recommendation) }
            if let text = texts[3] { interview.conclusion = TextInput.field(text) }
            if let debriefDate { interview.debriefDate = debriefDate }
            if let text = texts[4] { interview.debriefNotes = TextInput.field(text) }
            if let isPrivate { interview.isPrivate = isPrivate }
            try context.save()

            try printJSON(InterviewDetail.from(interview, todos: (interview.todos ?? []).filter { !$0.isTrashed }.sorted { $0.sortOrder < $1.sortOrder }), pretty: pretty)
        }
    }

    static func interview(id: String, in context: ModelContext) throws -> Interview {
        guard let uuid = UUID(uuidString: id) else {
            throw ValidationError("Invalid UUID: \(id)")
        }
        guard let interview = try context.fetch(FetchDescriptor<Interview>(predicate: #Predicate { $0.id == uuid })).first else {
            throw ValidationError("Interview not found: \(id)")
        }
        return interview
    }
}
