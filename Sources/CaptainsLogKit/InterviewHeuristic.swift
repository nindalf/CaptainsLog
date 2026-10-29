import Foundation

public struct CandidateInfo {
    public let candidateName: String
    public let role: String?
    public let problemName: String?
}

public func isLikelyInterview(_ title: String) -> Bool {
    title.localizedCaseInsensitiveContains("interview")
}

public func extractCandidateInfo(_ title: String) -> CandidateInfo {
    var working = title.trimmingCharacters(in: .whitespaces)

    // Strip leading emoji / non-alphabetic characters
    let stripped = working.drop { c in
        !c.unicodeScalars.allSatisfy { $0.properties.isAlphabetic || $0.isASCII }
    }
    working = String(stripped).trimmingCharacters(in: .whitespaces)

    let segments = working.components(separatedBy: " - ").map {
        $0.trimmingCharacters(in: .whitespaces)
    }

    // Expected format: "INTERVIEW - Systems Design - Julian  (Senior Software Engineer)"
    guard segments.count >= 3,
          segments[0].localizedCaseInsensitiveContains("interview") else {
        return CandidateInfo(candidateName: title, role: nil, problemName: nil)
    }

    let problemName = segments[1]
    let lastSegment = segments[2...].joined(separator: " - ")

    var candidateName = lastSegment
    var role: String?

    if let openParen = lastSegment.lastIndex(of: "("),
       let closeParen = lastSegment.lastIndex(of: ")"),
       openParen < closeParen {
        role = String(lastSegment[lastSegment.index(after: openParen)..<closeParen])
            .trimmingCharacters(in: .whitespaces)
        candidateName = String(lastSegment[..<openParen])
            .trimmingCharacters(in: .whitespaces)
    }

    if candidateName.isEmpty {
        candidateName = title
    }

    return CandidateInfo(
        candidateName: candidateName,
        role: role?.isEmpty == true ? nil : role,
        problemName: problemName.isEmpty ? nil : problemName
    )
}
