import Foundation

/// Result of matching per-slide stills to video frames (produced by
/// `VideoTimestampDeriver`, consumed by `VideoViewerGenerator` + `VideoDeployer`).
///
/// Invariants:
/// - `frames.count == timestamps.count == slideCount`
/// - `timestamps[i] == round((Double(frames[i]) / fps) * 1000) / 1000` (3dp)
/// - `frames` is strictly increasing (monotonic by DP-match construction)
struct VideoAnalysis: Sendable {
    let frames: [Int]          // matched video-frame index per slide
    let timestamps: [Double]   // frame/fps, rounded 3dp
    let slideCount: Int        // == stillPaths.count
    let width: Int
    let height: Int
    let fps: Double
}
