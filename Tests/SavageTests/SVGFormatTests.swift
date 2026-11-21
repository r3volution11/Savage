// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2026 Doug C. Hardester

import Foundation
import SwiftUI
import Testing
@testable import Savage

/// Numbers, colors, text and ids, and the document as a whole: valid XML,
/// the same every time.
@Suite("SVG formatting")
struct SVGFormatTests {
    @Test(arguments: [
        (0, "0"), (-0.0, "0"), (0.004, "0"), (-0.004, "0"), (0.005, "0.01"), (1, "1"), (-1, "-1"), (12, "12"),
        (10.256, "10.26"), (-0.5, "-0.5"), (0.1 + 0.2, "0.3"), (1.999, "2"), (123456.789, "123456.79"), (1e9, "1000000000"),
    ] as [(CGFloat, String)])
    func numbersAreShortAndRounded(_ value: CGFloat, _ text: String) {
        #expect(SVGFormat.number(value) == text)
    }

    @Test func numbersTakeMorePlacesWhenAsked() {
        #expect(SVGFormat.number(0.123456, places: 4) == "0.1235")
        #expect(SVGFormat.number(0.00001234, places: 8) == "0.00001234")
        #expect(SVGFormat.number(0.000012, places: 8) == "0.000012")
        #expect(SVGFormat.number(-2.5, places: 0) == "-3")
        // Never an exponent, never more than eight places.
        #expect(SVGFormat.number(1e-9, places: 12) == "0")
        #expect(!SVGFormat.number(1e20).contains("e"))
    }

    @Test func numbersThatArentFiniteStayValid() {
        #expect(SVGFormat.number(.nan) == "0")
        #expect(SVGFormat.number(.infinity) == "0")
        #expect(SVGFormat.number(-.infinity) == "0")
    }

    @Test func fractionsAreClampedToFourPlaces() {
        #expect(SVGFormat.fraction(0.123456) == "0.1235")
        #expect(SVGFormat.fraction(1.5) == "1")
        #expect(SVGFormat.fraction(-0.2) == "0")
        #expect(SVGFormat.fraction(0.9999) == "0.9999")
        #expect(SVGFormat.fraction(.nan) == "0")
    }

    @Test func colorsAreHexBytes() {
        #expect(SVGFormat.hex(PaintColor(red: 1, green: 0.5, blue: 0)) == "#ff8000")
        #expect(SVGFormat.hex(PaintColor(hex: 0x0A0B0C)) == "#0a0b0c")
        #expect(SVGFormat.hex(PaintColor(red: 1.4, green: -1, blue: .nan)) == "#ff0000")
        // Opacity is written on its own, never in the hex.
        #expect(SVGFormat.hex(PaintColor(red: 0, green: 0, blue: 0, opacity: 0.5)) == "#000000")
    }

    @Test func hexColorsReadTheirBytes() {
        let color = PaintColor(hex: 0xFF8000, opacity: 0.5)
        #expect(color == PaintColor(red: 1, green: 128.0 / 255, blue: 0, opacity: 0.5))
        // Only the low 24 bits count.
        #expect(PaintColor(hex: 0xAB_FFFFFF) == .white)
    }

    @Test func colorsMixAndFade() {
        let gray = PaintColor.black.mix(with: .white, by: 0.25)
        #expect(gray == PaintColor(red: 0.25, green: 0.25, blue: 0.25))
        #expect(PaintColor.white.opacity(0.5).opacity(0.5).opacity == 0.25)
        #expect(PaintColor.white.mix(with: PaintColor.white.opacity(0), by: 0.5).opacity == 0.5)
    }

    @Test func textIsEscaped() {
        #expect(SVGFormat.escaped(#"a & b < c > d "e" 'f'"#) == "a &amp; b &lt; c &gt; d &quot;e&quot; 'f'")
        // Characters XML can't hold are left out; the rest are kept.
        #expect(SVGFormat.escaped("bell\u{07}, tab\t, null\u{00}, é, 🌙") == "bell, tab\t, null, é, 🌙")
    }

    @Test func namesBecomeValidIDs() {
        #expect(SVGFormat.identifier("moon") == "moon")
        #expect(SVGFormat.identifier("the moon") == "the-moon")
        #expect(SVGFormat.identifier("a.b_c-d") == "a.b_c-d")
        #expect(SVGFormat.identifier("3 stars") == "_3-stars")
        #expect(SVGFormat.identifier("-x") == "_-x")
        #expect(SVGFormat.identifier("\"><script>") == "_---script-")
        #expect(SVGFormat.identifier("") == "group")
        #expect(SVGFormat.identifier("月") == "月")
    }

