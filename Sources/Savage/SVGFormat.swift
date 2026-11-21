// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2026 Doug C. Hardester

import Foundation
import SwiftUI

/// How values are written in SVG: short, exact to the precision asked for,
/// and the same every time.
enum SVGFormat {
    /// Ten to the power of 0 through 8, exactly.
    private static let powers: [Double] = [1, 10, 100, 1_000, 10_000, 100_000, 1_000_000, 10_000_000, 100_000_000]

    /// The most decimal places a number is written with.
    static let maxPlaces = 8

    /// `value` rounded to `places` decimal places, without trailing zeros
    /// or an exponent: `12`, `-0.5`, `10.26`. Zero (and negative zero) is
    /// `0`. A value that isn't finite is written as `0`, so the document
    /// stays valid.
    static func number(_ value: CGFloat, places: Int = 2) -> String {
        guard value.isFinite else { return "0" }
        let places = min(max(places, 0), maxPlaces)
        let scale = powers[places]
        let units = (Double(value) * scale).rounded()
        if units == 0 { return "0" }
        // Past what an Int64 holds exactly, there are no decimals to write.
        guard abs(units) < 9e15 else { return String(format: "%.0f", Double(value)) }
        let magnitude = UInt64(abs(units))
        let divisor = UInt64(scale)
        var text = units < 0 ? "-" : ""
        text += String(magnitude / divisor)
        let remainder = magnitude % divisor
        if remainder > 0 {
            var digits = String(remainder)
            digits = String(repeating: "0", count: places - digits.count) + digits
            while digits.last == "0" { digits.removeLast() }
            text += "." + digits
        }
        return text
    }

    /// An opacity or a gradient offset: clamped to 0…1, to four places.
    static func fraction(_ value: Double) -> String {
        number(min(1, max(0, value)), places: 4)
    }

    /// A color as `#rrggbb`, each component clamped to 0…1. Opacity is
    /// written separately.
    static func hex(_ color: PaintColor) -> String {
        func byte(_ v: Double) -> Int {
            guard v.isFinite else { return 0 }
            return Int((min(1, max(0, v)) * 255).rounded())
        }
        let value = byte(color.red) << 16 | byte(color.green) << 8 | byte(color.blue)
        let digits = String(value, radix: 16, uppercase: false)
        return "#" + String(repeating: "0", count: 6 - digits.count) + digits
    }

    /// A path's `d` attribute: absolute commands, no spaces between a
    /// command and its first number.
    static func pathData(_ path: Path, places: Int = 2) -> String {
        var d = ""
        func add(_ p: CGPoint) {
            d += number(p.x, places: places)
            d += " "
            d += number(p.y, places: places)
        }
        path.forEach { element in
            switch element {
            case .move(let p):
                d += "M"; add(p)
            case .line(let p):
                d += "L"; add(p)
            case .quadCurve(let p, let c):
                d += "Q"; add(c); d += " "; add(p)
            case .curve(let p, let c1, let c2):
                d += "C"; add(c1); d += " "; add(c2); d += " "; add(p)
            case .closeSubpath:
                d += "Z"
            }
        }
        return d
    }

    /// A ` transform="matrix(…)"` attribute, with its leading space, or
    /// nothing for the identity.
    static func transformAttribute(_ t: CGAffineTransform) -> String {
        guard !t.isIdentity else { return "" }
        let values = [t.a, t.b, t.c, t.d].map { number($0, places: 6) } + [t.tx, t.ty].map { number($0, places: 2) }
        return #" transform="matrix(\#(values.joined(separator: " ")))""#
    }

    /// How many decimal places keep coordinates drawn under `t` within a
    /// hundredth of a point on the page: two, plus one for each power of
    /// ten `t` enlarges by.
    static func places(for t: CGAffineTransform) -> Int {
        // The most `t` stretches any length (its largest singular value).
        let f2 = t.a * t.a + t.b * t.b + t.c * t.c + t.d * t.d
        let det = t.a * t.d - t.b * t.c
        let stretch = ((f2 + max(0, f2 * f2 - 4 * det * det).squareRoot()) / 2).squareRoot()
        guard stretch.isFinite, stretch > 1 else { return 2 }
        return min(maxPlaces, 2 + max(0, Int((log10(stretch) - 1e-6).rounded(.up))))
    }

    /// `text` safe inside an element or an attribute value: `&`, `<`, `>`
    /// and `"` escaped, and characters XML doesn't allow left out.
    static func escaped(_ text: String) -> String {
        var out = ""
        out.unicodeScalars.reserveCapacity(text.unicodeScalars.count)
        for scalar in text.unicodeScalars {
            switch scalar {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            default:
                let v = scalar.value
                if v == 0x9 || v == 0xA || v == 0xD || (0x20...0xD7FF).contains(v) || (0xE000...0xFFFD).contains(v) || v >= 0x10000 {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out
    }

    /// `name` as a valid XML `id`: letters, digits, `-`, `_` and `.` are
    /// kept, anything else becomes `-`, and a name that can't start an id
    /// gets a leading `_`.
    static func identifier(_ name: String) -> String {
        var out = String.UnicodeScalarView()
        for scalar in name.unicodeScalars {
            let v = scalar.value
            let ascii = (0x41...0x5A).contains(v) || (0x61...0x7A).contains(v) || (0x30...0x39).contains(v) || v == 0x2D || v == 0x5F || v == 0x2E
            out.append(ascii || (v >= 0xC0 && scalar.properties.isAlphabetic) ? scalar : "-")
        }
        guard let first = out.first else { return "group" }
        if (0x30...0x39).contains(first.value) || first == "-" || first == "." { out.insert("_", at: out.startIndex) }
        return String(out)
    }
}
