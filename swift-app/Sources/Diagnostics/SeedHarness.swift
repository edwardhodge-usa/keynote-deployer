import Foundation

/// Input for one diagnostic run: a deck video + its per-slide stills + where to write.
struct SeedHarnessInput: Sendable {
    let videoURL: URL
    let stillURLs: [URL]
    let outputDir: URL
}

/// Headless seed-measurement harness. Runs the REAL seed pipeline
/// (`GridSampler` → `StillsMatch` → `HoldDetector`) on a deck and produces a
/// per-slide diagnostic report. It deliberately BYPASSES `MarkStore` so it always
/// reports the FRESH seed — that is how MarkStore shadowing is detected in triage.
///
/// Pure orchestration over an injected `VideoEncoder` (tests inject a stub). It only
/// OBSERVES the pipeline — it does not change detection behavior. Off-main, cancellable.
enum SeedHarness {

    /// Number of frames on each side of an anchor to include in the diff profile.
    static let profileWindow = 10

    static func run(_ input: SeedHarnessInput, encoder: VideoEncoder) async throws -> HarnessReport {
        // 1. Natural-sort stills exactly as the real deriver does (numeric-aware).
        let stills = input.stillURLs.sorted {
            $0.path.compare($1.path, options: .numeric) == .orderedAscending
        }

        // 2. Probe the real fps (drives the detector's min-hold + far-threshold), then sample
        //    the video frames and each still (one grid per still).
        try Task.checkCancellation()
        let probedFps = (try? await encoder.probe(url: input.videoURL).fps) ?? 30
        let fps = probedFps > 0 ? probedFps : 30
        let frameGrids = try await encoder.sampleGrids(url: input.videoURL)
        let bound = frameGrids.count

        var stillGrids: [[Double]] = []
        stillGrids.reserveCapacity(stills.count)
        for url in stills {
            try Task.checkCancellation()
            let grids = try await encoder.sampleGrids(url: url)
            guard let first = grids.first else {
                throw VideoEncoderError.readerFailed("still produced no grid: \(url.lastPathComponent)")
            }
            stillGrids.append(first)
        }

        // 3. DP-match stills → frames, then the adaptive detector. detectDetailed returns
        //    marks + per-slide flags PARALLEL to the (sorted) anchors — one mark per slide —
        //    so we consume them 1:1 (the detector's Rest = a settled frame ≠ the anchor, so
        //    a holdStart→anchor lookup would mis-map; use the parallel arrays directly).
        try Task.checkCancellation()
        let anchors = try StillsMatch.matchStillsToFrames(stillGrids, frameGrids)
        let detail = HoldDetector.detectDetailed(frameGrids: frameGrids, anchors: anchors, frameCount: bound, fps: fps)
        let marks = detail.marks
        let sortedAnchors = anchors.sorted()   // detectDetailed sorts internally; mirror it for alignment

        let prof = diffProfile(frameGrids)   // consecutive-frame diff, length bound-1
        let globalMax = prof.max() ?? 0      // scale the anchor-motion read to the deck's distribution

        var perSlide: [PerSlideDiagnostic] = []
        var restGrids: [[Double]] = []
        var goGrids: [[Double]] = []
        let thumbsDir = try HarnessReport.safeOutputURL(
            dir: input.outputDir, name: "\(HarnessReport.safeSlug(deckName(input)))-thumbs")
        try FileManager.default.createDirectory(at: thumbsDir, withIntermediateDirectories: true)

        // marks/flags are 1:1 with sortedAnchors for the realistic n ≤ bound case.
        let aligned = marks.count == sortedAnchors.count
        for i in marks.indices {
            try Task.checkCancellation()
            let mark = marks[i]
            let anchor = aligned ? sortedAnchors[i] : mark.holdStart
            let clamped = max(0, min(anchor, max(0, bound - 1)))
            let collided = detail.collidedWithPrevious[safe: i] ?? false
            let lowConfidence = detail.lowConfidenceMatch[safe: i] ?? false
            let profile = profileAround(clamped, prof: prof)

            let restGrid = frameGrids[safe: mark.holdStart] ?? []
            let goGrid = frameGrids[safe: mark.holdEnd] ?? []
            restGrids.append(restGrid)
            goGrids.append(goGrid)

            let restPath = try writeThumb(restGrid, dir: thumbsDir, name: "slide-\(i)-rest.png")
            let goPath = try writeThumb(goGrid, dir: thumbsDir, name: "slide-\(i)-go.png")

            perSlide.append(PerSlideDiagnostic(
                slideIndex: i,
                matchedAnchorFrame: anchor,
                anchorCollidedWithPrevious: collided,
                markReused: false,
                lowConfidenceMatch: lowConfidence,
                seededRest: mark.holdStart,
                seededGo: mark.holdEnd,
                diffProfileAroundAnchor: profile,
                restFrameThumbnailPath: restPath,
                goFrameThumbnailPath: goPath))
        }

        return HarnessReport(
            deckName: deckName(input),
            slideCount: input.stillURLs.count,
            markCount: marks.count,
            perSlide: perSlide,
            restGrids: restGrids,
            goGrids: goGrids)
    }

    // MARK: helpers

    private static func deckName(_ input: SeedHarnessInput) -> String {
        input.videoURL.deletingPathExtension().lastPathComponent
    }

    /// Mean absolute per-component diff between two equal-length grids.
    static func gridDiff(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var s = 0.0
        for i in a.indices { s += abs(a[i] - b[i]) }
        return s / Double(a.count)
    }

    /// Consecutive-frame diff signal over all frames (length frameGrids.count - 1).
    static func diffProfile(_ frameGrids: [[Double]]) -> [Double] {
        guard frameGrids.count > 1 else { return [] }
        return (0..<(frameGrids.count - 1)).map { gridDiff(frameGrids[$0], frameGrids[$0 + 1]) }
    }

    /// The diff-profile slice in a ±profileWindow band around `anchor`.
    private static func profileAround(_ anchor: Int, prof: [Double]) -> [Double] {
        guard !prof.isEmpty else { return [] }
        let lo = max(0, anchor - profileWindow)
        let hi = min(prof.count - 1, anchor + profileWindow)
        guard lo <= hi else { return [] }
        return Array(prof[lo...hi])
    }

    /// Best-effort low-confidence heuristic: if the per-frame diff AT the anchor is a
    /// large fraction of the deck's GLOBAL diff max, the anchor sits in motion (not a
    /// settled frame) → flag StillsMatch as the suspect. Scaling to the global
    /// distribution (not an absolute unit) is what lets it fire on dark-fade decks
    /// where every diff is tiny but relative motion still peaks at transitions.
    /// A signal, never a drop.
    static func isLowConfidence(at anchor: Int, prof: [Double], globalMax: Double) -> Bool {
        guard anchor < prof.count, globalMax > 0 else { return false }
        return prof[anchor] >= 0.6 * globalMax
    }

    private static func nearestMark(_ marks: [SlideMark], to frame: Int) -> SlideMark? {
        marks.min { abs($0.holdStart - frame) < abs($1.holdStart - frame) }
    }

    private static func writeThumb(_ grid: [Double], dir: URL, name: String) throws -> String {
        let url = try HarnessReport.safeOutputURL(dir: dir, name: name)
        if let png = HarnessReport.pngData(from: grid) { try png.write(to: url) }
        return url.path
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
