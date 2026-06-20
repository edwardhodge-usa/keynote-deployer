import CoreGraphics

/// Downscales a `CGImage` (a decoded still, or a decoded video frame) to a fixed
/// 32×18 sRGB-normalized RGB grid and returns a flat `[Double]` in `0...255`,
/// row-major R,G,B per pixel. Used by both the stills path and the encoder's
/// frame sampler so cross-engine comparison happens in one color space (A3).
enum GridSampler {
    /// Grid width in cells.
    static let width = 32
    /// Grid height in cells.
    static let height = 18
    /// Channels emitted per cell (R,G,B — alpha skipped).
    static let channels = 3
    /// Flat output length: 32 × 18 × 3 = 1728.
    static let valueCount = width * height * channels

    /// Downscale a CGImage to a 32×18 RGB grid -> 1728 Doubles in 0...255.
    /// A3: draws the source into an explicit sRGB context before sampling so
    /// stills (often Display P3) and frames (sRGB) compare in one color space.
    static func sample(_ image: CGImage) -> [Double] {
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        // RGBA, alpha last, NOT premultiplied: reads raw R,G,B straight (no
        // alpha-scaling of the color channels) to mirror the Electron canvas
        // sampler. Drawing into an sRGB context converts a Display-P3 (or any
        // tagged) source into sRGB — this is amendment A3.
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: space,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            return [Double](repeating: 0, count: valueCount)
        }

        // .high so downscaling averages source pixels (a solid-color image must
        // yield a near-uniform grid rather than a single nearest-neighbor sample).
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let data = ctx.data else {
            return [Double](repeating: 0, count: valueCount)
        }
        let ptr = data.bindMemory(to: UInt8.self, capacity: bytesPerRow * height)

        var out = [Double]()
        out.reserveCapacity(valueCount)
        for y in 0..<height {
            let row = y * bytesPerRow
            for x in 0..<width {
                let p = row + x * bytesPerPixel
                out.append(Double(ptr[p]))     // R
                out.append(Double(ptr[p + 1])) // G
                out.append(Double(ptr[p + 2])) // B
            }
        }
        return out
    }
}
