// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2026 Doug C. Hardester

import SwiftUI
import Testing
@testable import Savage

/// What CanvasPainter draws, rendered offscreen.
@MainActor
@Suite("Canvas painter")
struct CanvasPainterTests {
    let size = CGSize(width: 100, height: 100)
    let red = PaintColor(red: 1, green: 0, blue: 0)

    private func render(_ draw: @escaping (inout CanvasPainter) -> Void) throws -> Bitmap {
        try #require(Rendering.canvas(size: size, draw))
    }

    @Test func fillsAndStrokesLandWhereTheyShould() throws {
        let image = try render { p in
            p.fill(Path(CGRect(x: 10, y: 10, width: 20, height: 20)), with: .color(red))
            p.stroke(Path(CGRect(x: 50, y: 10, width: 20, height: 20)), with: .color(.white), lineWidth: 4)
        }
        #expect(image.pixel(20, 20) == (1, 0, 0, 1))
        #expect(image.pixel(5, 5).a == 0)
        #expect(image.pixel(50, 20) == (1, 1, 1, 1))
        // Inside the stroked square, nothing.
        #expect(image.pixel(60, 20).a == 0)
    }

    @Test func colorsAndGradientsConvertExactly() {
        let color = PaintColor(red: 0.2, green: 0.4, blue: 0.6, opacity: 0.8)
        #expect(Color(color) == Color(.sRGB, red: 0.2, green: 0.4, blue: 0.6, opacity: 0.8))
        let gradient = PaintGradient(stops: [.init(color: .white, location: 0.25), .init(color: color, location: 1)])
        #expect(Gradient(gradient) == Gradient(stops: [.init(color: Color(.sRGB, red: 1, green: 1, blue: 1, opacity: 1), location: 0.25),
                                                       .init(color: Color(color), location: 1)]))
    }

    @Test func aLayerIsCompositedAsOne() throws {
        let image = try render { p in
            p.drawLayer(LayerStyle(opacity: 0.5)) { l in
                l.fill(Path(CGRect(x: 0, y: 0, width: 60, height: 60)), with: .color(red))
                l.fill(Path(CGRect(x: 40, y: 40, width: 60, height: 60)), with: .color(red))
            }
        }
        // Where the two overlap, still half: the layer's opacity applies once.
        #expect(abs(image.pixel(50, 50).a - 0.5) < 0.01)
        #expect(abs(image.pixel(10, 10).a - 0.5) < 0.01)
    }

    @Test func cutoutsFadesAndWashesComposite() throws {
        let image = try render { p in
            let style = LayerStyle(wash: .init(color: .white, rect: CGRect(x: 0, y: 0, width: 50, height: 100)),
                                   cutouts: [.init(path: Path(CGRect(x: 40, y: 40, width: 20, height: 20)))],
                                   fades: [.init(rect: CGRect(x: 0, y: 80, width: 100, height: 20), paint: .color(PaintColor.black.opacity(0.5)))])
            p.drawLayer(style) { l in
                l.fill(Path(CGRect(origin: .zero, size: CGSize(width: 100, height: 100))), with: .color(red))
            }
        }
        #expect(image.pixel(10, 10) == (1, 1, 1, 1))     // washed
        #expect(image.pixel(80, 10) == (1, 0, 0, 1))     // outside the wash
        #expect(image.pixel(50, 50).a == 0)              // cut out
        #expect(abs(image.pixel(80, 90).a - 0.5) < 0.01) // faded by half
    }

    @Test func blurSoftensTheFinishedLayer() throws {
        let image = try render { p in
            p.drawLayer(LayerStyle(blur: 4, cutouts: [.init(path: Path(CGRect(x: 50, y: 0, width: 50, height: 100)))])) { l in
                l.fill(Path(CGRect(x: 0, y: 0, width: 100, height: 100)), with: .color(red))
            }
        }
        // The cut-out's edge is soft too: the blur comes after it.
        let edge = image.pixel(50, 50).a
        #expect(edge > 0.3 && edge < 0.7, "\(edge)")
        #expect(image.pixel(20, 50).a > 0.99)
    }

    @Test func clipsAndTransformsStayWithTheirCopy() throws {
        let image = try render { p in
            var copy = p
            copy.clip(to: Path(CGRect(x: 0, y: 0, width: 50, height: 50)))
            copy.translateBy(x: 10, y: 0)
            copy.fill(Path(CGRect(x: 0, y: 0, width: 100, height: 100)), with: .color(red))
            p.fill(Path(CGRect(x: 0, y: 60, width: 10, height: 10)), with: .color(.white))
        }
        #expect(image.pixel(5, 5).a == 0)            // the copy moved right
        #expect(image.pixel(20, 20) == (1, 0, 0, 1))
        #expect(image.pixel(70, 20).a == 0)          // clipped
        #expect(image.pixel(5, 65) == (1, 1, 1, 1))  // the original isn't clipped or moved
    }

    @Test func groupsJustDraw() throws {
        let image = try render { p in
            p.group("square") { $0.fill(Path(CGRect(x: 0, y: 0, width: 10, height: 10)), with: .color(red)) }
        }
        #expect(image.pixel(5, 5) == (1, 0, 0, 1))
    }

    struct Stop: Error {}

    @Test func errorsFromTheDrawingPassThrough() {
        var caught = false
        _ = Rendering.canvas(size: size) { p in
            do {
                try p.drawLayer(LayerStyle(opacity: 0.5)) { l in
                    try l.group("g") { _ in throw Stop() }
                }
            } catch {
                caught = error is Stop
            }
        }
        #expect(caught)
    }
}
