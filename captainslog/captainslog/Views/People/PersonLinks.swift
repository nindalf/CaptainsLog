import SwiftUI
import CaptainsLogKit

/// People as a comma-separated run of links that wraps like text. Each name pushes the person
/// onto the current stack.
struct PersonLinks: View {
    let people: [Person]
    @Environment(Navigator.self) private var navigator

    private static let scheme = "captainslog-person"

    private var text: AttributedString {
        var result = AttributedString()
        for (index, person) in people.enumerated() {
            if index > 0 { result += AttributedString(", ") }
            var name = AttributedString(person.name)
            name.link = URL(string: "\(Self.scheme):\(person.id.uuidString)")
            result += name
        }
        return result
    }

    var body: some View {
        Text(text)
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == Self.scheme,
                      let id = UUID(uuidString: String(url.absoluteString.dropFirst(Self.scheme.count + 1))),
                      let person = people.first(where: { $0.id == id })
                else { return .systemAction }
                navigator.openPerson(person)
                return .handled
            })
    }
}
