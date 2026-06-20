import Foundation

enum NavigationTab: String, CaseIterable, Identifiable, Sendable {
    case deploy
    case video
    case projects
    case history
    case settings

    var id: Self { self }

    var label: String {
        switch self {
        case .deploy: "Deploy"
        case .video: "Deploy Video"
        case .projects: "Projects"
        case .history: "History"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .deploy: "cube"
        case .video: "film.stack"
        case .projects: "rectangle.grid.1x2"
        case .history: "clock"
        case .settings: "gearshape"
        }
    }
}
