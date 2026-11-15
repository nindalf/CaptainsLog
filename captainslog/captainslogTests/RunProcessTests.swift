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
}
