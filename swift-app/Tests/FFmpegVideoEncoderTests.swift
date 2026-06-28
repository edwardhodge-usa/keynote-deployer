import Testing
import Foundation
@testable import KeynoteDeployer

/// Section 5 — FFmpegVideoEncoder. Offline: exercises the pure arg builders, the
/// A1 no-shell/inert-path security property, and the missing-binary error.
/// Does NOT require ffmpeg installed or any real video.
@Suite("Section 5 — FFmpegVideoEncoder")
struct FFmpegVideoEncoderTests {

    // MARK: Arg parity vs electron/videoDeckPipeline.ts

    @Test func probeArgsMatchElectron() {
        #expect(FFmpegVideoEncoder.probeArgs(input: "/tmp/in.mp4") == [
            "-v", "error", "-select_streams", "v:0",
            "-show_entries", "stream=width,height,r_frame_rate",
            "-of", "default=noprint_wrappers=1", "/tmp/in.mp4",
        ])
    }

    @Test func sampleArgsMatchElectron() {
        #expect(FFmpegVideoEncoder.sampleArgs(input: "/tmp/in.mp4") == [
            "-v", "error", "-i", "/tmp/in.mp4",
            "-vf", "scale=32:18",
            "-f", "rawvideo", "-pix_fmt", "rgb24", "-",
        ])
    }

    @Test func encodeArgsAreCrf16BoundedGopWithSlideKeyframes() {
        // CRF16 constant quality + bounded 2s GOP (-g 60) + forced per-slide keyframes.
        // force_key_frames CSV uses JS-number formatting → "0,2.5,5" (NOT "0.0,2.5,5.0").
        #expect(FFmpegVideoEncoder.encodeArgs(
            input: "/tmp/in.mp4", output: "/tmp/out.mp4",
            timestamps: [0.0, 2.5, 5.0]) == [
            "-y", "-i", "/tmp/in.mp4",
            "-c:v", "libx264", "-crf", "16", "-preset", "medium",
            "-pix_fmt", "yuv420p",
            "-bf", "0", "-g", "60",
            "-force_key_frames", "0,2.5,5",
            "-movflags", "+faststart", "-an",
            "/tmp/out.mp4",
        ])
    }

    @Test func encodeArgsForceKeyFramesCsvIsJsNumberFormatted() {
        // integers no decimal, 3-decimal fractionals strip trailing zeros
        let args = FFmpegVideoEncoder.encodeArgs(
            input: "i", output: "o", timestamps: [0, 1.234, 5.6, 12])
        let i = args.firstIndex(of: "-force_key_frames")!
        #expect(args[i + 1] == "0,1.234,5.6,12")
    }

    @Test func encodeArgsRespectsCustomCrf() {
        let args = FFmpegVideoEncoder.encodeArgs(input: "i", output: "o", timestamps: [0], crf: 23)
        let i = args.firstIndex(of: "-crf")!
        #expect(args[i + 1] == "23")
    }

    // MARK: A1 — no shell, injection-laden path stays one inert argument

    @Test func injectionFilenameIsOneInertArgument() {
        let evil = "a\"; rm -rf ~ #.mp4"
        for args in [
            FFmpegVideoEncoder.sampleArgs(input: evil),
            FFmpegVideoEncoder.probeArgs(input: evil),
            FFmpegVideoEncoder.encodeArgs(input: evil, output: evil, timestamps: [0]),
        ] {
            // the payload appears verbatim as discrete element(s), never escaped/spliced
            #expect(args.contains(evil))
            // nothing got merged into a single shell command string
            #expect(!args.contains { $0.contains("/bin/sh") })
            #expect(!args.contains { $0.contains("rm -rf ~ #.mp4 ") })   // no concatenation
        }
    }

    // MARK: Missing binary → clear, actionable (Homebrew) error

    @Test func missingFfprobeThrowsActionable() async {
        let enc = FFmpegVideoEncoder(ffmpegPath: "/nonexistent/ffmpeg", ffprobePath: "/nonexistent/ffprobe")
        await #expect {
            _ = try await enc.probe(url: URL(fileURLWithPath: "/tmp/x.mp4"))
        } throws: { error in
            let msg = (error as? VideoEncoderError)?.errorDescription ?? ""
            return msg.contains("ffprobe") && msg.lowercased().contains("brew install ffmpeg")
        }
    }

    @Test func missingFfmpegThrowsActionable() async {
        let enc = FFmpegVideoEncoder(ffmpegPath: "/nonexistent/ffmpeg", ffprobePath: "/nonexistent/ffprobe")
        await #expect {
            _ = try await enc.sampleGrids(url: URL(fileURLWithPath: "/tmp/x.mp4"))
        } throws: { error in
            let msg = (error as? VideoEncoderError)?.errorDescription ?? ""
            return msg.contains("ffmpeg") && msg.lowercased().contains("brew install ffmpeg")
        }
    }

    @Test func missingFfmpegOnEncodeThrowsActionable() async {
        let enc = FFmpegVideoEncoder(ffmpegPath: "/nonexistent/ffmpeg", ffprobePath: "/nonexistent/ffprobe")
        await #expect {
            try await enc.encodeWithKeyframes(
                input: URL(fileURLWithPath: "/tmp/x.mp4"),
                output: URL(fileURLWithPath: "/tmp/y.mp4"), timestamps: [0], fps: 30)
        } throws: { error in
            let msg = (error as? VideoEncoderError)?.errorDescription ?? ""
            return msg.contains("ffmpeg") && msg.lowercased().contains("brew install ffmpeg")
        }
    }

    // MARK: Conforms to the Section-04 protocol

    @Test func conformsToVideoEncoder() {
        func requireEncoder(_: some VideoEncoder) {}
        requireEncoder(FFmpegVideoEncoder())
        #expect(true)
    }
}
