// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2026 Doug C. Hardester

import SwiftUI

/// How a layer is composited onto the drawing.
///
/// ``Painter/drawLayer(_:_:)`` draws its content on its own, then applies
/// the style, in this order:
///
/// 1. ``wash``: a flat color laid over what the layer drew.
/// 2. ``cutouts``: shapes cleared out of the layer.
/// 3. ``fades``: areas where the layer is kept only partly.
/// 4. ``blur``: the whole layer, softened.
/// 5. ``opacity``: the layer drawn onto what's below at this opacity.
///
/// This is the order `GraphicsContext` gives when you draw the same steps by
/// hand in `drawLayer` with blend modes and a blur filter. The SVG output
/// follows it too.
///
/// ```swift
/// // A reflection: see-through, cut by ripples, fading toward the bottom.
/// var reflection = LayerStyle(opacity: 0.35)
/// reflection.cutouts = [.init(path: ripples, opacity: 0.9)]
/// reflection.fades = [.init(rect: water, paint: .linearGradient(
///     PaintGradient(colors: [.black, .black.opacity(0)]),
///     startPoint: CGPoint(x: 0, y: water.minY), endPoint: CGPoint(x: 0, y: water.maxY)))]
/// painter.drawLayer(reflection) { layer in
///     drawBoat(&layer)
/// }
/// ```
///
/// A wash whose rect doesn't cover the whole picture makes the SVG draw the
/// layer's content twice, clipped to either side of the rect. See
/// ``SVGPainter`` for how layers become SVG.
public struct LayerStyle: Equatable, Sendable {
    /// A flat color laid over what a layer drew, inside a rect.
    ///
    /// The color covers only what the layer drew (the source-atop blend
    /// mode), at the color's opacity. Outside the rect, the layer is left
    /// alone.
    public struct Wash: Equatable, Sendable {
        /// The color, and how strongly it covers the layer.
        public var color: PaintColor
        /// Where the wash applies, in the painter's coordinates.
        public var rect: CGRect

        /// A wash.
        ///
        /// - Parameters:
        ///   - color: The color, and how strongly it covers the layer.
        ///   - rect: Where the wash applies.
        @inlinable
        public init(color: PaintColor, rect: CGRect) {
            self.color = color
            self.rect = rect
        }
    }

    /// A shape cleared out of a layer.
    ///
    /// Under `path`, the layer is cleared by `opacity`: 1 leaves a hole, 0.5
    /// leaves half the layer (the destination-out blend mode).
    public struct Cutout: Equatable, Sendable {
        /// The shape to clear, in the painter's coordinates. It's filled with
        /// the nonzero rule.
        public var path: Path
        /// How much to clear, from 0 (nothing) to 1 (all of it).
        public var opacity: Double

        /// A cut-out.
        ///
        /// - Parameters:
        ///   - path: The shape to clear.
        ///   - opacity: How much to clear, from 0 to 1. All of it if you
        ///     leave it out.
        @inlinable
        public init(path: Path, opacity: Double = 1) {
            self.path = path
            self.opacity = opacity
        }
    }

    /// An area where a layer is kept by a paint's opacity.
    ///
    /// Inside `rect`, the layer is kept as much as `paint` is opaque, and
    /// the paint's color doesn't matter (the destination-in blend mode). A
    /// gradient from opaque to clear fades the layer out. Outside `rect`,
    /// the layer is left alone.
    public struct Fade: Equatable, Sendable {
        /// Where the fade applies, in the painter's coordinates.
        public var rect: CGRect
        /// The paint whose opacity says how much of the layer to keep.
        public var paint: Paint

        /// A fade.
        ///
        /// - Parameters:
        ///   - rect: Where the fade applies.
        ///   - paint: The paint whose opacity says how much to keep.
        @inlinable
        public init(rect: CGRect, paint: Paint) {
            self.rect = rect
            self.paint = paint
        }
    }

    /// The layer's opacity when it's drawn onto what's below, from 0 to 1.
    public var opacity: Double
    /// A Gaussian blur over the finished layer. The radius is the blur's
    /// standard deviation, in the painter's coordinates (it grows when the
    /// painter is scaled up). 0 for none.
    public var blur: CGFloat
    /// A flat color laid over what the layer drew, or `nil` for none.
    public var wash: Wash?
    /// Shapes cleared out of the layer, in turn.
    public var cutouts: [Cutout]
    /// Areas where the layer is kept only partly, in turn.
    public var fades: [Fade]

    /// A layer style. Leave out what you don't need.
    ///
    /// - Parameters:
    ///   - opacity: The layer's opacity, from 0 to 1.
    ///   - blur: A Gaussian blur's standard deviation, or 0 for none.
    ///   - wash: A flat color over what the layer drew.
    ///   - cutouts: Shapes cleared out of the layer.
    ///   - fades: Areas where the layer is kept only partly.
    @inlinable
    public init(opacity: Double = 1, blur: CGFloat = 0, wash: Wash? = nil, cutouts: [Cutout] = [], fades: [Fade] = []) {
        self.opacity = opacity
        self.blur = blur
        self.wash = wash
        self.cutouts = cutouts
        self.fades = fades
    }
}
