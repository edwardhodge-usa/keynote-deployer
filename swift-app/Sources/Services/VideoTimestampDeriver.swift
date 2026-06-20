import Foundation

/// Derives per-slide timestamps for a video deck by DP-matching the user's
/// per-slide still images to the video's frames.
///
/// Slide boundaries can't be recovered from video pixels alone (a build/fade step
/// looks identical to a real slide on a constant background), so the user exports
/// one still per slide: the *count* of stills IS the slide count, and each still
/// is matched to the frame it appears on to derive that slide's timestamp. Stills
/// are a build-time input only — never inserted into the video, never deployed.
///
/// Pure orchestration over an injected `VideoEncoder` (the concrete encoder is
/// supplied by Section 07; tests inject a fake). Off-main, cancellable, and
/// reports fractional progress (A5).
enum VideoTimestampDeriver {

    static func derive(encoder: VideoEncoder,
                       videoURL: URL,
                       stillURLs: [URL],
                       fps: Double,
                       onProgress: @Sendable (Double) -> Void = { _ in }) async throws -> VideoAnalysis {
        // fps drives timestamp math (round((frame/fps)*1000)/1000); a non-positive
        // fps would yield inf/nan timestamps → corrupt -force_key_frames / {{TS}}.
        guard fps > 0 else {
            throw VideoEncoderError.corruptFile("invalid fps \(fps) for timestamp derivation")
        }

        // 1. Natural-sort the stills (numeric-aware: slide-010 after slide-002).
        // Sort the URLs DIRECTLY with the same comparator StillsMatch.naturalSort
        // uses (String.compare(.numeric)) — avoids a path→URL dictionary round-trip
        // that would collapse any duplicate paths. The matcher requires stills in
        // true slide order; do NOT reorder frames.
        let stills = stillURLs.sorted { $0.path.compare($1.path, options: .numeric) == .orderedAscending }

        // 2. Probe dimensions (width/height only; the supplied fps drives timestamp math).
        try Task.checkCancellation()
        let (width, height, _) = try await encoder.probe(url: videoURL)

        // 3. Sample the video frames → many 1728-value grids in frame order.
        try Task.checkCancellation()
        let frameGrids = try await encoder.sampleGrids(url: videoURL)
        onProgress(stills.isEmpty ? 1.0 : 0.5)

        // 4. Sample each still → one grid each (in natural-sorted order).
        var stillGrids: [[Double]] = []
        stillGrids.reserveCapacity(stills.count)
        for (i, url) in stills.enumerated() {
            try Task.checkCancellation()
            let grids = try await encoder.sampleGrids(url: url)
            // A still must yield exactly one grid (section-04/05 contract). Throw
            // rather than silently drop — dropping would make slideCount diverge
            // from frames/timestamps and produce an inconsistent VideoAnalysis.
            guard let first = grids.first else {
                throw VideoEncoderError.readerFailed("still produced no grid: \(url.lastPathComponent)")
            }
            stillGrids.append(first)
            onProgress(0.5 + 0.45 * (Double(i + 1) / Double(stills.count)))
        }

        // 5. DP-match stills → video frames (one monotonic frame index per slide).
        try Task.checkCancellation()
        let frames = try StillsMatch.matchStillsToFrames(stillGrids, frameGrids)

        // 6. Frame indices → 3-decimal (ms) timestamps. EXACT rounding — the viewer's
        // {{TS}} JSON (Section 03) and the encoder's -force_key_frames (Sections 04/05)
        // re-derive from these same values, so the rounding must be identical.
        let timestamps = frames.map { round((Double($0) / fps) * 1000) / 1000 }
        onProgress(1.0)

        // 7. slideCount is the stills count — the slide-count truth (== frames.count
        // by construction).
        return VideoAnalysis(
            frames: frames,
            timestamps: timestamps,
            slideCount: stillURLs.count,
            width: width,
            height: height,
            fps: fps
        )
    }
}
