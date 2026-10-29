import Foundation
import Testing
import CaptainsLogKit

// Projects and todos are built but never inserted, so no container is needed.
@Suite(.serialized) @MainActor
struct ProjectNamingTests {
    @Test func theBaseNameIsUsedWhenFree() {
        #expect(ProjectNaming.uniqueName(existing: ["Hiring"]) == "New Project")
    }

    @Test func takenNamesGetTheNextNumber() {
        #expect(ProjectNaming.uniqueName(existing: ["New Project"]) == "New Project 2")
        #expect(ProjectNaming.uniqueName(existing: ["new project", "New Project 2"]) == "New Project 3")
    }

    @Test func renamesAreTrimmed() {
        let project = Project(name: "A")
        #expect(ProjectNaming.validated("  Hiring  ", for: project, among: [project]) == "Hiring")
    }

    @Test func emptyNamesAreRejected() {
        let project = Project(name: "A")
        #expect(ProjectNaming.validated("   ", for: project, among: [project]) == nil)
    }

    @Test func anotherProjectsNameIsRejectedWhateverTheCase() {
        let project = Project(name: "A")
        let other = Project(name: "Hiring")
        #expect(ProjectNaming.validated("hiring", for: project, among: [project, other]) == nil)
    }

    @Test func aProjectMayKeepOrRecaseItsOwnName() {
        let project = Project(name: "Hiring")
        #expect(ProjectNaming.validated("HIRING", for: project, among: [project]) == "HIRING")
    }
}

@Suite(.serialized) @MainActor
struct ProjectCompletionTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test func completingCompletesTheProjectAndItsOpenTodos() {
        let project = Project(name: "P")
        let todos = [Todo(title: "a"), Todo(title: "b")]
        ProjectCompletion.complete(project, openTodos: todos, now: now)

        #expect(project.isCompleted)
        #expect(project.completedDate == now)
        #expect(todos.allSatisfy { $0.isCompleted && $0.completedDate == now })
    }

    @Test func alreadyCompletedTodosKeepTheirDate() {
        let earlier = now.addingTimeInterval(-86_400)
        let done = Todo(title: "done")
        done.completedDate = earlier
        ProjectCompletion.complete(Project(name: "P"), openTodos: [done], now: now)
        #expect(done.completedDate == earlier)
    }

    @Test func reopeningLeavesTodosCompleted() {
        let project = Project(name: "P")
        let todo = Todo(title: "a")
        ProjectCompletion.complete(project, openTodos: [todo], now: now)
        ProjectCompletion.reopen(project)

        #expect(!project.isCompleted)
        #expect(project.completedDate == nil)
        #expect(todo.isCompleted)
    }
}
