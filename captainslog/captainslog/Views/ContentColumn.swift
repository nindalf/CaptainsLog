import SwiftUI

/// The centred column every list and detail page sits in, so content keeps its place across tabs
/// and a row's page opens where the row was. Full-width screens (Calendar, Dashboard) don't use it.
enum ContentColumn {
    static let width: CGFloat = 760
    /// The gutter either side once the window is narrower than the column.
    static let gutter: CGFloat = 20
}

extension View {
    /// Centres this view in the content column, or when not `isEnabled`, lets it fill the width.
    /// Apply inside a `ScrollView`, so the scroller stays at the window edge.
    func contentColumn(_ isEnabled: Bool = true) -> some View {
        frame(maxWidth: isEnabled ? ContentColumn.width : .infinity, alignment: .leading)
            .padding(.horizontal, isEnabled ? ContentColumn.gutter : 0)
            .frame(maxWidth: .infinity)
    }
}
