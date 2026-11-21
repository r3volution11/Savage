// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2026 Doug C. Hardester

import SwiftUI

/// The colors of a gradient, at locations from 0 to 1.
///
/// It works like SwiftUI's `Gradient`, with ``PaintColor`` colors. Where the
/// gradient starts and ends, and whether it's linear or radial, is up to the
/// ``Paint`` that uses it.
///
/// ```swift
/// let sky = PaintGradient(colors: [PaintColor(hex: 0x1D2B53), PaintColor(hex: 0xFF77A8)])
/// let fade = PaintGradient(stops: [
///     .init(color: .black, location: 0),
///     .init(color: .black.opacity(0), location: 0.8),
/// ])
/// ```
public struct PaintGradient: Hashable, Sendable {
    /// One color in a gradient, and where it is.
    public struct Stop: Hashable, Sendable {
        /// The color at this stop.
        public var color: PaintColor
        /// Where the stop is, from 0 (the gradient's start) to 1 (its end).
        public var location: CGFloat

        /// A gradient stop.
        ///
        /// - Parameters:
        ///   - color: The color at this stop.
        ///   - location: Where the stop is, from 0 to 1.
        @inlinable
        public init(color: PaintColor, location: CGFloat) {
            self.color = color
            self.location = location
        }
    }

    /// The stops, in order of location.
    ///
    /// Keep them in order. Past the first and last stops, the gradient
    /// continues in their colors.
    public var stops: [Stop]

    /// A gradient from its stops.
    ///
    /// - Parameter stops: The stops, in order of location.
    @inlinable
    public init(stops: [Stop]) {
        self.stops = stops
    }

    /// A gradient through `colors`, spaced evenly from 0 to 1.
    ///
    /// - Parameter colors: The colors, from start to end.
    @inlinable
    public init(colors: [PaintColor]) {
        let last = CGFloat(Swift.max(1, colors.count - 1))
        stops = colors.enumerated().map { Stop(color: $0.element, location: CGFloat($0.offset) / last) }
    }
}

/// Savage adds a way to make a SwiftUI gradient from a ``PaintGradient``.
extension Gradient {
    /// A SwiftUI gradient with the same colors and locations.
    ///
    /// - Parameter gradient: The gradient to convert.
    @inlinable
    public init(_ gradient: PaintGradient) {
        self.init(stops: gradient.stops.map { Gradient.Stop(color: Color($0.color), location: $0.location) })
    }
}
