import Testing
@testable import KeynoteDeployer

@Suite("Section 1 — Models + project wiring")
struct ModelsAndProjectTests {

    // Proves the xcodegen test-target wiring works end-to-end:
    // this test compiling + running green IS the wiring acceptance gate.
    @Test func testTargetRunsAnEmptyTest() {
        #expect(true)
    }

    @Test func videoDeployRequestIsConstructible() {
        let req = VideoDeployRequest(
            videoPath: "/tmp/deck.mp4",
            stillPaths: ["/tmp/s001.jpeg", "/tmp/s002.jpeg"],
            fps: 30,
            projectName: "my-deck",
            title: "My Deck",
            secureEmbed: true
        )
        #expect(req.videoPath == "/tmp/deck.mp4")
        #expect(req.stillPaths.count == 2)
        #expect(req.fps == 30)
        #expect(req.projectName == "my-deck")
        #expect(req.title == "My Deck")
        #expect(req.secureEmbed)
    }

    @Test func videoAnalysisIsConstructible() {
        let a = VideoAnalysis(
            frames: [0, 45, 90],
            timestamps: [0.0, 1.5, 3.0],
            slideCount: 3,
            width: 1920, height: 1080, fps: 30,
            frameCount: 0
        )
        #expect(a.frames.count == a.slideCount)
        #expect(a.slideCount == a.timestamps.count)
        #expect(a.width == 1920)
        #expect(a.height == 1080)
        #expect(a.fps == 30)
    }

    // Self-documenting compile-time witness that both models are Sendable
    // (they cross actor boundaries in the async video pipeline).
    @Test func modelsAreSendable() {
        func requireSendable<T: Sendable>(_: T.Type) {}
        requireSendable(VideoDeployRequest.self)
        requireSendable(VideoAnalysis.self)
        #expect(true)
    }
}
