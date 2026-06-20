import Foundation

/// User inputs for a video deck deploy. The per-slide stills are the slide-count +
/// boundary source of truth (build-time input only — never inserted into the video,
/// never deployed). See docs/VIDEO_DECK_VIEWER.md.
struct VideoDeployRequest: Sendable {
    let videoPath: String      // H.264 .mp4/.mov/.m4v
    let stillPaths: [String]   // one image per slide, natural-sorted (boundary/count source)
    let fps: Double            // constant export frame rate (default 30)
    let projectName: String
    let title: String
    let secureEmbed: Bool
}
