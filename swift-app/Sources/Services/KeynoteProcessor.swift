import Foundation

/// Processes Keynote HTML exports: applies 7 HiDPI fixes to main.js and generates index.html wrapper.
actor KeynoteProcessor {

    static let hidpiScale = 3
    static let hidpiInv = "0.3333"

    struct Fix: Sendable {
        let name: String
        let search: String
        let replace: String
    }

    static let fixes: [Fix] = [
        Fix(
            name: "zC scale (PDF rasterization)",
            search: "qC=!0;const zC=1,",
            replace: "qC=!0;const zC=\(hidpiScale),"
        ),
        Fix(
            name: "Fullscreen bypass",
            search: "UC.isFullscreen||A>this.showWidth",
            replace: "!0||A>this.showWidth"
        ),
        Fix(
            name: "Viewport A (sparkle/particle effects)",
            search: "Q.viewport(0,0,Q.viewportWidth,Q.viewportHeight)",
            replace: "Q.viewport(0,0,Q.viewportWidth*\(hidpiScale),Q.viewportHeight*\(hidpiScale))"
        ),
        Fix(
            name: "Viewport B (firework effects)",
            search: "C.viewport(0,0,C.viewportWidth,C.viewportHeight)",
            replace: "C.viewport(0,0,C.viewportWidth*\(hidpiScale),C.viewportHeight*\(hidpiScale))"
        ),
        Fix(
            name: "Resize viewport DPR scaling",
            search: "B.viewport(0,0,g,C),B.viewportWidth=g,B.viewportHeight=C",
            replace: "B.viewport(0,0,g*\(hidpiScale),C*\(hidpiScale)),B.viewportWidth=g,B.viewportHeight=C"
        ),
        Fix(
            name: "Constructor viewport division",
            search: "g.viewportWidth=B.width,g.viewportHeight=B.height",
            replace: "g.viewportWidth=B.width/\(hidpiScale),g.viewportHeight=B.height/\(hidpiScale)"
        ),
        Fix(
            name: "Canvas DPR backing store",
            search: "B.width=UC.script.slideWidth,B.height=UC.script.slideHeight",
            replace: "B.width=UC.script.slideWidth*\(hidpiScale),B.height=UC.script.slideHeight*\(hidpiScale),B.style.width=UC.script.slideWidth*\(hidpiScale)+\"px\",B.style.height=UC.script.slideHeight*\(hidpiScale)+\"px\",B.style.transform=\"scale(\(hidpiInv))\",B.style.transformOrigin=\"0 0\""
        ),
    ]

    struct ProcessResult: Sendable {
        let fixesApplied: Int
        let fixesSkipped: Int
        let errors: [String]
    }

    /// Apply all 7 HiDPI fixes to the Keynote export at folderPath.
    func process(
        folderPath: String,
        metadata: KeynoteMetadata,
        secureEmbed: Bool,
        onProgress: @Sendable (ProcessingStep) -> Void
    ) async throws -> ProcessResult {
        let fm = FileManager.default
        let mainJsPath = (folderPath as NSString).appendingPathComponent("assets/player/main.js")
        let backupPath = mainJsPath + ".backup"

        // Step 1: Validate
        onProgress(ProcessingStep(id: 1, label: "Validate folder", detail: "Checking...", status: .active))
        guard fm.fileExists(atPath: mainJsPath) else {
            onProgress(ProcessingStep(id: 1, label: "Validate folder", detail: "main.js not found", status: .error))
            return ProcessResult(fixesApplied: 0, fixesSkipped: 0, errors: ["main.js not found"])
        }
        onProgress(ProcessingStep(id: 1, label: "Validate folder", detail: "Validated", status: .completed))

        // Step 2: Metadata
        onProgress(ProcessingStep(id: 2, label: "Read metadata", detail: "\(metadata.title) — \(metadata.slideCount) slides", status: .completed))

        // Step 3: Backup
        onProgress(ProcessingStep(id: 3, label: "Backup main.js", detail: "Checking backup...", status: .active))
        if fm.fileExists(atPath: backupPath) {
            // Restore clean copy from backup (remove destination first — copyItem throws if it exists)
            try fm.removeItem(atPath: mainJsPath)
            try fm.copyItem(atPath: backupPath, toPath: mainJsPath)
            onProgress(ProcessingStep(id: 3, label: "Backup main.js", detail: "Restored from backup", status: .completed))
        } else {
            try fm.copyItem(atPath: mainJsPath, toPath: backupPath)
            onProgress(ProcessingStep(id: 3, label: "Backup main.js", detail: "Backup created", status: .completed))
        }

        // Read content
        var content = try String(contentsOfFile: mainJsPath, encoding: .utf8)
        var fixesApplied = 0
        var fixesSkipped = 0
        var errors: [String] = []

        // Steps 4-10: Apply fixes
        for (i, fix) in Self.fixes.enumerated() {
            let stepId = i + 4
            let stepLabel = "Fix \(i + 1): \(fix.name)"
            onProgress(ProcessingStep(id: stepId, label: stepLabel, detail: "Applying...", status: .active))

            if content.contains(fix.search) {
                content = content.replacingOccurrences(of: fix.search, with: fix.replace)
                fixesApplied += 1
                onProgress(ProcessingStep(id: stepId, label: stepLabel, detail: "Applied", status: .completed))
            } else if content.contains(fix.replace) {
                fixesSkipped += 1
                onProgress(ProcessingStep(id: stepId, label: stepLabel, detail: "Already applied — skipped", status: .skipped))
            } else {
                errors.append("Fix \(i + 1) (\(fix.name)): pattern not found")
                onProgress(ProcessingStep(id: stepId, label: stepLabel, detail: "Pattern not found", status: .error))
            }
        }

        // Write modified content
        try content.write(toFile: mainJsPath, atomically: true, encoding: .utf8)

        // Step 11: Generate index.html
        onProgress(ProcessingStep(id: 11, label: "Generate index.html", detail: "Creating wrapper...", status: .active))
        let indexHtml = IndexHtmlGenerator.generate(slideCount: metadata.slideCount, secureEmbed: secureEmbed)
        let indexPath = (folderPath as NSString).appendingPathComponent("index.html")
        try indexHtml.write(toFile: indexPath, atomically: true, encoding: .utf8)
        onProgress(ProcessingStep(id: 11, label: "Generate index.html", detail: "Created", status: .completed))

        return ProcessResult(fixesApplied: fixesApplied, fixesSkipped: fixesSkipped, errors: errors)
    }
}
