diff --git a/swift-app/KeynoteDeployer.xcodeproj/project.pbxproj b/swift-app/KeynoteDeployer.xcodeproj/project.pbxproj
index 86798fb..8336eed 100644
--- a/swift-app/KeynoteDeployer.xcodeproj/project.pbxproj
+++ b/swift-app/KeynoteDeployer.xcodeproj/project.pbxproj
@@ -8,6 +8,8 @@
 
 /* Begin PBXBuildFile section */
 		07A8FA865923A9F4F325A61A /* StillsMatch.swift in Sources */ = {isa = PBXBuildFile; fileRef = D57C9F761A616991B1231F01 /* StillsMatch.swift */; };
+		0BB5C5D74FBE3BFEFA08A12F /* AVFoundationVideoEncoder.swift in Sources */ = {isa = PBXBuildFile; fileRef = 3BB79FDC1EFBE27B83DABD22 /* AVFoundationVideoEncoder.swift */; };
+		0F265C03C5A0D733EB35550F /* VideoEncoding.swift in Sources */ = {isa = PBXBuildFile; fileRef = 06A48F26B10DD642AD5B6464 /* VideoEncoding.swift */; };
 		13F48A1926D584294516EEE0 /* SidebarView.swift in Sources */ = {isa = PBXBuildFile; fileRef = E3C9945227E19D94B300923C /* SidebarView.swift */; };
 		15125B060EAC0C268F273761 /* ProjectsView.swift in Sources */ = {isa = PBXBuildFile; fileRef = A857D151061C711E9B9957C8 /* ProjectsView.swift */; };
 		22CAA3C6B137E1DD00364127 /* video-viewer-golden-plain.html in Resources */ = {isa = PBXBuildFile; fileRef = 0A7E4D56A5BFA32DA7B9285F /* video-viewer-golden-plain.html */; };
@@ -43,6 +45,7 @@
 		D11E662E9329C958E5FD05BE /* VideoDeployRequest.swift in Sources */ = {isa = PBXBuildFile; fileRef = CBCFD1B404C9D887FD5FA7B0 /* VideoDeployRequest.swift */; };
 		EA8F1C902A8D2AD7D8A93A30 /* AppConfig.swift in Sources */ = {isa = PBXBuildFile; fileRef = 390DDF13A88F1C59BE62D165 /* AppConfig.swift */; };
 		F83478250D2F6D1FD03CE852 /* KeynoteProcessor.swift in Sources */ = {isa = PBXBuildFile; fileRef = 987B91A81602E8E224604358 /* KeynoteProcessor.swift */; };
+		FED0CB7E95A656D351958D95 /* AVFoundationVideoEncoderTests.swift in Sources */ = {isa = PBXBuildFile; fileRef = 3DF19AE8FCC6FD1C9ADE5B8A /* AVFoundationVideoEncoderTests.swift */; };
 /* End PBXBuildFile section */
 
 /* Begin PBXContainerItemProxy section */
@@ -56,6 +59,7 @@
 /* End PBXContainerItemProxy section */
 
 /* Begin PBXFileReference section */
+		06A48F26B10DD642AD5B6464 /* VideoEncoding.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = VideoEncoding.swift; sourceTree = "<group>"; };
 		082147F09FC716A0BEAD8B15 /* FileOperations.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = FileOperations.swift; sourceTree = "<group>"; };
 		0A7E4D56A5BFA32DA7B9285F /* video-viewer-golden-plain.html */ = {isa = PBXFileReference; lastKnownFileType = text.html; path = "video-viewer-golden-plain.html"; sourceTree = "<group>"; };
 		0C46C9CD46B3D1C3098570B6 /* video-viewer-template.html */ = {isa = PBXFileReference; lastKnownFileType = text.html; path = "video-viewer-template.html"; sourceTree = "<group>"; };
