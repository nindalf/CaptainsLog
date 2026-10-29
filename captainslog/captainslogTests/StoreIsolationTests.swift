import Foundation
import Testing
import CaptainsLogKit

/// The test host launches the full app; it must never open (and so migrate or sync into) the real store.
struct StoreIsolationTests {
    @Test func testHostUsesScratchStore() {
        #expect(ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil)
        #expect(Store.isScratch)
    }
}