    @Test func decimalPlacesFollowTheScale() {
        #expect(SVGFormat.places(for: .identity) == 2)
        #expect(SVGFormat.places(for: CGAffineTransform(scaleX: 1, y: 0.24)) == 2)
        #expect(SVGFormat.places(for: CGAffineTransform(scaleX: 0.01, y: 0.01)) == 2)
        #expect(SVGFormat.places(for: CGAffineTransform(scaleX: 10, y: 1)) == 3)
        #expect(SVGFormat.places(for: CGAffineTransform(scaleX: 11, y: 1)) == 4)
        #expect(SVGFormat.places(for: CGAffineTransform(rotationAngle: 0.7)) == 2)
        #expect(SVGFormat.places(for: CGAffineTransform(scaleX: 1e12, y: 1)) == 8)
        #expect(SVGFormat.places(for: CGAffineTransform(translationX: 500, y: 500)) == 2)
    }

    @Test func transformsAreCompactMatrices() {
        #expect(SVGFormat.transformAttribute(.identity) == "")
        #expect(SVGFormat.transformAttribute(CGAffineTransform(translationX: 10.123, y: -4)) == #" transform="matrix(1 0 0 1 10.12 -4)""#)
        #expect(SVGFormat.transformAttribute(CGAffineTransform(rotationAngle: .pi / 6)) == #" transform="matrix(0.866025 0.5 -0.5 0.866025 0 0)""#)
    }

    // MARK: The whole document

    /// A drawing that uses every feature.
    static func everything<P: Painter>(_ p: inout P) {
        let frame = CGRect(x: 0, y: 0, width: 300, height: 200)
        let warm = PaintColor(hex: 0xFF8C42), cool = PaintColor(hex: 0x2E4057)
        p.fill(Path(frame), with: .linearGradient(PaintGradient(colors: [cool, warm]), startPoint: .zero, endPoint: CGPoint(x: 0, y: 200)))
        p.group("sun & <glow>") { g in
            g.fill(Path(ellipseIn: CGRect(x: 150, y: 40, width: 80, height: 80)),
                   with: .radialGradient(PaintGradient(colors: [warm.opacity(0.8), warm.opacity(0)]), center: CGPoint(x: 190, y: 80), startRadius: 10, endRadius: 40))
        }
        var clipped = p
        clipped.clip(to: Path(roundedRect: CGRect(x: 20, y: 20, width: 100, height: 100), cornerRadius: 12))
        clipped.translateBy(x: 70, y: 70)
        clipped.rotate(by: .degrees(30))
        clipped.scaleBy(x: 1.5, y: 1)
        clipped.stroke(Path(CGRect(x: -20, y: -20, width: 40, height: 40)), with: .color(.white),
                       style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .bevel, dash: [6, 3], dashPhase: 2))
        let box = CGRect(x: 160, y: 120, width: 120, height: 60)
        let style = LayerStyle(opacity: 0.8, blur: 1.5,
                               wash: .init(color: cool.opacity(0.4), rect: box),
                               cutouts: [.init(path: Path(ellipseIn: CGRect(x: 200, y: 140, width: 20, height: 10)), opacity: 0.7)],
                               fades: [.init(rect: box, paint: .linearGradient(PaintGradient(colors: [.black, .black.opacity(0)]), startPoint: CGPoint(x: 0, y: 120), endPoint: CGPoint(x: 0, y: 180)))])
        p.drawLayer(style) { l in
            l.fill(Path(CGRect(x: 140, y: 100, width: 160, height: 100)), with: .color(warm), style: FillStyle(eoFill: true))
            l.group("inner") { $0.fill(Path(ellipseIn: CGRect(x: 170, y: 130, width: 40, height: 40)), with: .color(.white)) }
        }
    }

    private func everythingSVG() -> String {
        let document = SVGDocument(size: CGSize(width: 300, height: 200), title: "Everything")
        document.draw { Self.everything(&$0) }
        return document.svgString
    }

    @Test func everythingTogetherIsValidVectorSVG() throws {
        let text = everythingSVG()
        let root = try parseSVG(text)
        let names = Set(root.descendants.map(\.name))
        #expect(names.isSuperset(of: ["title", "defs", "linearGradient", "radialGradient", "stop", "clipPath", "mask", "filter", "feGaussianBlur", "g", "path"]))
        // Vectors only.
        #expect(names.isSubset(of: ["title", "defs", "linearGradient", "radialGradient", "stop", "clipPath", "mask", "filter", "feGaussianBlur", "g", "path"]))
        #expect(!text.contains("data:"))
        #expect(root.all("g").contains { $0["id"] == "sun----glow-" })
        #expect(text.hasSuffix("</svg>\n"))
    }

    @Test func theSameDrawingGivesTheSameBytes() {
        let first = everythingSVG()
        #expect(everythingSVG() == first)
        // And ids don't depend on anything but the drawing.
        let ids = first.matches(of: /id="([^"]+)"/).map { String($0.1) }
        #expect(ids.prefix(4) == ["lg1", "rg3", "clip4", "blur6"])
    }
}
