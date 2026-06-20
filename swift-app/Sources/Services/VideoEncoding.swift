import Foundation

/// The encoder seam for the video-deploy path. Two conformers:
/// `AVFoundationVideoEncoder` (default, Apple-only) and `FFmpegVideoEncoder`
/// (Section 05 fallback). All three operations are pure-ish I/O on URLs so the
/// two engines are interchangeable behind this protocol.
protocol VideoEncoder: Sendable {
    /// Probe container/stream for dimensions + constant frame rate.
    /// Throws on no-video-track, corrupt input, or variable frame rate.
    func probe(url: URL) async throws -> (width: Int, height: Int, fps: Double)

    /// Decode `url` to per-frame 32×18 RGB grids (downscaled), in presentation
    /// order. Handles both a video (many frames) and a still image (one frame).
    /// Reuses `GridSampler.sample` so video frames and stills land on the SAME grid.
    func sampleGrids(url: URL) async throws -> [[Double]]

    /// Re-encode `input` to web-safe H.264 with a forced keyframe at each
    /// timestamp. Output: yuv420p, High profile, no audio, faststart.
    func encodeWithKeyframes(input: URL, output: URL, timestamps: [Double]) async throws
}

/// User-facing, actionable encoder errors.
enum VideoEncoderError: Error, LocalizedError, Sendable, Equatable {
    case noVideoTrack
    case corruptFile(String)
    case variableFrameRate
    case readerFailed(String)
    case writerFailed(String)
    case binaryNotFound(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noVideoTrack:
            return "The file has no video track. Drop a video (or an exported deck), not an audio-only file."
        case .corruptFile(let detail):
            return "The video file couldn't be read (\(detail)). Re-export it and try again."
        case .variableFrameRate:
            return "The video has a variable frame rate. Re-export it at a constant frame rate (Keynote exports CFR by default)."
        case .readerFailed(let detail):
            return "Reading the source video failed: \(detail)"
        case .writerFailed(let detail):
            return "Encoding the video failed: \(detail)"
        case .binaryNotFound(let detail):
            return detail
        case .cancelled:
            return "Encoding was cancelled."
        }
    }
}

/// Formats a `Double` the way JavaScript `Number.toString` / `JSON.stringify`
/// does: integer values without a decimal point (`12` not `12.0`), fractionals
/// with trailing zeros stripped (`5.6` not `5.600`). Load-bearing for byte-parity
/// with the Electron path — it backs BOTH the video viewer's baked `{{TS}}` array
/// and the ffmpeg `-force_key_frames` CSV, so a single shared definition keeps the
/// two engines from silently diverging. Assumes ≤3-decimal inputs (upstream
/// timestamps are `round((f/fps)*1000)/1000`).
enum JSNumber {
    static func format(_ x: Double) -> String {
        if x.isFinite && x == x.rounded() {
            // %.0f (not Int(x)) avoids the Int(Double) trap on out-of-range values.
            return String(format: "%.0f", x)
        }
        var s = String(format: "%.3f", x)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }
}

/// Maps each slide timestamp (seconds) to the nearest output frame index at `fps`.
/// Shared by both encoders so AVFoundation's forced-keyframe attachment and
/// ffmpeg's `-force_key_frames` land on the SAME frames. For the real pipeline
/// (timestamps = frameIndex / fps from Section 06), `round(t * fps)` recovers the
/// exact frame index. Negative results are clamped to 0; `fps <= 0` → all 0.
func forcedKeyframeFrameIndices(timestamps: [Double], fps: Double) -> [Int] {
    guard fps > 0 else { return timestamps.map { _ in 0 } }
    return timestamps.map { t in max(0, Int((t * fps).rounded())) }
}
