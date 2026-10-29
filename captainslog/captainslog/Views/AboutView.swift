import SwiftUI

/// The About window, opened from the app menu in place of the standard panel.
struct AboutView: View {
    private static let quotes = [
        "Make it so.",
        "Engage.",
        "Tea. Earl Grey. Hot.",
        "It is possible to commit no mistakes and still lose. That is not weakness. That is life.",
        "That is what it is to be human: To make yourself more than you are.",
        "We have powerful tools: Openness, optimism and the spirit of curiosity.",
        "What we leave behind is not as important as how we’ve lived.",
        "Things are only impossible until they are not.",
        "The past is written, but the future is left for us to write.",
        "To be alive is a responsibility as well as a right.",
        "There is a way out of every box, a solution to every puzzle. It’s just a matter of finding it.",
        "To say you have no choice is a failure of imagination.",
    ]

    @State private var quoteIndex = Int.random(in: 0..<quotes.count)
    @State private var showingMemorial = false

    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        return "Version \(short)"
    }

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)

            Text("Captain's Log")
                .font(.title.bold())
                .padding(.top, 8)
            Text(version)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text("A record of the week's work.")
                .padding(.top, 12)

            Divider()
                .frame(width: 160)
                .padding(.vertical, 20)

            // Both stay laid out so the window doesn't resize on toggle.
            ZStack {
                quote(Self.quotes[quoteIndex])
                    .opacity(showingMemorial ? 0 : 1)
                memorial
                    .opacity(showingMemorial ? 1 : 0)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation { showingMemorial.toggle() }
            }
        }
        .padding(32)
        .frame(width: 340)
        // The Window scene keeps this view's state across close and reopen, so re-pick here.
        .onAppear {
            quoteIndex = Int.random(in: 0..<Self.quotes.count)
            showingMemorial = false
        }
    }

    private func quote(_ text: String) -> some View {
        VStack(spacing: 4) {
            Text("“\(text)”")
                .italic()
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text("Captain Jean-Luc Picard")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var memorial: some View {
        VStack(spacing: 2) {
            Text("In memory of")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Sir Patrick Stewart")
                .font(.headline)
            Text("1940 – 2026")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Replaces "About Captain's Log" in the app menu with one that opens `AboutView`.
struct AboutCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Captain's Log") { openWindow(id: "about") }
        }
    }
}

#Preview {
    AboutView()
}
