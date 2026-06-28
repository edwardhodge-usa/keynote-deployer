import AVFoundation
import CoreGraphics
import ImageIO

/// Extracts a single still frame from a video as JPEG.
///
/// Used to give the video deck viewer a `<video poster>` so its FIRST paint shows
/// slide 1 instead of black. iOS WebKit won't render a *seeked* frame on a paused
/// video until it plays, and the viewer's initial load has no user gesture to
/// trigger the micro-play that would paint it — so without a poster the embed shows
/// black until the first Next tap. The poster covers exactly that first paint.
///
/// Pure `enum` + `static` func → trivially `Sendable`.
enum VideoPoster {

    enum PosterError: Error { case encodeFailed }

    /// Writes a JPEG of the frame at `seconds` from `videoURL` to `outputURL`.
    /// Best-effort by contract: the caller treats a throw as "no poster" and the
    /// viewer still works (it just falls back to black-on-load), so a corrupt or
    /// unseekable frame must never fail the whole deploy.
    static func extract(from videoURL: URL,
                        atSeconds seconds: Double,
                        to outputURL: URL,
                        quality: Double = 0.7) async throws {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        // Allow a little tolerance so we land on a real keyframe near the rest time
        // rather than forcing an exact decode that can fail on sparse-keyframe files.
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.3, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.3, preferredTimescale: 600)

        let time = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        let (cgImage, _) = try await generator.image(at: time)

        guard let dest = CGImageDestinationCreateWithURL(outputURL as CFURL, "public.jpeg" as CFString, 1, nil) else {
            throw PosterError.encodeFailed
        }
        CGImageDestinationAddImage(dest, cgImage, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw PosterError.encodeFailed }
    }
}
