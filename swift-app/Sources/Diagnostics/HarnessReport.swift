import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// One slide's seed diagnostic — the per-slide row the harness report surfaces so a
/// human can eyeball "Rest settled? Go bracketing the transition?" and triage WHERE
/// accuracy is lost (DP match vs Rest choice vs Go threshold vs count).
struct PerSlideDiagnostic: Codable, Sendable, Equatable {
    let slideIndex: Int
    /// The DP-matched frame index for this slide (the anchor).
    let matchedAnchorFrame: Int
    /// Two stills matched to the SAME frame. INVARIANT GUARD: unreachable while
    /// `StillsMatch` produces strictly-increasing anchors (it always does), so this
    /// is false on every valid deck. Kept to catch a future regression that breaks
    /// monotonicity — it is NOT the count-loss signal (count loss is structurally
    /// impossible in the current pipeline; the real "wrong count" cause is MarkStore
    /// shadowing, fixed in section 02).
    let anchorCollidedWithPrevious: Bool
    /// This slide had no own mark and borrowed a neighbor's (markByStart miss). An
    /// honest signal that the displayed Rest/Go is not this slide's own.
    let markReused: Bool
    /// High per-frame motion AT the anchor (relative to the deck's global diff
    /// distribution) → the anchor likely sits in a transition, so StillsMatch (not
    /// the detector) is the suspect. A signal, never a drop.
    let lowConfidenceMatch: Bool
    /// Produced Rest (holdStart) frame index.
    let seededRest: Int
    /// Produced Go (holdEnd) frame index.
    let seededGo: Int
    /// Consecutive grid diff for a ±window of frames around the anchor — eyeball the Go/Rest fit.
    let diffProfileAroundAnchor: [Double]
    /// On-disk path of the rendered Rest thumbnail (for the JSON dump).
    let restFrameThumbnailPath: String
    /// On-disk path of the rendered Go thumbnail.
    let goFrameThumbnailPath: String
}

/// Diagnostic report for one deck's seed run. Emits a machine-readable JSON dump and
/// a self-contained dark HTML montage (Rest/Go thumbnails + ASCII diff-profile bars).
/// The visual report is the artifact a human eyeballs; the JSON backs it.
struct HarnessReport: Sendable {
    let deckName: String
    /// Slide count == stillURLs.count — the COUNT authority.
    let slideCount: Int
    /// Produced marks.count — SHOULD equal slideCount.
    let markCount: Int
    let perSlide: [PerSlideDiagnostic]
    /// Rest/Go thumbnail grids (32×18×3 raw RGB), parallel to `perSlide`, kept in
    /// memory so the HTML montage can inline them as base64 without re-reading disk.
    let restGrids: [[Double]]
    let goGrids: [[Double]]

    // MARK: Path safety

    /// Reduce an arbitrary deck name to a filesystem-safe slug: strip path
    /// separators and `..`, allow only [A-Za-z0-9-_], collapse empties to "deck".
    /// Prevents a `deckName` like `../../etc` escaping the output directory.
    static func safeSlug(_ raw: String) -> String {
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        let mapped = raw.map { allowed.contains($0) ? $0 : "-" }
        let slug = String(mapped).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return slug.isEmpty ? "deck" : slug
    }

    /// Build an output URL under `dir` for `name`, verifying the resolved path stays
    /// inside `dir` (defense in depth on top of slug sanitizing). Throws on escape.
    static func safeOutputURL(dir: URL, name: String) throws -> URL {
        let base = dir.standardizedFileURL
        let url = base.appendingPathComponent(name).standardizedFileURL
        guard url.path == base.path || url.path.hasPrefix(base.path + "/") else {
            throw HarnessError.pathEscapesOutputDir(attempted: url.path, root: base.path)
        }
        return url
    }

    // MARK: JSON

    /// Write the per-slide diagnostics as pretty JSON to `<slug>-seed.json` under `dir`.
    func writeJSON(to dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let slug = Self.safeSlug(deckName)
        let url = try Self.safeOutputURL(dir: dir, name: "\(slug)-seed.json")
        let payload = JSONPayload(deckName: deckName, slideCount: slideCount,
                                  markCount: markCount, perSlide: perSlide)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(payload).write(to: url)
    }

    private struct JSONPayload: Codable {
        let deckName: String
        let slideCount: Int
        let markCount: Int
        let perSlide: [PerSlideDiagnostic]
    }

    // MARK: Visual report

    /// Write a single self-contained dark HTML montage to `<slug>-seed.html` under `dir`.
    /// Thumbnails are inlined as base64 `data:` URIs so the file needs no external assets.
    func writeVisualReport(to dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let slug = Self.safeSlug(deckName)
        let url = try Self.safeOutputURL(dir: dir, name: "\(slug)-seed.html")
        try Data(html().utf8).write(to: url)
    }

