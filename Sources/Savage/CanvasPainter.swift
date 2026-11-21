// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2026 Doug C. Hardester

import SwiftUI

/// A painter that draws through a SwiftUI `GraphicsContext`.
///
/// Make one in a `Canvas` and hand it to your drawing:
///
/// ```swift
/// Canvas { context, size in
///     var painter = CanvasPainter(context: context)
///     drawBadge(&painter, size: size)
/// }
/// ```
///
/// It's a thin wrapper: each call becomes the matching `GraphicsContext`
/// call, and layers use `drawLayer` with blend modes and a blur filter. Its
/// methods are always inlined into your drawing (`drawLayer` is inlinable),
/// so a drawing specialized for `CanvasPainter` costs the same as one
/// written against `GraphicsContext` directly.
///
/// The painter draws with the context's own settings too. If you set the
/// context's blend mode, filters or shadows before you wrap it, the canvas
/// shows them and an SVG won't.
public struct CanvasPainter: Painter {
    /// The context this painter draws into.
    public var context: GraphicsContext

    /// A painter that draws into `context`.
    ///
    /// - Parameter context: The context to draw into, usually the one a
    ///   `Canvas` passes to its renderer.
    @inlinable @inline(__always)
    public init(context: GraphicsContext) {
        self.context = context
    }

    /// Fills `path` with `paint`. See ``Painter/fill(_:with:style:)``.
    @inlinable @inline(__always)
    public func fill(_ path: Path, with paint: Paint, style: FillStyle) {
        context.fill(path, with: paint.shading, style: style)
    }

    /// Strokes `path` with `paint`. See ``Painter/stroke(_:with:style:)``.
    @inlinable @inline(__always)
    public func stroke(_ path: Path, with paint: Paint, style: StrokeStyle) {
        context.stroke(path, with: paint.shading, style: style)
    }

    /// Clips what this painter draws from now on. See ``Painter/clip(to:)``.
    @inlinable @inline(__always)
    public mutating func clip(to path: Path) {
        context.clip(to: path)
    }

    /// Moves the origin. See ``Painter/translateBy(x:y:)``.
    @inlinable @inline(__always)
    public mutating func translateBy(x: CGFloat, y: CGFloat) {
        context.translateBy(x: x, y: y)
    }

    /// Scales the drawing. See ``Painter/scaleBy(x:y:)``.
    @inlinable @inline(__always)
    public mutating func scaleBy(x: CGFloat, y: CGFloat) {
        context.scaleBy(x: x, y: y)
    }

    /// Rotates the drawing. See ``Painter/rotate(by:)``.
    @inlinable @inline(__always)
    public mutating func rotate(by angle: Angle) {
        context.rotate(by: angle)
    }

    /// Adds a transform. See ``Painter/concatenate(_:)``.
    @inlinable @inline(__always)
    public mutating func concatenate(_ matrix: CGAffineTransform) {
        context.concatenate(matrix)
    }

    /// Draws `content` as a layer composited with `style`. See
    /// ``Painter/drawLayer(_:_:)``.
    @inlinable
    public func drawLayer(_ style: LayerStyle, _ content: (inout CanvasPainter) throws -> Void) rethrows {
        var host = context
        if style.opacity < 1 { host.opacity *= style.opacity }
        try host.drawLayer { layer in
            // A filter added to a layer's context applies to the finished
            // layer, after the blend-mode fills below.
            if style.blur > 0 { layer.addFilter(.blur(radius: style.blur)) }
            var inner = CanvasPainter(context: layer)
            try content(&inner)
            if let wash = style.wash {
                layer.blendMode = .sourceAtop
                layer.fill(Path(wash.rect), with: .color(Color(wash.color)))
            }
            if !style.cutouts.isEmpty {
                layer.blendMode = .destinationOut
                for cutout in style.cutouts {
                    layer.fill(cutout.path, with: .color(.black.opacity(cutout.opacity)))
                }
            }
            if !style.fades.isEmpty {
                layer.blendMode = .destinationIn
                for fade in style.fades {
                    layer.fill(Path(fade.rect), with: fade.paint.shading)
                }
            }
        }
    }

    /// Draws `content` as is: a name only matters in an SVG. See
    /// ``Painter/group(_:_:)``.
    @inlinable @inline(__always)
    public func group(_ name: String, _ content: (inout CanvasPainter) throws -> Void) rethrows {
        var inner = self
        try content(&inner)
    }
}
