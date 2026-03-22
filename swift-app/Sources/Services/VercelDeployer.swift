import Foundation

/// Handles Vercel CLI deployment (shell out to `vercel` binary).
enum VercelDeployer {

    /// Deploy a folder to Vercel using the CLI.
    static func deploy(
        folderPath: String,
        projectId: String,
        token: String,
        teamId: String,
        secureEmbed: Bool,
        embedAllowedDomains: String,
        onProgress: @Sendable (ProcessingStep) -> Void
    ) async throws -> DeployResult {

        // Write vercel.json with CSP headers if secure embed
        if secureEmbed, !embedAllowedDomains.isEmpty {
            try writeVercelConfig(
                folderPath: folderPath,
                allowedDomains: embedAllowedDomains
            )
        }

        onProgress(ProcessingStep(id: 13, label: "Deploy", detail: "Uploading files...", status: .active))

        let vercelBin = try findVercelCli()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: vercelBin)
        process.arguments = ["--prod", "--yes", "--token", token]
        process.currentDirectoryURL = URL(fileURLWithPath: folderPath)

        var env = ProcessInfo.processInfo.environment
        env["VERCEL_ORG_ID"] = teamId
        env["VERCEL_PROJECT_ID"] = projectId
        let currentPath = env["PATH"] ?? ""
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(currentPath)"
        process.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        // Drain pipes on background threads to avoid deadlock
        // (if pipe buffer fills before waitUntilExit, child blocks and we hang)
        let stdoutData: Data = await withUnsafeContinuation { cont in
            DispatchQueue.global().async {
                cont.resume(returning: stdoutPipe.fileHandleForReading.readDataToEndOfFile())
            }
        }
        let stderrData: Data = await withUnsafeContinuation { cont in
            DispatchQueue.global().async {
                cont.resume(returning: stderrPipe.fileHandleForReading.readDataToEndOfFile())
            }
        }
        process.waitUntilExit()

        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""
        let output = stdout + "\n" + stderr

        guard output.contains("Aliased:") || output.contains("Production:") else {
            onProgress(ProcessingStep(id: 13, label: "Deploy", detail: "Deployment may have failed", status: .error))
            return DeployResult(success: false, url: "", error: "Deployment may have failed. Output: \(String(output.prefix(500)))")
        }

        onProgress(ProcessingStep(id: 13, label: "Deploy", detail: "Deployment complete", status: .completed))
        return DeployResult(success: true, url: "", error: nil)
    }

    struct DeployResult: Sendable {
        let success: Bool
        let url: String
        let error: String?
    }

    private static func findVercelCli() throws -> String {
        let candidates = [
            "/opt/homebrew/bin/vercel",
            "/usr/local/bin/vercel",
            "\(NSHomeDirectory())/.npm-global/bin/vercel",
        ]

        // Try `which vercel` first
        let which = Process()
        which.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        which.arguments = ["vercel"]
        let pipe = Pipe()
        which.standardOutput = pipe
        try? which.run()
        which.waitUntilExit()

        let whichResult = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !whichResult.isEmpty, FileManager.default.fileExists(atPath: whichResult) {
            return whichResult
        }

        for candidate in candidates {
            if FileManager.default.fileExists(atPath: candidate) {
                return candidate
            }
        }

        throw VercelError.fetchFailed("Vercel CLI not found. Install with: npm i -g vercel")
    }

    private static func writeVercelConfig(folderPath: String, allowedDomains: String) throws {
        let domains = allowedDomains
            .components(separatedBy: .whitespacesAndNewlines.union(.init(charactersIn: ",")))
            .filter { !$0.isEmpty }
            .map { $0.hasPrefix("https://") ? $0 : "https://\($0)" }
            .joined(separator: " ")

        let config: [String: Any] = [
            "headers": [
                [
                    "source": "/(.*)",
                    "headers": [
                        ["key": "Content-Security-Policy", "value": "frame-ancestors 'self' \(domains)"],
                        ["key": "X-Content-Type-Options", "value": "nosniff"],
                    ],
                ],
            ],
        ]

        let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
        let path = (folderPath as NSString).appendingPathComponent("vercel.json")
        try data.write(to: URL(fileURLWithPath: path))
    }
}
