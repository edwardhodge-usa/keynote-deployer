import Foundation

// Thin CLI wrapper around SeedHarness with the live AVFoundation encoder, so the
// harness can run on a real deck folder from the terminal:
//   kd-seed-harness <deck-video> <stills-dir> <output-dir>
// The stills dir is scanned for image files (jpg/jpeg/png), natural-sorted by the
// harness. Writes <slug>-seed.json + <slug>-seed.html (+ thumbnails) to output-dir.

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write(Data((msg + "\n").utf8))
    exit(1)
}

let args = CommandLine.arguments
guard args.count == 4 else {
    fail("usage: kd-seed-harness <deck-video> <stills-dir> <output-dir>")
}

let videoURL = URL(fileURLWithPath: args[1])
let stillsDir = URL(fileURLWithPath: args[2])
let outputDir = URL(fileURLWithPath: args[3])

let imageExts: Set<String> = ["jpg", "jpeg", "png"]
let stillURLs: [URL]
do {
    stillURLs = try FileManager.default
        .contentsOfDirectory(at: stillsDir, includingPropertiesForKeys: nil)
        .filter { imageExts.contains($0.pathExtension.lowercased()) }
} catch {
    fail("could not read stills dir: \(error.localizedDescription)")
}
guard !stillURLs.isEmpty else { fail("no image stills found in \(stillsDir.path)") }

let input = SeedHarnessInput(videoURL: videoURL, stillURLs: stillURLs, outputDir: outputDir)
let encoder = AVFoundationVideoEncoder()

do {
    let report = try await SeedHarness.run(input, encoder: encoder)
    try report.writeJSON(to: outputDir)
    try report.writeVisualReport(to: outputDir)
    let flag = report.markCount == report.slideCount ? "OK" : "MISMATCH"
    print("seed report → \(outputDir.path)")
    print("slides \(report.slideCount) · marks \(report.markCount) · count \(flag)")
} catch {
    fail("harness failed: \(error.localizedDescription)")
}
