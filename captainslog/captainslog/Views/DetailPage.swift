import SwiftUI
import CaptainsLogKit

/// A detail page laid out as a document: the content column, scrolling, holding a `DetailHeader`
/// and `DetailSection`s. Replaces the grouped `Form`, whose rows push values far from their labels.
struct DetailPage<Content: View>: View {
    /// Bumped to take focus back, as when a card closes, so the page's keys work again.
    var focusRequest = 0
    /// A row kept scrolled into view: the page's keyboard selection.
    var scrollTarget: UUID?
    @ViewBuilder var content: Content
    @FocusState private var isFocused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    content
                }
                .contentColumn()
                .padding(.vertical, 20)
            }
            .onChange(of: scrollTarget) { _, id in
                guard let id else { return }
                DispatchQueue.main.async { proxy.scrollTo(id) }
            }
        }
        // The page takes focus on arrival, as tabs do. Left alone, SwiftUI hands it to the title
        // with its text selected, so a keystroke would replace it.
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onAppear { DispatchQueue.main.async { isFocused = true } }
        // Cleared first: focus moving into an AppKit text view, such as a card's notes, doesn't
        // clear it, so setting it alone would change nothing.
        .onChange(of: focusRequest) {
            isFocused = false
            DispatchQueue.main.async { isFocused = true }
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
    /// The title's focus, for a page that focuses it itself; else the header keeps its own.
    var focus: FocusState<Bool>.Binding?
    @ViewBuilder var metadata: Metadata
    @FocusState private var ownFocus: Bool

    var body: some View {
        let isFocused = focus ?? $ownFocus
        VStack(alignment: .leading, spacing: 8) {
            TextField(placeholder, text: $title.skippingNoOps, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.title.bold())
                .focused(isFocused)
                .onSubmit(onCommit)
                .onChange(of: isFocused.wrappedValue) { _, focused in if !focused { onCommit() } }
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
        let stored = $text.skippingNoOps
        DetailProperty(label: label) {
            TextField(label, text: Binding(
                get: { stored.wrappedValue ?? "" },
                set: { stored.wrappedValue = $0.isEmpty ? nil : $0 }
            ), prompt: Text(prompt))
            .textFieldStyle(.plain)
            .labelsHidden()
            .focused($isFocused)
            .onSubmit(onCommit)
            .onChange(of: isFocused) { _, focused in if !focused { onCommit() } }
        }
    }
}

/// A section header over a rounded box, as a grouped form section looks, without the form's layout.
struct DetailSection<Content: View, Accessory: View>: View {
    let title: String
    var count: Int?
    var onAdd: (() -> Void)?
    var addHelp = "Add"
    /// A control after the header, such as the debrief's date.
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                SectionHeader(title: title, count: count, onAdd: onAdd, addHelp: addHelp)
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
    init(_ title: String, count: Int? = nil, onAdd: (() -> Void)? = nil, addHelp: String = "Add", @ViewBuilder content: () -> Content) {
        self.init(title: title, count: count, onAdd: onAdd, addHelp: addHelp, accessory: { EmptyView() }, content: content)
    }
}

extension DetailSection {
    init(_ title: String, @ViewBuilder accessory: () -> Accessory, @ViewBuilder content: () -> Content) {
        self.init(title: title, accessory: accessory, content: content)
    }
}

/// Rows in a `DetailSection`, divided as a grouped form divides them. Past `limit`, the rest
/// come a page of `limit` at a time, or as many pages as it takes to show `reveal`.
struct DetailRows<Data: RandomAccessCollection, Row: View>: View where Data.Element: Identifiable {
    let data: Data
    let limit: Int?
    let reveal: Data.Element.ID?
    @ViewBuilder var row: (Data.Element) -> Row
    @State private var shown: Int?

    init(data: Data, limit: Int? = nil, reveal: Data.Element.ID? = nil, @ViewBuilder row: @escaping (Data.Element) -> Row) {
        self.data = data
        self.limit = limit
        self.reveal = reveal
        self.row = row
    }

    private var visible: [Data.Element] {
        guard let count = shown ?? limit else { return Array(data) }
        return Array(data.prefix(count))
    }

    var body: some View {
        ForEach(Array(visible.enumerated()), id: \.element.id) { index, element in
            if index > 0 { Divider().padding(.vertical, 6) }
            row(element)
                .id(element.id)
        }
        if let limit, data.count > visible.count {
            Divider().padding(.vertical, 6)
            ShowMoreButton(remaining: data.count - visible.count, pageSize: limit) {
                shown = visible.count + limit
            }
        }
        // On the section rather than a row, as a hidden row has no view to watch.
        Color.clear.frame(height: 0)
            .onChange(of: reveal) { _, id in
                guard let limit, let id, let index = data.firstIndex(where: { $0.id == id }) else { return }
                let offset = data.distance(from: data.startIndex, to: index)
                if offset >= visible.count { shown = (offset / limit + 1) * limit }
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
            let stored = $urlString.skippingNoOps
            TextField(title, text: Binding(
                get: { stored.wrappedValue ?? "" },
                set: {
                    let trimmed = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    stored.wrappedValue = trimmed.isEmpty ? nil : trimmed
                }
            ), prompt: Text(prompt))
            .textFieldStyle(.roundedBorder)
            .frame(width: 360)
            .padding(12)
            .onSubmit { isEditing = false }
        }
    }
}
