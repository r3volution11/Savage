// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2026 Doug C. Hardester

import SwiftUI

/// What a fill or a stroke is painted with: a flat color, or a linear or
/// radial gradient.
///
/// `Paint` mirrors the parts of `GraphicsContext.Shading` that have an exact
/// SVG counterpart. Gradient points and radii are in the drawing's own
/// coordinates (the painter's, with its current transform), not relative to
/// the shape. Past their ends, gradients continue in their end colors.
///
/// ```swift
/// painter.fill(circle, with: .color(.white))
/// painter.fill(sky, with: .linearGradient(gradient, startPoint: .zero, endPoint: CGPoint(x: 0, y: 200)))
/// painter.fill(glow, with: .radialGradient(halo, center: sun, startRadius: 10, endRadius: 40))
/// ```
public enum Paint: Hashable, Sendable {
    /// A flat color.
    case color(PaintColor)

    /// A gradient along the line from `startPoint` to `endPoint`.
    ///
    /// The colors change along that line and stay the same across it.
    case linearGradient(PaintGradient, startPoint: CGPoint, endPoint: CGPoint)

    /// A gradient in circles around `center`, from `startRadius` (the first
    /// stop) to `endRadius` (the last).
    ///
    /// Inside `startRadius` the paint is the first stop's color. For an
    /// elliptical gradient, scale the painter before you fill.
    case radialGradient(PaintGradient, center: CGPoint, startRadius: CGFloat, endRadius: CGFloat)

    /// The same paint as a `GraphicsContext` shading.
    ///
    /// ``CanvasPainter`` uses this. It's here so you can fill with a `Paint`
    /// directly on a `GraphicsContext` too.
    @inlinable
    public var shading: GraphicsContext.Shading {
        switch self {
        case .color(let color):
            .color(Color(color))
        case .linearGradient(let gradient, let startPoint, let endPoint):
            .linearGradient(Gradient(gradient), startPoint: startPoint, endPoint: endPoint)
        case .radialGradient(let gradient, let center, let startRadius, let endRadius):
            .radialGradient(Gradient(gradient), center: center, startRadius: startRadius, endRadius: endRadius)
        }
    }
}
