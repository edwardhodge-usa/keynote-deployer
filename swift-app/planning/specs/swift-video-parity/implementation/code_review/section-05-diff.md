diff --git a/swift-app/KeynoteDeployer.xcodeproj/project.pbxproj b/swift-app/KeynoteDeployer.xcodeproj/project.pbxproj
index 8336eed..c3a5007 100644
--- a/swift-app/KeynoteDeployer.xcodeproj/project.pbxproj
+++ b/swift-app/KeynoteDeployer.xcodeproj/project.pbxproj
@@ -27,6 +27,7 @@
 		53C52E6F5AC05C366512AD08 /* NavigationTab.swift in Sources */ = {isa = PBXBuildFile; fileRef = 91B38AC4D9349306424DE153 /* NavigationTab.swift */; };
 		54EA0EA3D9BD76F228023924 /* SettingsView.swift in Sources */ = {isa = PBXBuildFile; fileRef = 4A3AD033AAD0411C7CA1B6CD /* SettingsView.swift */; };
 		68FCF5155F11F63CBB34761F /* DeploymentVerifier.swift in Sources */ = {isa = PBXBuildFile; fileRef = 25181D8CAB9909769D352295 /* DeploymentVerifier.swift */; };
+		6CA11C44E5D0640DB47D2A83 /* FFmpegVideoEncoderTests.swift in Sources */ = {isa = PBXBuildFile; fileRef = 21BB4E825DF33B80AB6A0E9C /* FFmpegVideoEncoderTests.swift */; };
 		70CBE64B6030B4BAC00B9F32 /* FileOperations.swift in Sources */ = {isa = PBXBuildFile; fileRef = 082147F09FC716A0BEAD8B15 /* FileOperations.swift */; };
 		77788CDBF10422EED9C391D2 /* video-viewer-template.html in Resources */ = {isa = PBXBuildFile; fileRef = 0C46C9CD46B3D1C3098570B6 /* video-viewer-template.html */; };
 		7DAEEC6461E2EA43B6189CBE /* UpdaterService.swift in Sources */ = {isa = PBXBuildFile; fileRef = 1C1AE82499CE26C6968F8AA7 /* UpdaterService.swift */; };
@@ -41,6 +42,7 @@
 		BE71A16FFD585CD12AD762B1 /* KeynoteMetadata.swift in Sources */ = {isa = PBXBuildFile; fileRef = CE7E2BD93E4F1F90654BA3E7 /* KeynoteMetadata.swift */; };
 		C1320156DDC609C7483B1F6A /* GridSampler.swift in Sources */ = {isa = PBXBuildFile; fileRef = 38B3998DF7B225F311525034 /* GridSampler.swift */; };
 		C4E54C86FF711C684113EACE /* HistoryView.swift in Sources */ = {isa = PBXBuildFile; fileRef = B55FB9E316B645CFD0C08B4F /* HistoryView.swift */; };
+		C6F91B76D51C9A06A0354265 /* FFmpegVideoEncoder.swift in Sources */ = {isa = PBXBuildFile; fileRef = 62962D07AF83802E42A4D632 /* FFmpegVideoEncoder.swift */; };
 		CF38C9DBAC8AFF2AF62781ED /* VideoViewerGeneratorTests.swift in Sources */ = {isa = PBXBuildFile; fileRef = B13D91BAAE5426D7EB676719 /* VideoViewerGeneratorTests.swift */; };
 		D11E662E9329C958E5FD05BE /* VideoDeployRequest.swift in Sources */ = {isa = PBXBuildFile; fileRef = CBCFD1B404C9D887FD5FA7B0 /* VideoDeployRequest.swift */; };
 		EA8F1C902A8D2AD7D8A93A30 /* AppConfig.swift in Sources */ = {isa = PBXBuildFile; fileRef = 390DDF13A88F1C59BE62D165 /* AppConfig.swift */; };
