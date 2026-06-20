import Foundation
import AVFoundation
import CoreImage
import CoreGraphics
import ImageIO

/// Default (shipping) encoder for the video-deploy path. Apple-frameworks only —
/// no bundled binary, so no nested-binary codesigning / notarization surface.
/// Stateless `struct` → `Sendable`; everything passes via parameters.
///
/// Forced keyframes: VideoToolbox's H.264 encoder honors
/// `kCMSampleBufferAttachmentKey_ForceKeyFrame` on individual sample buffers
/// during an `AVAssetReader → AVAssetWriter` re-encode, which lets us put an
/// I-frame at each arbitrary slide timestamp. VideoToolbox is less quality-
/// efficient than `libx264 -crf 18`, so we bias hard toward quality (High
/// profile, high bitrate) and gate on human review (Section 05 ffmpeg is the
/// escape hatch).
struct AVFoundationVideoEncoder: VideoEncoder {

    // MARK: probe

    func probe(url: URL) async throws -> (width: Int, height: Int, fps: Double) {
        let asset = AVURLAsset(url: url)
        let tracks: [AVAssetTrack]
        do {
            tracks = try await asset.loadTracks(withMediaType: .video)
        } catch {
            throw VideoEncoderError.corruptFile(error.localizedDescription)
        }
        guard let track = tracks.first else { throw VideoEncoderError.noVideoTrack }

        let naturalSize: CGSize
        let transform: CGAffineTransform
        let nominalFrameRate: Float
        do {
            (naturalSize, transform, nominalFrameRate) =
                try await track.load(.naturalSize, .preferredTransform, .nominalFrameRate)
        } catch {
            throw VideoEncoderError.corruptFile(error.localizedDescription)
        }

        let oriented = naturalSize.applying(transform)
        var w = Int(abs(oriented.width).rounded())
        var h = Int(abs(oriented.height).rounded())
        if w == 0 || h == 0 { w = 1920; h = 1080 }   // valid track, unusable size

        var fps = Double(nominalFrameRate)
        if fps <= 0 { fps = 30 }

        try await assertConstantFrameRate(asset: asset, track: track, expectedFps: fps)
        return (w, h, fps)
    }

    /// Reject variable frame rate (A2). Reads up to ~20 decompressed frames (so
    /// PTS arrive in presentation order, unaffected by B-frame decode reordering)
    /// and compares each inter-frame PTS delta to the expected 1/fps. Rejects only
    /// when ≥2 deltas deviate by >25% — gross VFR (dropped/added frames, e.g.
    /// screen-capture) trips it while ordinary encoder jitter and a single outlier
    /// (a long first GOP, timescale rounding) do not.
    private func assertConstantFrameRate(asset: AVURLAsset, track: AVAssetTrack, expectedFps: Double) async throws {
        guard let reader = try? AVAssetReader(asset: asset) else {
            throw VideoEncoderError.readerFailed("could not create reader for VFR probe")
        }
        let settings: [String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw VideoEncoderError.readerFailed("cannot add VFR-probe output") }
        reader.add(output)
        guard reader.startReading() else {
            throw VideoEncoderError.readerFailed(reader.error?.localizedDescription ?? "VFR probe start failed")
        }

        var deltas: [Double] = []
        var prev: CMTime?
        var count = 0
        while count < 20, let sb = output.copyNextSampleBuffer() {
            let pts = CMSampleBufferGetPresentationTimeStamp(sb)
            if let p = prev { deltas.append((pts - p).seconds) }
            prev = pts
            count += 1
        }
        reader.cancelReading()

        guard deltas.count >= 2, expectedFps > 0 else { return }   // too few frames / unknown fps → accept
        let expected = 1.0 / expectedFps
        let tolerance = expected * 0.25
        let violations = deltas.filter { abs($0 - expected) > tolerance }.count
        if violations >= 2 { throw VideoEncoderError.variableFrameRate }
    }

    // MARK: sampleGrids

    func sampleGrids(url: URL) async throws -> [[Double]] {
        let asset = AVURLAsset(url: url)
        let tracks = (try? await asset.loadTracks(withMediaType: .video)) ?? []

        // Still image: no video track → decode one CGImage via ImageIO.
        if tracks.isEmpty {
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
                throw VideoEncoderError.corruptFile("not a decodable image or video: \(url.lastPathComponent)")
            }
            return [GridSampler.sample(img)]
        }

        // Video: read every frame decompressed (presentation order) → grid.
        let track = tracks[0]
        guard let reader = try? AVAssetReader(asset: asset) else {
            throw VideoEncoderError.readerFailed("could not create reader for sampleGrids")
        }
        let settings: [String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw VideoEncoderError.readerFailed("cannot add sampleGrids output") }
        reader.add(output)
        guard reader.startReading() else {
            throw VideoEncoderError.readerFailed(reader.error?.localizedDescription ?? "sampleGrids start failed")
        }

