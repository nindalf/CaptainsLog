// Enums only the frozen schemas still use, so SwiftData recognises the stores written by them.
// Internal: no current model or code should pick them up.

enum DeploymentStatus: String, Codable, Sendable, CaseIterable {
    case notDeployed, partiallyDeployed, deployed
}
