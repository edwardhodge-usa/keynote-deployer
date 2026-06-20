import Testing
import Foundation
import AVFoundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import KeynoteDeployer

/// Section 4 — VideoEncoder protocol + AVFoundationVideoEncoder.
/// Fixtures are synthesized in-test (no binary assets in the repo): solid-color
/// CFR/VFR videos via AVAssetWriter, a PNG still via ImageIO, and a garbage mp4.
@Suite("Section 4 — AVFoundationVideoEncoder")
struct AVFoundationVideoEncoderTests {

    // MARK: - Pure helper

    @Test func forcedKeyframeMapsToNearestFrameIndex() {
        // timestamps = frameIndex/fps → exact recovery
        #expect(forcedKeyframeFrameIndices(timestamps: [0, 5.0/30.0, 9.0/30.0], fps: 30) == [0, 5, 9])
        // nearest rounding
        #expect(forcedKeyframeFrameIndices(timestamps: [0.49/30.0, 0.51/30.0], fps: 30) == [0, 1])
        // clamp + degenerate fps
        #expect(forcedKeyframeFrameIndices(timestamps: [-1.0, 2.0], fps: 0) == [0, 0])
    }

    // MARK: - Output settings

    @Test func outputSettingsAreH264HighNoReorder() {
        let s = AVFoundationVideoEncoder.h264OutputSettings(width: 1920, height: 1080)
        #expect((s[AVVideoCodecKey] as? AVVideoCodecType) == .h264)
        #expect((s[AVVideoWidthKey] as? Int) == 1920)
        #expect((s[AVVideoHeightKey] as? Int) == 1080)
        let comp = try? #require(s[AVVideoCompressionPropertiesKey] as? [String: Any])
        #expect((comp?[AVVideoProfileLevelKey] as? String) == AVVideoProfileLevelH264HighAutoLevel)
        #expect((comp?[AVVideoAllowFrameReorderingKey] as? Bool) == false)
        let bitRate = try? #require(comp?[AVVideoAverageBitRateKey] as? Int)
        #expect((bitRate ?? 0) > 1_000_000)   // biased high
    }

    // MARK: - probe

    @Test func probeReturnsDimensionsAndFps() async throws {
        let url = try await Self.makeVideo(frames: 12, fps: 30, size: CGSize(width: 320, height: 180), vfr: false)
        defer { try? FileManager.default.removeItem(at: url) }
        let (w, h, fps) = try await AVFoundationVideoEncoder().probe(url: url)
        #expect(w == 320)
        #expect(h == 180)
        #expect(abs(fps - 30) < 0.5)
    }

