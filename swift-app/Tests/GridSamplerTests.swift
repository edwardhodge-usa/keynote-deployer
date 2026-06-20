import Testing
import CoreGraphics
@testable import KeynoteDeployer

@Suite("Section 2 — GridSampler shape + sRGB normalization")
struct GridSamplerTests {

    /// Build a solid-color `CGImage` of the given size in the given color space.
    /// `comps` are raw channel bytes (0...255) interpreted in `space`.
    private func solidImage(
        r: UInt8, g: UInt8, b: UInt8,
        space: CGColorSpace,
        width: Int = 64, height: Int = 36
    ) -> CGImage {
        let bitsPerComponent = 8
        let bytesPerRow = width * 4
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: bitsPerComponent, bytesPerRow: bytesPerRow,
            space: space, bitmapInfo: info
        )!
        ctx.setFillColor(
            red: CGFloat(r) / 255, green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255, alpha: 1
        )
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    private var sRGB: CGColorSpace { CGColorSpace(name: CGColorSpace.sRGB)! }
    private var p3: CGColorSpace { CGColorSpace(name: CGColorSpace.displayP3)! }

    @Test func sampleReturnsExactly1728Values() {
        let img = solidImage(r: 10, g: 20, b: 30, space: sRGB)
        let grid = GridSampler.sample(img)
        #expect(grid.count == GridSampler.valueCount)
        #expect(grid.count == 1728)
    }

    @Test func allValuesInRange() {
        let img = solidImage(r: 200, g: 100, b: 50, space: sRGB)
        let grid = GridSampler.sample(img)
        #expect(grid.allSatisfy { $0 >= 0 && $0 <= 255 })
    }

    @Test func solidColorYieldsNearUniformGrid() {
        // Pure red in sRGB -> every cell ~ (255, 0, 0).
        let img = solidImage(r: 255, g: 0, b: 0, space: sRGB)
        let grid = GridSampler.sample(img)
        // Row-major R,G,B triples.
        for i in stride(from: 0, to: grid.count, by: 3) {
            #expect(abs(grid[i] - 255) <= 2)      // R
            #expect(abs(grid[i + 1] - 0) <= 2)    // G
            #expect(abs(grid[i + 2] - 0) <= 2)    // B
        }
    }

    @Test func a3NeutralGrayIsColorSpaceStable() {
        // A3: a still (often Display P3) and a frame (sRGB) of the SAME visual
        // color must produce near-equal grids after sRGB normalization. Neutral
        // gray shares the gray axis + D65 white point across sRGB and P3, so a
        // correct sRGB normalization yields near-equal grids; per-channel diffs
        // must stay within a small tolerance.
        let gray: UInt8 = 128
        let sRGBGrid = GridSampler.sample(solidImage(r: gray, g: gray, b: gray, space: sRGB))
        let p3Grid = GridSampler.sample(solidImage(r: gray, g: gray, b: gray, space: p3))
        #expect(sRGBGrid.count == p3Grid.count)
        for i in 0..<sRGBGrid.count {
            #expect(abs(sRGBGrid[i] - p3Grid[i]) <= 3)
        }
    }
}
