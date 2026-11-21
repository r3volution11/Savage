// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2026 Doug C. Hardester

import SwiftUI

/// A painter that writes what it draws into an ``SVGDocument``, as vectors.
///
/// Get one from ``SVGDocument/draw(_:)``, or make one with
/// ``init(document:)``.
///
/// How drawing becomes SVG:
///
/// - **Fills and strokes** are `<path>` elements, with `fill` or `stroke`,
///   an opacity, the fill rule, and the stroke's width, caps, joins, miter
///   limit and dashes.
/// - **Gradients** are `<linearGradient>` and `<radialGradient>` definitions
///   in user space (`gradientUnits="userSpaceOnUse"`). A radial gradient's
///   start radius becomes its stops' offsets, since SVG radii start at the
///   center. A Canvas blends a gradient's colors premultiplied by their
///   opacity, and some SVG renderers don't. Where that would show, the SVG
///   gets extra stops, so it looks the same either way.
/// - **Transforms** go on each shape as `transform="matrix(…)"`.
/// - **Clips** are `<clipPath>` definitions, with the shapes they clip in a
///   group that refers to them.
/// - **Groups** are `<g>` elements with your name as their `id`.
/// - **Layers:** the opacity and cut-outs are one luminance `<mask>`, and
///   each fade another (white outside the fade's rect). The blur is an
///   `<feGaussianBlur>` filter on the layer's outermost group. A wash isn't
///   an element: it's mixed into the colors of what the layer draws, which
///   gives the same result as laying it on top (source atop).
/// - A wash over **part** of the picture changes nothing outside its rect,
///   so the layer's content is drawn twice: plain, clipped to outside the
///   rect (reaching a point into it, so no seam opens), and washed, clipped
///   to the rect. Shapes entirely inside the rect are left out of the plain
///   copy. Where the content is translucent, that one-point overlap can
///   show as a faint line.
///
/// Every masked group has a group just inside it with `opacity="0.9999"`.
/// Apple's SVG renderers (WebKit, so Safari, and NSImage and Quick Look)
/// mask each shape in a group on its own, so where shapes overlap they'd
/// come out too opaque. A group with an opacity is drawn as one, which
/// fixes it, and 0.9999 is a change no one can see. NSImage also applies a
/// group's opacity again to every group with an opacity inside it, so a
/// layer's opacity goes into its mask instead.
public struct SVGPainter: Painter {
    /// The document this painter writes into.
    public let document: SVGDocument
    private var chain: [SVGDocument.Group] = []
    private var transform: CGAffineTransform = .identity
    /// Decimal places for coordinates under `transform`.
    private var places = 2
    /// Flat colors laid over everything drawn here, innermost first (a
    /// layer's wash: source atop, which on each shape is a plain mix).
    private var washes: [PaintColor] = []
    /// Shapes entirely inside any of these rects (on the page) are left out:
    /// they'd be clipped away.
    private var omitWithin: [CGRect] = []

    /// A painter that writes into `document`, with no clip or transform.
    ///
    /// - Parameter document: The document to write into.
    public init(document: SVGDocument) {
        self.document = document
    }

    // MARK: Shapes

