import SwiftUI
import CaptainsLogKit

/// A card's project control: the project as a pill, else an icon, opening `ProjectPopover`.
struct ProjectControl: View {
    let current: Project?
    let projects: [Project]
    let onPick: (Project?) -> Void
    @State private var isPicking = false

    var body: some View {
        Button { isPicking.toggle() } label: {
            if let current {
                Text(current.name).cardPill(.blue)
            } else {
                Image(systemName: "list.bullet")
            }
        }
        .buttonStyle(.plain)
        .help("Project")
        .popover(isPresented: $isPicking) {
            ProjectPopover(current: current, projects: projects, onPick: onPick)
        }
    }
}

/// A detail page's project, in its header's metadata line.
struct ProjectMetadataItem: View {
    let current: Project?
    let projects: [Project]
    let onPick: (Project?) -> Void
    @State private var isPicking = false

    var body: some View {
        Button { isPicking.toggle() } label: {
            Label(current?.name ?? "Add to project", systemImage: "list.bullet")
        }
        .buttonStyle(.plain)
        .help("Project")
        .popover(isPresented: $isPicking) {
            ProjectPopover(current: current, projects: projects, onPick: onPick)
        }
    }
}

/// Picks a record's project. Callers holding an unsaved draft keep the pick until it's saved,
/// since relating a draft to a project inserts it.
struct ProjectPopover: View {
    let current: Project?
    let projects: [Project]
    let onPick: (Project?) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                onPick(nil)
                dismiss()
            } label: {
                HStack {
                    Text("No Project")
                    Spacer()
                    if current == nil {
                        Image(systemName: "checkmark").foregroundStyle(.blue)
                    }
                }
            }
            .buttonStyle(.plain)

            Divider()

            // Completed projects are hidden unless the record is already in one.
            ForEach(projects.filter { !$0.isCompleted || $0.id == current?.id }) { project in
                Button {
                    onPick(project)
                    dismiss()
                } label: {
                    HStack {
                        Text(project.name)
                        Spacer()
                        if current?.id == project.id {
                            Image(systemName: "checkmark").foregroundStyle(.blue)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        // Its own type, not the styling of the control that opened it.
        .font(.body)
        .foregroundStyle(.primary)
        .padding(12)
        .frame(width: 200)
    }
}
