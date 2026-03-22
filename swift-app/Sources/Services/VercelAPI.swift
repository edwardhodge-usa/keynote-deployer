import Foundation

/// Vercel REST API client for project management and deployment URL resolution.
actor VercelAPI {
    private let token: String
    private let teamId: String

    init(token: String, teamId: String) {
        self.token = token
        self.teamId = teamId
    }

    private var authHeaders: [String: String] {
        ["Authorization": "Bearer \(token)"]
    }

    /// Fetch or create a Vercel project by name.
    func ensureProject(name: String) async throws -> VercelProject {
        // Try GET first
        let getURL = URL(string: "https://api.vercel.com/v9/projects/\(name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name)?teamId=\(teamId)")!
        var getReq = URLRequest(url: getURL)
        getReq.allHTTPHeaderFields = authHeaders

        let (getData, getResp) = try await URLSession.shared.data(for: getReq)
        if (getResp as? HTTPURLResponse)?.statusCode == 200 {
            return try JSONDecoder().decode(VercelProject.self, from: getData)
        }

        // Create new project
        let createURL = URL(string: "https://api.vercel.com/v10/projects?teamId=\(teamId)")!
        var createReq = URLRequest(url: createURL)
        createReq.httpMethod = "POST"
        createReq.allHTTPHeaderFields = authHeaders
        createReq.addValue("application/json", forHTTPHeaderField: "Content-Type")
        createReq.httpBody = try JSONEncoder().encode(["name": name])

        let (createData, createResp) = try await URLSession.shared.data(for: createReq)
        guard (createResp as? HTTPURLResponse)?.statusCode == 200 else {
            let body = String(data: createData, encoding: .utf8) ?? "Unknown error"
            throw VercelError.projectCreationFailed(body)
        }

        return try JSONDecoder().decode(VercelProject.self, from: createData)
    }

    /// Fetch all Vercel projects, filtered to only those in local history.
    func fetchProjects(deployedNames: Set<String>) async throws -> [VercelProject] {
        let url = URL(string: "https://api.vercel.com/v9/projects?teamId=\(teamId)&limit=100")!
        var req = URLRequest(url: url)
        req.allHTTPHeaderFields = authHeaders

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw VercelError.fetchFailed(body)
        }

        let response = try JSONDecoder().decode(ProjectsResponse.self, from: data)
        return response.projects.filter { deployedNames.contains($0.name) }
    }

    /// Delete a Vercel project by ID.
    func deleteProject(id: String) async throws {
        let url = URL(string: "https://api.vercel.com/v9/projects/\(id)?teamId=\(teamId)")!
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.allHTTPHeaderFields = authHeaders

        let (_, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 || status == 204 || status == 404 else {
            throw VercelError.deleteFailed("Status: \(status)")
        }
    }

    /// Get the actual production URL from project aliases (handles Vercel subdomain truncation).
    func resolveProductionUrl(projectId: String) async throws -> String? {
        let url = URL(string: "https://api.vercel.com/v9/projects/\(projectId)?teamId=\(teamId)")!
        var req = URLRequest(url: url)
        req.allHTTPHeaderFields = authHeaders

        let (data, _) = try await URLSession.shared.data(for: req)
        let project = try JSONDecoder().decode(ProjectDetailResponse.self, from: data)

        let aliases = project.targets?.production?.alias ?? []
        let vercelDomain = aliases.first { $0.hasSuffix(".vercel.app") && !$0.contains("-edward-hodges-") }
            ?? aliases.first { $0.hasSuffix(".vercel.app") }

        return vercelDomain.map { "https://\($0)" }
    }
}

enum VercelError: LocalizedError {
    case projectCreationFailed(String)
    case fetchFailed(String)
    case deleteFailed(String)

    var errorDescription: String? {
        switch self {
        case .projectCreationFailed(let msg): "Failed to create project: \(msg)"
        case .fetchFailed(let msg): "Failed to fetch projects: \(msg)"
        case .deleteFailed(let msg): "Failed to delete project: \(msg)"
        }
    }
}

// MARK: - API response types

private struct ProjectsResponse: Codable {
    let projects: [VercelProject]
}

private struct ProjectDetailResponse: Codable {
    let targets: Targets?

    struct Targets: Codable {
        let production: Production?

        struct Production: Codable {
            let alias: [String]?
        }
    }
}
