// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2026 Doug C. Hardester

// The README's code examples, exactly as the README shows them. Each one
// sits between a "README: begin" and a "README: end" line, and
// ReadmeTests checks that the README's Swift blocks are these, in order.
// This target sees only Savage's public API.

// README: begin
import Savage
import SwiftUI

/// A sunset: a sky, a glowing sun and a hill.
struct Sunset {
    var sky = PaintColor(hex: 0x2B3A67)
    var sun = PaintColor(hex: 0xFFB86C)
    var hill = PaintColor(hex: 0x1B2A41)

    func draw<P: Painter>(_ painter: inout P, size: CGSize) {
        let w = size.width, h = size.height

        // The sky, lighter toward the horizon.
        painter.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
            PaintGradient(colors: [sky, sky.mix(with: sun, by: 0.6)]),
            startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))

        // The sun, with a soft glow around it.
        let center = CGPoint(x: w * 0.65, y: h * 0.62)
        let r = h * 0.1
        painter.fill(Path(ellipseIn: CGRect(x: center.x - 3 * r, y: center.y - 3 * r, width: 6 * r, height: 6 * r)),
                     with: .radialGradient(PaintGradient(colors: [sun.opacity(0.6), sun.opacity(0)]),
                                           center: center, startRadius: r, endRadius: 3 * r))
        painter.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)),
                     with: .color(sun))

        // A hill in front.
        var ground = Path()
        ground.move(to: CGPoint(x: 0, y: h * 0.78))
        ground.addQuadCurve(to: CGPoint(x: w, y: h * 0.72), control: CGPoint(x: w * 0.45, y: h * 0.58))
        ground.addLine(to: CGPoint(x: w, y: h))
        ground.addLine(to: CGPoint(x: 0, y: h))
        ground.closeSubpath()
        painter.fill(ground, with: .color(hill))
    }
}
// README: end

// README: begin
struct SunsetView: View {
    var body: some View {
        Canvas { context, size in
            var painter = CanvasPainter(context: context)
            Sunset().draw(&painter, size: size)
        }
    }
}
// README: end

// README: begin
func exportSunset(to url: URL) throws {
    let size = CGSize(width: 600, height: 380)
    let document = SVGDocument(size: size, title: "Sunset")
    document.draw { painter in
        Sunset().draw(&painter, size: size)
    }
    try document.write(to: url)  // or use document.svgString, document.svgData
}
// README: end

// README: begin
/// The sunset upside down in a lake along the bottom: see-through,
/// blurred, and fading out toward the bottom.
func drawReflection<P: Painter>(_ painter: inout P, of sunset: Sunset, size: CGSize) {
    let water = CGRect(x: 0, y: size.height * 0.8, width: size.width, height: size.height * 0.2)
    let fadeOut = PaintGradient(colors: [.black, .black.opacity(0)])
    let style = LayerStyle(opacity: 0.5, blur: 2, fades: [
        .init(rect: water, paint: .linearGradient(fadeOut, startPoint: CGPoint(x: 0, y: water.minY),
                                                  endPoint: CGPoint(x: 0, y: water.maxY))),
    ])

    var lake = painter
    lake.clip(to: Path(water))
    lake.drawLayer(style) { layer in
        // Mirror the picture in the water's top edge.
        layer.translateBy(x: 0, y: 2 * water.minY)
        layer.scaleBy(x: 1, y: -1)
        sunset.draw(&layer, size: size)
    }
}
// README: end