    /// Writes a filled `<path>`. See ``Painter/fill(_:with:style:)``.
    ///
    /// An empty path, or one filled with a fully transparent color, writes
    /// nothing.
    public func fill(_ path: Path, with paint: Paint, style: FillStyle) {
        guard !path.isEmpty, !isInvisible(paint), shows(path.boundingRect) else { return }
        var element = #"<path d="\#(SVGFormat.pathData(path, places: places))" "# + paintAttributes(paint, "fill")
        if style.isEOFilled { element += #" fill-rule="evenodd""# }
        element += SVGFormat.transformAttribute(transform) + "/>"
        document.emit(element, in: chain)
    }

    /// Writes a stroked `<path>`. See ``Painter/stroke(_:with:style:)``.
    ///
    /// The width, caps, joins, miter limit and dashes carry over. A dash
    /// pattern SVG can't draw (a negative length, or all zeros) is left
    /// out, so the line is solid.
    public func stroke(_ path: Path, with paint: Paint, style: StrokeStyle) {
        let corner = max(style.lineJoin == .miter ? style.miterLimit : 1, style.lineCap == .square ? 2.squareRoot() : 1)
        let reach = style.lineWidth / 2 * corner
        guard !path.isEmpty, !isInvisible(paint), shows(path.boundingRect.insetBy(dx: -reach, dy: -reach)) else { return }
        let n = { (value: CGFloat) in SVGFormat.number(value, places: places) }
        var element = #"<path d="\#(SVGFormat.pathData(path, places: places))" fill="none" "# + paintAttributes(paint, "stroke")
        element += #" stroke-width="\#(n(style.lineWidth))""#
        switch style.lineCap {
        case .round: element += #" stroke-linecap="round""#
        case .square: element += #" stroke-linecap="square""#
        default: break
        }
        switch style.lineJoin {
        case .round: element += #" stroke-linejoin="round""#
        case .bevel: element += #" stroke-linejoin="bevel""#
        default: element += #" stroke-miterlimit="\#(SVGFormat.number(max(1, style.miterLimit)))""#
        }
        if !style.dash.isEmpty, style.dash.allSatisfy({ $0 >= 0 && $0.isFinite }), style.dash.contains(where: { $0 > 0 }) {
            element += #" stroke-dasharray="\#(style.dash.map(n).joined(separator: " "))""#
            if style.dashPhase != 0 { element += #" stroke-dashoffset="\#(n(style.dashPhase))""# }
        }
        element += SVGFormat.transformAttribute(transform) + "/>"
        document.emit(element, in: chain)
    }

    private func isInvisible(_ paint: Paint) -> Bool {
        if case .color(let color) = paint { return !(color.opacity > 0) }
        return false
    }

    private func shows(_ bounds: CGRect) -> Bool {
        guard !omitWithin.isEmpty else { return true }
        let box = bounds.applying(transform)
        return !omitWithin.contains { $0.contains(box) }
    }

    // MARK: State

    /// Adds a `<clipPath>` and puts what this painter draws from now on in
    /// a group that uses it. See ``Painter/clip(to:)``.
    public mutating func clip(to path: Path) {
        let id = document.makeID("clip")
        document.addDef(#"<clipPath id="\#(id)"><path d="\#(SVGFormat.pathData(path, places: places))"\#(SVGFormat.transformAttribute(transform))/></clipPath>"#)
        chain.append(document.group(#"clip-path="url(#\#(id))""#))
    }

    /// Moves the origin. See ``Painter/translateBy(x:y:)``.
    public mutating func translateBy(x: CGFloat, y: CGFloat) {
        setTransform(transform.translatedBy(x: x, y: y))
    }

    /// Scales the drawing. See ``Painter/scaleBy(x:y:)``.
    public mutating func scaleBy(x: CGFloat, y: CGFloat) {
        setTransform(transform.scaledBy(x: x, y: y))
    }

    /// Rotates the drawing. See ``Painter/rotate(by:)``.
    public mutating func rotate(by angle: Angle) {
        setTransform(transform.rotated(by: angle.radians))
    }

    /// Adds a transform. See ``Painter/concatenate(_:)``.
    public mutating func concatenate(_ matrix: CGAffineTransform) {
        setTransform(matrix.concatenating(transform))
    }

    private mutating func setTransform(_ t: CGAffineTransform) {
        transform = t
        places = SVGFormat.places(for: t)
    }

    /// Puts `content` in a `<g>` with `name` as its `id`. See
    /// ``Painter/group(_:_:)``.
    ///
    /// The name is made a valid XML id (characters it can't have become
    /// `-`) and unique (a second `moon` is `moon-2`). A group nothing is
    /// drawn in isn't written.
    public func group(_ name: String, _ content: (inout SVGPainter) throws -> Void) rethrows {
        var inner = self
        inner.chain.append(document.group(#"id="\#(document.uniqueName(name))""#))
        try content(&inner)
    }

    // MARK: Layers

    /// The group just inside every masked group, drawn as one. See the
    /// type's discussion.
    static let wholeGroup = #"opacity="0.9999""#

    /// Masks what this painter draws from now on with the mask `id`.
    private mutating func mask(with id: String) {
        chain.append(document.group(#"mask="url(#\#(id))""#))
        chain.append(document.group(Self.wholeGroup))
    }

    /// Draws `content` as a layer composited with `style`. See
    /// ``Painter/drawLayer(_:_:)`` and the type's discussion.
    public func drawLayer(_ style: LayerStyle, _ content: (inout SVGPainter) throws -> Void) rethrows {
        var outer = self
        // The blur goes outermost: it softens the finished layer, cut-outs
        // and fades included, as a Canvas does.
        if style.blur > 0 {
            outer.chain.append(document.group(#"filter="url(#\#(blurFilter(style.blur)))""#))
        }
        if !style.cutouts.isEmpty || style.opacity < 1 {
            outer.mask(with: layerMask(opacity: style.opacity, cutouts: style.cutouts))
        }
        for fade in style.fades.reversed() where !fade.rect.isEmpty {
            outer.mask(with: fadeMask(fade))
        }
        guard let wash = style.wash, !wash.rect.isEmpty else {
            try content(&outer)
            return
        }
        if !isInvertible || coversAll(wash.rect) {
            outer.washes.insert(wash.color, at: 0)
            try content(&outer)
            return
        }
        // A wash over part of the picture changes nothing outside its rect:
        // draw the layer twice, plain outside the rect (reaching a point
        // into it, so no seam opens) and washed inside it.
        var plain = outer
        let reach = wash.rect.width > 2 && wash.rect.height > 2 ? wash.rect.insetBy(dx: 1, dy: 1) : wash.rect
        plain.clip(to: Self.outside(reach, within: farFrame))
        // Shapes inside the hole would be clipped away. It's only exact to
        // tell which when the transform keeps rects upright.
        if transform.b == 0, transform.c == 0 { plain.omitWithin.append(reach.applying(transform)) }
        try content(&plain)
        var within = outer
        within.clip(to: Path(wash.rect))
        within.washes.insert(wash.color, at: 0)
        try content(&within)
    }

    private var isInvertible: Bool {
        let det = transform.a * transform.d - transform.b * transform.c
        return det != 0 && det.isFinite
    }

    /// Whether `rect`, in this painter's coordinates, covers the whole
    /// picture.
    private func coversAll(_ rect: CGRect) -> Bool {
        if transform.b == 0, transform.c == 0 { return rect.applying(transform).contains(document.bounds) }
        guard isInvertible else { return false }
        // The picture's corners, brought into this painter's coordinates.
        let inverse = transform.inverted(), b = document.bounds, slack: CGFloat = 1e-9
        return [CGPoint(x: b.minX, y: b.minY), CGPoint(x: b.maxX, y: b.minY), CGPoint(x: b.maxX, y: b.maxY), CGPoint(x: b.minX, y: b.maxY)].allSatisfy { corner in
            let p = corner.applying(inverse)
            return p.x >= rect.minX - slack && p.x <= rect.maxX + slack && p.y >= rect.minY - slack && p.y <= rect.maxY + slack
        }
    }

    /// A rect well past the picture on every side, in this painter's
    /// coordinates.
    private var farFrame: CGRect {
        let frame = document.bounds.insetBy(dx: -document.size.width, dy: -document.size.height)
        return transform.isIdentity ? frame : frame.applying(transform.inverted())
    }

    /// `frame` less `hole`: the hole wound the other way, so it's a hole
    /// under the nonzero rule (macOS's SVG renderer ignores `clip-rule`).
    static func outside(_ hole: CGRect, within frame: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: frame.minX, y: frame.minY))
        path.addLine(to: CGPoint(x: frame.maxX, y: frame.minY))
        path.addLine(to: CGPoint(x: frame.maxX, y: frame.maxY))
        path.addLine(to: CGPoint(x: frame.minX, y: frame.maxY))
        path.closeSubpath()
        path.move(to: CGPoint(x: hole.minX, y: hole.minY))
        path.addLine(to: CGPoint(x: hole.minX, y: hole.maxY))
        path.addLine(to: CGPoint(x: hole.maxX, y: hole.maxY))
        path.addLine(to: CGPoint(x: hole.maxX, y: hole.minY))
        path.closeSubpath()
        return path
    }

    // MARK: Paints and definitions

    /// `color` under this painter's washes, its opacity kept.
    private func washed(_ color: PaintColor) -> PaintColor {
        var c = color
        for wash in washes {
            c.red = c.red + (wash.red - c.red) * wash.opacity
            c.green = c.green + (wash.green - c.green) * wash.opacity
            c.blue = c.blue + (wash.blue - c.blue) * wash.opacity
        }
        return c
    }

    /// `fill="…"` or `stroke="…"`, with an opacity when there is one.
    private func paintAttributes(_ paint: Paint, _ kind: String) -> String {
        if case .color(let base) = paint {
            let color = washed(base)
            var text = #"\#(kind)="\#(SVGFormat.hex(color))""#
            if color.opacity < 1 { text += #" \#(kind)-opacity="\#(SVGFormat.fraction(color.opacity))""# }
            return text
        }
        return #"\#(kind)="url(#\#(gradient(paint, recolor: washed)))""#
    }

    /// A gradient definition in user space; its id.
    private func gradient(_ paint: Paint, recolor: (PaintColor) -> PaintColor) -> String {
        func stops(_ stops: [PaintGradient.Stop], remap: (CGFloat) -> CGFloat = { $0 }) -> String {
            let recolored = stops.map { PaintGradient.Stop(color: recolor($0.color), location: $0.location) }
            return Self.premultipliedStops(recolored).map { stop in
                let color = stop.color
                var text = #"<stop offset="\#(SVGFormat.fraction(Double(remap(stop.location))))" stop-color="\#(SVGFormat.hex(color))""#
                if color.opacity < 1 { text += #" stop-opacity="\#(SVGFormat.fraction(color.opacity))""# }
                return text + "/>"
            }.joined()
        }
        let n = { (value: CGFloat) in SVGFormat.number(value, places: places) }
        switch paint {
        case .color:
            preconditionFailure("not a gradient")
        case .linearGradient(let gradient, let start, let end):
            let id = document.makeID("lg")
            document.addDef(#"<linearGradient id="\#(id)" gradientUnits="userSpaceOnUse" x1="\#(n(start.x))" y1="\#(n(start.y))" x2="\#(n(end.x))" y2="\#(n(end.y))">\#(stops(gradient.stops))</linearGradient>"#)
            return id
        case .radialGradient(let gradient, let center, let startRadius, let endRadius):
            // SVG radii start at the center: map the stops onto 0…endRadius.
            let id = document.makeID("rg")
            let r = max(endRadius, 0.0001)
            let remap = { (location: CGFloat) in (startRadius + location * (endRadius - startRadius)) / r }
            document.addDef(#"<radialGradient id="\#(id)" gradientUnits="userSpaceOnUse" cx="\#(n(center.x))" cy="\#(n(center.y))" r="\#(n(r))">\#(stops(gradient.stops, remap: remap))</radialGradient>"#)
            return id
        }
    }

    /// A luminance mask keeping what's under `fade.rect` by the paint's
    /// opacity, and everything outside it.
    private func fadeMask(_ fade: LayerStyle.Fade) -> String {
        let rect = #"<path d="\#(SVGFormat.pathData(Path(fade.rect), places: places))" "#
        let transformAttribute = SVGFormat.transformAttribute(transform)
        if coversAll(fade.rect) {
            // Over the whole picture: the paint redrawn in white.
            let white = { (color: PaintColor) in PaintColor(red: 1, green: 1, blue: 1, opacity: color.opacity) }
            let paint: String
            if case .color(let color) = fade.paint {
                paint = ##"fill="#fff" fill-opacity="\##(SVGFormat.fraction(color.opacity))""##
            } else {
                paint = #"fill="url(#\#(gradient(fade.paint, recolor: white)))""#
            }
            return mask(rect + paint + transformAttribute + "/>")
        }
        // Over part of it: the page in white, then over the rect the paint's
        // clear parts in black. At the rect's soft edges this keeps what a
        // Canvas keeps, and no part of the layer is drawn twice.
        let clearness = { (color: PaintColor) in PaintColor(red: 0, green: 0, blue: 0, opacity: 1 - min(1, max(0, color.opacity))) }
        let paint: String
        if case .color(let color) = fade.paint {
            paint = ##"fill="#000" fill-opacity="\##(SVGFormat.fraction(clearness(color).opacity))""##
        } else {
            paint = #"fill="url(#\#(gradient(fade.paint, recolor: clearness)))""#
        }
        let page = ##"<path d="\##(SVGFormat.pathData(Path(document.bounds)))" fill="#fff"/>"##
        return mask(page + rect + paint + transformAttribute + "/>")
    }

    /// Stops that any SVG renderer draws as a Canvas does.
    ///
    /// A Canvas blends a gradient's colors premultiplied by their opacity,
    /// so a fade from white to clear black stays white. Some SVG renderers
    /// (macOS's own among them) blend the colors and opacities separately,
    /// and that fade turns gray. So a clear stop takes the color of the
    /// stops beside it (two stops at one location when they differ), and
    /// between stops whose color and opacity both change, seven more stops
    /// follow the premultiplied blend. Stops that already agree under both
    /// blends are left as they are.
    static func premultipliedStops(_ stops: [PaintGradient.Stop]) -> [PaintGradient.Stop] {
        func sameColor(_ a: PaintColor, _ b: PaintColor) -> Bool { a.red == b.red && a.green == b.green && a.blue == b.blue }
        func isClear(_ c: PaintColor) -> Bool { !(c.opacity > 0) }
        var out: [PaintGradient.Stop] = []
        out.reserveCapacity(stops.count)
        for (i, stop) in stops.enumerated() {
            let before = i > 0 ? stops[i - 1] : nil
            let after = i + 1 < stops.count ? stops[i + 1] : nil
            if isClear(stop.color) {
                let left = before.flatMap { isClear($0.color) ? nil : $0.color } ?? after.flatMap { isClear($0.color) ? nil : $0.color } ?? stop.color
                let right = after.flatMap { isClear($0.color) ? nil : $0.color } ?? left
                out.append(.init(color: left.opacity(0), location: stop.location))
                if !sameColor(left, right) { out.append(.init(color: right.opacity(0), location: stop.location)) }
                continue
            }
            if let before, !isClear(before.color), !sameColor(before.color, stop.color),
               before.color.opacity != stop.color.opacity, stop.location > before.location {
                let a = before.color, b = stop.color, steps = 8
                for k in 1..<steps {
                    let t = Double(k) / Double(steps)
                    let opacity = a.opacity + (b.opacity - a.opacity) * t
                    func channel(_ x: Double, _ y: Double) -> Double { (x * a.opacity * (1 - t) + y * b.opacity * t) / opacity }
                    out.append(.init(color: PaintColor(red: channel(a.red, b.red), green: channel(a.green, b.green), blue: channel(a.blue, b.blue), opacity: opacity),
                                     location: before.location + (stop.location - before.location) * CGFloat(t)))
                }
            }
            out.append(stop)
        }
        return out
    }

    /// A luminance mask for a layer's opacity, clearing what's under the
    /// cut-outs by their opacity.
    private func layerMask(opacity: Double, cutouts: [LayerStyle.Cutout]) -> String {
        let all = SVGFormat.pathData(Path(document.bounds))
        var content = ##"<path d="\##(all)" fill="#fff""##
        if opacity < 1 { content += #" fill-opacity="\#(SVGFormat.fraction(opacity))""# }
        content += "/>"
        for cutout in cutouts where !cutout.path.isEmpty {
            content += ##"<path d="\##(SVGFormat.pathData(cutout.path, places: places))" fill="#000" fill-opacity="\##(SVGFormat.fraction(cutout.opacity))"\##(SVGFormat.transformAttribute(transform))/>"##
        }
        return mask(content)
    }

    private func mask(_ content: String) -> String {
        let id = document.makeID("mask")
        let area = document.bounds
        let n = { (value: CGFloat) in SVGFormat.number(value) }
        document.addDef(#"<mask id="\#(id)" maskUnits="userSpaceOnUse" x="\#(n(area.minX))" y="\#(n(area.minY))" width="\#(n(area.width))" height="\#(n(area.height))">\#(content)</mask>"#)
        return id
    }

    /// A blur filter of `radius` in this painter's coordinates. The filter
    /// sits on a group in the page's coordinates, so the radius is scaled
    /// along each axis as the transform scales it.
    private func blurFilter(_ radius: CGFloat) -> String {
        let id = document.makeID("blur")
        let sx = radius * hypot(transform.a, transform.c), sy = radius * hypot(transform.b, transform.d)
        let n = { (value: CGFloat) in SVGFormat.number(value) }
        let deviation = n(sx) == n(sy) ? n(sx) : "\(n(sx)) \(n(sy))"
        let area = document.bounds.insetBy(dx: -sx * 3, dy: -sy * 3)
        document.addDef(#"<filter id="\#(id)" filterUnits="userSpaceOnUse" x="\#(n(area.minX))" y="\#(n(area.minY))" width="\#(n(area.width))" height="\#(n(area.height))" color-interpolation-filters="sRGB"><feGaussianBlur stdDeviation="\#(deviation)"/></filter>"#)
        return id
    }
}
