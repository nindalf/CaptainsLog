import SwiftUI

/// The privacy control everywhere: an open eye, or a crossed-out one when private.
struct PrivacyEye: View {
    @Binding var isOn: Bool
    /// In a window toolbar, which styles its own buttons.
    var inToolbar = false

    var body: some View {
        if inToolbar {
            button
        } else {
            button
                .buttonStyle(.plain)
                .foregroundStyle(isOn ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
        }
    }

    private var button: some View {
        Button { isOn.toggle() } label: {
            Label(isOn ? "Private" : "Not Private", systemImage: isOn ? "eye.slash" : "eye")
                .labelStyle(.iconOnly)
                // Fixed width, so swapping the two eyes doesn't shift the icons beside it.
                .frame(width: 20)
        }
        // Matches what the CLI prints (docs/cli.md).
        .help(isOn ? "Private: hidden from Claude, apart from its title" : "Visible to Claude. Make private")
    }
}

extension View {
    /// A tappable pill in a card's controls: a project, a date, a tag.
    func cardPill(_ tint: Color) -> some View {
        font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.15))
            .foregroundStyle(tint)
            .clipShape(Capsule())
    }
}
