// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2026 Doug C. Hardester

import CoreGraphics
import ImageIO
import Foundation
import Savage
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// Premultiplied sRGB pixels, 8 bits a channel, top row first.
struct Bitmap {
    let width: Int
    let height: Int
    var bytes: [UInt8]

    func pixel(_ x: Int, _ y: Int) -> (r: Double, g: Double, b: Double, a: Double) {
        let i = (y * width + x) * 4
        return (Double(bytes[i]) / 255, Double(bytes[i + 1]) / 255, Double(bytes[i + 2]) / 255, Double(bytes[i + 3]) / 255)
    }

    /// How far apart two pictures of the same size are: the mean difference
    /// per channel (of 255), the share of pixels off by more than
    /// `threshold` in some channel, and the worst difference.
    func difference(from other: Bitmap, threshold: Int = 16) -> (mean: Double, over: Double, max: Int) {
        precondition(width == other.width && height == other.height)
        var total = 0, over = 0, worst = 0
        for i in stride(from: 0, to: bytes.count, by: 4) {
            var pixelWorst = 0
            for c in 0..<4 {
                let d = abs(Int(bytes[i + c]) - Int(other.bytes[i + c]))
                total += d
                pixelWorst = max(pixelWorst, d)
            }
            if pixelWorst > threshold { over += 1 }
            worst = max(worst, pixelWorst)
        }
        return (Double(total) / Double(bytes.count), Double(over) / Double(width * height), worst)
    }

    /// The share of pixels where the pictures really differ: some channel
    /// is more than `threshold` outside the range of that channel among the
    /// other picture's pixels within `radius`. Checked both ways.
    ///
    /// An edge antialiased a little differently, or placed a fraction of a
    /// pixel apart, stays within its neighbors' range and doesn't count. A
    /// wrong color, a missing shape or a shape out of place does.
    func mismatch(from other: Bitmap, radius: Int = 1, threshold: Int = 16) -> Double {
        precondition(width == other.width && height == other.height)
        func unmatched(_ a: [UInt8], _ b: [UInt8]) -> Int {
            a.withUnsafeBufferPointer { a in
                b.withUnsafeBufferPointer { b in
                    var count = 0
                    for y in 0..<height {
                        for x in 0..<width {
                            let i = (y * width + x) * 4
                            var low = (255, 255, 255, 255), high = (0, 0, 0, 0)
                            for ny in max(0, y - radius)...min(height - 1, y + radius) {
                                for nx in max(0, x - radius)...min(width - 1, x + radius) {
                                    let j = (ny * width + nx) * 4
                                    low = (min(low.0, Int(b[j])), min(low.1, Int(b[j + 1])), min(low.2, Int(b[j + 2])), min(low.3, Int(b[j + 3])))
                                    high = (max(high.0, Int(b[j])), max(high.1, Int(b[j + 1])), max(high.2, Int(b[j + 2])), max(high.3, Int(b[j + 3])))
                                }
                            }
                            func outside(_ v: UInt8, _ lo: Int, _ hi: Int) -> Bool { Int(v) < lo - threshold || Int(v) > hi + threshold }
                            if outside(a[i], low.0, high.0) || outside(a[i + 1], low.1, high.1) || outside(a[i + 2], low.2, high.2) || outside(a[i + 3], low.3, high.3) {
                                count += 1
                            }
                        }
                    }
                    return count
                }
            }
        }
        return Double(max(unmatched(bytes, other.bytes), unmatched(other.bytes, bytes))) / Double(width * height)
    }

    /// Where two pictures differ: black where they match, brighter where
    /// they don't (the largest channel difference, scaled up four times).
    func differenceMap(from other: Bitmap) -> Bitmap {
        var out = [UInt8](repeating: 255, count: bytes.count)
        for i in stride(from: 0, to: bytes.count, by: 4) {
            var worst = 0
            for c in 0..<4 { worst = max(worst, abs(Int(bytes[i + c]) - Int(other.bytes[i + c]))) }
            let v = UInt8(min(255, worst * 4))
            out[i] = v; out[i + 1] = v; out[i + 2] = v
        }
        return Bitmap(width: width, height: height, bytes: out)
    }

    /// The picture as PNG data.
    func png() throws -> Data {
        var copy = bytes
        let data = NSMutableData()
        guard let provider = CGDataProvider(data: Data(bytes: &copy, count: copy.count) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
              let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        return data as Data
    }
}

enum Rendering {
    static func context(width: Int, height: Int) -> CGContext {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    }

    static func bitmap(of context: CGContext) -> Bitmap {
        let count = context.bytesPerRow * context.height
        let pointer = context.data!.bindMemory(to: UInt8.self, capacity: count)
        return Bitmap(width: context.width, height: context.height, bytes: Array(UnsafeBufferPointer(start: pointer, count: count)))
    }

    static func bitmap(_ image: CGImage) -> Bitmap {
        let context = context(width: image.width, height: image.height)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return bitmap(of: context)
    }

    /// `draw` through a CanvasPainter in a SwiftUI Canvas, rendered offscreen
    /// by ImageRenderer.
    @MainActor
    static func canvas(size: CGSize, scale: CGFloat = 1, _ draw: @escaping (inout CanvasPainter) -> Void) -> Bitmap? {
        let view = Canvas { context, _ in
            var painter = CanvasPainter(context: context)
            draw(&painter)
        }
        .frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        return renderer.cgImage.map(bitmap)
    }

    /// `draw` written as an SVG.
    static func svg(size: CGSize, _ draw: (inout SVGPainter) -> Void) -> String {
        let document = SVGDocument(size: size)
        document.draw(draw)
        return document.svgString
    }

    #if canImport(AppKit)
    /// An SVG drawn by macOS's own SVG renderer (NSImage), at a pixel size.
    @MainActor
    static func rasterize(svg: String, width: Int, height: Int) -> Bitmap? {
        guard let image = NSImage(data: Data(svg.utf8)) else { return nil }
        let context = context(width: width, height: height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        image.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        return bitmap(of: context)
    }
    #endif
}
