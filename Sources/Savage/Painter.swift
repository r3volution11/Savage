// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2026 Doug C. Hardester

import SwiftUI

/// Something a drawing can paint on: on screen, or into an SVG.
///
/// Write your drawing once, generic over `Painter`, and run it with either
/// backend:
///
/// - ``CanvasPainter`` draws through a SwiftUI `GraphicsContext`, in a
///   `Canvas`.
/// - ``SVGPainter`` writes the same drawing into an ``SVGDocument``, as
///   vectors.
///
/// ```swift
/// func drawBadge<P: Painter>(_ painter: inout P, size: CGSize) {
///     let frame = CGRect(origin: .zero, size: size)
///     painter.fill(Path(ellipseIn: frame), with: .color(PaintColor(hex: 0x3366CC)))
///     painter.stroke(Path(ellipseIn: frame.insetBy(dx: 4, dy: 4)), with: .color(.white), lineWidth: 2)
/// }
/// ```
///
/// The methods work like their `GraphicsContext` namesakes. Coordinates are
/// in points, with the origin at the top left and y pointing down.
///
/// A painter is a value. Changing a copy's clip or transform leaves the
/// original alone, which is how you scope them:
///
/// ```swift
/// var clipped = painter
/// clipped.clip(to: window)
/// clipped.fill(view, with: .color(sky))   // inside the window only
/// painter.fill(frame, with: .color(wood)) // not clipped
/// ```
///
/// Make your drawing generic (`<P: Painter>`) rather than taking
/// `any Painter`, so the compiler can specialize it for each backend.
public protocol Painter {
    /// Fills `path` with `paint`.
    ///
    /// - Parameters:
    ///   - path: The shape to fill.
    ///   - paint: A color or a gradient.
    ///   - style: The fill rule: nonzero, or even-odd with
    ///     `FillStyle(eoFill: true)`. Antialiasing is always on in SVG.
    func fill(_ path: Path, with paint: Paint, style: FillStyle)

    /// Strokes the outline of `path` with `paint`.
    ///
    /// - Parameters:
    ///   - path: The outline to stroke.
    ///   - paint: A color or a gradient.
    ///   - style: The line width, caps, joins, miter limit and dashes.
    func stroke(_ path: Path, with paint: Paint, style: StrokeStyle)

    /// Clips everything this painter draws from now on to `path`, filled
    /// with the nonzero rule.
    ///
    /// Clips add up: a second clip keeps only what's inside both. Copies
    /// made earlier keep their own clip.
    ///
    /// - Parameter path: The area to keep, in the painter's coordinates.
    mutating func clip(to path: Path)

    /// Moves the origin of what this painter draws from now on.
    ///
    /// - Parameters:
    ///   - x: The distance to move right.
    ///   - y: The distance to move down.
    mutating func translateBy(x: CGFloat, y: CGFloat)

    /// Scales what this painter draws from now on.
    ///
    /// - Parameters:
    ///   - x: The horizontal factor.
    ///   - y: The vertical factor.
    mutating func scaleBy(x: CGFloat, y: CGFloat)

    /// Rotates what this painter draws from now on, about the origin.
    ///
    /// - Parameter angle: The angle. Positive angles turn clockwise on
    ///   screen, as in `GraphicsContext`.
    mutating func rotate(by angle: Angle)

    /// Applies `matrix` to what this painter draws from now on, before the
    /// transform it already has.
    ///
    /// - Parameter matrix: The transform to add.
    mutating func concatenate(_ matrix: CGAffineTransform)

    /// Draws `content` as a separate layer, then composites it with `style`.
    ///
    /// The layer is drawn on its own, then washed, cut, faded, blurred and
    /// drawn at its opacity. See ``LayerStyle``. The painter passed to
    /// `content` starts with this painter's clip and transform.
    ///
    /// `content` may be called more than once (the SVG backend draws a
    /// layer twice for a wash or fade that covers only part of the
    /// picture). Draw the same thing each time.
    ///
    /// - Parameters:
    ///   - style: How to composite the layer.
    ///   - content: The layer's drawing.
    func drawLayer(_ style: LayerStyle, _ content: (inout Self) throws -> Void) rethrows

    /// A named part of the drawing.
    ///
    /// In an SVG, `content` goes in a group (`<g>`) with `name` as its `id`.
    /// On screen it draws as usual. The painter passed to `content` starts
    /// with this painter's clip and transform.
    ///
    /// - Parameters:
    ///   - name: The part's name. The SVG makes it a valid, unique `id`.
    ///   - content: The part's drawing.
    func group(_ name: String, _ content: (inout Self) throws -> Void) rethrows
}

extension Painter {
    /// Fills `path` with `paint`, with the nonzero rule.
    ///
    /// - Parameters:
    ///   - path: The shape to fill.
    ///   - paint: A color or a gradient.
    @inlinable
    public func fill(_ path: Path, with paint: Paint) {
        fill(path, with: paint, style: FillStyle())
    }

    /// Strokes the outline of `path` with `paint`, `lineWidth` wide, with
    /// butt caps and miter joins.
    ///
    /// - Parameters:
    ///   - path: The outline to stroke.
    ///   - paint: A color or a gradient.
    ///   - lineWidth: The line's width. 1 point if you leave it out.
    @inlinable
    public func stroke(_ path: Path, with paint: Paint, lineWidth: CGFloat = 1) {
        stroke(path, with: paint, style: StrokeStyle(lineWidth: lineWidth))
    }
}
