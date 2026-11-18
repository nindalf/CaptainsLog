import SwiftUI

/// The one section header: a title, a plain count, then `›` to open the section's tab or `+` to
/// add to it. Lists on a tab of their own pin it with `.pinnedSectionHeader()`; lists in a box
/// (a detail page, the Dashboard) put it above the box.
struct SectionHeader: View {
    let title: String
    var icon: String?
    var count: Int?
    /// Makes the title a button that opens the section's tab or page.
    var onOpen: (() -> Void)?
    var onAdd: (() -> Void)?
    var addHelp = "Add"
    /// For a group the caller collapses: a chevron, down when expanded.
    var isExpanded: Bool?

    var body: some View {
        HStack(spacing: 8) {
            if let onOpen {
                Button(action: onOpen) {
                    HStack(spacing: 4) {
                        label
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
            } else {
                label
            }
            if let isExpanded {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            if let onAdd {
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .help(addHelp)
            }
        }
        .font(.headline)
        .lineLimit(1)
    }

    private var label: some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .foregroundStyle(.blue)
            }
            Text(title)
            if let count {
                Text("\(count)")
                    .fontWeight(.regular)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}

extension View {
    /// A section header pinned over a tab's list, painting the page behind it.
    func pinnedSectionHeader() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 16)
            .padding(.bottom, 6)
            .padding(.horizontal, 8)
            .background(.background)
            .contentShape(Rectangle())
    }
}

/// Under a long list: shows the next page of what's left.
struct ShowMoreButton: View {
    let remaining: Int
    let pageSize: Int
    let action: () -> Void

    var body: some View {
        if remaining > 0 {
            Button {
                withAnimation { action() }
            } label: {
                Text("Show \(min(remaining, pageSize)) More")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help("\(remaining) more")
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
