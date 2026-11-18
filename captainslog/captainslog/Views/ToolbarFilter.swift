import SwiftUI

/// The filter a list tab puts first in its toolbar: All, then each kind with its icon. Toolbars
/// run filter, then add, then search, which macOS keeps at the trailing edge.
struct ToolbarFilter<Kind: Hashable>: View {
    @Binding var selection: Kind?
    let kinds: [Kind]
    let title: (Kind) -> String
    let icon: (Kind) -> String

    var body: some View {
        Menu {
            Picker("Show", selection: $selection) {
                Text("All").tag(Kind?.none)
                Divider()
                ForEach(kinds, id: \.self) { kind in
                    Label(title(kind), systemImage: icon(kind)).tag(Kind?.some(kind))
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            Label(
                selection.map(title) ?? "All",
                systemImage: selection == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill"
            )
            .labelStyle(.titleAndIcon)
        }
        .help("Show one kind only")
    }
}
