import Foundation

struct VercelProject: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let accountId: String
    let createdAt: Int?
    let updatedAt: Int?
    let productionUrl: String?
    let latestDeployment: LatestDeployment?

    struct LatestDeployment: Codable, Sendable {
        let url: String
        let createdAt: Int
        let state: DeploymentState
    }
}

enum DeploymentState: String, Codable, Sendable {
    case ready = "READY"
    case error = "ERROR"
    case building = "BUILDING"
    case queued = "QUEUED"
    case canceled = "CANCELED"
}
