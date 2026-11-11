import Foundation
import Testing
import CaptainsLogKit

struct RunProcessTests {
    /// A cancelled task calls the cancellation handler before the child launches; terminating an
    /// unlaunched `Process` raises, which crashed the app when a login's status recheck was cancelled.
    @Test func cancelledBeforeLaunchThrows() async {
        let plain = Task {
            while !Task.isCancelled { await Task.yield() }
            return try await runProcess("/bin/echo", arguments: ["hi"])
        }
        plain.cancel()
        await #expect(throws: CancellationError.self) { try await plain.value }

        let watching = Task {
            while !Task.isCancelled { await Task.yield() }
            try await runWatchingStderr("/bin/echo", arguments: ["hi"], timeout: .seconds(5)) { _ in }
        }
        watching.cancel()
        await #expect(throws: CancellationError.self) { try await watching.value }
    }
}