    @Test func probeRejectsVariableFrameRate() async throws {
        let url = try await Self.makeVideo(frames: 8, fps: 30, size: CGSize(width: 320, height: 180), vfr: true)
        defer { try? FileManager.default.removeItem(at: url) }
        await #expect(throws: VideoEncoderError.variableFrameRate) {
            _ = try await AVFoundationVideoEncoder().probe(url: url)
        }
    }

    @Test func probeNoVideoTrackThrows() async throws {
        // A real audio-only container: AVFoundation opens it fine and reports
        // zero video tracks → the .noVideoTrack branch (distinct from .corruptFile,
        // which fires when the container can't be opened at all).
        let url = try Self.makeAudioOnly()
        defer { try? FileManager.default.removeItem(at: url) }
        await #expect(throws: VideoEncoderError.noVideoTrack) {
            _ = try await AVFoundationVideoEncoder().probe(url: url)
        }
    }

    @Test func probeCorruptFileThrows() async throws {
        let url = try Self.makeGarbageMP4()
        defer { try? FileManager.default.removeItem(at: url) }
        // Garbage container → corruptFile (load throws) or noVideoTrack (loads, no track).
        // Either is an actionable VideoEncoderError; assert it throws one.
        await #expect(throws: VideoEncoderError.self) {
            _ = try await AVFoundationVideoEncoder().probe(url: url)
        }
    }

    // MARK: - sampleGrids

    @Test func sampleGridsStillReturnsOneGrid() async throws {
        let url = try Self.makePNG(size: CGSize(width: 200, height: 120))
        defer { try? FileManager.default.removeItem(at: url) }
        let grids = try await AVFoundationVideoEncoder().sampleGrids(url: url)
        #expect(grids.count == 1)
        #expect(grids[0].count == GridSampler.valueCount)   // 1728
        #expect(grids[0].allSatisfy { $0 >= 0 && $0 <= 255 })
    }

    /// A3: a video frame and a still of the SAME solid color must produce
    /// near-identical grids (frames and stills take the same sRGB color path).
    /// Gray (R=G=B) sidesteps BT.709↔sRGB matrix nuance; H.264 is lossy so a
    /// small tolerance is allowed.
    @Test func frameAndStillGridsMatchForSolidColor() async throws {
        let gray: UInt8 = 100
        let size = CGSize(width: 320, height: 180)
        // makeVideo's frame 0 fills gray = min(255, 100 + 0) = 100.
        let video = try await Self.makeVideo(frames: 1, fps: 30, size: size, vfr: false)
        let still = try Self.makeGrayPNG(gray: gray, size: size)
        defer { try? FileManager.default.removeItem(at: video); try? FileManager.default.removeItem(at: still) }

        let encoder = AVFoundationVideoEncoder()
        let vGrid = try await encoder.sampleGrids(url: video)[0]
        let sGrid = try await encoder.sampleGrids(url: still)[0]
        #expect(vGrid.count == sGrid.count)
        let maxDiff = zip(vGrid, sGrid).map { abs($0 - $1) }.max() ?? 0
        // ~11/255 is ordinary H.264 quantization on a single-frame clip. The guard
        // is against GROSS color-path divergence (wrong colorspace, full↔video range
        // luma offset), which would land 30–100+. 20 catches that with headroom.
        #expect(maxDiff < 20, "frame vs still grid max channel diff \(maxDiff) — color paths diverge")
    }

    @Test func sampleGridsVideoReturnsGridPerFrame() async throws {
        let url = try await Self.makeVideo(frames: 10, fps: 30, size: CGSize(width: 320, height: 180), vfr: false)
        defer { try? FileManager.default.removeItem(at: url) }
        let grids = try await AVFoundationVideoEncoder().sampleGrids(url: url)
        #expect(grids.count == 10)
        #expect(grids.allSatisfy { $0.count == GridSampler.valueCount })
    }

    // MARK: - encodeWithKeyframes (integration)

    @Test func encodeForcesKeyframesAndIsFaststart() async throws {
        let src = try await Self.makeVideo(frames: 12, fps: 30, size: CGSize(width: 320, height: 180), vfr: false)
        let out = Self.tmpURL(ext: "mp4")
        defer { try? FileManager.default.removeItem(at: src); try? FileManager.default.removeItem(at: out) }

        let encoder = AVFoundationVideoEncoder()
        // Derive timestamps from the PROBED fps so the encoder's frame mapping and
        // the test's expected indices use the same fps (no 30-vs-actual drift).
        let (_, _, fps) = try await encoder.probe(url: src)
        let srcFrameCount = try await encoder.sampleGrids(url: src).count
        let targetFrames = [0, 5, 9]
        let timestamps = targetFrames.map { Double($0) / fps }
        try await encoder.encodeWithKeyframes(input: src, output: out, timestamps: timestamps, fps: fps)
        #expect(FileManager.default.fileExists(atPath: out.path))

        // Frame-count integrity: decoded output frames must equal source frames.
        let outDecodedCount = try await encoder.sampleGrids(url: out).count
        #expect(outDecodedCount == srcFrameCount, "decoded output frames \(outDecodedCount) != source \(srcFrameCount)")

        // Keyframes located by PTS→frame-index (robust to how the compressed
        // reader batches samples), not by buffer position.
        let keyframes = try await Self.keyframeFrameIndices(url: out, fps: fps)
        for idx in forcedKeyframeFrameIndices(timestamps: timestamps, fps: fps) {
            #expect(keyframes.contains(idx), "frame \(idx) should be a keyframe; actual keyframes=\(keyframes.sorted()), decoded=\(outDecodedCount), fps=\(fps)")
        }

        // faststart: moov before mdat
        let order = try Self.topLevelBoxOrder(url: out)
        let moov = order.firstIndex(of: "moov")
        let mdat = order.firstIndex(of: "mdat")
        #expect(moov != nil && mdat != nil)
        if let m = moov, let d = mdat { #expect(m < d, "moov must precede mdat (faststart)") }
    }

    /// C1 regression: the encoder must place keyframes using the PASSED fps (the
    /// rate the timestamps were derived against), NOT the track's nominalFrameRate.
    /// Source is 30fps; we deploy timestamps derived at 15fps. Under the old bug
    /// (encoder re-derived fps=30) the keyframes would land on round(t*30) — the
    /// wrong frames. With the fix they land on round(t*15).
    @Test func encodeHonorsPassedFpsNotTrackRate() async throws {
        let src = try await Self.makeVideo(frames: 20, fps: 30, size: CGSize(width: 320, height: 180), vfr: false)
        let out = Self.tmpURL(ext: "mp4")
        defer { try? FileManager.default.removeItem(at: src); try? FileManager.default.removeItem(at: out) }

        let encoder = AVFoundationVideoEncoder()
        let requestedFps = 15.0
        let targetFrames = [0, 4, 9]
        let timestamps = targetFrames.map { Double($0) / requestedFps }   // 0, 0.266…, 0.6 at 15fps

        try await encoder.encodeWithKeyframes(input: src, output: out, timestamps: timestamps, fps: requestedFps)
        #expect(FileManager.default.fileExists(atPath: out.path))

        // Output is re-stamped at the requested fps → keyframes located against it.
        let keyframes = try await Self.keyframeFrameIndices(url: out, fps: requestedFps)
        for idx in forcedKeyframeFrameIndices(timestamps: timestamps, fps: requestedFps) {
            #expect(keyframes.contains(idx), "keyframe \(idx) (passed fps) missing; actual=\(keyframes.sorted())")
        }
    }

    @Test func cancellationCleansUp() async throws {
        let src = try await Self.makeVideo(frames: 120, fps: 30, size: CGSize(width: 480, height: 270), vfr: false)
        let out = Self.tmpURL(ext: "mp4")
        defer { try? FileManager.default.removeItem(at: src); try? FileManager.default.removeItem(at: out) }

        let encoder = AVFoundationVideoEncoder()
        let task = Task { try await encoder.encodeWithKeyframes(input: src, output: out, timestamps: [0], fps: 30) }
        task.cancel()
        await #expect(throws: VideoEncoderError.cancelled) { try await task.value }
        #expect(!FileManager.default.fileExists(atPath: out.path), "partial output must be removed on cancel")
    }

    // MARK: - Fixture helpers

    static func tmpURL(ext: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("kd-sec4-\(UUID().uuidString)")
            .appendingPathExtension(ext)
    }

    /// Write a solid-gray-ramp H.264 video. CFR: PTS = i/fps. VFR: uneven PTS.
    static func makeVideo(frames: Int, fps: Int32, size: CGSize, vfr: Bool) async throws -> URL {
        let url = tmpURL(ext: "mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height),
            ]
        )
        #expect(writer.canAdd(input))
        writer.add(input)
        #expect(writer.startWriting())
        writer.startSession(atSourceTime: .zero)

        // Uneven, strictly increasing PTS (seconds) for the VFR fixture.
        let vfrTimes: [Double] = [0, 0.10, 0.45, 0.50, 0.95, 1.0, 1.60, 1.65]

        for i in 0..<frames {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
            // Near-constant brightness (1/255 step/frame) → low motion, so the
            // encoder does NOT scene-detect keyframes on every frame; forced
            // keyframes then stand out against a sparse auto-keyframe baseline.
            let gray = UInt8(min(255, 100 + i))
            let pb = makePixelBuffer(size: size, gray: gray)
            let pts: CMTime
            if vfr {
                pts = CMTime(seconds: vfrTimes[min(i, vfrTimes.count - 1)], preferredTimescale: 600)
            } else {
                pts = CMTime(value: CMTimeValue(i), timescale: fps)
            }
            #expect(adaptor.append(pb, withPresentationTime: pts))
        }
        input.markAsFinished()
        await writer.finishWriting()
        #expect(writer.status == .completed, "fixture writer failed: \(writer.error?.localizedDescription ?? "?")")
        return url
    }

    static func makePixelBuffer(size: CGSize, gray: UInt8) -> CVPixelBuffer {
        var pb: CVPixelBuffer?
        let attrs: CFDictionary = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ] as CFDictionary
        CVPixelBufferCreate(kCFAllocatorDefault, Int(size.width), Int(size.height),
                            kCVPixelFormatType_32ARGB, attrs, &pb)
        let buffer = pb!
        CVPixelBufferLockBaseAddress(buffer, [])
        let ctx = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: Int(size.width), height: Int(size.height),
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        )!
        let v = Double(gray) / 255.0
        ctx.setFillColor(CGColor(red: v, green: v, blue: v, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: size))
        CVPixelBufferUnlockBaseAddress(buffer, [])
        return buffer
    }

    static func makePNG(size: CGSize) throws -> URL {
        let url = tmpURL(ext: "png")
        let ctx = CGContext(
            data: nil, width: Int(size.width), height: Int(size.height),
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: size))
        let img = ctx.makeImage()!
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw VideoEncoderError.corruptFile("could not create PNG destination")
        }
        CGImageDestinationAddImage(dest, img, nil)
        #expect(CGImageDestinationFinalize(dest))
        return url
    }

    static func makeGrayPNG(gray: UInt8, size: CGSize) throws -> URL {
        let url = tmpURL(ext: "png")
        let ctx = CGContext(
            data: nil, width: Int(size.width), height: Int(size.height),
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let v = Double(gray) / 255.0
        ctx.setFillColor(CGColor(red: v, green: v, blue: v, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: size))
        let img = ctx.makeImage()!
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw VideoEncoderError.corruptFile("could not create gray PNG destination")
        }
        CGImageDestinationAddImage(dest, img, nil)
        #expect(CGImageDestinationFinalize(dest))
        return url
    }

    static func makeGarbageMP4() throws -> URL {
        let url = tmpURL(ext: "mp4")
        var bytes = [UInt8]()
        for i in 0..<4096 { bytes.append(UInt8((i * 31 + 7) % 256)) }
        try Data(bytes).write(to: url)
        return url
    }

    /// A valid audio-only container (1 s of silence). AVFoundation opens it and
    /// reports zero video tracks → exercises the .noVideoTrack branch.
    static func makeAudioOnly() throws -> URL {
        let url = tmpURL(ext: "caf")
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let frameCount: AVAudioFrameCount = 44_100
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount   // zero-filled = silence
        try file.write(from: buffer)
        return url
    }

    /// Keyframe frame-indices of the encoded output, located by presentation time
    /// (frameIndex = round(pts * fps)). Reading compressed (outputSettings: nil)
    /// can yield sample buffers that don't map 1:1 to frame positions, so we key
    /// off PTS rather than buffer index. A sample is a keyframe unless it carries
    /// NotSync == true.
    static func keyframeFrameIndices(url: URL, fps: Double) async throws -> Set<Int> {
        let asset = AVURLAsset(url: url)
        let track = try await asset.loadTracks(withMediaType: .video)[0]
        let reader = try AVAssetReader(asset: asset)
        let out = AVAssetReaderTrackOutput(track: track, outputSettings: nil)   // compressed
        out.alwaysCopiesSampleData = false
        reader.add(out)
        reader.startReading()
        var keys: Set<Int> = []
        while let sb = out.copyNextSampleBuffer() {
            guard CMSampleBufferGetNumSamples(sb) > 0 else { continue }
            let pts = CMSampleBufferGetPresentationTimeStamp(sb)
            guard pts.isValid, !pts.isIndefinite else { continue }
            var isKey = true
            if let arr = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[CFString: Any]],
               let first = arr.first,
               let notSync = first[kCMSampleAttachmentKey_NotSync] as? Bool {
                isKey = !notSync
            }
            if isKey { keys.insert(Int((pts.seconds * fps).rounded())) }
        }
        return keys
    }

    /// Ordered list of top-level MP4 box types (for faststart verification).
    static func topLevelBoxOrder(url: URL) throws -> [String] {
        let data = try Data(contentsOf: url)
        var order: [String] = []
        var off = 0
        while off + 8 <= data.count {
            let size = Int(data[off]) << 24 | Int(data[off + 1]) << 16 | Int(data[off + 2]) << 8 | Int(data[off + 3])
            let type = String(bytes: data[off + 4 ..< off + 8], encoding: .ascii) ?? "????"
            order.append(type)
            if size == 1 {
                guard off + 16 <= data.count else { break }
                var large = 0
                for k in 0..<8 { large = large << 8 | Int(data[off + 8 + k]) }
                guard large >= 16 else { break }
                off += large
            } else if size >= 8 {
                off += size
            } else {
                break
            }
        }
        return order
    }
}
