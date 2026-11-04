import ArgumentParser
import CaptainsLogKit
import Foundation
import SwiftData

struct Whoami: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show which person is me, or mark one with --set",
        discussion: "When nobody is marked, `me` is null and `candidates` lists likely people, with why: the author of my PRs, then whoever is on the most calendar events."
    )

    @Option(name: .long, help: "Mark this person (UUID) as me, and unmark anyone else")
    var set: String?

    @Flag(name: .long, help: "Pretty-print JSON output")
    var pretty: Bool = false

    mutating func run() async throws {
        let context = ModelContext(try Store.makeContainer())
        if let set {
            let person = try People.person(id: set, in: context)
            try person.markAsSelf(in: context)
            try context.save()
        }
        if let me = try Person.me(in: context) {
            try printJSON(WhoamiDTO(me: PersonDTO.from(me), candidates: []), pretty: pretty)
        } else {
            let candidates = try Person.selfCandidates(in: context).map(SelfCandidateDTO.from)
            try printJSON(WhoamiDTO(me: nil, candidates: candidates), pretty: pretty)
        }
    }
}

struct WhoamiDTO: Encodable {
    let me: PersonDTO?
    /// Empty when `me` is set.
    let candidates: [SelfCandidateDTO]

    private enum CodingKeys: String, CodingKey { case me, candidates }

    // `me` stays in the output as null, so an unset user reads as unset, not as a missing field.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(me, forKey: .me)
        try container.encode(candidates, forKey: .candidates)
    }
}

struct SelfCandidateDTO: Encodable {
    let id: UUID
    let name: String
    let email: String?
    let githubHandle: String?
    let reason: String

    static func from(_ c: SelfCandidate) -> SelfCandidateDTO {
        SelfCandidateDTO(
            id: c.person.id, name: c.person.name, email: c.person.email,
            githubHandle: c.person.githubHandle, reason: c.reason
        )
    }
}
