import SwiftUI

extension Binding where Value: Equatable {
    /// Drops writes of the value it already holds. A text field writes one when it takes focus, and
    /// SwiftData counts it as a change, which keeps the CLI's writes from reaching the open record.
    var skippingNoOps: Binding<Value> {
        Binding(get: { wrappedValue }, set: { if $0 != wrappedValue { wrappedValue = $0 } })
    }
}
