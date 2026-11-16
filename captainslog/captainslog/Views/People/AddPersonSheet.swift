import SwiftData
import SwiftUI
import CaptainsLogKit

/// Adds a person by hand (`Person.add`), then opens them. An email or handle someone already has
/// matches them instead, which the sheet says before Add.
struct AddPersonSheet: View {
    var onAdd: (Person) -> Void

    @Query private var allPeople: [Person]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var email = ""
    @State private var github = ""
    @State private var slack = ""
    @State private var error: String?

    private var entry: RosterEntry {
        RosterEntry(name: name, email: email, github: github, slack: slack)
    }

    private var plan: Result<RosterImportRow, any Error> {
        Result { try Person.planAdd(entry, among: allPeople) }
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                TextField("Email", text: $email)
                TextField("GitHub", text: $github, prompt: Text("handle"))
                TextField("Slack", text: $slack, prompt: Text("handle"))
                if let note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add Person")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", action: add)
                        .disabled((try? plan.get()) == nil)
                }
            }
        }
        .frame(minWidth: 380, minHeight: 300)
        .alert("Couldn't Add Person", isPresented: Binding(
            get: { error != nil },
            set: { if !$0 { error = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(error ?? "")
        }
    }

    /// Who Add matches, or why it's disabled. Not while the name is empty or the email half typed.
    private var note: String? {
        switch plan {
        case .failure(let error as PersonAddError):
            if case .matchesSeveral = error { return error.localizedDescription }
            return nil
        case .failure(let error):
            return error.localizedDescription
        case .success(let row):
            if !Person.namesakes(of: row, among: allPeople).isEmpty {
                return "There's already a \(row.entry.name) in People. An email or handle tells them apart."
            }
            guard row.action != .create, let existing = row.personName else { return nil }
            var note = "\(existing) is already in Captain's Log."
            if !row.filled.isEmpty {
                note += " Adds their \(row.filled.map(\.field.label).joined(separator: ", "))."
            }
            if !row.conflicts.isEmpty {
                note += " Keeps their " + row.conflicts.map { "\($0.field.label) \($0.stored)" }.joined(separator: ", ") + "."
            }
            return note
        }
    }

    private func add() {
        do {
            let person = try Person.add(entry, in: modelContext).person
            try modelContext.save()
            dismiss()
            onAdd(person)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
