import SwiftUI
import SwiftData
import CaptainsLogKit

/// The Dashboard's setup steps, including the ones no tab covers: backups, a roster, the weekly review.
/// The next unfinished step is open, done ones are ticked in a line, and the list goes once all are done.
struct SetupChecklist: View {
    enum Step: String, CaseIterable {
        case github, calendar, roster, backups, weeklyReview

        var title: String {
            switch self {
            case .github: "Connect GitHub"
            case .calendar: "Connect your calendar"
            case .roster: "Import your team"
            case .backups: "Back up your notes"
            case .weeklyReview: "Run your first weekly review"
            }
        }

        /// Steps that can be done without, so they mustn't nag forever.
        var isSkippable: Bool { self == .roster || self == .weeklyReview }
    }

    /// The Dashboard's pane colour.
    let background: Color

    @Environment(SyncCoordinator.self) private var sync
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openSettings) private var openSettings

    @Query(Self.first(Todo.self)) private var anyTodo: [Todo]
    @Query(Self.first(LogEntry.self)) private var anyLogEntry: [LogEntry]
    @Query(Self.first(Meeting.self)) private var anyMeeting: [Meeting]
    /// Sync fills in emails (calendar) or GitHub handles (PRs), never both and never Slack, so either
    /// marks a roster import or someone's own edits.
    @Query(Self.first(Person.self, #Predicate<Person> {
        $0.slackHandle != nil || ($0.email != nil && $0.githubHandle != nil)
    })) private var rosterPerson: [Person]
    /// Tags can't go in a predicate, so the weekly-review check filters in memory.
    @Query private var logEntries: [LogEntry]

    @State private var chosen: Step?
    @State private var rosterImport: RosterImportPreview?
    @State private var rosterError: String?

    private static func first<T: PersistentModel>(_: T.Type, _ predicate: Predicate<T>? = nil) -> FetchDescriptor<T> {
        var descriptor = FetchDescriptor<T>(predicate: predicate)
        descriptor.fetchLimit = 1
        return descriptor
    }

    /// Steps that apply: a hidden tab's step goes with it, and backups wait until there's something to lose.
    private var steps: [Step] {
        Step.allCases.filter { step in
            switch step {
            case .github: settings.isShown(.pullRequests)
            case .calendar: settings.isShown(.meetings)
            case .roster: settings.isShown(.people)
            case .backups: !(anyTodo.isEmpty && anyLogEntry.isEmpty && anyMeeting.isEmpty)
            case .weeklyReview: true
            }
        }
    }

    private func isDone(_ step: Step) -> Bool {
        if step.isSkippable, settings.skippedSetupSteps.contains(step.rawValue) { return true }
        switch step {
        case .github: return sync.githubSetup == .ready
        case .calendar: return sync.calendarSetup == .ready
        case .roster: return !rosterPerson.isEmpty
        case .backups: return sync.backupStage == .ready
        case .weeklyReview: return logEntries.contains { $0.tags.contains("weekly-review") }
        }
    }

    var body: some View {
        // Wait for the first setup check, so done steps don't show as to-do for a moment.
        if sync.githubSetup != nil, sync.calendarSetup != nil, sync.backupStage != nil {
            let steps = steps
            let done = steps.filter(isDone)
            let pending = steps.filter { !isDone($0) }
            if let current = chosen.flatMap({ pending.contains($0) ? $0 : nil }) ?? pending.first {
                checklist(current: current, done: done, later: pending.filter { $0 != current }, total: steps.count)
            }
        }
    }

    private func checklist(current: Step, done: [Step], later: [Step], total: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Get set up").font(.headline)
                Text("\(done.count) of \(total) done")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            if !done.isEmpty {
                FlowLayout(spacing: 12) {
                    ForEach(done, id: \.self) { step in
                        Label(step.title, systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .labelStyle(TintedIconLabelStyle(tint: .green))
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "circle")
                        .foregroundStyle(.secondary)
                    Text(current.title).font(.subheadline.weight(.semibold))
                    Spacer()
                    if current.isSkippable {
                        Button("Skip") { settings.skippedSetupSteps.append(current.rawValue) }
                            .buttonStyle(.borderless)
                            .font(.caption)
                    }
                }
                content(for: current)
                    .font(.callout)
                    .padding(.leading, 22)
            }
            if !later.isEmpty {
                HStack(spacing: 4) {
                    Text("Then:").foregroundStyle(.secondary)
                    ForEach(later, id: \.self) { step in
                        Button(step.title) { chosen = step }
                            .buttonStyle(.link)
                        if step != later.last { Text("·").foregroundStyle(.secondary) }
                    }
                }
                .font(.caption)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background, in: .rect(cornerRadius: 10))
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .sheet(item: $rosterImport) { RosterImportSheet(preview: $0) }
        .alert("Couldn't Read Roster", isPresented: Binding(
            get: { rosterError != nil },
            set: { if !$0 { rosterError = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(rosterError ?? "")
        }
    }

    @ViewBuilder
    private func content(for step: Step) -> some View {
        switch step {
        case .github:
            if let instruction = SetupInstruction.github(sync.githubSetup) {
                SetupInstructionView(instruction: instruction, style: .inline)
            }
        case .calendar:
            if let instruction = SetupInstruction.calendar(sync.calendarSetup, canLogIn: sync.canLogInToCalendar) {
                SetupInstructionView(instruction: instruction, style: .inline)
            }
        case .roster:
            VStack(alignment: .leading, spacing: 8) {
                Text("If someone has shared a roster of your teammates' GitHub and Slack handles, import it. Or add handles on each person's page.")
                    .foregroundStyle(.secondary)
                Button("Import Roster…", action: chooseRoster)
            }
        case .backups:
            VStack(alignment: .leading, spacing: 8) {
                Text("Your notes are only on this Mac. Back them up, encrypted, to your Google Drive.")
                    .foregroundStyle(.secondary)
                Button("Set Up Backups") {
                    SettingsTab.selected = .backups
                    openSettings()
                }
            }
        case .weeklyReview:
            VStack(alignment: .leading, spacing: 8) {
                Text(Calendar.current.component(.weekday, from: .now) == 6
                    ? "It's Friday. Open Claude Code in any folder and run:"
                    : "On Friday, open Claude Code in any folder and run:")
                    .foregroundStyle(.secondary)
                CommandBox(command: "/weekly-review")
                    .frame(maxWidth: 320)
                Text("Claude reads your week, asks you about it, and saves brag-doc entries to the Log.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func chooseRoster() {
        do {
            rosterImport = try RosterImportPreview.choose(in: modelContext)
        } catch {
            rosterError = error.localizedDescription
        }
    }
}

private struct TintedIconLabelStyle: LabelStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.foregroundStyle(tint)
            configuration.title
        }
    }
}
