import SwiftUI
import AppKit
import SwiftData
import CaptainsLogKit

struct DashboardView: View {
    @Binding var selectedSidebarItem: SidebarItem?
    @Environment(SyncCoordinator.self) private var syncCoordinator
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @Environment(Navigator.self) private var navigator

    @Query(filter: #Predicate<CalendarEvent> { !$0.isHidden }, sort: \CalendarEvent.startTime)
    private var allEvents: [CalendarEvent]

    @Query(filter: #Predicate<PullRequest> { $0.isAuthoredByMe },
           sort: \PullRequest.createdAt, order: .reverse)
    private var myAuthoredPRs: [PullRequest]

    // displayStatus is computed, so it can't go in #Predicate: filter on stored fields, refine in Swift.
    @Query(filter: #Predicate<PullRequest> {
               !$0.isAuthoredByMe && !$0.isTeammateOnly && $0.stateRawValue == "open"
           },
           sort: \PullRequest.createdAt, order: .reverse)
    private var openReviewRequests: [PullRequest]

    private var reviewRequests: [PullRequest] {
        openReviewRequests.filter { $0.displayStatus == .open && !settings.isHidden($0) }
    }

    private var myDashboardPRs: [PullRequest] {
        Array(myAuthoredPRs.filter { $0.state == .open }.prefix(4))
    }

