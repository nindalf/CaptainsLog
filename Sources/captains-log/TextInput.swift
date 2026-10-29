import ArgumentParser
import Foundation

enum TextInput {
    /// The option's text, or stdin when it is `-`, so long notes needn't be shell-quoted. At most
    /// one option per command may read stdin.
    static func resolve(_ values: [String?]) throws -> [String?] {
        guard values.filter({ $0 == "-" }).count <= 1 else {
            throw ValidationError("Only one option can read stdin (-)")
        }
        return values.map { value in
            guard value == "-" else { return value }
            return String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
        }
    }

    /// Empty text clears a field, as emptying it does in the app.
    static func field(_ text: String) -> String? {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
    }
}