@@ -66,6 +68,7 @@
 		17821C750B379235D1F37C5E /* PipelineResult.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = PipelineResult.swift; sourceTree = "<group>"; };
 		17A85902F080898C86352154 /* VercelAPI.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = VercelAPI.swift; sourceTree = "<group>"; };
 		1C1AE82499CE26C6968F8AA7 /* UpdaterService.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = UpdaterService.swift; sourceTree = "<group>"; };
+		21BB4E825DF33B80AB6A0E9C /* FFmpegVideoEncoderTests.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = FFmpegVideoEncoderTests.swift; sourceTree = "<group>"; };
 		23F61A6BE61C1CDC6237ADF6 /* VercelProject.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = VercelProject.swift; sourceTree = "<group>"; };
 		25181D8CAB9909769D352295 /* DeploymentVerifier.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = DeploymentVerifier.swift; sourceTree = "<group>"; };
 		252E013E7FB809AC24354D6C /* DeployProgressView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = DeployProgressView.swift; sourceTree = "<group>"; };
@@ -83,6 +86,7 @@
 		5D3403EAA4D97975ADF59927 /* VideoAnalysis.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = VideoAnalysis.swift; sourceTree = "<group>"; };
 		6014F6E3BFFA0FEA826D475F /* HistoryEntry.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = HistoryEntry.swift; sourceTree = "<group>"; };
 		61E0452AB31EE55316A70A2D /* video-viewer-golden-secure.html */ = {isa = PBXFileReference; lastKnownFileType = text.html; path = "video-viewer-golden-secure.html"; sourceTree = "<group>"; };
+		62962D07AF83802E42A4D632 /* FFmpegVideoEncoder.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = FFmpegVideoEncoder.swift; sourceTree = "<group>"; };
 		643B10849DA333A7037B54A5 /* KeynoteDeployer.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = KeynoteDeployer.app; sourceTree = BUILT_PRODUCTS_DIR; };
 		66C0C927B53D57B936E42EA7 /* Sparkle.xcconfig */ = {isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Sparkle.xcconfig; sourceTree = "<group>"; };
 		6E9CE1B85FB4D719BE7B0EC8 /* ProcessingStep.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ProcessingStep.swift; sourceTree = "<group>"; };
@@ -122,6 +126,7 @@
 			children = (
 				3BB79FDC1EFBE27B83DABD22 /* AVFoundationVideoEncoder.swift */,
 				25181D8CAB9909769D352295 /* DeploymentVerifier.swift */,
+				62962D07AF83802E42A4D632 /* FFmpegVideoEncoder.swift */,
 				082147F09FC716A0BEAD8B15 /* FileOperations.swift */,
 				38B3998DF7B225F311525034 /* GridSampler.swift */,
 				A80FCBDC9C1ECDDA55886B5A /* IndexHtmlGenerator.swift */,