        // Pin the CIContext to sRGB so frames take the SAME color path GridSampler
        // applies to stills (A3: stills/frames must land on one grid). An unpinned
        // default context can color-manage differently.
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        let ciContext = CIContext(options: [.workingColorSpace: srgb, .outputColorSpace: srgb])
        var grids: [[Double]] = []
        var frameNo = 0
        while let sb = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            // Throw (don't silently drop) on an unexpected nil — a missing frame
            // would shift Section-06's still↔frame DP alignment by one.
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sb) else {
                throw VideoEncoderError.readerFailed("no image buffer at frame \(frameNo)")
            }
            guard let cg = Self.cgImage(from: pixelBuffer, context: ciContext) else {
                throw VideoEncoderError.readerFailed("could not render frame \(frameNo) to CGImage")
            }
            grids.append(GridSampler.sample(cg))
            frameNo += 1
        }
        if reader.status == .failed {
            throw VideoEncoderError.readerFailed(reader.error?.localizedDescription ?? "sampleGrids read failed")
        }
        return grids
    }

    private static func cgImage(from pixelBuffer: CVPixelBuffer, context: CIContext) -> CGImage? {
        let ci = CIImage(cvPixelBuffer: pixelBuffer)
        return context.createCGImage(ci, from: ci.extent)
    }

    // MARK: encodeWithKeyframes

    /// REQUIRED H.264 output settings (asserted by tests). High profile, no
    /// frame reordering, high bitrate (VideoToolbox is less efficient than x264).
    /// Pixel format (yuv420p) is the encoder default for `.h264` and is verified
    /// in the integration test, not encoded here.
    static func h264OutputSettings(width: Int, height: Int) -> [String: Any] {
        // ~0.20 bits/pixel/frame @ 30fps → ~12.4 Mbps at 1080p. Generous on
        // purpose: quality over size, gated by human review.
        let bitRate = Int(Double(max(width * height, 1)) * 0.20 * 30.0)
        return [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoAllowFrameReorderingKey: false,
                AVVideoAverageBitRateKey: bitRate,
            ] as [String: Any],
        ]
    }

    func encodeWithKeyframes(input: URL, output: URL, timestamps: [Double]) async throws {
        // Funnel any cancellation (from the pre-loop awaits OR the encode loop)
        // into a single .cancelled + best-effort cleanup. The loop also cleans up
        // and throws .cancelled directly; that passes through here unchanged.
        do {
            try await runEncode(input: input, output: output, timestamps: timestamps)
        } catch is CancellationError {
            try? FileManager.default.removeItem(at: output)
            throw VideoEncoderError.cancelled
        }
    }

    private func runEncode(input: URL, output: URL, timestamps: [Double]) async throws {
        // Contract: callers (Section 07) probe() first — this method assumes a
        // valid, CFR, integer-fps source. The integer-timescale rebuild below and
        // round(t*fps) keyframe mapping are exact only for integer fps; a VFR /
        // non-integer source is rejected by probe(), not re-checked here.
        let asset = AVURLAsset(url: input)
        let tracks: [AVAssetTrack]
        do { tracks = try await asset.loadTracks(withMediaType: .video) }
        catch is CancellationError { throw CancellationError() }   // do not mask as corrupt
        catch { throw VideoEncoderError.corruptFile(error.localizedDescription) }
        guard let track = tracks.first else { throw VideoEncoderError.noVideoTrack }

        let (naturalSize, _, nominalFrameRate) =
            try await track.load(.naturalSize, .preferredTransform, .nominalFrameRate)
        // Size the writer to the RAW decoded buffer size — the reader emits frames
        // at naturalSize (untransformed) and we rebuild them verbatim without
        // rotating, so applying preferredTransform here would mismatch the pixels
        // (stretch/letterbox) on any rotated source. probe() returns the oriented
        // dims for the viewer's aspect ratio; for Keynote exports (identity
        // transform) the two are equal.
        var w = Int(abs(naturalSize.width).rounded())
        var h = Int(abs(naturalSize.height).rounded())
        if w == 0 || h == 0 { w = 1920; h = 1080 }
        var fps = Double(nominalFrameRate)
        if fps <= 0 { fps = 30 }

        try? FileManager.default.removeItem(at: output)

        // Reader → decompressed 4:2:0 frames.
        guard let reader = try? AVAssetReader(asset: asset) else {
            throw VideoEncoderError.readerFailed("could not create reader")
        }
        let readerSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        ]
        let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: readerSettings)
        // true: we mutate each sample buffer (CMSetAttachment ForceKeyFrame) before
        // appending; a shared/read-only buffer can drop the attachment.
        readerOutput.alwaysCopiesSampleData = true
        guard reader.canAdd(readerOutput) else { throw VideoEncoderError.readerFailed("cannot add reader output") }
        reader.add(readerOutput)

        // Writer → H.264 mp4, faststart.
        guard let writer = try? AVAssetWriter(outputURL: output, fileType: .mp4) else {
            throw VideoEncoderError.writerFailed("could not create writer")
        }
        writer.shouldOptimizeForNetworkUse = true
        let writerInput = AVAssetWriterInput(mediaType: .video,
                                             outputSettings: Self.h264OutputSettings(width: w, height: h))
        writerInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(writerInput) else { throw VideoEncoderError.writerFailed("cannot add writer input") }
        writer.add(writerInput)

        guard reader.startReading() else {
            throw VideoEncoderError.readerFailed(reader.error?.localizedDescription ?? "reader start failed")
        }
        guard writer.startWriting() else {
            throw VideoEncoderError.writerFailed(writer.error?.localizedDescription ?? "writer start failed")
        }
        writer.startSession(atSourceTime: .zero)

        let keyframeFrames = Set(forcedKeyframeFrameIndices(timestamps: timestamps, fps: fps))
        // Stamp explicit, uniform timing (PTS = i/fps, duration = 1/fps) onto each
        // rebuilt frame. Appending the reader's decompressed buffers verbatim lets
        // VideoToolbox re-time/interpolate the stream (observed: 12 in → 16 out),
        // which breaks the 1:1 frame mapping that forced-keyframe placement relies
        // on. Rebuilding with a fixed cadence guarantees exactly N output frames
        // and lands each forced keyframe on its intended index.
        let timescale = Int32(max(fps.rounded(), 1))
        let frameDuration = CMTime(value: 1, timescale: timescale)
        var frameIndex = 0

        do {
            // Manual pull loop (no escaping @Sendable closure → Swift-6 clean;
            // CMSampleBuffer stays confined to this task).
            while let sample = readerOutput.copyNextSampleBuffer() {
                try Task.checkCancellation()
                guard let imageBuffer = CMSampleBufferGetImageBuffer(sample) else { continue }

                var formatDesc: CMVideoFormatDescription?
                CMVideoFormatDescriptionCreateForImageBuffer(
                    allocator: kCFAllocatorDefault, imageBuffer: imageBuffer, formatDescriptionOut: &formatDesc)
                guard let fd = formatDesc else {
                    throw VideoEncoderError.writerFailed("could not build format description at frame \(frameIndex)")
                }
                var timing = CMSampleTimingInfo(
                    duration: frameDuration,
                    presentationTimeStamp: CMTime(value: CMTimeValue(frameIndex), timescale: timescale),
                    decodeTimeStamp: .invalid)
                var rebuilt: CMSampleBuffer?
                let status = CMSampleBufferCreateForImageBuffer(
                    allocator: kCFAllocatorDefault, imageBuffer: imageBuffer, dataReady: true,
                    makeDataReadyCallback: nil, refcon: nil, formatDescription: fd,
                    sampleTiming: &timing, sampleBufferOut: &rebuilt)
                guard status == noErr, let frame = rebuilt else {
                    throw VideoEncoderError.writerFailed("could not rebuild sample buffer at frame \(frameIndex) (status \(status))")
                }

                // Wait for the input, bounded by a stall watchdog so a wedged
                // encoder surfaces as an error instead of hanging forever.
                // 6000 × 5 ms = 30 s of no progress.
                var stalls = 0
                while !writerInput.isReadyForMoreMediaData {
                    try Task.checkCancellation()
                    stalls += 1
                    if stalls > 6_000 {
                        reader.cancelReading()
                        writer.cancelWriting()
                        try? FileManager.default.removeItem(at: output)
                        throw VideoEncoderError.writerFailed("encoder stalled at frame \(frameIndex) (input not ready for 30s)")
                    }
                    try await Task.sleep(nanoseconds: 5_000_000)   // 5 ms
                }
                if keyframeFrames.contains(frameIndex) {
                    CMSetAttachment(frame,
                                    key: kCMSampleBufferAttachmentKey_ForceKeyFrame,
                                    value: kCFBooleanTrue,
                                    attachmentMode: kCMAttachmentMode_ShouldNotPropagate)
                }
                if !writerInput.append(frame) {
                    throw VideoEncoderError.writerFailed(writer.error?.localizedDescription ?? "append failed at frame \(frameIndex)")
                }
                frameIndex += 1
            }
        } catch is CancellationError {
            reader.cancelReading()
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: output)
            throw VideoEncoderError.cancelled
        } catch {
            reader.cancelReading()
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: output)
            throw error
        }

        if reader.status == .failed {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: output)
            throw VideoEncoderError.readerFailed(reader.error?.localizedDescription ?? "reader failed mid-stream")
        }

        writerInput.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
            try? FileManager.default.removeItem(at: output)
            throw VideoEncoderError.writerFailed(writer.error?.localizedDescription ?? "finishWriting status \(writer.status.rawValue)")
        }
    }
}
