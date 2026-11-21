// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2026 Doug C. Hardester

import Foundation
import SwiftUI
import Testing
@testable import Savage

/// What each drawing call writes into the SVG.
@Suite("SVG output")
struct SVGOutputTests {
    let size = CGSize(width: 200, height: 100)
    let red = PaintColor(red: 1, green: 0, blue: 0)

    private func svg(title: String? = "Test", _ draw: (inout SVGPainter) -> Void) throws -> Element {
        let document = SVGDocument(size: size, title: title)
        document.draw(draw)
        return try parseSVG(document.svgString)
    }

    private func square(_ x: CGFloat = 0, _ y: CGFloat = 0, _ side: CGFloat = 10) -> Path {
        Path(CGRect(x: x, y: y, width: side, height: side))
    }

    // MARK: The document

    @Test func theRootHasASizeAndAViewBox() throws {
        let root = try svg { _ in }
        #expect(root["width"] == "200")
        #expect(root["height"] == "100")
        #expect(root["viewBox"] == "0 0 200 100")
        #expect(root.children("title").first?.text == "Test")
        // Nothing to define: no <defs>.
        #expect(root.children("defs").isEmpty)
        #expect(root.children.count == 1)
    }

    @Test func theSizeIsOptional() throws {
        let document = SVGDocument(size: CGSize(width: 12.5, height: 8), includesSize: false)
        let root = try parseSVG(document.svgString)
        #expect(root["width"] == nil)
        #expect(root["height"] == nil)
        #expect(root["viewBox"] == "0 0 12.5 8")
        #expect(root.children("title").isEmpty)
    }

