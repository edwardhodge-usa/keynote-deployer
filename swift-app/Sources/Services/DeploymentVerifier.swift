import Foundation

/// Verifies a deployed Keynote presentation by fetching main.js and index.html
/// and checking that all 7 HiDPI fixes are present.
enum DeploymentVerifier {

    private static let expectedFixes: [(number: Int, name: String, pattern: String)] = [
        (1, "zC scale (PDF rasterization)", "qC=!0;const zC=3,"),
        (2, "Fullscreen bypass", "!0||A>this.showWidth"),
        (3, "Viewport A (sparkle/particle effects)", "Q.viewport(0,0,Q.viewportWidth*3,Q.viewportHeight*3)"),
        (4, "Viewport B (firework effects)", "C.viewport(0,0,C.viewportWidth*3,C.viewportHeight*3)"),
        (5, "Resize viewport DPR scaling", "B.viewport(0,0,g*3,C*3)"),
        (6, "Constructor viewport division", "g.viewportWidth=B.width/3,g.viewportHeight=B.height/3"),
        (7, "Canvas DPR backing store", "B.width=UC.script.slideWidth*3,B.height=UC.script.slideHeight*3,B.style.width=UC.script.slideWidth*3+\"px\""),
    ]

    static func verify(
        deployUrl: String,
        onProgress: @Sendable (ProcessingStep) -> Void
    ) async -> VerificationResult {
        var fixes: [FixVerification] = []
        var totalFound = 0
        var totalMissing = 0

        do {
            onProgress(ProcessingStep(id: 14, label: "Verify deployment", detail: "Fetching deployed files...", status: .active))

            // Fetch main.js
            let mainJsUrl = URL(string: "\(deployUrl)/assets/player/main.js")!
            let (mainJsData, mainJsResp) = try await URLSession.shared.data(from: mainJsUrl)

            guard (mainJsResp as? HTTPURLResponse)?.statusCode == 200 else {
                let status = (mainJsResp as? HTTPURLResponse)?.statusCode ?? 0
                throw VerifierError.fetchFailed("main.js returned \(status)")
            }

            let mainJsContent = String(data: mainJsData, encoding: .utf8) ?? ""

            onProgress(ProcessingStep(id: 14, label: "Verify deployment", detail: "Checking fixes...", status: .active))

            // Check each fix pattern
            for fix in expectedFixes {
                let found = mainJsContent.contains(fix.pattern)
                fixes.append(FixVerification(
                    fixNumber: fix.number,
                    name: fix.name,
                    found: found,
                    pattern: String(fix.pattern.prefix(50)) + "..."
                ))
                if found { totalFound += 1 } else { totalMissing += 1 }
            }

            let mainJsVerified = totalMissing == 0

            // Fetch and verify index.html
            let indexUrl = URL(string: deployUrl)!
            let (indexData, _) = try await URLSession.shared.data(from: indexUrl)
            let indexContent = String(data: indexData, encoding: .utf8) ?? ""

            let hasPolling = indexContent.contains("pollingInterval=setInterval") && indexContent.contains("triggerReRenders")
            let hasNavBar = indexContent.contains("id=\"navBar\"")
            let hasLoadingOverlay = indexContent.contains("id=\"loadingOverlay\"")
            let indexHtmlVerified = hasPolling && hasNavBar && hasLoadingOverlay

            let success = mainJsVerified && indexHtmlVerified

            if success {
                onProgress(ProcessingStep(id: 14, label: "Verify deployment", detail: "All \(totalFound) fixes verified", status: .completed))
            } else {
                var issues: [String] = []
                if !mainJsVerified { issues.append("\(totalMissing) fixes missing") }
                if !indexHtmlVerified { issues.append("index.html issues") }
                onProgress(ProcessingStep(id: 14, label: "Verify deployment", detail: issues.joined(separator: ", "), status: .error))
            }

            return VerificationResult(
                success: success,
                url: deployUrl,
                mainJsVerified: mainJsVerified,
                indexHtmlVerified: indexHtmlVerified,
                fixes: fixes,
                totalFixesFound: totalFound,
                totalFixesMissing: totalMissing,
                error: nil
            )

        } catch {
            onProgress(ProcessingStep(id: 14, label: "Verify deployment", detail: error.localizedDescription, status: .error))

            return VerificationResult(
                success: false,
                url: deployUrl,
                mainJsVerified: false,
                indexHtmlVerified: false,
                fixes: fixes,
                totalFixesFound: totalFound,
                totalFixesMissing: totalMissing,
                error: error.localizedDescription
            )
        }
    }

    private enum VerifierError: LocalizedError {
        case fetchFailed(String)

        var errorDescription: String? {
            switch self {
            case .fetchFailed(let msg): "Verification failed: \(msg)"
            }
        }
    }
}
