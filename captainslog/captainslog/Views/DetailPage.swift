import SwiftUI
import CaptainsLogKit

/// A detail page laid out as a document: the content column, scrolling, holding a `DetailHeader`
/// and `DetailSection`s. Replaces the grouped `Form`, whose rows push values far from their labels.
struct DetailPage<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                content
            }
            .contentColumn()
            .padding(.vertical, 20)
        }
        // The page's own title replaces the toolbar's.
        .navigationTitle("")
    }
}

/// Large editable title, then a line of metadata in secondary text.
struct DetailHeader<Metadata: View>: View {
    @Binding var title: String
    var placeholder: String = "Title"
    /// Runs on Return and when the title loses focus: the binding writes every keystroke.
    var onCommit: () -> Void = {}
    @ViewBuilder var metadata: Metadata
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(placeholder, text: $title, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.title.bold())
                .focused($isFocused)
                .onSubmit(onCommit)
                .onChange(of: isFocused) { _, focused in if !focused { onCommit() } }
            FlowLayout(spacing: 14) {
                metadata
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }
}

/// Label and value pairs under a header, the label in a narrow column right beside its value.
struct DetailProperties<Content: View>: View {
    var font: Font = .callout
    /// Semibold primary labels, for a box whose secondary text would be grey on grey.
    var prominentLabels = false
    @ViewBuilder var content: Content

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 8) {
            content
        }
        .font(font)
        .environment(\.prominentPropertyLabels, prominentLabels)
    }
}

extension EnvironmentValues {
    @Entry var prominentPropertyLabels = false
}

struct DetailProperty<Value: View>: View {
    let label: String
    @ViewBuilder var value: Value
    @Environment(\.prominentPropertyLabels) private var prominent

    var body: some View {
        GridRow {
            Text(label)
                .fontWeight(prominent ? .semibold : nil)
                .foregroundStyle(prominent ? .primary : .secondary)
                .gridColumnAlignment(.leading)
            value
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A plain text property that saves an empty string as nil.
struct DetailTextProperty: View {
    let label: String
    let prompt: String
    @Binding var text: String?
    /// Runs on Return and when the field loses focus: the binding writes every keystroke.
    var onCommit: () -> Void = {}
    @FocusState private var isFocused: Bool

    var body: some View {
        DetailProperty(label: label) {
            TextField(label, text: Binding(
                get: { text ?? "" },
                set: { text = $0.isEmpty ? nil : $0 }
            ), prompt: Text(prompt))
            .textFieldStyle(.plain)
            .labelsHidden()
            .focused($isFocused)
            .onSubmit(onCommit)
            .onChange(of: isFocused) { _, focused in if !focused { onCommit() } }
        }
    }
}

/// A heading over a rounded box, as a grouped form section looks, without the form's layout.
struct DetailSection<Content: View, Accessory: View>: View {
    let title: String
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(title).font(.headline)
                accessory
            }
            .padding(.horizontal, 4)
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quinary, in: .rect(cornerRadius: 10))
        }
    }
}

extension DetailSection where Accessory == EmptyView {
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.accessory = EmptyView()
        self.content = content()
    }
}

extension DetailSection {
    init(_ title: String, @ViewBuilder accessory: () -> Accessory, @ViewBuilder content: () -> Content) {
        self.title = title
        self.accessory = accessory()
        self.content = content()
    }
}

/// Rows in a `DetailSection`, divided as a grouped form divides them.
struct DetailRows<Data: RandomAccessCollection, Row: View>: View where Data.Element: Identifiable {
    let data: Data
    @ViewBuilder var row: (Data.Element) -> Row

    var body: some View {
        ForEach(Array(data.enumerated()), id: \.element.id) { index, element in
            if index > 0 { Divider().padding(.vertical, 6) }
            row(element)
        }
    }
}

/// A link in a metadata line: opens the URL when set, and edits it in a popover.
struct LinkMetadataItem: View {
    let title: String
    let prompt: String
    @Binding var urlString: String?
    @State private var isEditing = false

    private var url: URL? {
        guard let urlString, let url = URL(string: urlString), url.scheme != nil else { return nil }
        return url
    }

    var body: some View {
        HStack(spacing: 4) {
            if let url {
                Link(destination: url) { Label(title, systemImage: "link") }
                    .help(url.absoluteString)
                Button { isEditing = true } label: { Image(systemName: "pencil") }
                    .buttonStyle(.plain)
                    .help("Edit \(title) link")
            } else {
                Button { isEditing = true } label: { Label("Add \(title) link", systemImage: "link") }
                    .buttonStyle(.plain)
            }
        }
        .popover(isPresented: $isEditing) {
            TextField(title, text: Binding(
                get: { urlString ?? "" },
                set: {
                    let trimmed = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    urlString = trimmed.isEmpty ? nil : trimmed
                }
            ), prompt: Text(prompt))
            .textFieldStyle(.roundedBorder)
            .frame(width: 360)
            .padding(12)
            .onSubmit { isEditing = false }
        }
    }
}