    private func html() -> String {
        let countFlag = markCount == slideCount
            ? "<span class='ok'>count OK</span>"
            : "<span class='bad'>COUNT MISMATCH \(markCount) ≠ \(slideCount)</span>"
        var blocks = ""
        for (i, d) in perSlide.enumerated() {
            let restURI = Self.dataURI(restGrids[safe: i] ?? [])
            let goURI = Self.dataURI(goGrids[safe: i] ?? [])
            let flags = [
                d.anchorCollidedWithPrevious ? "<span class='bad'>collision</span>" : "",
                d.markReused ? "<span class='warn'>mark reused</span>" : "",
                d.lowConfidenceMatch ? "<span class='warn'>low-confidence anchor</span>" : ""
            ].filter { !$0.isEmpty }.joined(separator: " ")
            blocks += """
            <div class="slide">
              <div class="hd">slide \(d.slideIndex) \(flags)</div>
              <div class="thumbs">
                <figure><img src="\(restURI)"><figcaption>Rest \(d.seededRest)</figcaption></figure>
                <figure><img src="\(goURI)"><figcaption>Go \(d.seededGo)</figcaption></figure>
              </div>
              <div class="meta">anchor \(d.matchedAnchorFrame)</div>
              <pre class="profile">\(Self.asciiBars(d.diffProfileAroundAnchor))</pre>
            </div>
            """
        }
        return """
        <!DOCTYPE html><html><head><meta charset="utf-8">
        <title>\(htmlEscape(deckName)) — seed report</title>
        <style>
          body{background:#0b0b0d;color:#e6e6ea;font:13px -apple-system,system-ui,sans-serif;margin:24px}
          h1{font-size:18px;font-weight:600}
          .ok{color:#34c759} .bad{color:#ff453a;font-weight:600} .warn{color:#ff9f0a}
          .slide{border:1px solid #2a2a31;border-radius:10px;padding:12px;margin:10px 0;background:#141418}
          .hd{font-weight:600;margin-bottom:6px}
          .thumbs{display:flex;gap:14px}
          figure{margin:0} img{width:160px;height:90px;image-rendering:pixelated;border:1px solid #2a2a31;border-radius:4px}
          figcaption{color:#9a9aa2;font-size:11px;margin-top:3px}
          .meta{color:#9a9aa2;font-size:11px;margin-top:6px}
          .profile{color:#5e9cff;font:11px ui-monospace,monospace;margin:6px 0 0;white-space:pre}
        </style></head><body>
        <h1>\(htmlEscape(deckName)) — seed report &nbsp; slides \(slideCount) · marks \(markCount) &nbsp; \(countFlag)</h1>
        \(blocks)
        </body></html>
        """
    }

    // MARK: Rendering helpers

    /// ASCII-bar rendering of a diff profile (matches the house live-dashboard style;
    /// unicode dies under nohup's C locale, so ASCII only). The absolute max is printed
    /// so the normalized bars are calibrated — a flat profile of tiny-but-equal values
    /// would otherwise render as all-full bars and read as maximal motion.
    static func asciiBars(_ values: [Double]) -> String {
        guard let maxV = values.max(), maxV > 0 else {
            // All-zero (or empty) profile: render empty bars vertically, consistent
            // with the normal branch, so slides compare cleanly in the same <pre>.
            return values.map { _ in String(repeating: ".", count: 20) }.joined(separator: "\n")
        }
        let bars = values.map { v -> String in
            let n = Int((v / maxV) * 20)
            return String(repeating: "#", count: max(0, n)).padding(toLength: 20, withPad: ".", startingAt: 0)
        }.joined(separator: "\n")
        return "max \(String(format: "%.2f", maxV))\n\(bars)"
    }

    /// Encode a 32×18×3 raw-RGB grid as a base64 PNG `data:` URI for inline HTML.
    static func dataURI(_ grid: [Double]) -> String {
        guard let png = pngData(from: grid) else { return "" }
        return "data:image/png;base64,\(png.base64EncodedString())"
    }

    /// Build a small PNG from a 32×18×3 raw-RGB grid (honestly shows what the
    /// detector "sees"; native-res extraction is deliberately out of scope here).
    static func pngData(from grid: [Double]) -> Data? {
        let w = GridSampler.width, h = GridSampler.height
        guard grid.count == w * h * GridSampler.channels else { return nil }
        var rgba = [UInt8](repeating: 255, count: w * h * 4)
        for cell in 0..<(w * h) {
            let s = cell * 3, d = cell * 4
            rgba[d] = UInt8(max(0, min(255, grid[s])))
            rgba[d + 1] = UInt8(max(0, min(255, grid[s + 1])))
            rgba[d + 2] = UInt8(max(0, min(255, grid[s + 2])))
            rgba[d + 3] = 255
        }
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: &rgba, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let img = ctx.makeImage() else { return nil }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(dest, img, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    private func htmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

enum HarnessError: Error, LocalizedError, Equatable {
    case pathEscapesOutputDir(attempted: String, root: String)
    var errorDescription: String? {
        switch self {
        case let .pathEscapesOutputDir(attempted, root):
            return "Refused to write outside the output directory (\(attempted) escapes \(root))."
        }
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
