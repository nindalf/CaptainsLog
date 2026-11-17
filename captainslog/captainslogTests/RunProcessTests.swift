import Foundation
import Testing
import CaptainsLogKit

struct RunProcessTests {
    /// A cancelled task calls the cancellation handler before the child launches; terminating an
    /// unlaunched `Process` raises, which crashes the app.
    @Test func cancelledBeforeLaunchThrows() async {
        let plain = Task {
            while !Task.isCancelled { await Task.yield() }
            return try await runProcess("/bin/echo", arguments: ["hi"])
        }
        plain.cancel()
        await #expect(throws: CancellationError.self) { try await plain.value }
    }

    /// `gh api graphql` exits non-zero with partial data that is still worth reading.
    @Test func aNonZeroExitCanStillBeRead() async throws {
        let result = try await runProcess("/usr/bin/false", arguments: [], allowsNonZeroExit: true)
        #expect(result.exitCode == 1)
        await #expect(throws: ProcessError.self) { try await runProcess("/usr/bin/false", arguments: []) }
    }
}
