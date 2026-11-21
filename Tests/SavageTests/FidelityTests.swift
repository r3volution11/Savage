// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2026 Doug C. Hardester

#if canImport(AppKit)
import Foundation
import SwiftUI
import Testing
@testable import Savage

/// The fidelity test's drawings, one per feature.
enum FidelityDrawings {
    struct Drawing: CustomTestStringConvertible, Sendable {
        let name: String
        let draw: @Sendable (inout CanvasPainter) -> Void
        let svg: @Sendable (inout SVGPainter) -> Void
        var testDescription: String { name }

        init(_ name: String, _ body: @escaping @Sendable (inout CanvasPainter) -> Void, _ svg: @escaping @Sendable (inout SVGPainter) -> Void) {
            self.name = name
            self.draw = body
            self.svg = svg
        }
    }

    static let size = CGSize(width: 300, height: 200)
    static let warm = PaintColor(hex: 0xFF8C42), cool = PaintColor(hex: 0x2E4057), leaf = PaintColor(hex: 0x66A182)

    // MARK: Drawings, one per feature

    static func shapes<P: Painter>(_ p: inout P) {
        p.fill(Path(CGRect(x: 10, y: 10, width: 120, height: 80)), with: .color(cool))
        var ring = Path(ellipseIn: CGRect(x: 30, y: 20, width: 60, height: 60))
        ring.addEllipse(in: CGRect(x: 45, y: 35, width: 30, height: 30))
        p.fill(ring, with: .color(warm), style: FillStyle(eoFill: true))
        p.fill(Path(ellipseIn: CGRect(x: 70, y: 40, width: 50, height: 50)), with: .color(leaf.opacity(0.6)))
        var zigzag = Path()
        zigzag.move(to: CGPoint(x: 150, y: 80))
        for i in 1...6 { zigzag.addLine(to: CGPoint(x: 150 + CGFloat(i) * 22, y: i % 2 == 0 ? 80 : 30)) }
        p.stroke(zigzag, with: .color(.white), style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
        var bevel = zigzag
        bevel = bevel.offsetBy(dx: 0, dy: 50)
        p.stroke(bevel, with: .color(warm), style: StrokeStyle(lineWidth: 6, lineCap: .square, lineJoin: .bevel))
        p.stroke(zigzag.offsetBy(dx: 0, dy: 100), with: .color(leaf), style: StrokeStyle(lineWidth: 5, lineJoin: .miter, miterLimit: 4))
        // Dashes on straight lines: along curves, renderers measure length a
        // little differently, and the dashes drift.
        var line = Path()
        line.move(to: CGPoint(x: 10, y: 120))
        line.addLine(to: CGPoint(x: 80, y: 150))
        line.addLine(to: CGPoint(x: 140, y: 120))
        p.stroke(line, with: .color(.white), style: StrokeStyle(lineWidth: 3, dash: [10, 6], dashPhase: 3))
        var quad = Path()
        quad.move(to: CGPoint(x: 10, y: 190))
        quad.addQuadCurve(to: CGPoint(x: 140, y: 190), control: CGPoint(x: 75, y: 130))
        p.stroke(quad, with: .color(cool.mix(with: .white, by: 0.5)), lineWidth: 2)
    }

    static func gradients<P: Painter>(_ p: inout P) {
        p.fill(Path(CGRect(x: 0, y: 0, width: 300, height: 200)),
               with: .linearGradient(PaintGradient(colors: [cool, warm, leaf]), startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 300, y: 200)))
        p.fill(Path(ellipseIn: CGRect(x: 20, y: 20, width: 120, height: 120)),
               with: .radialGradient(PaintGradient(stops: [.init(color: .white, location: 0), .init(color: warm.opacity(0.5), location: 0.6), .init(color: warm.opacity(0), location: 1)]),
                                     center: CGPoint(x: 80, y: 80), startRadius: 15, endRadius: 60))
        p.fill(Path(CGRect(x: 160, y: 20, width: 120, height: 60)),
               with: .linearGradient(PaintGradient(colors: [PaintColor.black.opacity(0.8), PaintColor.black.opacity(0)]), startPoint: CGPoint(x: 160, y: 0), endPoint: CGPoint(x: 280, y: 0)))
        // Past its ends, a gradient keeps its end colors.
        p.fill(Path(CGRect(x: 160, y: 100, width: 120, height: 80)),
               with: .linearGradient(PaintGradient(colors: [.white, cool]), startPoint: CGPoint(x: 200, y: 0), endPoint: CGPoint(x: 240, y: 0)))
        var arc = Path()
        arc.addArc(center: CGPoint(x: 80, y: 160), radius: 30, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
        p.stroke(arc, with: .linearGradient(PaintGradient(colors: [.white, leaf]), startPoint: CGPoint(x: 50, y: 0), endPoint: CGPoint(x: 110, y: 0)), lineWidth: 8)
    }

    static func clipsAndTransforms<P: Painter>(_ p: inout P) {
        var clipped = p
        clipped.clip(to: Path(ellipseIn: CGRect(x: 10, y: 10, width: 140, height: 140)))
        clipped.fill(Path(CGRect(x: 0, y: 0, width: 300, height: 200)), with: .color(cool))
        clipped.clip(to: Path(CGRect(x: 0, y: 0, width: 80, height: 200)))
        clipped.fill(Path(CGRect(x: 0, y: 0, width: 300, height: 200)), with: .color(warm))
        var turned = p
        turned.translateBy(x: 220, y: 60)
        turned.rotate(by: .degrees(30))
        turned.scaleBy(x: 1.5, y: 0.75)
        turned.fill(Path(roundedRect: CGRect(x: -30, y: -30, width: 60, height: 60), cornerRadius: 10), with: .color(leaf))
        turned.stroke(Path(CGRect(x: -30, y: -30, width: 60, height: 60)), with: .color(.white), lineWidth: 2)
        var skewed = p
        skewed.concatenate(CGAffineTransform(a: 1, b: 0, c: 0.4, d: 1, tx: 150, ty: 130))
        skewed.clip(to: Path(CGRect(x: 0, y: 0, width: 100, height: 60)))
        skewed.fill(Path(ellipseIn: CGRect(x: 20, y: -20, width: 100, height: 100)),
                    with: .radialGradient(PaintGradient(colors: [.white, warm]), center: CGPoint(x: 70, y: 30), startRadius: 0, endRadius: 50))
        // A drawing in unit coordinates, scaled up.
        var unit = p
        unit.translateBy(x: 10, y: 160)
        unit.scaleBy(x: 120, y: 30)
        var wave = Path()
        wave.move(to: CGPoint(x: 0, y: 0.5))
        wave.addCurve(to: CGPoint(x: 1, y: 0.5), control1: CGPoint(x: 0.33, y: -0.4), control2: CGPoint(x: 0.66, y: 1.4))
        unit.stroke(wave, with: .color(.white), lineWidth: 0.04)
    }

    static func layers<P: Painter>(_ p: inout P) {
        p.fill(Path(CGRect(x: 0, y: 0, width: 300, height: 200)), with: .color(cool))
        // Opacity over overlapping shapes, with cut-outs.
        p.drawLayer(LayerStyle(opacity: 0.6, cutouts: [.init(path: Path(ellipseIn: CGRect(x: 40, y: 40, width: 30, height: 30))),
                                                       .init(path: Path(CGRect(x: 90, y: 20, width: 20, height: 80)), opacity: 0.5)])) { l in
            l.fill(Path(CGRect(x: 10, y: 10, width: 100, height: 100)), with: .color(warm))
            l.fill(Path(ellipseIn: CGRect(x: 50, y: 50, width: 80, height: 80)), with: .color(leaf))
        }
        // A fade over the whole picture, and a wash.
        let all = CGRect(x: 0, y: 0, width: 300, height: 200)
        p.drawLayer(LayerStyle(wash: .init(color: PaintColor.white.opacity(0.3), rect: all),
                               fades: [.init(rect: all, paint: .linearGradient(PaintGradient(colors: [.black, .black.opacity(0)]),
                                                                               startPoint: CGPoint(x: 150, y: 0), endPoint: CGPoint(x: 290, y: 0)))])) { l in
            l.fill(Path(ellipseIn: CGRect(x: 140, y: 10, width: 150, height: 90)), with: .color(warm))
            l.fill(Path(ellipseIn: CGRect(x: 180, y: 30, width: 60, height: 50)),
                   with: .radialGradient(PaintGradient(colors: [leaf, cool]), center: CGPoint(x: 210, y: 55), startRadius: 0, endRadius: 30))
        }
        // A wash and a fade over part of it: drawn twice in the SVG.
        let box = CGRect(x: 150, y: 120, width: 140, height: 70)
        p.drawLayer(LayerStyle(opacity: 0.9, wash: .init(color: leaf.opacity(0.5), rect: box),
                               fades: [.init(rect: box, paint: .linearGradient(PaintGradient(colors: [.black, .black.opacity(0.2)]),
                                                                               startPoint: CGPoint(x: 0, y: 120), endPoint: CGPoint(x: 0, y: 190)))])) { l in
            l.fill(Path(CGRect(x: 120, y: 100, width: 170, height: 95)), with: .color(warm))
            l.fill(Path(ellipseIn: CGRect(x: 170, y: 130, width: 40, height: 40)), with: .color(.white))
        }
        // Layers in layers.
        p.drawLayer(LayerStyle(opacity: 0.8)) { outer in
            outer.fill(Path(CGRect(x: 10, y: 130, width: 120, height: 60)), with: .color(.white))
            outer.drawLayer(LayerStyle(fades: [.init(rect: CGRect(x: 10, y: 130, width: 120, height: 60), paint: .color(PaintColor.black.opacity(0.5)))])) { inner in
                inner.fill(Path(ellipseIn: CGRect(x: 30, y: 135, width: 80, height: 50)), with: .color(warm))
            }
        }
    }

    static let all: [Drawing] = [
        Drawing("fills and strokes", { shapes(&$0) }, { shapes(&$0) }),
        Drawing("gradients", { gradients(&$0) }, { gradients(&$0) }),
        Drawing("clips and transforms", { clipsAndTransforms(&$0) }, { clipsAndTransforms(&$0) }),
        Drawing("layers", { layers(&$0) }, { layers(&$0) }),
    ]
}

/// The SVG against the Canvas: one drawing, rendered by SwiftUI through
/// CanvasPainter and by macOS's own SVG renderer (NSImage) from the SVG,
/// offscreen, then compared pixel by pixel.
///
/// NSImage doesn't draw SVG filters, so blur is left out here; the SVG
/// output tests check its filter instead.
@MainActor
@Suite("Canvas and SVG fidelity")
struct FidelityTests {
    @Test(arguments: FidelityDrawings.all)
    func svgMatchesTheCanvas(_ drawing: FidelityDrawings.Drawing) throws {
        let scale: CGFloat = 2
        let canvas = try #require(Rendering.canvas(size: FidelityDrawings.size, scale: scale, drawing.draw))
        let svg = Rendering.svg(size: FidelityDrawings.size, drawing.svg)
        _ = try parseSVG(svg)
        let image = try #require(Rendering.rasterize(svg: svg, width: canvas.width, height: canvas.height))
        let difference = canvas.difference(from: image)
        let mismatch = canvas.mismatch(from: image)
        print("Fidelity (\(drawing.name), \(canvas.width)×\(canvas.height) px): mean \(String(format: "%.3f", difference.mean))/255 a channel, \(String(format: "%.3f", difference.over * 100))% of pixels off by more than 16, \(String(format: "%.3f", mismatch * 100))% really different (outside their neighbors' range), worst \(difference.max)")
        // SAVAGE_FIDELITY_OUTPUT=<folder> keeps the pictures, to look at.
        if let folder = ProcessInfo.processInfo.environment["SAVAGE_FIDELITY_OUTPUT"] {
            let base = URL(filePath: folder, directoryHint: .isDirectory).appending(path: drawing.name.replacingOccurrences(of: " ", with: "-"))
            try FileManager.default.createDirectory(at: base.deletingLastPathComponent(), withIntermediateDirectories: true)
            try svg.write(to: base.appendingPathExtension("svg"), atomically: true, encoding: .utf8)
            try canvas.png().write(to: URL(filePath: base.path() + "-canvas.png"))
            try image.png().write(to: URL(filePath: base.path() + "-svg.png"))
            try canvas.differenceMap(from: image).png().write(to: URL(filePath: base.path() + "-difference.png"))
        }
        // The Canvas dithers gradients and NSImage doesn't, which costs up to
        // about 1.6 levels on average over a picture full of gradients.
        #expect(difference.mean < 2)
        #expect(mismatch < 0.001)
    }

    /// The comparison isn't blind: a shape two points out of place, or a
    /// color 24 levels off, fails it.
    @Test func theComparisonCatchesRealDifferences() throws {
        let scale: CGFloat = 2, size = FidelityDrawings.size
        let canvas = try #require(Rendering.canvas(size: size, scale: scale) { FidelityDrawings.shapes(&$0) })
        let moved = Rendering.svg(size: size) { p in
            FidelityDrawings.shapes(&p)
            var shifted = p
            shifted.translateBy(x: 2, y: 0)
            shifted.fill(Path(ellipseIn: CGRect(x: 70, y: 40, width: 50, height: 50)), with: .color(FidelityDrawings.leaf))
        }
        let recolored = Rendering.svg(size: size) { p in
            FidelityDrawings.shapes(&p)
            p.fill(Path(CGRect(x: 10, y: 10, width: 120, height: 80)), with: .color(FidelityDrawings.cool.mix(with: .white, by: 0.1)))
        }
        for svg in [moved, recolored] {
            let image = try #require(Rendering.rasterize(svg: svg, width: canvas.width, height: canvas.height))
            #expect(canvas.mismatch(from: image) > 0.005)
        }
    }
}
#endif