    @Test func theTitleIsEscaped() throws {
        let root = try svg(title: #"Rock & "Roll" <live>"#) { _ in }
        #expect(root.children("title").first?.text == #"Rock & "Roll" <live>"#)
    }

    @Test func dataAndFilesHoldTheSameText() throws {
        let document = SVGDocument(size: size)
        document.draw { $0.fill(square(), with: .color(red)) }
        #expect(String(decoding: document.svgData, as: UTF8.self) == document.svgString)
        let url = FileManager.default.temporaryDirectory.appending(path: "Savage-\(UUID().uuidString).svg")
        defer { try? FileManager.default.removeItem(at: url) }
        try document.write(to: url)
        #expect(try Data(contentsOf: url) == document.svgData)
    }

    @Test func readingTheTextDoesNotEndTheDocument() throws {
        let document = SVGDocument(size: size)
        document.draw { p in p.group("first") { $0.fill(square(), with: .color(red)) } }
        let before = try parseSVG(document.svgString)
        #expect(before.all("path").count == 1)
        document.draw { $0.fill(square(20), with: .color(red)) }
        let after = try parseSVG(document.svgString)
        #expect(after.all("path").count == 2)
        // The second shape is outside the first's group.
        #expect(after.children("path").count == 1)
    }

    // MARK: Fills

    @Test func fillsArePathsWithFlatColors() throws {
        let root = try svg { p in
            var path = Path()
            path.move(to: CGPoint(x: 1, y: 2))
            path.addLine(to: CGPoint(x: 10.256, y: 2))
            path.addQuadCurve(to: CGPoint(x: 20, y: 20), control: CGPoint(x: 15, y: 0))
            path.addCurve(to: CGPoint(x: 0, y: 20), control1: CGPoint(x: 10, y: 30), control2: CGPoint(x: 5, y: 30))
            path.closeSubpath()
            p.fill(path, with: .color(PaintColor(red: 1, green: 0.5, blue: 0, opacity: 0.25)), style: FillStyle(eoFill: true))
            p.fill(square(), with: .color(PaintColor(hex: 0x3366CC)))
        }
        let paths = root.children("path")
        #expect(paths.count == 2)
        #expect(paths[0]["d"] == "M1 2L10.26 2Q15 0 20 20C10 30 5 30 0 20Z")
        #expect(paths[0]["fill"] == "#ff8000")
        #expect(paths[0]["fill-opacity"] == "0.25")
        #expect(paths[0]["fill-rule"] == "evenodd")
        #expect(paths[1]["fill"] == "#3366cc")
        // Opaque, nonzero: no opacity or rule written.
        #expect(paths[1]["fill-opacity"] == nil)
        #expect(paths[1]["fill-rule"] == nil)
    }

    @Test func emptyAndInvisibleShapesAreLeftOut() throws {
        let root = try svg { p in
            p.fill(Path(), with: .color(red))
            p.fill(square(), with: .color(red.opacity(0)))
            p.stroke(square(), with: .color(red.opacity(0)), lineWidth: 2)
            // A gradient may still show, even with clear stops.
            p.fill(square(), with: .linearGradient(PaintGradient(colors: [red.opacity(0), red]), startPoint: .zero, endPoint: CGPoint(x: 10, y: 0)))
        }
        #expect(root.all("path").count == 1)
    }

    // MARK: Strokes

    @Test func strokesKeepTheirStyle() throws {
        let root = try svg { p in
            p.stroke(square(), with: .color(.black), lineWidth: 2)
            p.stroke(square(), with: .color(.black), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            p.stroke(square(), with: .color(.black), style: StrokeStyle(lineWidth: 3, lineCap: .square, lineJoin: .bevel))
            p.stroke(square(), with: .color(.black), style: StrokeStyle(lineWidth: 1, lineJoin: .miter, miterLimit: 0.5))
        }
        let paths = root.children("path")
        #expect(paths.count == 4)
        #expect(paths.allSatisfy { $0["fill"] == "none" && $0["stroke"] == "#000000" })
        #expect(paths.map { $0["stroke-width"] } == ["2", "1.5", "3", "1"])
        #expect(paths.map { $0["stroke-linecap"] } == [nil, "round", "square", nil])
        #expect(paths.map { $0["stroke-linejoin"] } == [nil, "round", "bevel", nil])
        // Miter joins carry their limit (SwiftUI's default is 10, SVG's is
        // 4), never under SVG's minimum of 1.
        #expect(paths.map { $0["stroke-miterlimit"] } == ["10", nil, nil, "1"])
    }

    @Test func dashesCarryOver() throws {
        let root = try svg { p in
            p.stroke(square(), with: .color(.black), style: StrokeStyle(lineWidth: 1, dash: [4, 2.5], dashPhase: 1))
            p.stroke(square(), with: .color(.black), style: StrokeStyle(lineWidth: 1, dash: [3]))
            // Patterns SVG can't draw make a solid line, as they do on screen.
            p.stroke(square(), with: .color(.black), style: StrokeStyle(lineWidth: 1, dash: [0, 0]))
            p.stroke(square(), with: .color(.black), style: StrokeStyle(lineWidth: 1, dash: [4, -1]))
        }
        let paths = root.children("path")
        #expect(paths.map { $0["stroke-dasharray"] } == ["4 2.5", "3", nil, nil])
        #expect(paths.map { $0["stroke-dashoffset"] } == ["1", nil, nil, nil])
    }

    @Test func strokesTakeGradients() throws {
        let root = try svg { p in
            p.stroke(square(), with: .linearGradient(PaintGradient(colors: [.white, .black]), startPoint: .zero, endPoint: CGPoint(x: 10, y: 0)), lineWidth: 2)
        }
        let gradient = try #require(root.all("linearGradient").first)
        #expect(root.children("path").first?["stroke"] == "url(#\(gradient["id"]!))")
        #expect(root.children("path").first?["fill"] == "none")
    }

    // MARK: Gradients

    @Test func linearGradientsAreInUserSpace() throws {
        let root = try svg { p in
            p.fill(square(0, 0, 100), with: .linearGradient(PaintGradient(colors: [.white, .black, PaintColor.black.opacity(0.5)]),
                                                            startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: 100)))
        }
        let linear = try #require(root.all("linearGradient").first)
        #expect(linear.parent?.name == "defs")
        #expect(linear["gradientUnits"] == "userSpaceOnUse")
        #expect([linear["x1"], linear["y1"], linear["x2"], linear["y2"]] == ["0", "0", "0", "100"])
        let stops = linear.children("stop")
        #expect(stops.map { $0["offset"] } == ["0", "0.5", "1"])
        #expect(stops.map { $0["stop-color"] } == ["#ffffff", "#000000", "#000000"])
        #expect(stops.map { $0["stop-opacity"] } == [nil, nil, "0.5"])
        #expect(root.children("path").first?["fill"] == "url(#\(linear["id"]!))")
    }

    @Test func radialGradientsMapTheStartRadiusOntoTheStops() throws {
        let root = try svg { p in
            p.fill(Path(ellipseIn: CGRect(x: 0, y: 0, width: 40, height: 40)),
                   with: .radialGradient(PaintGradient(stops: [.init(color: .white, location: 0), .init(color: .white, location: 0.5), .init(color: .black, location: 1)]),
                                         center: CGPoint(x: 20, y: 20), startRadius: 10, endRadius: 20))
        }
        let radial = try #require(root.all("radialGradient").first)
        #expect(radial["gradientUnits"] == "userSpaceOnUse")
        #expect([radial["cx"], radial["cy"], radial["r"]] == ["20", "20", "20"])
        // 10…20 of a radius of 20: the stops move to 0.5, 0.75 and 1.
        #expect(radial.children("stop").map { $0["offset"] } == ["0.5", "0.75", "1"])
    }

    @Test func gradientsSpreadColorsEvenly() {
        let gradient = PaintGradient(colors: [.white, .black, .white])
        #expect(gradient.stops.map(\.location) == [0, 0.5, 1])
        #expect(PaintGradient(colors: [.white]).stops.map(\.location) == [0])
    }

    // MARK: Clips

    @Test func clipsWrapWhatTheyClip() throws {
        let root = try svg { p in
            var clipped = p
            clipped.clip(to: Path(ellipseIn: CGRect(x: 0, y: 0, width: 50, height: 50)))
            clipped.fill(square(0, 0, 80), with: .color(.white))
            clipped.fill(square(0, 0, 20), with: .color(.black))
            p.fill(square(90, 0), with: .color(.black))
        }
        let clip = try #require(root.all("clipPath").first)
        #expect(clip.children("path").count == 1)
        // Both clipped shapes share one group; the third is outside it.
        let groups = root.all("g").filter { $0["clip-path"] != nil }
        #expect(groups.count == 1)
        #expect(groups.first?["clip-path"] == "url(#\(clip["id"]!))")
        #expect(groups.first?.children("path").count == 2)
        #expect(root.children("path").count == 1)
    }

    @Test func clipsAddUp() throws {
        let root = try svg { p in
            p.clip(to: square(0, 0, 50))
            p.clip(to: square(25, 25, 50))
            p.fill(square(0, 0, 100), with: .color(.black))
        }
        let shape = try #require(root.all("path").last)
        #expect(shape.parent?["clip-path"] != nil)
        #expect(shape.parent?.parent?["clip-path"] != nil)
        #expect(shape.parent?["clip-path"] != shape.parent?.parent?["clip-path"])
    }

    @Test func aCopysClipLeavesTheOriginalAlone() throws {
        let root = try svg { p in
            var copy = p
            copy.clip(to: square())
            copy.translateBy(x: 5, y: 5)
            p.fill(square(), with: .color(.black))
        }
        let path = try #require(root.children("path").first)
        #expect(path["transform"] == nil)
    }

    @Test func clipsCarryTheTransform() throws {
        let root = try svg { p in
            p.translateBy(x: 10, y: 0)
            p.clip(to: square())
            p.fill(square(), with: .color(.black))
        }
        let clipPath = try #require(root.all("clipPath").first?.children("path").first)
        #expect(clipPath["transform"] == "matrix(1 0 0 1 10 0)")
    }

    // MARK: Transforms

    @Test func transformsTravelWithTheShape() throws {
        let root = try svg { p in
            var moved = p
            moved.translateBy(x: 10, y: 20)
            moved.scaleBy(x: 1, y: 0.5)
            moved.fill(Path(ellipseIn: CGRect(x: -5, y: -5, width: 10, height: 10)),
                       with: .radialGradient(PaintGradient(colors: [.white, .black]), center: .zero, startRadius: 0, endRadius: 5))
            var turned = p
            turned.rotate(by: .degrees(90))
            turned.fill(square(), with: .color(.black))
            var skewed = p
            skewed.concatenate(CGAffineTransform(a: 1, b: 0, c: 0.25, d: 1, tx: 0, ty: 0))
            skewed.translateBy(x: 4, y: 0)
            skewed.fill(square(), with: .color(.black))
        }
        let paths = root.children("path")
        #expect(paths.map { $0["transform"] } == ["matrix(1 0 0 0.5 10 20)", "matrix(0 1 -1 0 0 0)", "matrix(1 0 0.25 1 4 0)"])
    }

    @Test func precisionFollowsTheScale() throws {
        // A drawing in unit coordinates, scaled up to the page: its
        // coordinates keep a hundredth of a point of precision there.
        let root = try svg { p in
            p.scaleBy(x: 200, y: 100)
            var path = Path()
            path.move(to: CGPoint(x: 0.123456, y: 0.5))
            path.addLine(to: CGPoint(x: 0.75, y: 0.987654))
            p.stroke(path, with: .linearGradient(PaintGradient(colors: [.white, .black]), startPoint: CGPoint(x: 0.123456, y: 0), endPoint: CGPoint(x: 1, y: 0)),
                     lineWidth: 0.0123)
        }
        let path = try #require(root.children("path").first)
        #expect(path["d"] == "M0.12346 0.5L0.75 0.98765")
        #expect(path["stroke-width"] == "0.0123")
        #expect(root.all("linearGradient").first?["x1"] == "0.12346")
        #expect(path["transform"] == "matrix(200 0 0 100 0 0)")
    }

    // MARK: Groups

    @Test func groupsAreNamedAndUnique() throws {
        let root = try svg { p in
            p.group("moon") { $0.fill(square(), with: .color(.white)) }
            p.group("moon") { $0.fill(square(), with: .color(.white)) }
            p.group("night sky") { $0.fill(square(), with: .color(.white)) }
            p.group("2nd <star>") { $0.fill(square(), with: .color(.white)) }
            p.group("") { $0.fill(square(), with: .color(.white)) }
            p.group("étoile") { $0.fill(square(), with: .color(.white)) }
        }
        #expect(root.all("g").map { $0["id"] } == ["moon", "moon-2", "night-sky", "_2nd--star-", "group", "étoile"])
    }

    @Test func namesNeverTakeAGeneratedID() throws {
        // The group takes the counter's 1; the clip would be clip2.
        let root = try svg { p in
            p.group("clip2") { g in
                g.clip(to: square())
                g.fill(square(), with: .color(.white))
            }
        }
        let ids = root.descendants.compactMap { $0["id"] }
        #expect(Set(ids).count == ids.count)
        #expect(root.all("g").first { $0["id"] != nil }?["id"] == "clip2")
        #expect(root.all("clipPath").first?["id"] == "clip3")
    }

    @Test func groupsNestAndEmptyOnesAreLeftOut() throws {
        let root = try svg { p in
            p.group("outer") { g in
                g.group("empty") { _ in }
                g.group("inner") { $0.fill(square(), with: .color(.white)) }
            }
        }
        #expect(root.all("g").map { $0["id"] } == ["outer", "inner"])
        #expect(root.all("g").last?.parent?["id"] == "outer")
    }

    // MARK: Layers

    @Test func aLayersOpacityIsAMask() throws {
        let root = try svg { p in
            p.drawLayer(LayerStyle(opacity: 0.5)) { $0.fill(square(), with: .color(red)) }
        }
        let mask = try #require(root.all("mask").first)
        #expect(mask["maskUnits"] == "userSpaceOnUse")
        #expect([mask["x"], mask["y"], mask["width"], mask["height"]] == ["0", "0", "200", "100"])
        let white = try #require(mask.children("path").first)
        #expect(white["fill"] == "#fff")
        #expect(white["fill-opacity"] == "0.5")
        // The shape is in a group drawn as one, inside the masked group.
        let shape = try #require(root.all("path").first { $0["fill"] == "#ff0000" })
        #expect(shape.parent?["opacity"] == "0.9999")
        #expect(shape.parent?.parent?["mask"] == "url(#\(mask["id"]!))")
        // No group gets a lower opacity than that.
        #expect(root.all("g").allSatisfy { $0["opacity"] == nil || $0["opacity"] == "0.9999" })
    }

    @Test func anOpaqueLayerWithNothingToDoIsJustItsContent() throws {
        let root = try svg { p in
            p.drawLayer(LayerStyle()) { $0.fill(square(), with: .color(red)) }
        }
        #expect(root.all("g").isEmpty)
        #expect(root.children("path").count == 1)
    }

    @Test func cutoutsClearTheLayersMask() throws {
        let style = LayerStyle(opacity: 0.5, cutouts: [.init(path: square(10, 10, 5), opacity: 0.9), .init(path: square(30, 10, 5))])
        let root = try svg { p in
            p.drawLayer(style) { $0.fill(square(0, 0, 50), with: .color(red)) }
        }
        let mask = try #require(root.all("mask").first)
        let paths = mask.children("path")
        #expect(paths.map { $0["fill"] } == ["#fff", "#000", "#000"])
        #expect(paths.map { $0["fill-opacity"] } == ["0.5", "0.9", "1"])
        #expect(paths[1]["d"] == "M10 10L15 10L15 15L10 15Z")
    }

    @Test func cutoutsFollowTheTransform() throws {
        let root = try svg { p in
            p.translateBy(x: 20, y: 0)
            p.drawLayer(LayerStyle(cutouts: [.init(path: square())])) { $0.fill(square(), with: .color(red)) }
        }
        let cut = try #require(root.all("mask").first?.children("path").last)
        #expect(cut["transform"] == "matrix(1 0 0 1 20 0)")
        // The mask's own rect is the page's.
        #expect(root.all("mask").first?.children("path").first?["transform"] == nil)
    }

    @Test func fadesAreLuminanceMasks() throws {
        let fade = LayerStyle.Fade(rect: CGRect(origin: .zero, size: size),
                                   paint: .linearGradient(PaintGradient(colors: [PaintColor(hex: 0x123456), PaintColor(hex: 0x123456, opacity: 0)]),
                                                          startPoint: .zero, endPoint: CGPoint(x: 200, y: 0)))
        let flat = LayerStyle.Fade(rect: CGRect(origin: .zero, size: size), paint: .color(PaintColor.black.opacity(0.25)))
        let root = try svg { p in
            p.drawLayer(LayerStyle(fades: [fade, flat])) { $0.fill(square(0, 0, 200), with: .color(red)) }
        }
        let masks = root.all("mask")
        #expect(masks.count == 2)
        // A fade is its paint's opacity in white; the color doesn't matter.
        #expect(root.all("stop").map { $0["stop-color"] } == ["#ffffff", "#ffffff"])
        #expect(root.all("stop").map { $0["stop-opacity"] } == [nil, "0"])
        let flatMask = try #require(masks.first { $0.children("path").first?["fill"] == "#fff" })
        #expect(flatMask.children("path").first?["fill-opacity"] == "0.25")
        // Each mask over a group drawn as one.
        let shape = try #require(root.all("path").first { $0["fill"] == "#ff0000" })
        #expect(shape.parent?["opacity"] == "0.9999")
        #expect(shape.parent?.parent?["mask"] != nil)
        #expect(shape.parent?.parent?.parent?["opacity"] == "0.9999")
        #expect(shape.parent?.parent?.parent?.parent?["mask"] != nil)
    }

    @Test func blurIsAFilterOnTheWholeLayer() throws {
        let root = try svg { p in
            p.drawLayer(LayerStyle(opacity: 0.5, blur: 3, cutouts: [.init(path: square())])) { $0.fill(square(0, 0, 50), with: .color(.white)) }
        }
        let filter = try #require(root.all("filter").first)
        #expect(filter["filterUnits"] == "userSpaceOnUse")
        #expect(filter["color-interpolation-filters"] == "sRGB")
        // The filter region reaches three deviations past the page.
        #expect([filter["x"], filter["y"], filter["width"], filter["height"]] == ["-9", "-9", "218", "118"])
        #expect(filter.children("feGaussianBlur").first?["stdDeviation"] == "3")
        // Outermost: it softens the cut-outs and the opacity too.
        let blurred = try #require(root.children("g").first)
        #expect(blurred["filter"] == "url(#\(filter["id"]!))")
        #expect(blurred.children("g").first?["mask"] != nil)
    }

    @Test func blurScalesWithThePainter() throws {
        let root = try svg { p in
            var wide = p
            wide.scaleBy(x: 2, y: 1)
            wide.drawLayer(LayerStyle(blur: 3)) { $0.fill(square(), with: .color(.white)) }
            // Turned a quarter, then stretched: tall on the page.
            var tall = p
            tall.rotate(by: .degrees(90))
            tall.scaleBy(x: 2, y: 1)
            tall.drawLayer(LayerStyle(blur: 3)) { $0.fill(square(), with: .color(.white)) }
        }
        let deviations = root.all("feGaussianBlur").map { $0["stdDeviation"] }
        #expect(deviations == ["6 3", "3 6"])
    }

    @Test func aWashOverEverythingMixesIntoTheColors() throws {
        let style = LayerStyle(wash: .init(color: PaintColor.white.opacity(0.5), rect: CGRect(origin: .zero, size: size)))
        let root = try svg { p in
            p.drawLayer(style) { l in
                l.fill(square(), with: .color(PaintColor.black.opacity(0.4)))
                l.fill(square(), with: .linearGradient(PaintGradient(colors: [.black, red]), startPoint: .zero, endPoint: CGPoint(x: 10, y: 0)))
            }
        }
        // Drawn once, no clips: the wash is in the colors.
        #expect(root.all("clipPath").isEmpty)
        let paths = root.children("path")
        #expect(paths.first?["fill"] == "#808080")
        #expect(paths.first?["fill-opacity"] == "0.4")
        #expect(root.all("stop").map { $0["stop-color"] } == ["#808080", "#ff8080"])
    }

    @Test func washesNestInnermostFirst() throws {
        let all = CGRect(origin: .zero, size: size)
        let root = try svg { p in
            p.drawLayer(LayerStyle(wash: .init(color: PaintColor.white.opacity(0.5), rect: all))) { outer in
                outer.drawLayer(LayerStyle(wash: .init(color: red, rect: all))) { inner in
                    inner.fill(square(), with: .color(.black))
                }
            }
        }
        // Black, then all red, then halfway to white.
        #expect(root.children("path").first?["fill"] == "#ff8080")
    }

    @Test func aPartialWashDrawsTwice() throws {
        // Outside its rect a layer's wash changes nothing: the part of a
        // shape there is drawn plain, the part inside washed.
        let box = CGRect(x: 50, y: 50, width: 100, height: 50)
        let style = LayerStyle(wash: .init(color: PaintColor.white.opacity(0.5), rect: box), fades: [.init(rect: box, paint: .color(PaintColor.black.opacity(0.5)))])
        let root = try svg { p in
            p.drawLayer(style) { l in
                l.fill(square(0, 0, 100), with: .color(.black))   // crosses the box
                l.fill(square(60, 60, 10), with: .color(.black))  // inside it
            }
        }
        let paths = root.all("path")
        #expect(paths.filter { $0["fill"] == "#000000" }.count == 1)
        #expect(paths.filter { $0["fill"] == "#808080" }.count == 2)
        // Plain outside the rect (a frame with a hole a point inside it),
        // washed inside it.
        let clips = root.all("clipPath").compactMap { $0.children("path").first?["d"] }
        #expect(clips == ["M-200 -100L400 -100L400 200L-200 200ZM51 51L51 99L149 99L149 51Z", "M50 50L150 50L150 100L50 100Z"])
        // The fade is one mask around both copies.
        #expect(root.all("mask").count == 1)
        let masked = try #require(root.all("g").first { $0["mask"] != nil })
        #expect(masked.all("path").count == 3)
    }

    @Test func aPartialFadeIsOneMaskThatKeepsTheRest() throws {
        let top = CGRect(x: 0, y: 0, width: 200, height: 50)
        let fadeOut = PaintGradient(colors: [.black, .black.opacity(0.25)])
        let style = LayerStyle(fades: [.init(rect: top, paint: .color(PaintColor.black.opacity(0.75))),
                                       .init(rect: top, paint: .linearGradient(fadeOut, startPoint: .zero, endPoint: CGPoint(x: 200, y: 0)))])
        let root = try svg { p in
            p.drawLayer(style) { $0.fill(square(0, 0, 200), with: .color(red)) }
        }
        // The layer is drawn once, with no clips.
        #expect(root.all("path").filter { $0["fill"] == "#ff0000" }.count == 1)
        #expect(root.all("clipPath").isEmpty)
        // Each mask: the page in white, then the paint's clear parts in black
        // over the rect.
        let masks = root.all("mask")
        #expect(masks.count == 2)
        for mask in masks {
            let paths = mask.children("path")
            #expect(paths.map { $0["d"] } == ["M0 0L200 0L200 100L0 100Z", "M0 0L200 0L200 50L0 50Z"])
            #expect(paths.first?["fill"] == "#fff")
        }
        let flat = try #require(masks.first { $0.children("path").last?["fill"] == "#000" })
        #expect(flat.children("path").last?["fill-opacity"] == "0.25")
        #expect(root.all("stop").map { $0["stop-color"] } == ["#000000", "#000000"])
        #expect(root.all("stop").map { $0["stop-opacity"] } == ["0", "0.75"])
    }

    @Test func clearStopsTakeTheirNeighborsColors() {
        let blue = PaintColor(red: 0, green: 0, blue: 1)
        // White to clear black stays white, as on a Canvas.
        let fade = SVGPainter.premultipliedStops([.init(color: .white, location: 0), .init(color: .black.opacity(0), location: 1)])
        #expect(fade.map(\.color) == [.white, PaintColor.white.opacity(0)])
        // A clear stop between two colors becomes two, one for each side.
        let through = SVGPainter.premultipliedStops([.init(color: red, location: 0), .init(color: .black.opacity(0), location: 0.5), .init(color: blue, location: 1)])
        #expect(through.map(\.color) == [red, red.opacity(0), blue.opacity(0), blue])
        #expect(through.map(\.location) == [0, 0.5, 0.5, 1])
    }

    @Test func stopsChangingColorAndOpacityFollowThePremultipliedBlend() throws {
        let stops = SVGPainter.premultipliedStops([.init(color: .white, location: 0), .init(color: PaintColor.black.opacity(0.5), location: 1)])
        #expect(stops.count == 9)
        #expect(stops.map(\.location) == (0...8).map { CGFloat($0) / 8 })
        // Halfway: opacity 0.75, and white weighted 0.5 against black's 0.25.
        let middle = stops[4].color
        #expect(middle.opacity == 0.75)
        #expect(abs(middle.red - 2.0 / 3) < 1e-12)
        // Stops that agree under either blend are left alone.
        let sameColor: [PaintGradient.Stop] = [.init(color: red, location: 0), .init(color: red.opacity(0.2), location: 1)]
        let sameOpacity: [PaintGradient.Stop] = [.init(color: red, location: 0), .init(color: .white, location: 1)]
        #expect(SVGPainter.premultipliedStops(sameColor) == sameColor)
        #expect(SVGPainter.premultipliedStops(sameOpacity) == sameOpacity)
        // In the SVG, too.
        let root = try svg { p in
            p.fill(square(), with: .linearGradient(PaintGradient(colors: [.white, PaintColor.black.opacity(0.5)]), startPoint: .zero, endPoint: CGPoint(x: 10, y: 0)))
        }
        #expect(root.all("stop").count == 9)
        #expect(root.all("stop")[4]["stop-color"] == "#aaaaaa")
        #expect(root.all("stop")[4]["stop-opacity"] == "0.75")
    }

    @Test func shapesInsideAPartialRectAreLeftOutOfThePlainCopy() throws {
        let box = CGRect(x: 50, y: 20, width: 100, height: 60)
        let root = try svg { p in
            p.drawLayer(LayerStyle(wash: .init(color: .white, rect: box))) { l in
                l.fill(square(60, 30, 10), with: .color(.black))
            }
        }
        // Only the washed copy is written.
        let shapes = root.all("path").filter { $0.parent?.name != "clipPath" }
        #expect(shapes.map { $0["fill"] } == ["#ffffff"])
    }

    @Test func partialRectsWorkUnderATransform() throws {
        // Scaled down by half: the box covers the right half of the page in
        // the painter's coordinates, so it's partial.
        let root = try svg { p in
            p.scaleBy(x: 0.5, y: 0.5)
            p.drawLayer(LayerStyle(wash: .init(color: .white, rect: CGRect(x: 200, y: 0, width: 200, height: 200)))) { l in
                l.fill(square(0, 0, 400), with: .color(.black))
            }
            // Turned a quarter: a rect that covers the page once turned back.
            var turned = SVGPainter(document: p.document)
            turned.translateBy(x: 200, y: 0)
            turned.rotate(by: .degrees(90))
            turned.drawLayer(LayerStyle(wash: .init(color: red, rect: CGRect(x: -1, y: -1, width: 102, height: 202)))) { l in
                l.fill(square(0, 0, 100), with: .color(.black))
            }
        }
        // The first is drawn twice; the outer frame of its plain copy covers
        // the page in the painter's (scaled) coordinates.
        let frame = try #require(root.all("clipPath").first?.children("path").first?["d"])
        #expect(frame.hasPrefix("M-400 -200L800 -200L800 400L-400 400Z"))
        // The second covers everything: drawn once, washed.
        let washed = root.all("path").filter { $0["fill"] == "#ff0000" }
        #expect(washed.count == 1)
        #expect(root.all("clipPath").count == 2)
    }

    // MARK: Throwing drawings

    struct Stop: Error {}

    @Test func errorsFromTheDrawingPassThrough() {
        let document = SVGDocument(size: size)
        #expect(throws: Stop.self) {
            try document.draw { p in
                try p.group("g") { g in
                    try g.drawLayer(LayerStyle(opacity: 0.5)) { _ in throw Stop() }
                }
            }
        }
    }
}
