import Foundation

/// Fallback `VideoEncoder` that shells out to `ffmpeg`/`ffprobe` via an argument
/// ARRAY `Process` (never a shell). Reproduces the EXACT flags of the live
/// Electron `videoDeckPipeline.ts` so its output is byte-equivalent to the
/// already-quality-approved ffmpeg deploy path.
///
/// Not the default and NOT bundled — selected only via the hidden
/// `useFfmpegEncoder` UserDefaults flag (wired in Section 07). Safety net for
/// `AVFoundationVideoEncoder`: if the AV H.264 quality is rejected, flip the flag
/// (no rebuild) to swap this in.
struct FFmpegVideoEncoder: VideoEncoder {

    /// Explicit binary paths (tests inject a known/nonexistent path); nil → discover.
    let ffmpegPath: String?
    let ffprobePath: String?

    init(ffmpegPath: String? = nil, ffprobePath: String? = nil) {
        self.ffmpegPath = ffmpegPath
        self.ffprobePath = ffprobePath
    }

    private static let sampleW = 32
    private static let sampleH = 18
    private static let frameBytes = 32 * 18 * 3   // 1728, matches GridSampler.valueCount

    // MARK: - Pure argument builders (arg-parity + security tested directly)

    /// ffprobe args — verbatim parity with Electron `probeVideo`.
    static func probeArgs(input: String) -> [String] {
        ["-v", "error", "-select_streams", "v:0",
         "-show_entries", "stream=width,height,r_frame_rate",
         "-of", "default=noprint_wrappers=1", input]
    }

    /// ffmpeg args — verbatim parity with Electron `sampleGrids`. Raw rgb24 on stdout.
    static func sampleArgs(input: String) -> [String] {
        ["-v", "error", "-i", input,
         "-vf", "scale=\(sampleW):\(sampleH)",
         "-f", "rawvideo", "-pix_fmt", "rgb24", "-"]
    }

    /// ffmpeg args — verbatim parity with Electron `encodeWithKeyframes`.
    /// `-force_key_frames` is the timestamps joined by `,` using JS Number
    /// formatting (Electron does `timestamps.join(',')`, so 0/2.5/5 → "0,2.5,5",
    /// NOT "0.0,2.5,5.0").
    static func encodeArgs(input: String, output: String, timestamps: [Double], crf: Int = 18) -> [String] {
        // -force_key_frames CSV uses the shared JS-number formatter so it is
        // byte-identical to Electron's `timestamps.join(',')` ("0,2.5,5", not
        // "0.0,2.5,5.0") — the SAME helper the video viewer uses, so the two
        // engines cannot drift.
        let kf = timestamps.map(JSNumber.format).joined(separator: ",")
        return ["-y", "-i", input,
                "-c:v", "libx264", "-crf", String(crf), "-preset", "medium",
                "-pix_fmt", "yuv420p",
                "-force_key_frames", kf,
                "-movflags", "+faststart", "-an",
                output]
    }

    // MARK: - VideoEncoder