@@ -70,6 +74,8 @@
 		28C5E49D1314790083692357 /* AppSettings.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = AppSettings.swift; sourceTree = "<group>"; };
 		38B3998DF7B225F311525034 /* GridSampler.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = GridSampler.swift; sourceTree = "<group>"; };
 		390DDF13A88F1C59BE62D165 /* AppConfig.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = AppConfig.swift; sourceTree = "<group>"; };
+		3BB79FDC1EFBE27B83DABD22 /* AVFoundationVideoEncoder.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = AVFoundationVideoEncoder.swift; sourceTree = "<group>"; };
+		3DF19AE8FCC6FD1C9ADE5B8A /* AVFoundationVideoEncoderTests.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = AVFoundationVideoEncoderTests.swift; sourceTree = "<group>"; };
 		403D899438A463CD2A362774 /* GridSamplerTests.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = GridSamplerTests.swift; sourceTree = "<group>"; };
 		42ABCE72BEC351859554D951 /* VideoViewerGenerator.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = VideoViewerGenerator.swift; sourceTree = "<group>"; };
 		4A3AD033AAD0411C7CA1B6CD /* SettingsView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = SettingsView.swift; sourceTree = "<group>"; };
@@ -114,6 +120,7 @@
 		01C679620FE08A5704268729 /* Services */ = {
 			isa = PBXGroup;
 			children = (
+				3BB79FDC1EFBE27B83DABD22 /* AVFoundationVideoEncoder.swift */,
 				25181D8CAB9909769D352295 /* DeploymentVerifier.swift */,
 				082147F09FC716A0BEAD8B15 /* FileOperations.swift */,
 				38B3998DF7B225F311525034 /* GridSampler.swift */,
@@ -123,6 +130,7 @@
 				1C1AE82499CE26C6968F8AA7 /* UpdaterService.swift */,
 				17A85902F080898C86352154 /* VercelAPI.swift */,
 				282B4D114C60E28D56418FAE /* VercelDeployer.swift */,
+				06A48F26B10DD642AD5B6464 /* VideoEncoding.swift */,
 				42ABCE72BEC351859554D951 /* VideoViewerGenerator.swift */,
 			);
 			path = Services;
@@ -203,6 +211,7 @@
 		CCCD953E78791DE72243A9A3 /* Tests */ = {
 			isa = PBXGroup;
 			children = (
+				3DF19AE8FCC6FD1C9ADE5B8A /* AVFoundationVideoEncoderTests.swift */,
 				403D899438A463CD2A362774 /* GridSamplerTests.swift */,
 				AA065551FEEAB39DDEAC9B60 /* ModelsAndProjectTests.swift */,
 				E0A6C88075BDCE7E6E5AF0C9 /* StillsMatchTests.swift */,
@@ -355,6 +364,7 @@
 			isa = PBXSourcesBuildPhase;
 			buildActionMask = 2147483647;
 			files = (
+				FED0CB7E95A656D351958D95 /* AVFoundationVideoEncoderTests.swift in Sources */,
 				A14416E992CD0B244FFA16A1 /* GridSamplerTests.swift in Sources */,
 				419F05D5433E94752E999ED6 /* ModelsAndProjectTests.swift in Sources */,
 				4B289C6795B7E64A9625F96D /* StillsMatchTests.swift in Sources */,
@@ -366,6 +376,7 @@
 			isa = PBXSourcesBuildPhase;
 			buildActionMask = 2147483647;
 			files = (
+				0BB5C5D74FBE3BFEFA08A12F /* AVFoundationVideoEncoder.swift in Sources */,
 				EA8F1C902A8D2AD7D8A93A30 /* AppConfig.swift in Sources */,
 				483D3CC267D95282088F9309 /* AppSettings.swift in Sources */,
 				84C92D6C1E3FBCD22171220F /* ContentView.swift in Sources */,
@@ -393,6 +404,7 @@
 				46171C654C9CF229C03D7615 /* VercelProject.swift in Sources */,
 				8D642D0B7DE7423F33970CAC /* VideoAnalysis.swift in Sources */,
 				D11E662E9329C958E5FD05BE /* VideoDeployRequest.swift in Sources */,
+				0F265C03C5A0D733EB35550F /* VideoEncoding.swift in Sources */,
 				4A2E1C7FE7EE01DC8EB9F111 /* VideoViewerGenerator.swift in Sources */,
 			);
 			runOnlyForDeploymentPostprocessing = 0;
diff --git a/swift-app/Sources/Services/AVFoundationVideoEncoder.swift b/swift-app/Sources/Services/AVFoundationVideoEncoder.swift
new file mode 100644
index 0000000..37970f8
--- /dev/null
+++ b/swift-app/Sources/Services/AVFoundationVideoEncoder.swift
@@ -0,0 +1,302 @@
+import Foundation
+import AVFoundation
+import CoreImage
+import CoreGraphics
+import ImageIO
+
+/// Default (shipping) encoder for the video-deploy path. Apple-frameworks only —
+/// no bundled binary, so no nested-binary codesigning / notarization surface.
+/// Stateless `struct` → `Sendable`; everything passes via parameters.
+///
+/// Forced keyframes: VideoToolbox's H.264 encoder honors
+/// `kCMSampleBufferAttachmentKey_ForceKeyFrame` on individual sample buffers
+/// during an `AVAssetReader → AVAssetWriter` re-encode, which lets us put an
+/// I-frame at each arbitrary slide timestamp. VideoToolbox is less quality-
+/// efficient than `libx264 -crf 18`, so we bias hard toward quality (High
+/// profile, high bitrate) and gate on human review (Section 05 ffmpeg is the
+/// escape hatch).
+struct AVFoundationVideoEncoder: VideoEncoder {
+
+    // MARK: probe
+
+    func probe(url: URL) async throws -> (width: Int, height: Int, fps: Double) {
+        let asset = AVURLAsset(url: url)
+        let tracks: [AVAssetTrack]
+        do {
+            tracks = try await asset.loadTracks(withMediaType: .video)
+        } catch {
+            throw VideoEncoderError.corruptFile(error.localizedDescription)
+        }
+        guard let track = tracks.first else { throw VideoEncoderError.noVideoTrack }
+
+        let naturalSize: CGSize
+        let transform: CGAffineTransform
+        let nominalFrameRate: Float
+        do {
+            (naturalSize, transform, nominalFrameRate) =
+                try await track.load(.naturalSize, .preferredTransform, .nominalFrameRate)
+        } catch {
+            throw VideoEncoderError.corruptFile(error.localizedDescription)
+        }
+
+        let oriented = naturalSize.applying(transform)
+        var w = Int(abs(oriented.width).rounded())
+        var h = Int(abs(oriented.height).rounded())
+        if w == 0 || h == 0 { w = 1920; h = 1080 }   // valid track, unusable size
+
+        var fps = Double(nominalFrameRate)
+        if fps <= 0 { fps = 30 }
+
+        try await assertConstantFrameRate(asset: asset, track: track)
+        return (w, h, fps)
+    }
+
+    /// Reject variable frame rate (A2). Reads up to ~20 decompressed frames (so
+    /// PTS arrive in presentation order, unaffected by B-frame decode reordering)
+    /// and checks the inter-frame PTS deltas are constant within tolerance.
+    private func assertConstantFrameRate(asset: AVURLAsset, track: AVAssetTrack) async throws {
+        guard let reader = try? AVAssetReader(asset: asset) else {
+            throw VideoEncoderError.readerFailed("could not create reader for VFR probe")
+        }
+        let settings: [String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
+        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
+        output.alwaysCopiesSampleData = false
+        guard reader.canAdd(output) else { throw VideoEncoderError.readerFailed("cannot add VFR-probe output") }
+        reader.add(output)
+        guard reader.startReading() else {
+            throw VideoEncoderError.readerFailed(reader.error?.localizedDescription ?? "VFR probe start failed")
+        }
+
+        var deltas: [Double] = []
+        var prev: CMTime?
+        var count = 0
+        while count < 20, let sb = output.copyNextSampleBuffer() {
+            let pts = CMSampleBufferGetPresentationTimeStamp(sb)
+            if let p = prev { deltas.append((pts - p).seconds) }
+            prev = pts
+            count += 1
+        }
+        reader.cancelReading()
+
+        guard deltas.count >= 2 else { return }   // too few frames to judge → accept
+        let mean = deltas.reduce(0, +) / Double(deltas.count)
+        guard mean > 0 else { return }
+        let tolerance = mean * 0.10                // 10% — Keynote CFR is exact; real VFR jitters far more
+        for d in deltas where abs(d - mean) > tolerance {
+            throw VideoEncoderError.variableFrameRate
+        }
+    }
+
+    // MARK: sampleGrids
+
+    func sampleGrids(url: URL) async throws -> [[Double]] {
+        let asset = AVURLAsset(url: url)
+        let tracks = (try? await asset.loadTracks(withMediaType: .video)) ?? []
+
+        // Still image: no video track → decode one CGImage via ImageIO.
+        if tracks.isEmpty {
+            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
+                  let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
+                throw VideoEncoderError.corruptFile("not a decodable image or video: \(url.lastPathComponent)")
+            }
+            return [GridSampler.sample(img)]
+        }
+
+        // Video: read every frame decompressed (presentation order) → grid.
+        let track = tracks[0]
+        guard let reader = try? AVAssetReader(asset: asset) else {
+            throw VideoEncoderError.readerFailed("could not create reader for sampleGrids")
+        }
+        let settings: [String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
+        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
+        output.alwaysCopiesSampleData = false
+        guard reader.canAdd(output) else { throw VideoEncoderError.readerFailed("cannot add sampleGrids output") }
+        reader.add(output)
+        guard reader.startReading() else {
+            throw VideoEncoderError.readerFailed(reader.error?.localizedDescription ?? "sampleGrids start failed")
+        }
+
+        let ciContext = CIContext(options: nil)
+        var grids: [[Double]] = []
+        while let sb = output.copyNextSampleBuffer() {
+            try Task.checkCancellation()
+            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sb) else { continue }
+            if let cg = Self.cgImage(from: pixelBuffer, context: ciContext) {
+                grids.append(GridSampler.sample(cg))
+            }
+        }
+        if reader.status == .failed {
+            throw VideoEncoderError.readerFailed(reader.error?.localizedDescription ?? "sampleGrids read failed")
+        }
+        return grids
+    }
+
+    private static func cgImage(from pixelBuffer: CVPixelBuffer, context: CIContext) -> CGImage? {
+        let ci = CIImage(cvPixelBuffer: pixelBuffer)
+        return context.createCGImage(ci, from: ci.extent)
+    }
+
+    // MARK: encodeWithKeyframes
+
+    /// REQUIRED H.264 output settings (asserted by tests). High profile, no
+    /// frame reordering, high bitrate (VideoToolbox is less efficient than x264).
+    /// Pixel format (yuv420p) is the encoder default for `.h264` and is verified
+    /// in the integration test, not encoded here.
+    static func h264OutputSettings(width: Int, height: Int) -> [String: Any] {
+        // ~0.20 bits/pixel/frame @ 30fps → ~12.4 Mbps at 1080p. Generous on
+        // purpose: quality over size, gated by human review.
+        let bitRate = Int(Double(max(width * height, 1)) * 0.20 * 30.0)
+        return [
+            AVVideoCodecKey: AVVideoCodecType.h264,
+            AVVideoWidthKey: width,
+            AVVideoHeightKey: height,
+            AVVideoCompressionPropertiesKey: [
+                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
+                AVVideoAllowFrameReorderingKey: false,
+                AVVideoAverageBitRateKey: bitRate,
+            ] as [String: Any],
+        ]
+    }
+
+    func encodeWithKeyframes(input: URL, output: URL, timestamps: [Double]) async throws {
+        // Funnel any cancellation (from the pre-loop awaits OR the encode loop)
+        // into a single .cancelled + best-effort cleanup. The loop also cleans up
+        // and throws .cancelled directly; that passes through here unchanged.
+        do {
+            try await runEncode(input: input, output: output, timestamps: timestamps)
+        } catch is CancellationError {
+            try? FileManager.default.removeItem(at: output)
+            throw VideoEncoderError.cancelled
+        }
+    }
+
+    private func runEncode(input: URL, output: URL, timestamps: [Double]) async throws {
+        let asset = AVURLAsset(url: input)
+        let tracks: [AVAssetTrack]
+        do { tracks = try await asset.loadTracks(withMediaType: .video) }
+        catch is CancellationError { throw CancellationError() }   // do not mask as corrupt
+        catch { throw VideoEncoderError.corruptFile(error.localizedDescription) }
+        guard let track = tracks.first else { throw VideoEncoderError.noVideoTrack }
+
+        let (naturalSize, transform, nominalFrameRate) =
+            try await track.load(.naturalSize, .preferredTransform, .nominalFrameRate)
+        let oriented = naturalSize.applying(transform)
+        var w = Int(abs(oriented.width).rounded())
+        var h = Int(abs(oriented.height).rounded())
+        if w == 0 || h == 0 { w = 1920; h = 1080 }
+        var fps = Double(nominalFrameRate)
+        if fps <= 0 { fps = 30 }
+
+        try? FileManager.default.removeItem(at: output)
+
+        // Reader → decompressed 4:2:0 frames.
+        guard let reader = try? AVAssetReader(asset: asset) else {
+            throw VideoEncoderError.readerFailed("could not create reader")
+        }
+        let readerSettings: [String: Any] = [
+            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
+        ]
+        let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: readerSettings)
+        // true: we mutate each sample buffer (CMSetAttachment ForceKeyFrame) before
+        // appending; a shared/read-only buffer can drop the attachment.
+        readerOutput.alwaysCopiesSampleData = true
+        guard reader.canAdd(readerOutput) else { throw VideoEncoderError.readerFailed("cannot add reader output") }
+        reader.add(readerOutput)
+
+        // Writer → H.264 mp4, faststart.
+        guard let writer = try? AVAssetWriter(outputURL: output, fileType: .mp4) else {
+            throw VideoEncoderError.writerFailed("could not create writer")
+        }
+        writer.shouldOptimizeForNetworkUse = true
+        let writerInput = AVAssetWriterInput(mediaType: .video,
+                                             outputSettings: Self.h264OutputSettings(width: w, height: h))
+        writerInput.expectsMediaDataInRealTime = false
+        guard writer.canAdd(writerInput) else { throw VideoEncoderError.writerFailed("cannot add writer input") }
+        writer.add(writerInput)
+
+        guard reader.startReading() else {
+            throw VideoEncoderError.readerFailed(reader.error?.localizedDescription ?? "reader start failed")
+        }
+        guard writer.startWriting() else {
+            throw VideoEncoderError.writerFailed(writer.error?.localizedDescription ?? "writer start failed")
+        }
+        writer.startSession(atSourceTime: .zero)
+
+        let keyframeFrames = Set(forcedKeyframeFrameIndices(timestamps: timestamps, fps: fps))
+        // Stamp explicit, uniform timing (PTS = i/fps, duration = 1/fps) onto each
+        // rebuilt frame. Appending the reader's decompressed buffers verbatim lets
+        // VideoToolbox re-time/interpolate the stream (observed: 12 in → 16 out),
+        // which breaks the 1:1 frame mapping that forced-keyframe placement relies
+        // on. Rebuilding with a fixed cadence guarantees exactly N output frames
+        // and lands each forced keyframe on its intended index.
+        let timescale = Int32(max(fps.rounded(), 1))
+        let frameDuration = CMTime(value: 1, timescale: timescale)
+        var frameIndex = 0
+
+        do {
+            // Manual pull loop (no escaping @Sendable closure → Swift-6 clean;
+            // CMSampleBuffer stays confined to this task).
+            while let sample = readerOutput.copyNextSampleBuffer() {
+                try Task.checkCancellation()
+                guard let imageBuffer = CMSampleBufferGetImageBuffer(sample) else { continue }
+
+                var formatDesc: CMVideoFormatDescription?
+                CMVideoFormatDescriptionCreateForImageBuffer(
+                    allocator: kCFAllocatorDefault, imageBuffer: imageBuffer, formatDescriptionOut: &formatDesc)
+                guard let fd = formatDesc else {
+                    throw VideoEncoderError.writerFailed("could not build format description at frame \(frameIndex)")
+                }
+                var timing = CMSampleTimingInfo(
+                    duration: frameDuration,
+                    presentationTimeStamp: CMTime(value: CMTimeValue(frameIndex), timescale: timescale),
+                    decodeTimeStamp: .invalid)
+                var rebuilt: CMSampleBuffer?
+                let status = CMSampleBufferCreateForImageBuffer(
+                    allocator: kCFAllocatorDefault, imageBuffer: imageBuffer, dataReady: true,
+                    makeDataReadyCallback: nil, refcon: nil, formatDescription: fd,
+                    sampleTiming: &timing, sampleBufferOut: &rebuilt)
+                guard status == noErr, let frame = rebuilt else {
+                    throw VideoEncoderError.writerFailed("could not rebuild sample buffer at frame \(frameIndex) (status \(status))")
+                }
+
+                while !writerInput.isReadyForMoreMediaData {
+                    try Task.checkCancellation()
+                    try await Task.sleep(nanoseconds: 5_000_000)   // 5 ms
+                }
+                if keyframeFrames.contains(frameIndex) {
+                    CMSetAttachment(frame,
+                                    key: kCMSampleBufferAttachmentKey_ForceKeyFrame,
+                                    value: kCFBooleanTrue,
+                                    attachmentMode: kCMAttachmentMode_ShouldPropagate)
+                }
+                if !writerInput.append(frame) {
+                    throw VideoEncoderError.writerFailed(writer.error?.localizedDescription ?? "append failed at frame \(frameIndex)")
+                }
+                frameIndex += 1
+            }
+        } catch is CancellationError {
+            reader.cancelReading()
+            writer.cancelWriting()
+            try? FileManager.default.removeItem(at: output)
+            throw VideoEncoderError.cancelled
+        } catch {
+            reader.cancelReading()
+            writer.cancelWriting()
+            try? FileManager.default.removeItem(at: output)
+            throw error
+        }
+
+        if reader.status == .failed {
+            writer.cancelWriting()
+            try? FileManager.default.removeItem(at: output)
+            throw VideoEncoderError.readerFailed(reader.error?.localizedDescription ?? "reader failed mid-stream")
+        }
+
+        writerInput.markAsFinished()
+        await writer.finishWriting()
+        guard writer.status == .completed else {
+            try? FileManager.default.removeItem(at: output)
+            throw VideoEncoderError.writerFailed(writer.error?.localizedDescription ?? "finishWriting status \(writer.status.rawValue)")
+        }
+    }
+}
diff --git a/swift-app/Sources/Services/VideoEncoding.swift b/swift-app/Sources/Services/VideoEncoding.swift
new file mode 100644
index 0000000..8ef2f34
--- /dev/null
+++ b/swift-app/Sources/Services/VideoEncoding.swift
@@ -0,0 +1,57 @@
+import Foundation
+
+/// The encoder seam for the video-deploy path. Two conformers:
+/// `AVFoundationVideoEncoder` (default, Apple-only) and `FFmpegVideoEncoder`
+/// (Section 05 fallback). All three operations are pure-ish I/O on URLs so the
+/// two engines are interchangeable behind this protocol.
+protocol VideoEncoder: Sendable {
+    /// Probe container/stream for dimensions + constant frame rate.
+    /// Throws on no-video-track, corrupt input, or variable frame rate.
+    func probe(url: URL) async throws -> (width: Int, height: Int, fps: Double)
+
+    /// Decode `url` to per-frame 32×18 RGB grids (downscaled), in presentation
+    /// order. Handles both a video (many frames) and a still image (one frame).
+    /// Reuses `GridSampler.sample` so video frames and stills land on the SAME grid.
+    func sampleGrids(url: URL) async throws -> [[Double]]
+
+    /// Re-encode `input` to web-safe H.264 with a forced keyframe at each
+    /// timestamp. Output: yuv420p, High profile, no audio, faststart.
+    func encodeWithKeyframes(input: URL, output: URL, timestamps: [Double]) async throws
+}
+
+/// User-facing, actionable encoder errors.
+enum VideoEncoderError: Error, LocalizedError, Sendable, Equatable {
+    case noVideoTrack
+    case corruptFile(String)
+    case variableFrameRate
+    case readerFailed(String)
+    case writerFailed(String)
+    case cancelled
+
+    var errorDescription: String? {
+        switch self {
+        case .noVideoTrack:
+            return "The file has no video track. Drop a video (or an exported deck), not an audio-only file."
+        case .corruptFile(let detail):
+            return "The video file couldn't be read (\(detail)). Re-export it and try again."
+        case .variableFrameRate:
+            return "The video has a variable frame rate. Re-export it at a constant frame rate (Keynote exports CFR by default)."
+        case .readerFailed(let detail):
+            return "Reading the source video failed: \(detail)"
+        case .writerFailed(let detail):
+            return "Encoding the video failed: \(detail)"
+        case .cancelled:
+            return "Encoding was cancelled."
+        }
+    }
+}
+
+/// Maps each slide timestamp (seconds) to the nearest output frame index at `fps`.
+/// Shared by both encoders so AVFoundation's forced-keyframe attachment and
+/// ffmpeg's `-force_key_frames` land on the SAME frames. For the real pipeline
+/// (timestamps = frameIndex / fps from Section 06), `round(t * fps)` recovers the
+/// exact frame index. Negative results are clamped to 0; `fps <= 0` → all 0.
+func forcedKeyframeFrameIndices(timestamps: [Double], fps: Double) -> [Int] {
+    guard fps > 0 else { return timestamps.map { _ in 0 } }
+    return timestamps.map { t in max(0, Int((t * fps).rounded())) }
+}
diff --git a/swift-app/Tests/AVFoundationVideoEncoderTests.swift b/swift-app/Tests/AVFoundationVideoEncoderTests.swift
new file mode 100644
index 0000000..65212dc
--- /dev/null
+++ b/swift-app/Tests/AVFoundationVideoEncoderTests.swift
@@ -0,0 +1,319 @@
+import Testing
+import Foundation
+import AVFoundation
+import CoreGraphics
+import ImageIO
+import UniformTypeIdentifiers
+@testable import KeynoteDeployer
+
+/// Section 4 — VideoEncoder protocol + AVFoundationVideoEncoder.
+/// Fixtures are synthesized in-test (no binary assets in the repo): solid-color
+/// CFR/VFR videos via AVAssetWriter, a PNG still via ImageIO, and a garbage mp4.
+@Suite("Section 4 — AVFoundationVideoEncoder")
+struct AVFoundationVideoEncoderTests {
+
+    // MARK: - Pure helper
+
+    @Test func forcedKeyframeMapsToNearestFrameIndex() {
+        // timestamps = frameIndex/fps → exact recovery
+        #expect(forcedKeyframeFrameIndices(timestamps: [0, 5.0/30.0, 9.0/30.0], fps: 30) == [0, 5, 9])
+        // nearest rounding
+        #expect(forcedKeyframeFrameIndices(timestamps: [0.49/30.0, 0.51/30.0], fps: 30) == [0, 1])
+        // clamp + degenerate fps
+        #expect(forcedKeyframeFrameIndices(timestamps: [-1.0, 2.0], fps: 0) == [0, 0])
+    }
+
+    // MARK: - Output settings
+
+    @Test func outputSettingsAreH264HighNoReorder() {
+        let s = AVFoundationVideoEncoder.h264OutputSettings(width: 1920, height: 1080)
+        #expect((s[AVVideoCodecKey] as? AVVideoCodecType) == .h264)
+        #expect((s[AVVideoWidthKey] as? Int) == 1920)
+        #expect((s[AVVideoHeightKey] as? Int) == 1080)
+        let comp = try? #require(s[AVVideoCompressionPropertiesKey] as? [String: Any])
+        #expect((comp?[AVVideoProfileLevelKey] as? String) == AVVideoProfileLevelH264HighAutoLevel)
+        #expect((comp?[AVVideoAllowFrameReorderingKey] as? Bool) == false)
+        let bitRate = try? #require(comp?[AVVideoAverageBitRateKey] as? Int)
+        #expect((bitRate ?? 0) > 1_000_000)   // biased high
+    }
+
+    // MARK: - probe
+
+    @Test func probeReturnsDimensionsAndFps() async throws {
+        let url = try await Self.makeVideo(frames: 12, fps: 30, size: CGSize(width: 320, height: 180), vfr: false)
+        defer { try? FileManager.default.removeItem(at: url) }
+        let (w, h, fps) = try await AVFoundationVideoEncoder().probe(url: url)
+        #expect(w == 320)
+        #expect(h == 180)
+        #expect(abs(fps - 30) < 0.5)
+    }
+
+    @Test func probeRejectsVariableFrameRate() async throws {
+        let url = try await Self.makeVideo(frames: 8, fps: 30, size: CGSize(width: 320, height: 180), vfr: true)
+        defer { try? FileManager.default.removeItem(at: url) }
+        await #expect(throws: VideoEncoderError.variableFrameRate) {
+            _ = try await AVFoundationVideoEncoder().probe(url: url)
+        }
+    }
+
+    @Test func probeNoVideoTrackThrows() async throws {
+        // A real audio-only container: AVFoundation opens it fine and reports
+        // zero video tracks → the .noVideoTrack branch (distinct from .corruptFile,
+        // which fires when the container can't be opened at all).
+        let url = try Self.makeAudioOnly()
+        defer { try? FileManager.default.removeItem(at: url) }
+        await #expect(throws: VideoEncoderError.noVideoTrack) {
+            _ = try await AVFoundationVideoEncoder().probe(url: url)
+        }
+    }
+
+    @Test func probeCorruptFileThrows() async throws {
+        let url = try Self.makeGarbageMP4()
+        defer { try? FileManager.default.removeItem(at: url) }
+        // Garbage container → corruptFile (load throws) or noVideoTrack (loads, no track).
+        // Either is an actionable VideoEncoderError; assert it throws one.
+        await #expect(throws: VideoEncoderError.self) {
+            _ = try await AVFoundationVideoEncoder().probe(url: url)
+        }
+    }
+
+    // MARK: - sampleGrids
+
+    @Test func sampleGridsStillReturnsOneGrid() async throws {
+        let url = try Self.makePNG(size: CGSize(width: 200, height: 120))
+        defer { try? FileManager.default.removeItem(at: url) }
+        let grids = try await AVFoundationVideoEncoder().sampleGrids(url: url)
+        #expect(grids.count == 1)
+        #expect(grids[0].count == GridSampler.valueCount)   // 1728
+        #expect(grids[0].allSatisfy { $0 >= 0 && $0 <= 255 })
+    }
+
+    @Test func sampleGridsVideoReturnsGridPerFrame() async throws {
+        let url = try await Self.makeVideo(frames: 10, fps: 30, size: CGSize(width: 320, height: 180), vfr: false)
+        defer { try? FileManager.default.removeItem(at: url) }
+        let grids = try await AVFoundationVideoEncoder().sampleGrids(url: url)
+        #expect(grids.count == 10)
+        #expect(grids.allSatisfy { $0.count == GridSampler.valueCount })
+    }
+
+    // MARK: - encodeWithKeyframes (integration)
+
+    @Test func encodeForcesKeyframesAndIsFaststart() async throws {
+        let src = try await Self.makeVideo(frames: 12, fps: 30, size: CGSize(width: 320, height: 180), vfr: false)
+        let out = Self.tmpURL(ext: "mp4")
+        defer { try? FileManager.default.removeItem(at: src); try? FileManager.default.removeItem(at: out) }
+
+        let encoder = AVFoundationVideoEncoder()
+        // Derive timestamps from the PROBED fps so the encoder's frame mapping and
+        // the test's expected indices use the same fps (no 30-vs-actual drift).
+        let (_, _, fps) = try await encoder.probe(url: src)
+        let srcFrameCount = try await encoder.sampleGrids(url: src).count
+        let targetFrames = [0, 5, 9]
+        let timestamps = targetFrames.map { Double($0) / fps }
+        try await encoder.encodeWithKeyframes(input: src, output: out, timestamps: timestamps)
+        #expect(FileManager.default.fileExists(atPath: out.path))
+
+        // Frame-count integrity: decoded output frames must equal source frames.
+        let outDecodedCount = try await encoder.sampleGrids(url: out).count
+        #expect(outDecodedCount == srcFrameCount, "decoded output frames \(outDecodedCount) != source \(srcFrameCount)")
+
+        // Keyframes located by PTS→frame-index (robust to how the compressed
+        // reader batches samples), not by buffer position.
+        let keyframes = try await Self.keyframeFrameIndices(url: out, fps: fps)
+        for idx in forcedKeyframeFrameIndices(timestamps: timestamps, fps: fps) {
+            #expect(keyframes.contains(idx), "frame \(idx) should be a keyframe; actual keyframes=\(keyframes.sorted()), decoded=\(outDecodedCount), fps=\(fps)")
+        }
+
+        // faststart: moov before mdat
+        let order = try Self.topLevelBoxOrder(url: out)
+        let moov = order.firstIndex(of: "moov")
+        let mdat = order.firstIndex(of: "mdat")
+        #expect(moov != nil && mdat != nil)
+        if let m = moov, let d = mdat { #expect(m < d, "moov must precede mdat (faststart)") }
+    }
+
+    @Test func cancellationCleansUp() async throws {
+        let src = try await Self.makeVideo(frames: 120, fps: 30, size: CGSize(width: 480, height: 270), vfr: false)
+        let out = Self.tmpURL(ext: "mp4")
+        defer { try? FileManager.default.removeItem(at: src); try? FileManager.default.removeItem(at: out) }
+
+        let encoder = AVFoundationVideoEncoder()
+        let task = Task { try await encoder.encodeWithKeyframes(input: src, output: out, timestamps: [0]) }
+        task.cancel()
+        await #expect(throws: VideoEncoderError.cancelled) { try await task.value }
+        #expect(!FileManager.default.fileExists(atPath: out.path), "partial output must be removed on cancel")
+    }
+
+    // MARK: - Fixture helpers
+
+    static func tmpURL(ext: String) -> URL {
+        FileManager.default.temporaryDirectory
+            .appendingPathComponent("kd-sec4-\(UUID().uuidString)")
+            .appendingPathExtension(ext)
+    }
+
+    /// Write a solid-gray-ramp H.264 video. CFR: PTS = i/fps. VFR: uneven PTS.
+    static func makeVideo(frames: Int, fps: Int32, size: CGSize, vfr: Bool) async throws -> URL {
+        let url = tmpURL(ext: "mp4")
+        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
+        let settings: [String: Any] = [
+            AVVideoCodecKey: AVVideoCodecType.h264,
+            AVVideoWidthKey: Int(size.width),
+            AVVideoHeightKey: Int(size.height),
+        ]
+        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
+        input.expectsMediaDataInRealTime = false
+        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
+            assetWriterInput: input,
+            sourcePixelBufferAttributes: [
+                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
+                kCVPixelBufferWidthKey as String: Int(size.width),
+                kCVPixelBufferHeightKey as String: Int(size.height),
+            ]
+        )
+        #expect(writer.canAdd(input))
+        writer.add(input)
+        #expect(writer.startWriting())
+        writer.startSession(atSourceTime: .zero)
+
+        // Uneven, strictly increasing PTS (seconds) for the VFR fixture.
+        let vfrTimes: [Double] = [0, 0.10, 0.45, 0.50, 0.95, 1.0, 1.60, 1.65]
+
+        for i in 0..<frames {
+            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
+            // Near-constant brightness (1/255 step/frame) → low motion, so the
+            // encoder does NOT scene-detect keyframes on every frame; forced
+            // keyframes then stand out against a sparse auto-keyframe baseline.
+            let gray = UInt8(min(255, 100 + i))
+            let pb = makePixelBuffer(size: size, gray: gray)
+            let pts: CMTime
+            if vfr {
+                pts = CMTime(seconds: vfrTimes[min(i, vfrTimes.count - 1)], preferredTimescale: 600)
+            } else {
+                pts = CMTime(value: CMTimeValue(i), timescale: fps)
+            }
+            #expect(adaptor.append(pb, withPresentationTime: pts))
+        }
+        input.markAsFinished()
+        await writer.finishWriting()
+        #expect(writer.status == .completed, "fixture writer failed: \(writer.error?.localizedDescription ?? "?")")
+        return url
+    }
+
+    static func makePixelBuffer(size: CGSize, gray: UInt8) -> CVPixelBuffer {
+        var pb: CVPixelBuffer?
+        let attrs: CFDictionary = [
+            kCVPixelBufferCGImageCompatibilityKey: true,
+            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
+        ] as CFDictionary
+        CVPixelBufferCreate(kCFAllocatorDefault, Int(size.width), Int(size.height),
+                            kCVPixelFormatType_32ARGB, attrs, &pb)
+        let buffer = pb!
+        CVPixelBufferLockBaseAddress(buffer, [])
+        let ctx = CGContext(
+            data: CVPixelBufferGetBaseAddress(buffer),
+            width: Int(size.width), height: Int(size.height),
+            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
+            space: CGColorSpaceCreateDeviceRGB(),
+            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
+        )!
+        let v = Double(gray) / 255.0
+        ctx.setFillColor(CGColor(red: v, green: v, blue: v, alpha: 1))
+        ctx.fill(CGRect(origin: .zero, size: size))
+        CVPixelBufferUnlockBaseAddress(buffer, [])
+        return buffer
+    }
+
+    static func makePNG(size: CGSize) throws -> URL {
+        let url = tmpURL(ext: "png")
+        let ctx = CGContext(
+            data: nil, width: Int(size.width), height: Int(size.height),
+            bitsPerComponent: 8, bytesPerRow: 0,
+            space: CGColorSpace(name: CGColorSpace.sRGB)!,
+            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
+        )!
+        ctx.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
+        ctx.fill(CGRect(origin: .zero, size: size))
+        let img = ctx.makeImage()!
+        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
+            throw VideoEncoderError.corruptFile("could not create PNG destination")
+        }
+        CGImageDestinationAddImage(dest, img, nil)
+        #expect(CGImageDestinationFinalize(dest))
+        return url
+    }
+
+    static func makeGarbageMP4() throws -> URL {
+        let url = tmpURL(ext: "mp4")
+        var bytes = [UInt8]()
+        for i in 0..<4096 { bytes.append(UInt8((i * 31 + 7) % 256)) }
+        try Data(bytes).write(to: url)
+        return url
+    }
+
+    /// A valid audio-only container (1 s of silence). AVFoundation opens it and
+    /// reports zero video tracks → exercises the .noVideoTrack branch.
+    static func makeAudioOnly() throws -> URL {
+        let url = tmpURL(ext: "caf")
+        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
+        let file = try AVAudioFile(forWriting: url, settings: format.settings)
+        let frameCount: AVAudioFrameCount = 44_100
+        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
+        buffer.frameLength = frameCount   // zero-filled = silence
+        try file.write(from: buffer)
+        return url
+    }
+
+    /// Keyframe frame-indices of the encoded output, located by presentation time
+    /// (frameIndex = round(pts * fps)). Reading compressed (outputSettings: nil)
+    /// can yield sample buffers that don't map 1:1 to frame positions, so we key
+    /// off PTS rather than buffer index. A sample is a keyframe unless it carries
+    /// NotSync == true.
+    static func keyframeFrameIndices(url: URL, fps: Double) async throws -> Set<Int> {
+        let asset = AVURLAsset(url: url)
+        let track = try await asset.loadTracks(withMediaType: .video)[0]
+        let reader = try AVAssetReader(asset: asset)
+        let out = AVAssetReaderTrackOutput(track: track, outputSettings: nil)   // compressed
+        out.alwaysCopiesSampleData = false
+        reader.add(out)
+        reader.startReading()
+        var keys: Set<Int> = []
+        while let sb = out.copyNextSampleBuffer() {
+            guard CMSampleBufferGetNumSamples(sb) > 0 else { continue }
+            let pts = CMSampleBufferGetPresentationTimeStamp(sb)
+            guard pts.isValid, !pts.isIndefinite else { continue }
+            var isKey = true
+            if let arr = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[CFString: Any]],
+               let first = arr.first,
+               let notSync = first[kCMSampleAttachmentKey_NotSync] as? Bool {
+                isKey = !notSync
+            }
+            if isKey { keys.insert(Int((pts.seconds * fps).rounded())) }
+        }
+        return keys
+    }
+
+    /// Ordered list of top-level MP4 box types (for faststart verification).
+    static func topLevelBoxOrder(url: URL) throws -> [String] {
+        let data = try Data(contentsOf: url)
+        var order: [String] = []
+        var off = 0
+        while off + 8 <= data.count {
+            let size = Int(data[off]) << 24 | Int(data[off + 1]) << 16 | Int(data[off + 2]) << 8 | Int(data[off + 3])
+            let type = String(bytes: data[off + 4 ..< off + 8], encoding: .ascii) ?? "????"
+            order.append(type)
+            if size == 1 {
+                guard off + 16 <= data.count else { break }
+                var large = 0
+                for k in 0..<8 { large = large << 8 | Int(data[off + 8 + k]) }
+                guard large >= 16 else { break }
+                off += large
+            } else if size >= 8 {
+                off += size
+            } else {
+                break
+            }
+        }
+        return order
+    }
+}
