import Testing
import Foundation
@testable import KeynoteDeployer

/// Parity gate for the video viewer generator. The golden fixtures in
/// `Tests/Fixtures/` were captured by running the SAME inputs through the
/// TypeScript `generateVideoViewerHtml` (`electron/videoViewerGenerator.ts`)
/// via `node`, so they are the byte-parity oracle.
/// Anchors `Bundle(for:)` to the test bundle so golden fixtures load from the
/// bundle's Resources (where the project wires them) rather than a compile-time
/// `#filePath` absolute path — robust across relocated builds / CI.
private final class BundleAnchor {}

@Suite("Section 3 — VideoViewerGenerator parity")
struct VideoViewerGeneratorTests {

    // Goldens are bundled into the test target's Resources; load them from the
    // test bundle (not off disk) so the test survives any checkout/build relocation.
    private func goldenString(_ resource: String) throws -> String {
        let bundle = Bundle(for: BundleAnchor.self)
        let url = try #require(
            bundle.url(forResource: resource, withExtension: "html"),
            "golden fixture \(resource).html must be bundled into the test target Resources"
        )
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// The bundled template loads from Bundle.main at runtime (not nil).
    /// Guards the resource-bundling wiring from section-01.
    @Test func templateBundleResourceLoads() throws {
        let url = Bundle.main.url(forResource: "video-viewer-template", withExtension: "html")
        #expect(url != nil, "video-viewer-template.html must be bundled into Bundle.main")
        let html = try String(contentsOf: #require(url), encoding: .utf8)
        #expect(html.hasPrefix("<!DOCTYPE html>"))
        #expect(html.contains("{{TS}}"))
    }

    /// BYTE-PARITY (secure branch): generate(...) == the Electron golden for
    /// identical inputs (secureEmbed=true, default 1920x1080).
    @Test func byteParityWithElectronGoldenSecure() throws {
        let golden = try goldenString("video-viewer-golden-secure")
        let output = VideoViewerGenerator.generate(
            videoFilename: "deck.mp4",
            secureEmbed: true,
            spans: [[0, 0.5], [1.234, 4.0], [5.6, 11.0], [12.0, 14.0]],
            videoWidth: 1920,
            videoHeight: 1080
        )
        #expect(output == golden)
    }

    /// BYTE-PARITY (plain branch): secureEmbed=false + non-16:9 dimensions
    /// (1024x768) to confirm every {{VW}}/{{VH}} site fills and both secure
    /// tokens collapse to "".
    @Test func byteParityWithElectronGoldenPlain() throws {
        let golden = try goldenString("video-viewer-golden-plain")
        let output = VideoViewerGenerator.generate(
            videoFilename: "slides.mp4",
            secureEmbed: false,
            spans: [[0, 1.0], [2.5, 6.0], [7.0, 9.0]],
            videoWidth: 1024,
            videoHeight: 768
        )
        #expect(output == golden)
    }

    /// {{TS}} is emitted as compact JSON with no spaces, matching JS
    /// JSON.stringify. Integers render with no decimal point; empty -> [].
    @Test func spansAreCompactJson() {
        let out = VideoViewerGenerator.generate(
            videoFilename: "deck.mp4", secureEmbed: false,
            spans: [[0, 0.5], [1.234, 4.0], [5.6, 11.0], [12.0, 14.0]],
            videoWidth: 1920, videoHeight: 1080
        )
        #expect(out.contains("var TS = [[0,0.5],[1.234,4],[5.6,11],[12,14]];"))
        // no spaces after commas
        #expect(!out.contains("[[0, 0.5"))

        let empty = VideoViewerGenerator.generate(
            videoFilename: "deck.mp4", secureEmbed: false,
            spans: [], videoWidth: 1920, videoHeight: 1080
        )
        #expect(empty.contains("var TS = [];"))
    }

    /// jsNumber parity for the 3-decimal/ms-rounded input contract (section-06
    /// rounds timestamps to 3 decimals). Locks: small terminating fractional
    /// (0.001), binary-non-terminating (0.1 -> "0.1"), and integer-valued
    /// (100, 12) all match JS JSON.stringify. Guards against the `%.3f` helper
    /// drifting and against the (former) Int() crash on integer values.
    @Test func spansPairParityForContractBoundedValues() {
        let out = VideoViewerGenerator.generate(
            videoFilename: "deck.mp4", secureEmbed: false,
            spans: [[0.001, 0.05], [0.1, 1.0], [100.0, 110.0], [12.0, 20.0]],
            videoWidth: 1920, videoHeight: 1080
        )
        // JS: JSON.stringify([[0.001,0.05],[0.1,1],[100,110],[12,20]])
        #expect(out.contains("var TS = [[0.001,0.05],[0.1,1],[100,110],[12,20]];"))
    }

    /// spans fill {{TS}} as a JSON array of [start,end] pairs
    @Test("spans fill {{TS}} as a JSON array of [start,end] pairs")
    func spansPairs() {
        let html = VideoViewerGenerator.generate(
            videoFilename: "deck.mp4", secureEmbed: false,
            spans: [[0, 1.5], [2.0, 3.0]], videoWidth: 1920, videoHeight: 1080)
        #expect(html.contains("var TS = [[0,1.5],[2,3]];"))
    }

    /// secureEmbed=true injects the EXACT css + contextmenu script strings;
    /// secureEmbed=false omits both (tokens fill with "").
    @Test func secureEmbedStringsExact() {
        let on = VideoViewerGenerator.generate(
            videoFilename: "deck.mp4", secureEmbed: true,
            spans: [[0, 1.0]], videoWidth: 1920, videoHeight: 1080
        )
        #expect(on.contains("body { user-select: none; } #deck video { pointer-events: none; }"))
        #expect(on.contains("document.addEventListener('contextmenu', function(e){ e.preventDefault(); });"))

        let off = VideoViewerGenerator.generate(
            videoFilename: "deck.mp4", secureEmbed: false,
            spans: [[0, 1.0]], videoWidth: 1920, videoHeight: 1080
        )
        #expect(!off.contains("user-select: none"))
        #expect(!off.contains("contextmenu"))
        #expect(!off.contains("preventDefault"))
    }

    /// filename + width/height land in the JS blob loader URL ("./<file>") and the
    /// aspect-ratio CSS + JS vars. (The deck is fetched into memory and played from a
    /// blob, so the filename is NOT a static <video src> attribute anymore.)
    @Test func filenameAndDimensionsLandInTokens() {
        let out = VideoViewerGenerator.generate(
            videoFilename: "myDeck.mp4", secureEmbed: false,
            spans: [[0, 1.0]], videoWidth: 1600, videoHeight: 900
        )
        #expect(out.contains("\"./myDeck.mp4\""))   // blob loader URL
        #expect(!out.contains("src=\"./myDeck.mp4\""))   // no static src attribute
        #expect(out.contains("aspect-ratio:1600/900"))
        #expect(out.contains("VW=1600, VH=900"))
        #expect(out.contains("max-width:1600px"))
        // no leftover tokens
        #expect(!out.contains("{{"))
        #expect(!out.contains("}}"))
    }

    /// posterFilename nil (default) → no poster attribute on the <video>, and no
    /// static src either (the deck is loaded via JS). The {{POSTER_ATTR}} token
    /// collapses to "".
    @Test func noPosterByDefault() {
        let out = VideoViewerGenerator.generate(
            videoFilename: "deck.mp4", secureEmbed: false, spans: [[0, 1.0]]
        )
        #expect(!out.contains("poster="))
        #expect(out.contains("muted playsinline preload=\"auto\"></video>"))
        #expect(out.contains("\"./deck.mp4\""))   // filename in the JS loader
        #expect(!out.contains("{{POSTER_ATTR}}"))
    }

    /// posterFilename present → emits ` poster="./<file>"` on the <video> (still a
    /// static attribute); the deck src is set later in JS, so no static src.
    @Test func posterAttributeWhenProvided() {
        let out = VideoViewerGenerator.generate(
            videoFilename: "deck.mp4", secureEmbed: false, spans: [[0, 1.0]],
            videoWidth: 1920, videoHeight: 1080, posterFilename: "poster.jpg"
        )
        #expect(out.contains("preload=\"auto\" poster=\"./poster.jpg\"></video>"))
        #expect(!out.contains("src=\"./deck.mp4\""))
    }

    /// Default parameters mirror Electron (1920x1080) when omitted.
    @Test func defaultDimensionsAre1920x1080() {
        let out = VideoViewerGenerator.generate(
            videoFilename: "deck.mp4", secureEmbed: false, spans: [[0, 1.0]]
        )
        #expect(out.contains("aspect-ratio:1920/1080"))
        #expect(out.contains("VW=1920, VH=1080"))
    }

    /// REST_BIAS is retired — the viewer now derives rest/start positions from the
    /// holdStart/holdEnd pair in each span. Verifies both the removal and the
    /// presence of the replacement helper functions.
    @Test("REST_BIAS retired — viewer uses holdStart/holdEnd from spans")
    func restBiasRetired() {
        let html = VideoViewerGenerator.generate(
            videoFilename: "deck.mp4", secureEmbed: false,
            spans: [[0, 0.5], [1.5, 3.0]], videoWidth: 1920, videoHeight: 1080)
        #expect(!html.contains("REST_BIAS"))
        #expect(html.contains("function holdStart(i)"))
        #expect(html.contains("function holdEnd(i)"))
    }
}
