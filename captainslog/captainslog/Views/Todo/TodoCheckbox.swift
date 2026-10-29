import SwiftUI
import CaptainsLogKit

struct TodoCheckbox: View {
    let todo: Todo
    var onComplete: () -> Void

    var body: some View {
        Button(action: onComplete) {
            Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(todo.isCompleted ? .green : .secondary.opacity(0.4))
                .font(.system(size: 18, weight: .light))
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
    }
}
