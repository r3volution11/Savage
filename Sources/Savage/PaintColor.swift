// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2026 Doug C. Hardester

import SwiftUI

/// A color in the sRGB color space, with an opacity.
///
/// Savage paints with `PaintColor` instead of SwiftUI's `Color`. An SVG needs
/// a color's exact components, and a `Color` can change with the
/// environment it's drawn in (light or dark, accessibility settings).
/// An `PaintColor` is always the same four numbers.
///
/// Each component runs from 0 to 1. Keep them in that range: the SVG output
/// clamps them, and a Canvas may not.
///
/// ```swift
/// let night = PaintColor(hex: 0x1D2B53)
/// let haze = night.mix(with: .white, by: 0.3).opacity(0.5)
/// ```
public struct PaintColor: Hashable, Sendable {
    /// The red component, from 0 to 1.
    public var red: Double
    /// The green component, from 0 to 1.
    public var green: Double
    /// The blue component, from 0 to 1.
    public var blue: Double
    /// The opacity, from 0 (transparent) to 1 (opaque).
    public var opacity: Double

    /// A color from its sRGB components.
    ///
    /// - Parameters:
    ///   - red: The red component, from 0 to 1.
    ///   - green: The green component, from 0 to 1.
    ///   - blue: The blue component, from 0 to 1.
    ///   - opacity: The opacity, from 0 to 1. Opaque if you leave it out.
    @inlinable
    public init(red: Double, green: Double, blue: Double, opacity: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.opacity = opacity
    }

    /// A color from a 24-bit hex value, written `0xRRGGBB`.
    ///
    /// ```swift
    /// let orange = PaintColor(hex: 0xFF8000)
    /// ```
    ///
    /// - Parameters:
    ///   - hex: The red, green and blue bytes, most significant first.
    ///     Bits above the lowest 24 are ignored.
    ///   - opacity: The opacity, from 0 to 1. Opaque if you leave it out.
    @inlinable
    public init(hex: UInt32, opacity: Double = 1) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }

    // White and black are computed and inlinable, not stored, so the
    // compiler can fold them into constants in your code (a stored static
    // in another module can't be), and arrays of stops built from them need
    // no allocation.

    /// Opaque white.
    @inlinable
    public static var white: PaintColor { PaintColor(red: 1, green: 1, blue: 1) }

    /// Opaque black.
    @inlinable
    public static var black: PaintColor { PaintColor(red: 0, green: 0, blue: 0) }

    /// This color with its opacity multiplied by `opacity`, like SwiftUI's
    /// `Color.opacity(_:)`.
    ///
    /// To fade a gradient to nothing, end it on the same color at opacity 0,
    /// not on a different transparent color. Gradients blend each component
    /// on its own, so fading white to transparent black passes through gray.
    ///
    /// - Parameter opacity: The factor, from 0 to 1.
    /// - Returns: The same color, more transparent.
    @inlinable
    public func opacity(_ opacity: Double) -> PaintColor {
        PaintColor(red: red, green: green, blue: blue, opacity: self.opacity * opacity)
    }

    /// The color `fraction` of the way from this color to `other`.
    ///
    /// Each component, opacity included, moves in a straight line, in sRGB.
    ///
    /// - Parameters:
    ///   - other: The color to move toward.
    ///   - fraction: How far to go: 0 is this color, 1 is `other`.
    /// - Returns: The mixed color.
    @inlinable
    public func mix(with other: PaintColor, by fraction: Double) -> PaintColor {
        PaintColor(red: red + (other.red - red) * fraction,
                 green: green + (other.green - green) * fraction,
                 blue: blue + (other.blue - blue) * fraction,
                 opacity: opacity + (other.opacity - opacity) * fraction)
    }
}

/// Savage adds a way to make a SwiftUI color from a ``PaintColor``.
extension Color {
    /// A SwiftUI color with the same sRGB components and opacity.
    ///
    /// Use it to share a palette between a drawing and the rest of your
    /// views.
    ///
    /// - Parameter color: The color to convert.
    @inlinable
    public init(_ color: PaintColor) {
        self.init(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: color.opacity)
    }
}