    func probe(url: URL) async throws -> (width: Int, height: Int, fps: Double) {
        let ffprobe = try resolvedFfprobe()
        let (data, _) = try await Self.run(executable: ffprobe, arguments: Self.probeArgs(input: url.path))
        let out = String(data: data, encoding: .utf8) ?? ""

        let w = Self.firstInt(in: out, pattern: #"width=(\d+)"#) ?? 1920
        let h = Self.firstInt(in: out, pattern: #"height=(\d+)"#) ?? 1080
        var fps = 30.0
        if let m = Self.firstMatch(in: out, pattern: #"r_frame_rate=(\d+)/(\d+)"#, groups: 2),
           let num = Double(m[0]), let den = Double(m[1]), den != 0 {
            fps = num / den
        }
        return (w, h, fps)
    }

    func sampleGrids(url: URL) async throws -> [[Double]] {
        let ffmpeg = try resolvedFfmpeg()
        let (data, _) = try await Self.run(executable: ffmpeg, arguments: Self.sampleArgs(input: url.path))
        let count = data.count / Self.frameBytes
        guard count > 0 else { return [] }
        var grids: [[Double]] = []
        grids.reserveCapacity(count)
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let bytes = raw.bindMemory(to: UInt8.self)
            for i in 0..<count {
                let start = i * Self.frameBytes
                var grid = [Double](repeating: 0, count: Self.frameBytes)
                for j in 0..<Self.frameBytes { grid[j] = Double(bytes[start + j]) }
                grids.append(grid)
            }
        }
        return grids
    }

    func encodeWithKeyframes(input: URL, output: URL, timestamps: [Double], fps: Double) async throws {
        // `fps` is part of the protocol contract (the rate the timestamps were
        // derived against). ffmpeg forces keyframes at the SECOND-valued timestamps
        // directly (`-force_key_frames`, byte-parity with Electron) and preserves
        // the input cadence, so it needs no fps arg: correctness holds as long as
        // those timestamps are in the same fps-seconds the viewer seeks to, which
        // the deriver guarantees. (Fallback encoder; not bundled. Don't override
        // the fps field away from the export rate when using it.)
        _ = fps
        let ffmpeg = try resolvedFfmpeg()
        let args = Self.encodeArgs(input: input.path, output: output.path, timestamps: timestamps)
        let (_, status) = try await Self.run(executable: ffmpeg, arguments: args)
        guard status == 0 else {
            try? FileManager.default.removeItem(at: output)
            throw VideoEncoderError.writerFailed("ffmpeg exited with status \(status)")
        }
    }

    // MARK: - Binary discovery

    private func resolvedFfmpeg() throws -> String { try Self.resolveBinary(name: "ffmpeg", explicit: ffmpegPath) }
    private func resolvedFfprobe() throws -> String { try Self.resolveBinary(name: "ffprobe", explicit: ffprobePath) }

    private static func resolveBinary(name: String, explicit: String?) throws -> String {
        if let explicit {
            if FileManager.default.fileExists(atPath: explicit) { return explicit }
            throw VideoEncoderError.binaryNotFound(
                "\(name) not found at \(explicit). Install via Homebrew: brew install ffmpeg")
        }
        // `which <name>` first.
        let which = Process()
        which.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        which.arguments = [name]
        let pipe = Pipe()
        which.standardOutput = pipe
        try? which.run()
        which.waitUntilExit()
        let found = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !found.isEmpty, FileManager.default.fileExists(atPath: found) { return found }

        for candidate in ["/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)"] {
            if FileManager.default.fileExists(atPath: candidate) { return candidate }
        }
        throw VideoEncoderError.binaryNotFound(
            "\(name) not found on PATH. Install via Homebrew: brew install ffmpeg")
    }

    // MARK: - Process runner (argument array, never a shell; pipe-drained)

    /// Runs `executable` with `arguments` (no shell). Drains stdout on a
    /// background thread before waiting (rawvideo can be hundreds of MB → a full
    /// pipe buffer would deadlock the child). Honors task cancellation by
    /// terminating the process. Returns (stdoutData, exitStatus).
    private static func run(executable: String, arguments: [String]) async throws -> (Data, Int32) {
        try Task.checkCancellation()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        var env = ProcessInfo.processInfo.environment
        let currentPath = env["PATH"] ?? ""
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(currentPath)"
        process.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        return try await withTaskCancellationHandler {
            do { try process.run() }
            catch { throw VideoEncoderError.writerFailed("could not launch \(executable): \(error.localizedDescription)") }

            // Drain BOTH pipes concurrently off-thread BEFORE waitUntilExit. stdout
            // can be hundreds of MB (rawvideo); stderr must also be drained in
            // parallel — if it ever exceeds the ~64KB pipe buffer before stdout
            // closes, the child blocks on stderr and stdout never reaches EOF.
            async let stdoutData: Data = withUnsafeContinuation { cont in
                DispatchQueue.global().async {
                    cont.resume(returning: stdoutPipe.fileHandleForReading.readDataToEndOfFile())
                }
            }
            async let stderrData: Data = withUnsafeContinuation { cont in
                DispatchQueue.global().async {
                    cont.resume(returning: stderrPipe.fileHandleForReading.readDataToEndOfFile())
                }
            }
            let out = await stdoutData
            _ = await stderrData
            process.waitUntilExit()
            // A cancel reads as a cancel, not a confusing "encoding failed".
            if Task.isCancelled { throw VideoEncoderError.cancelled }
            return (out, process.terminationStatus)
        } onCancel: {
            process.terminate()
        }
    }

    // MARK: - Regex helpers

    private static func firstMatch(in text: String, pattern: String, groups: Int) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        var out: [String] = []
        for g in 1...groups {
            guard let r = Range(m.range(at: g), in: text) else { return nil }
            out.append(String(text[r]))
        }
        return out
    }

    private static func firstInt(in text: String, pattern: String) -> Int? {
        guard let m = firstMatch(in: text, pattern: pattern, groups: 1) else { return nil }
        return Int(m[0])
    }
}
