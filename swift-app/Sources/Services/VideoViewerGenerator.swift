import Foundation

/// Generates the deployable `index.html` for the H.264 video deck viewer.
///
/// Mirrors Electron's `generateVideoViewerHtml()` (`electron/videoViewerGenerator.ts`)
/// byte-for-byte. The full HTML/CSS/JS lives in the bundled resource
/// `video-viewer-template.html` with interpolated values replaced by `{{TOKEN}}`
/// placeholders. `generate(...)` loads the template from `Bundle.main`, fills the
/// tokens in a single pass (no re-scan of injected values — matches the GIF port's
/// parity discipline), and returns the result.
///
/// Pure `enum` with `static` funcs → trivially `Sendable`/concurrency-safe.
enum VideoViewerGenerator {

    /// Returns the deployable index.html for the video viewer.
    /// Output is byte-identical to Electron's `generateVideoViewerHtml()` for
    /// identical inputs.
    ///
    /// - Parameters:
    ///   - videoFilename: bare filename, e.g. `deck.mp4` (lands in `src="./<file>"`).
    ///   - secureEmbed: when true, injects the no-select CSS + contextmenu-block script.
    ///   - timestamps: per-slide keyframe seconds; emitted as compact JSON (`{{TS}}`).
    ///   - videoWidth: pixel width (default 1920, mirrors Electron).
    ///   - videoHeight: pixel height (default 1080, mirrors Electron).
    static func generate(videoFilename: String,
                         secureEmbed: Bool,
                         timestamps: [Double],
                         videoWidth: Int = 1920,
                         videoHeight: Int = 1080) -> String {
        // The template is a required bundled resource. A missing template is a
        // build/packaging bug, never a runtime-recoverable condition.
        guard let url = Bundle.main.url(forResource: "video-viewer-template", withExtension: "html"),
              let template = try? String(contentsOf: url, encoding: .utf8) else {
            fatalError("video-viewer-template.html missing from app bundle — resource bundling is broken (see project.yml Sources/Resources).")
        }

        // {{TS}} — compact JSON matching JS `JSON.stringify([…])` (no spaces; no
        // trailing zeros; integer values have no decimal point). Empty -> "[]".
        let ts = "[" + timestamps.map(JSNumber.format).joined(separator: ",") + "]"

        let secureEmbedCss = secureEmbed
            ? "body { user-select: none; } #deck video { pointer-events: none; }"
            : ""
        let secureEmbedScript = secureEmbed
            ? "document.addEventListener('contextmenu', function(e){ e.preventDefault(); });"
            : ""

        // Single-pass fill: each token replaced exactly once across the original
        // template. Injected values never contain `{{…}}`, and the token strings
        // do not overlap, so replacement order is irrelevant for correctness.
        return template
            .replacingOccurrences(of: "{{VIDEO_FILENAME}}", with: videoFilename)
            .replacingOccurrences(of: "{{TS}}", with: ts)
            .replacingOccurrences(of: "{{VW}}", with: String(videoWidth))
            .replacingOccurrences(of: "{{VH}}", with: String(videoHeight))
            .replacingOccurrences(of: "{{SECURE_EMBED_CSS}}", with: secureEmbedCss)
            .replacingOccurrences(of: "{{SECURE_EMBED_SCRIPT}}", with: secureEmbedScript)
    }
}