@@ -212,6 +217,7 @@
 			isa = PBXGroup;
 			children = (
 				3DF19AE8FCC6FD1C9ADE5B8A /* AVFoundationVideoEncoderTests.swift */,
+				21BB4E825DF33B80AB6A0E9C /* FFmpegVideoEncoderTests.swift */,
 				403D899438A463CD2A362774 /* GridSamplerTests.swift */,
 				AA065551FEEAB39DDEAC9B60 /* ModelsAndProjectTests.swift */,
 				E0A6C88075BDCE7E6E5AF0C9 /* StillsMatchTests.swift */,
@@ -365,6 +371,7 @@
 			buildActionMask = 2147483647;
 			files = (
 				FED0CB7E95A656D351958D95 /* AVFoundationVideoEncoderTests.swift in Sources */,
+				6CA11C44E5D0640DB47D2A83 /* FFmpegVideoEncoderTests.swift in Sources */,
 				A14416E992CD0B244FFA16A1 /* GridSamplerTests.swift in Sources */,
 				419F05D5433E94752E999ED6 /* ModelsAndProjectTests.swift in Sources */,
 				4B289C6795B7E64A9625F96D /* StillsMatchTests.swift in Sources */,
@@ -383,6 +390,7 @@
 				9467E10D5FA4765BE26819DF /* DeployProgressView.swift in Sources */,
 				84AF2E114BF9B992367626D4 /* DeployView.swift in Sources */,
 				68FCF5155F11F63CBB34761F /* DeploymentVerifier.swift in Sources */,
+				C6F91B76D51C9A06A0354265 /* FFmpegVideoEncoder.swift in Sources */,
 				70CBE64B6030B4BAC00B9F32 /* FileOperations.swift in Sources */,
 				C1320156DDC609C7483B1F6A /* GridSampler.swift in Sources */,
 				32E92AFC106BE6E110B3B5BA /* HistoryEntry.swift in Sources */,
diff --git a/swift-app/Sources/Services/FFmpegVideoEncoder.swift b/swift-app/Sources/Services/FFmpegVideoEncoder.swift
new file mode 100644
index 0000000..514bf08
--- /dev/null
+++ b/swift-app/Sources/Services/FFmpegVideoEncoder.swift
@@ -0,0 +1,201 @@
+import Foundation
+
+/// Fallback `VideoEncoder` that shells out to `ffmpeg`/`ffprobe` via an argument
+/// ARRAY `Process` (never a shell). Reproduces the EXACT flags of the live
+/// Electron `videoDeckPipeline.ts` so its output is byte-equivalent to the
+/// already-quality-approved ffmpeg deploy path.
+///
+/// Not the default and NOT bundled — selected only via the hidden
+/// `useFfmpegEncoder` UserDefaults flag (wired in Section 07). Safety net for
+/// `AVFoundationVideoEncoder`: if the AV H.264 quality is rejected, flip the flag
+/// (no rebuild) to swap this in.
+struct FFmpegVideoEncoder: VideoEncoder {
+
+    /// Explicit binary paths (tests inject a known/nonexistent path); nil → discover.
+    let ffmpegPath: String?
+    let ffprobePath: String?
+
+    init(ffmpegPath: String? = nil, ffprobePath: String? = nil) {
+        self.ffmpegPath = ffmpegPath
+        self.ffprobePath = ffprobePath
+    }
+
+    private static let sampleW = 32
+    private static let sampleH = 18
+    private static let frameBytes = 32 * 18 * 3   // 1728, matches GridSampler.valueCount
+
+    // MARK: - Pure argument builders (arg-parity + security tested directly)
+
+    /// ffprobe args — verbatim parity with Electron `probeVideo`.
+    static func probeArgs(input: String) -> [String] {
+        ["-v", "error", "-select_streams", "v:0",
+         "-show_entries", "stream=width,height,r_frame_rate",
+         "-of", "default=noprint_wrappers=1", input]
+    }
+
+    /// ffmpeg args — verbatim parity with Electron `sampleGrids`. Raw rgb24 on stdout.
+    static func sampleArgs(input: String) -> [String] {
+        ["-v", "error", "-i", input,
+         "-vf", "scale=\(sampleW):\(sampleH)",
+         "-f", "rawvideo", "-pix_fmt", "rgb24", "-"]
+    }
+
+    /// ffmpeg args — verbatim parity with Electron `encodeWithKeyframes`.
+    /// `-force_key_frames` is the timestamps joined by `,` using JS Number
+    /// formatting (Electron does `timestamps.join(',')`, so 0/2.5/5 → "0,2.5,5",
+    /// NOT "0.0,2.5,5.0").
+    static func encodeArgs(input: String, output: String, timestamps: [Double], crf: Int = 18) -> [String] {
+        let kf = timestamps.map(jsNumber).joined(separator: ",")
+        return ["-y", "-i", input,
+                "-c:v", "libx264", "-crf", String(crf), "-preset", "medium",
+                "-pix_fmt", "yuv420p",
+                "-force_key_frames", kf,
+                "-movflags", "+faststart", "-an",
+                output]
+    }
+
+    /// Format a Double the way JavaScript `Array.join`/`Number.toString` does, so
+    /// the `-force_key_frames` CSV is byte-identical to the Electron path. Mirrors
+    /// VideoViewerGenerator's JSON-number formatting.
+    static func jsNumber(_ x: Double) -> String {
+        if x.isFinite && x == x.rounded() { return String(format: "%.0f", x) }
+        var s = String(format: "%.3f", x)
+        while s.hasSuffix("0") { s.removeLast() }
+        if s.hasSuffix(".") { s.removeLast() }
+        return s
+    }
+
+    // MARK: - VideoEncoder
+
+    func probe(url: URL) async throws -> (width: Int, height: Int, fps: Double) {
+        let ffprobe = try resolvedFfprobe()
+        let (data, _) = try await Self.run(executable: ffprobe, arguments: Self.probeArgs(input: url.path))
+        let out = String(data: data, encoding: .utf8) ?? ""
+
+        let w = Self.firstInt(in: out, pattern: #"width=(\d+)"#) ?? 1920
+        let h = Self.firstInt(in: out, pattern: #"height=(\d+)"#) ?? 1080
+        var fps = 30.0
+        if let m = Self.firstMatch(in: out, pattern: #"r_frame_rate=(\d+)/(\d+)"#, groups: 2),
+           let num = Double(m[0]), let den = Double(m[1]), den != 0 {
+            fps = num / den
+        }
+        return (w, h, fps)
+    }
+
+    func sampleGrids(url: URL) async throws -> [[Double]] {
+        let ffmpeg = try resolvedFfmpeg()
+        let (data, _) = try await Self.run(executable: ffmpeg, arguments: Self.sampleArgs(input: url.path))
+        let count = data.count / Self.frameBytes
+        guard count > 0 else { return [] }
+        var grids: [[Double]] = []
+        grids.reserveCapacity(count)
+        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
+            let bytes = raw.bindMemory(to: UInt8.self)
+            for i in 0..<count {
+                let start = i * Self.frameBytes
+                var grid = [Double](repeating: 0, count: Self.frameBytes)
+                for j in 0..<Self.frameBytes { grid[j] = Double(bytes[start + j]) }
+                grids.append(grid)
+            }
+        }
+        return grids
+    }
+
+    func encodeWithKeyframes(input: URL, output: URL, timestamps: [Double]) async throws {
+        let ffmpeg = try resolvedFfmpeg()
+        let args = Self.encodeArgs(input: input.path, output: output.path, timestamps: timestamps)
+        let (_, status) = try await Self.run(executable: ffmpeg, arguments: args)
+        guard status == 0 else {
+            try? FileManager.default.removeItem(at: output)
+            throw VideoEncoderError.writerFailed("ffmpeg exited with status \(status)")
+        }
+    }
+
+    // MARK: - Binary discovery
+
+    private func resolvedFfmpeg() throws -> String { try Self.resolveBinary(name: "ffmpeg", explicit: ffmpegPath) }
+    private func resolvedFfprobe() throws -> String { try Self.resolveBinary(name: "ffprobe", explicit: ffprobePath) }
+
+    private static func resolveBinary(name: String, explicit: String?) throws -> String {
+        if let explicit {
+            if FileManager.default.fileExists(atPath: explicit) { return explicit }
+            throw VideoEncoderError.binaryNotFound(
+                "\(name) not found at \(explicit). Install via Homebrew: brew install ffmpeg")
+        }
+        // `which <name>` first.
+        let which = Process()
+        which.executableURL = URL(fileURLWithPath: "/usr/bin/which")
+        which.arguments = [name]
+        let pipe = Pipe()
+        which.standardOutput = pipe
+        try? which.run()
+        which.waitUntilExit()
+        let found = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
+            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
+        if !found.isEmpty, FileManager.default.fileExists(atPath: found) { return found }
+
+        for candidate in ["/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)"] {
+            if FileManager.default.fileExists(atPath: candidate) { return candidate }
+        }
+        throw VideoEncoderError.binaryNotFound(
+            "\(name) not found on PATH. Install via Homebrew: brew install ffmpeg")
+    }
+
+    // MARK: - Process runner (argument array, never a shell; pipe-drained)
+
+    /// Runs `executable` with `arguments` (no shell). Drains stdout on a
+    /// background thread before waiting (rawvideo can be hundreds of MB → a full
+    /// pipe buffer would deadlock the child). Honors task cancellation by
+    /// terminating the process. Returns (stdoutData, exitStatus).
+    private static func run(executable: String, arguments: [String]) async throws -> (Data, Int32) {
+        try Task.checkCancellation()
+        let process = Process()
+        process.executableURL = URL(fileURLWithPath: executable)
+        process.arguments = arguments
+
+        var env = ProcessInfo.processInfo.environment
+        let currentPath = env["PATH"] ?? ""
+        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(currentPath)"
+        process.environment = env
+
+        let stdoutPipe = Pipe()
+        let stderrPipe = Pipe()
+        process.standardOutput = stdoutPipe
+        process.standardError = stderrPipe
+
+        return try await withTaskCancellationHandler {
+            do { try process.run() }
+            catch { throw VideoEncoderError.writerFailed("could not launch \(executable): \(error.localizedDescription)") }
+
+            // Drain stdout off-thread BEFORE waitUntilExit (deadlock guard).
+            let stdoutData: Data = await withUnsafeContinuation { cont in
+                DispatchQueue.global().async {
+                    cont.resume(returning: stdoutPipe.fileHandleForReading.readDataToEndOfFile())
+                }
+            }
+            _ = try? stderrPipe.fileHandleForReading.readToEnd()
+            process.waitUntilExit()
+            return (stdoutData, process.terminationStatus)
+        } onCancel: {
+            process.terminate()
+        }
+    }
+
+    // MARK: - Regex helpers
+
+    private static func firstMatch(in text: String, pattern: String, groups: Int) -> [String]? {
+        guard let re = try? NSRegularExpression(pattern: pattern),
+              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
+        var out: [String] = []
+        for g in 1...groups {
+            guard let r = Range(m.range(at: g), in: text) else { return nil }
+            out.append(String(text[r]))
+        }
+        return out
+    }
+
+    private static func firstInt(in text: String, pattern: String) -> Int? {
+        guard let m = firstMatch(in: text, pattern: pattern, groups: 1) else { return nil }
+        return Int(m[0])
+    }
+}
diff --git a/swift-app/Sources/Services/VideoEncoding.swift b/swift-app/Sources/Services/VideoEncoding.swift
index 8ef2f34..15dd94f 100644
--- a/swift-app/Sources/Services/VideoEncoding.swift
+++ b/swift-app/Sources/Services/VideoEncoding.swift
@@ -26,6 +26,7 @@ enum VideoEncoderError: Error, LocalizedError, Sendable, Equatable {
     case variableFrameRate
     case readerFailed(String)
     case writerFailed(String)
+    case binaryNotFound(String)
     case cancelled
 
     var errorDescription: String? {
@@ -40,6 +41,8 @@ enum VideoEncoderError: Error, LocalizedError, Sendable, Equatable {
             return "Reading the source video failed: \(detail)"
         case .writerFailed(let detail):
             return "Encoding the video failed: \(detail)"
+        case .binaryNotFound(let detail):
+            return detail
         case .cancelled:
             return "Encoding was cancelled."
         }
diff --git a/swift-app/Tests/FFmpegVideoEncoderTests.swift b/swift-app/Tests/FFmpegVideoEncoderTests.swift
new file mode 100644
index 0000000..06f2c34
--- /dev/null
+++ b/swift-app/Tests/FFmpegVideoEncoderTests.swift
@@ -0,0 +1,115 @@
+import Testing
+import Foundation
+@testable import KeynoteDeployer
+
+/// Section 5 — FFmpegVideoEncoder. Offline: exercises the pure arg builders, the
+/// A1 no-shell/inert-path security property, and the missing-binary error.
+/// Does NOT require ffmpeg installed or any real video.
+@Suite("Section 5 — FFmpegVideoEncoder")
+struct FFmpegVideoEncoderTests {
+
+    // MARK: Arg parity vs electron/videoDeckPipeline.ts
+
+    @Test func probeArgsMatchElectron() {
+        #expect(FFmpegVideoEncoder.probeArgs(input: "/tmp/in.mp4") == [
+            "-v", "error", "-select_streams", "v:0",
+            "-show_entries", "stream=width,height,r_frame_rate",
+            "-of", "default=noprint_wrappers=1", "/tmp/in.mp4",
+        ])
+    }
+
+    @Test func sampleArgsMatchElectron() {
+        #expect(FFmpegVideoEncoder.sampleArgs(input: "/tmp/in.mp4") == [
+            "-v", "error", "-i", "/tmp/in.mp4",
+            "-vf", "scale=32:18",
+            "-f", "rawvideo", "-pix_fmt", "rgb24", "-",
+        ])
+    }
+
+    @Test func encodeArgsMatchElectron() {
+        // Electron does timestamps.join(',') on JS numbers → "0,2.5,5" (NOT "0.0,2.5,5.0").
+        #expect(FFmpegVideoEncoder.encodeArgs(
+            input: "/tmp/in.mp4", output: "/tmp/out.mp4",
+            timestamps: [0.0, 2.5, 5.0]) == [
+            "-y", "-i", "/tmp/in.mp4",
+            "-c:v", "libx264", "-crf", "18", "-preset", "medium",
+            "-pix_fmt", "yuv420p",
+            "-force_key_frames", "0,2.5,5",
+            "-movflags", "+faststart", "-an",
+            "/tmp/out.mp4",
+        ])
+    }
+
+    @Test func encodeArgsForceKeyFramesCsvIsJsNumberFormatted() {
+        // integers no decimal, 3-decimal fractionals strip trailing zeros
+        let args = FFmpegVideoEncoder.encodeArgs(
+            input: "i", output: "o", timestamps: [0, 1.234, 5.6, 12])
+        let i = args.firstIndex(of: "-force_key_frames")!
+        #expect(args[i + 1] == "0,1.234,5.6,12")
+    }
+
+    @Test func encodeArgsRespectsCustomCrf() {
+        let args = FFmpegVideoEncoder.encodeArgs(input: "i", output: "o", timestamps: [0], crf: 23)
+        let i = args.firstIndex(of: "-crf")!
+        #expect(args[i + 1] == "23")
+    }
+
+    // MARK: A1 — no shell, injection-laden path stays one inert argument
+
+    @Test func injectionFilenameIsOneInertArgument() {
+        let evil = "a\"; rm -rf ~ #.mp4"
+        for args in [
+            FFmpegVideoEncoder.sampleArgs(input: evil),
+            FFmpegVideoEncoder.probeArgs(input: evil),
+            FFmpegVideoEncoder.encodeArgs(input: evil, output: evil, timestamps: [0]),
+        ] {
+            // the payload appears verbatim as discrete element(s), never escaped/spliced
+            #expect(args.contains(evil))
+            // nothing got merged into a single shell command string
+            #expect(!args.contains { $0.contains("/bin/sh") })
+            #expect(!args.contains { $0.contains("rm -rf ~ #.mp4 ") })   // no concatenation
+        }
+    }
+
+    // MARK: Missing binary → clear, actionable (Homebrew) error
+
+    @Test func missingFfprobeThrowsActionable() async {
+        let enc = FFmpegVideoEncoder(ffmpegPath: "/nonexistent/ffmpeg", ffprobePath: "/nonexistent/ffprobe")
+        await #expect {
+            _ = try await enc.probe(url: URL(fileURLWithPath: "/tmp/x.mp4"))
+        } throws: { error in
+            let msg = (error as? VideoEncoderError)?.errorDescription ?? ""
+            return msg.contains("ffprobe") && msg.lowercased().contains("brew install ffmpeg")
+        }
+    }
+
+    @Test func missingFfmpegThrowsActionable() async {
+        let enc = FFmpegVideoEncoder(ffmpegPath: "/nonexistent/ffmpeg", ffprobePath: "/nonexistent/ffprobe")
+        await #expect {
+            _ = try await enc.sampleGrids(url: URL(fileURLWithPath: "/tmp/x.mp4"))
+        } throws: { error in
+            let msg = (error as? VideoEncoderError)?.errorDescription ?? ""
+            return msg.contains("ffmpeg") && msg.lowercased().contains("brew install ffmpeg")
+        }
+    }
+
+    @Test func missingFfmpegOnEncodeThrowsActionable() async {
+        let enc = FFmpegVideoEncoder(ffmpegPath: "/nonexistent/ffmpeg", ffprobePath: "/nonexistent/ffprobe")
+        await #expect {
+            try await enc.encodeWithKeyframes(
+                input: URL(fileURLWithPath: "/tmp/x.mp4"),
+                output: URL(fileURLWithPath: "/tmp/y.mp4"), timestamps: [0])
+        } throws: { error in
+            let msg = (error as? VideoEncoderError)?.errorDescription ?? ""
+            return msg.contains("ffmpeg") && msg.lowercased().contains("brew install ffmpeg")
+        }
+    }
+
+    // MARK: Conforms to the Section-04 protocol
+
+    @Test func conformsToVideoEncoder() {
+        func requireEncoder(_: some VideoEncoder) {}
+        requireEncoder(FFmpegVideoEncoder())
+        #expect(true)
+    }
+}