    @State private var unlinkedEvent: CalendarEvent?
    @State private var prSelectedID: UUID?
    @State private var prExpandedID: UUID?
    @FocusState private var prFocusField: PRFocusField?
    @State private var todoAddTick = 0
    @State private var logAddTick = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                stardateHeader
                Spacer()
                syncStatus
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 10)

            SetupChecklist(background: Self.paneColor)

            // Each column's last pane takes what the others leave and scrolls; the rest fit their
            // content. A pane goes with its tab when Settings hides that tab, and a column with it.
            let showsSchedule = settings.isShown(.meetings)
            let showsPRs = settings.isShown(.pullRequests)
            let showsTodos = settings.isShown(.todos)
            let showsLog = settings.isShown(.log)
            HStack(alignment: .top, spacing: 16) {
                if showsSchedule || showsPRs {
                    VStack(alignment: .leading, spacing: 16) {
                        if showsSchedule { schedulePane }
                        if showsPRs {
                            myPRsPane
                            reviewRequestsPane
                        }
                    }
                }
                if showsTodos || showsLog {
                    VStack(alignment: .leading, spacing: 16) {
                        if showsTodos { todosPane }
                        if showsLog { logPane }
                    }
                }
                if !(showsSchedule || showsPRs || showsTodos || showsLog) {
                    Text("Every tab the Dashboard draws on is hidden in Settings.")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .navigationTitle("Dashboard")
        .toolbar { toolbarContent }
        .popover(item: $unlinkedEvent) { event in
            CalendarEventPopover(event: event) { action in
                handleEventAction(event, action: action)
                unlinkedEvent = nil
            }
        }
    }

    // MARK: - Panes

    /// A slight grey on the page, as `.quinary` looks on it, but opaque, so a pinned header covers
    /// the rows scrolling under it.
    static let paneColor = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(white: 0.165, alpha: 1)
            : NSColor(white: 0.965, alpha: 1)
    })

    private var schedulePane: some View {
        pane("Schedule", destination: .meetings) {
            DashboardAgenda(events: allEvents, onTap: { handleEventTap($0) })
        }
    }

    private var reviewRequestsPane: some View {
        pane("Review Requests (\(reviewRequests.count))", destination: .pullRequests) {
            if reviewRequests.isEmpty {
                emptyPaneLabel("Nothing to review")
            } else {
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(reviewRequests) { pr in dashboardPRRow(pr) }
                    }
                }
            }
        }
    }

    private var myPRsPane: some View {
        pane("My PRs (\(myDashboardPRs.count))", destination: .pullRequests) {
            if myDashboardPRs.isEmpty {
                emptyPaneLabel("No open PRs")
            } else {
                // At most four, so no scrolling.
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(myDashboardPRs) { pr in dashboardPRRow(pr) }
                }
            }
        }
    }

    // Same views as the Todos tab, minus the toolbar: reorder, expand, complete and drafts all come along.
    private var todosPane: some View {
        pane("Today", destination: .todos, onAdd: { todoAddTick += 1 }) {
            TodoListContent(
                scope: .smart(.today),
                addTick: todoAddTick,
                fillsWidth: true,
                focusesOnAppear: false,
                fittedHeightLimit: 360
            )
        }
    }

    private var logPane: some View {
        pane("Log", destination: .log, onAdd: { logAddTick += 1 }) {
            LogListContent(
                typeFilter: .constant(nil),
                addTick: logAddTick,
                fillsWidth: true,
                focusesOnAppear: false,
                includesCompletedTodos: false
            )
        }
    }

    private func pane<Content: View>(
        _ title: String,
        destination: SidebarItem,
        onAdd: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                sectionHeader(title, destination: destination)
                if let onAdd {
                    Button(action: onAdd) {
                        Image(systemName: "plus")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                    .help("Add")
                }
                Spacer()
            }
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Self.paneColor, in: .rect(cornerRadius: 10))
        // Pinned headers inside (the Log's days) paint `.background`, so give them the pane's colour.
        .backgroundStyle(Self.paneColor)
    }

    private func emptyPaneLabel(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem {
            Button { syncCoordinator.syncNow() } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .help("Refresh GitHub and calendar")
            .disabled(syncCoordinator.isSyncing)
        }
    }

    // MARK: - PR rows

    private func sectionHeader(_ title: String, destination: SidebarItem) -> some View {
        Button { selectedSidebarItem = destination } label: {
            HStack(spacing: 4) {
                Text(title)
                    .font(.headline)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
    }

    @ViewBuilder
    private func dashboardPRRow(_ pr: PullRequest) -> some View {
        if prExpandedID == pr.id {
            PRCardView(pr: pr, focusedField: $prFocusField, onCollapse: { collapsePRCard() })
                .padding(.vertical, 2)
                .contextMenu { PRContextMenu(pr: pr) }
        } else {
            PRCollapsedRow(pr: pr, isSelected: prSelectedID == pr.id)
                .onTapGesture {
                    if prSelectedID == pr.id {
                        prSelectedID = pr.id
                        prExpandedID = pr.id
                        prFocusField = .notes(pr.id)
                    } else {
                        collapsePRCard()
                        prSelectedID = pr.id
                    }
                }
                .contextMenu { PRContextMenu(pr: pr) }
        }
    }

    private func collapsePRCard() {
        prExpandedID = nil
        prFocusField = nil
    }

    /// When GitHub and the calendar last synced, or why they failed.
    private var syncStatus: some View {
        VStack(alignment: .trailing, spacing: 4) {
            if settings.isShown(.pullRequests) { SyncStatusLabel(source: .github, alignment: .trailing) }
            if settings.isShown(.meetings) { SyncStatusLabel(source: .calendar, alignment: .trailing) }
        }
        .frame(maxWidth: 360, alignment: .trailing)
    }

    private var stardateHeader: some View {
        TimelineView(.everyMinute) { context in
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Stardate")
                        .foregroundStyle(.secondary)
                    Text(Self.stardate(context.date))
                        .fontDesign(.monospaced)
                }
                .font(.title2.weight(.semibold))
                Text(context.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Year, day of the year, hour: "2026.298.08".
    private static func stardate(_ date: Date) -> String {
        let cal = Calendar.current
        let year = cal.component(.year, from: date)
        let dayOfYear = cal.ordinality(of: .day, in: .year, for: date) ?? 1
        let hour = cal.component(.hour, from: date)
        return "\(year).\(String(format: "%03d", dayOfYear)).\(String(format: "%02d", hour))"
    }

    private func handleEventTap(_ event: CalendarEvent) {
        if event.meeting != nil || event.interview != nil {
            navigator.openEvent(event)
        } else {
            unlinkedEvent = event
        }
    }

    private func handleEventAction(_ event: CalendarEvent, action: CalendarEventPopover.CalendarEventAction) {
        switch action {
        case .createMeeting:
            event.createMeeting(in: modelContext)
            try? modelContext.save()
            navigator.openEvent(event)
        case .hide:
            event.isHidden = true
            try? modelContext.save()
        case .removed:
            event.deleteWithEmptyStubs(in: modelContext)
            try? modelContext.save()
        }
    }
}


#Preview {
    @Previewable @State var sidebar: SidebarItem? = .dashboard
    NavigationStack {
        DashboardView(selectedSidebarItem: $sidebar)
    }
    .previewEnvironment()
}
