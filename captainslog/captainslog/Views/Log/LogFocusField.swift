import Foundation

nonisolated enum LogFocusField: Hashable {
    case list
    case title(UUID)
    case content(UUID)
}
