import Testing
import Foundation
@testable import KeynoteDeployer

/// Section 8 — VideoDeployView pure logic. The View's UI is verified live; the
/// logic it relies on is extracted into `VideoDeployLogic` (free static funcs, no
/// SwiftUI) so these stay offline + synchronous.
@Suite("Section 8 — VideoDeployView logic")
struct VideoDeployViewTests {

    // Project name = settings prefix + kebab(filename without extension), reusing
    // AppConfig.toKebabCase (the same helper the HTML path uses — no new rules).
    @Test func projectNameIsPrefixPlusKebabOfFilename() {
        #expect(VideoDeployLogic.projectName(prefix: "ils-", filename: "ILS Quals Deck.mp4") == "ils-ils-quals-deck")
        // No prefix, mixed separators/punctuation collapse to single hyphens.
        #expect(VideoDeployLogic.projectName(prefix: "", filename: "My  Deck (v2).mov") == "my-deck-v2")
        // Path, not just a name, still keys off the last component.
        #expect(VideoDeployLogic.projectName(prefix: "p-", filename: "/tmp/decks/Final.m4v") == "p-final")
    }

    // UTType.image filter (A8): images only, natural-sorted, count == images.
    @Test func stillsPickerFiltersToImagesAndCountsSlides() {
        let urls = [
            URL(fileURLWithPath: "/d/slide-2.png"),
            URL(fileURLWithPath: "/d/slide-10.jpeg"),
            URL(fileURLWithPath: "/d/slide-1.png"),
            URL(fileURLWithPath: "/d/.DS_Store"),
            URL(fileURLWithPath: "/d/Icon\r"),
            URL(fileURLWithPath: "/d/notes.txt"),
        ]
        let out = VideoDeployLogic.filterImages(urls)
        #expect(out.count == 3)                                   // slideCount == image count
        #expect(out == ["/d/slide-1.png", "/d/slide-2.png", "/d/slide-10.jpeg"])  // natural-sorted
    }

    // Deploy disabled until video AND stills.count > 0 AND non-empty name.
    @Test func deployDisabledUntilVideoAndStillsAndName() {
        #expect(VideoDeployLogic.canDeploy(videoPath: nil, stillCount: 3, projectName: "x") == false)
        #expect(VideoDeployLogic.canDeploy(videoPath: "/v.mp4", stillCount: 0, projectName: "x") == false)
        #expect(VideoDeployLogic.canDeploy(videoPath: "/v.mp4", stillCount: 3, projectName: "") == false)
        #expect(VideoDeployLogic.canDeploy(videoPath: "/v.mp4", stillCount: 3, projectName: "   ") == false)  // whitespace only
        #expect(VideoDeployLogic.canDeploy(videoPath: "/v.mp4", stillCount: 3, projectName: "deck") == true)
    }

    // Framer embed uses the PROBED aspect ratio (raw width/height), mirroring the
    // Electron GifViewer.tsx embed: `aspect-ratio:${w}/${h}` (NOT a hardcoded 16/9).
    @Test func framerEmbedUsesProbedAspectRatio() {
        let wide = VideoDeployLogic.framerEmbed(url: "https://x.vercel.app", width: 1920, height: 1080)
        #expect(wide.contains("aspect-ratio:1920/1080"))
        #expect(wide.contains("src=\"https://x.vercel.app\""))

        let tall = VideoDeployLogic.framerEmbed(url: "https://y.vercel.app", width: 1600, height: 1200)
        #expect(tall.contains("aspect-ratio:1600/1200"))
        #expect(!tall.contains("16/9"))  // not hardcoded
    }
}
