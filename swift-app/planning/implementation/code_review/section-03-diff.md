diff --git a/swift-app/Sources/Services/GridSampler.swift b/swift-app/Sources/Services/GridSampler.swift
new file mode 100644
index 0000000..8f2003b
--- /dev/null
+++ b/swift-app/Sources/Services/GridSampler.swift
@@ -0,0 +1,105 @@
+import Foundation
+import CoreGraphics
+
+/// Bridges decoded GIF frames to the slide-detection algorithm.
+///
+/// Converts each `CGImage` into a fixed-length RGB sample vector, computes the
+/// mean-absolute-difference between two vectors, and streams the adjacent-frame
+/// diff array that `SlideDetector` (section 04) consumes.
+///
+/// Memory discipline (the load-bearing reason this is a streaming function, not a
+/// `[CGImage] -> [Double]` map): the Electron path crashed mobile Safari by
+/// decoding all frames to RGBA at once (~2.5 GB for 963 frames). `frameDiffs`
+/// holds at most ONE decoded image plus the PREVIOUS sample vector at any moment —
+/// there is deliberately no full-array retention API.
+///
+/// Grid choice: 1000 sample points ⇒ `gridSize = ceil(sqrt(1000)) = 32`, sampled
+/// on a 32×32 grid, RGB only (alpha dropped) ⇒ vector length `32*32*3 = 3072`.
+/// (The Electron detection sampler used a comparable down-scaled sample canvas;
+/// the Swift port follows claude-plan.md Task 3, which specifies 32×32 / 1000
+/// points. Detection output is validated downstream against ground-truth stills,
+/// not against Electron's raw diff values, so the grid size need not match Electron
+/// bit-for-bit.)
+enum GridSampler {
+    static let samplePoints = 1000
+    static let gridSize = 32     // ceil(sqrt(1000))
+
+    /// Sample RGB at the grid points → flat `[Double]` of length `gridSize*gridSize*3`.
+    /// The source image is resampled to a `gridSize × gridSize` bitmap; alpha is dropped.
+    /// Channel values are raw 0–255 byte magnitudes (the diff math + test fixtures assume
+    /// this range — do NOT normalize to 0–1 without adjusting `meanAbs` expectations).
+    static func sample(_ image: CGImage) -> [Double] {
+        let g = gridSize
+        let bytesPerRow = g * 4
+        var buffer = [UInt8](repeating: 0, count: g * bytesPerRow)
+        let colorSpace = CGColorSpaceCreateDeviceRGB()
+        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue   // R,G,B,A byte order
+
+        buffer.withUnsafeMutableBytes { raw in
+            guard let ctx = CGContext(
+                data: raw.baseAddress,
+                width: g, height: g,
+                bitsPerComponent: 8,
+                bytesPerRow: bytesPerRow,
+                space: colorSpace,
+                bitmapInfo: bitmapInfo
+            ) else { return }
+            // Scales any source size down to the grid.
+            ctx.draw(image, in: CGRect(x: 0, y: 0, width: g, height: g))
+        }
+
+        var out = [Double]()
+        out.reserveCapacity(g * g * 3)
+        for pixel in 0..<(g * g) {
+            let o = pixel * 4
+            out.append(Double(buffer[o]))       // R
+            out.append(Double(buffer[o + 1]))   // G
+            out.append(Double(buffer[o + 2]))   // B
+            // skip buffer[o + 3] (alpha)
+        }
+        return out
+    }
+
+    /// Mean absolute difference between two vectors; `0` if either is empty
+    /// (the empty→0 contract guards divide-by-zero). Vectors are equal length by
+    /// construction (both come from `sample`); `min` is defensive belt-and-braces.
+    static func meanAbs(_ a: [Double], _ b: [Double]) -> Double {
+        let count = min(a.count, b.count)
+        guard count > 0 else { return 0 }
+        var sum = 0.0
+        for i in 0..<count { sum += abs(a[i] - b[i]) }
+        return sum / Double(count)
+    }
+
+    /// Streams frames forward from `source`, keeping only the previous sample vector.
+    /// `diffs[i] = meanAbs(sample(frame[i]), sample(frame[i-1]))`; `diffs[0] = 0`.
+    /// Result length == `source.frameCount`.
+    ///
+    /// Returns `[]` for a 0/1-frame source — a DEFENSIVE path: `GifFrameSource.init`
+    /// already hard-throws `.tooFewFrames` below 2 frames, so this branch is
+    /// unreachable through the public initializer (kept as belt-and-braces only).
+    ///
+    /// Cancellation: calls `try Task.checkCancellation()` at entry and between frames,
+    /// so an enclosing cancelled `Task` surfaces a `CancellationError`. A mid-stream
+    /// decode failure propagates as `GifFrameSource.nextFrame()` throws (data
+    /// corruption, NOT end-of-stream) rather than silently truncating the deck.
+    static func frameDiffs(_ source: GifFrameSource) throws -> [Double] {
+        try Task.checkCancellation()
+        let n = source.frameCount
+        guard n >= 2 else { return [] }
+
+        var diffs = [Double](repeating: 0, count: n)
+        guard let first = try source.nextFrame() else { return [] }
+        var previous = sample(first)   // `first` released at end of statement
+
+        var index = 1
+        while let frame = try source.nextFrame() {
+            try Task.checkCancellation()
+            let current = sample(frame)
+            diffs[index] = meanAbs(current, previous)
+            previous = current
+            index += 1
+        }
+        return diffs
+    }
+}
diff --git a/swift-app/Tests/GridSamplerTests.swift b/swift-app/Tests/GridSamplerTests.swift
new file mode 100644
index 0000000..a56e6fe
--- /dev/null
+++ b/swift-app/Tests/GridSamplerTests.swift
@@ -0,0 +1,124 @@
+import Testing
+import Foundation
+import ImageIO
+import CoreGraphics
+import UniformTypeIdentifiers
+@testable import KeynoteDeployer
+
+@Suite("GridSampler")
+struct GridSamplerTests {
+
+    // MARK: - Synthetic helpers (offline, mirror GifFrameSourceTests)
+
+    /// Solid-color CGImage (any size — `sample` resamples to the grid).
+    private static func solidImage(size: Int, gray: UInt8) -> CGImage {
+        let cs = CGColorSpaceCreateDeviceRGB()
+        let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
+                            bytesPerRow: size * 4, space: cs,
+                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
+        let g = CGFloat(gray) / 255.0
+        ctx.setFillColor(CGColor(red: g, green: g, blue: g, alpha: 1))
+        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
+        return ctx.makeImage()!
+    }
+
+    /// Synthetic N-frame GIF whose frames differ frame-to-frame (varying gray).
+    private static func makeGIF(frameCount: Int, size: Int = 16) -> URL {
+        let url = FileManager.default.temporaryDirectory
+            .appendingPathComponent("gs-\(UUID().uuidString).gif")
+        let dest = CGImageDestinationCreateWithURL(
+            url as CFURL, UTType.gif.identifier as CFString, frameCount, nil)!
+        CGImageDestinationSetProperties(
+            dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
+        for i in 0..<frameCount {
+            let img = solidImage(size: size, gray: UInt8((i * 37) % 256))
+            CGImageDestinationAddImage(
+                dest, img,
+                [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.05]] as CFDictionary)
+        }
+        #expect(CGImageDestinationFinalize(dest))
+        return url
+    }
+
+    // MARK: - meanAbs
+
+    @Test("meanAbs of two empty vectors is exactly 0 (no divide-by-zero)")
+    func meanAbsEmptyIsZero() {
+        #expect(GridSampler.meanAbs([], []) == 0)
+    }
+
+    @Test("meanAbs matches a hand-computed value")
+    func meanAbsHandComputed() {
+        // (|0-0| + |10-0| + |20-0|) / 3 == 10
+        #expect(GridSampler.meanAbs([0, 10, 20], [0, 0, 0]) == 10)
+    }
+
+    @Test("meanAbs of identical vectors is 0")
+    func meanAbsIdenticalIsZero() {
+        let v: [Double] = [3, 17, 200, 255]
+        #expect(GridSampler.meanAbs(v, v) == 0)
+    }
+
+    // MARK: - sample
+
+    @Test("sample returns a length 32*32*3 == 3072 RGB vector")
+    func sampleVectorLength() {
+        let img = Self.solidImage(size: 64, gray: 128)
+        let v = GridSampler.sample(img)
+        #expect(v.count == GridSampler.gridSize * GridSampler.gridSize * 3)
+        #expect(v.count == 3072)
+    }
+
+    @Test("sample of a solid color yields internally uniform channels")
+    func sampleSolidColorIsUniform() {
+        // A solid-color image resamples to a uniform grid. We assert INTERNAL
+        // uniformity (all samples equal each other) rather than a specific value:
+        // CGColor → DeviceRGB-premultiplied color-matching/gamma can shift the
+        // absolute magnitude, but a flat input must still produce a flat vector.
+        let v = GridSampler.sample(Self.solidImage(size: 32, gray: 200))
+        let lo = v.min() ?? 0, hi = v.max() ?? 0
+        #expect(hi - lo <= 1)        // uniform to within rounding
+        #expect(hi > 0)              // and non-trivially populated (not all zero)
+    }
+
+    // MARK: - frameDiffs
+
+    @Test("frameDiffs returns length == frameCount with diffs[0] == 0")
+    func frameDiffsLengthAndFirstIsZero() throws {
+        let url = Self.makeGIF(frameCount: 5)
+        defer { try? FileManager.default.removeItem(at: url) }
+        let src = try GifFrameSource(gifURL: url)
+        let diffs = try GridSampler.frameDiffs(src)
+        #expect(diffs.count == 5)
+        #expect(diffs[0] == 0)
+        // Frames vary (gray steps) ⇒ subsequent diffs are non-zero.
+        #expect(diffs.dropFirst().allSatisfy { $0 > 0 })
+    }
+
+    @Test("frameDiffs handles the 2-frame minimum")
+    func frameDiffsTwoFrameMinimum() throws {
+        // Smallest source the public init permits (it hard-throws below 2 frames,
+        // so the `frameCount < 2 -> []` guard in frameDiffs is unreachable here and
+        // is defensive only — see GridSampler.frameDiffs docs).
+        let url = Self.makeGIF(frameCount: 2)
+        defer { try? FileManager.default.removeItem(at: url) }
+        let src = try GifFrameSource(gifURL: url)
+        let diffs = try GridSampler.frameDiffs(src)
+        #expect(diffs.count == 2)
+        #expect(diffs[0] == 0)
+    }
+
+    @Test("frameDiffs propagates CancellationError when its Task is cancelled")
+    func frameDiffsPropagatesCancellation() async throws {
+        let url = Self.makeGIF(frameCount: 40)
+        defer { try? FileManager.default.removeItem(at: url) }
+        let task = Task { () throws -> [Double] in
+            let src = try GifFrameSource(gifURL: url)
+            return try GridSampler.frameDiffs(src)
+        }
+        task.cancel()   // sets the flag synchronously; entry checkCancellation throws
+        await #expect(throws: CancellationError.self) {
+            _ = try await task.value
+        }
+    }
+}
