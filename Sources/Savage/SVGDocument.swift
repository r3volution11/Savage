// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2026 Doug C. Hardester

import Foundation
import SwiftUI

/// A standalone SVG, written by drawing into it with an ``SVGPainter``.
///
/// ```swift
/// let size = CGSize(width: 320, height: 200)
/// let document = SVGDocument(size: size, title: "Badge")
/// document.draw { painter in
///     drawBadge(&painter, size: size)
/// }
/// let text = document.svgString
/// try document.write(to: url)
/// ```
///
/// The output is all vectors (paths, gradients, clip paths, masks and blur
/// filters), with no embedded images. It's compact and deterministic: the
/// same drawing always gives the same bytes.
///
/// - Coordinates are rounded to a hundredth of a point on the page. Under a
///   transform that enlarges, they get more decimal places, so a drawing in
///   unit coordinates scaled up keeps its precision.
/// - Gradients, clips, masks and filters are defined once in `<defs>`, with
///   ids from a counter (`lg1`, `clip2`, …). Groups you name keep your
///   name as their id, made valid and unique.
/// - Text you give, such as the title, is escaped.
///
/// An `SVGDocument` is a reference type: every painter drawing into it adds
/// to the same document. It isn't thread-safe; draw into it from one thread
/// at a time.
public final class SVGDocument {
    /// The picture's size in points. The SVG's `viewBox` is
    /// `0 0 width height`.
    public let size: CGSize

    /// A title for the SVG's `<title>` element (what screen readers and
    /// some viewers show), or `nil` for none.
    public var title: String?

    /// Whether the root element gets `width` and `height` attributes, in
    /// points. It always gets a `viewBox`. Without a size, the SVG scales
    /// to whatever shows it.
    public var includesSize: Bool

    private var defs: [String] = []
    private var body: [String] = []
    /// The groups now open in `body`, outermost first.
    private var open: [Group] = []
    private var serial = 0
    /// Every `id` given out so far, generated or named.
    private var ids: Set<String> = []

    /// A `<g>` with its attributes. Each one is distinct, so two groups with
    /// the same attributes are never merged.
    struct Group: Equatable {
        let serial: Int
        let attributes: String
    }

    /// An empty document.
    ///
    /// - Parameters:
    ///   - size: The picture's size in points.
    ///   - title: A title for the SVG's `<title>` element, or `nil`.
    ///   - includesSize: Whether to write `width` and `height` on the root
    ///     element. It always gets a `viewBox`.
    public init(size: CGSize, title: String? = nil, includesSize: Bool = true) {
        self.size = size
        self.title = title
        self.includesSize = includesSize
    }

    /// Draws into the document with a new ``SVGPainter``.
    ///
    /// You can call it more than once: each drawing goes on top of the
    /// last.
    ///
    /// - Parameter content: The drawing.
    public func draw(_ content: (inout SVGPainter) throws -> Void) rethrows {
        var painter = SVGPainter(document: self)
        try content(&painter)
    }

    /// The finished SVG, as text (UTF-8, with an XML declaration).
    ///
    /// Reading it doesn't end the document: you can keep drawing and read
    /// it again.
    public var svgString: String {
        let w = SVGFormat.number(size.width), h = SVGFormat.number(size.height)
        let dimensions = includesSize ? #" width="\#(w)" height="\#(h)""# : ""
        var lines = [
            #"<?xml version="1.0" encoding="UTF-8"?>"#,
            #"<svg xmlns="http://www.w3.org/2000/svg"\#(dimensions) viewBox="0 0 \#(w) \#(h)">"#,
        ]
        if let title { lines.append("<title>\(SVGFormat.escaped(title))</title>") }
        if !defs.isEmpty {
            lines.append("<defs>")
            lines += defs
            lines.append("</defs>")
        }
        lines += body
        lines += Array(repeating: "</g>", count: open.count)
        lines.append("</svg>")
        return lines.joined(separator: "\n") + "\n"
    }

    /// The finished SVG, as UTF-8 data.
    public var svgData: Data {
        Data(svgString.utf8)
    }

    /// Writes the finished SVG to a file, replacing any file already there.
    ///
    /// - Parameter url: Where to write it, usually ending in `.svg`.
    /// - Throws: The error from writing the file.
    public func write(to url: URL) throws {
        try svgData.write(to: url, options: .atomic)
    }

    // MARK: Building

    /// The picture's area, in points.
    var bounds: CGRect { CGRect(origin: .zero, size: size) }

    /// A new id for a definition: `prefix` and a number, never one given
    /// out before.
    func makeID(_ prefix: String) -> String {
        var id: String
        repeat {
            serial += 1
            id = "\(prefix)\(serial)"
        } while ids.contains(id)
        ids.insert(id)
        return id
    }

    /// A new group with `attributes`.
    func group(_ attributes: String) -> Group {
        serial += 1
        return Group(serial: serial, attributes: attributes)
    }

    /// An `id` for a named group: the name made valid, and unique if it's
    /// used again (`moon`, `moon-2`).
    func uniqueName(_ name: String) -> String {
        let base = SVGFormat.identifier(name)
        var candidate = base
        var n = 1
        while ids.contains(candidate) {
            n += 1
            candidate = "\(base)-\(n)"
        }
        ids.insert(candidate)
        return candidate
    }

    /// Adds a definition to `<defs>`.
    func addDef(_ text: String) {
        defs.append(text)
    }

    /// Writes `element` inside the groups `chain`, reusing the groups
    /// already open where they match.
    func emit(_ element: String, in chain: [Group]) {
        var shared = 0
        while shared < open.count, shared < chain.count, open[shared] == chain[shared] { shared += 1 }
        for _ in shared..<open.count { body.append("</g>") }
        open.removeLast(open.count - shared)
        for group in chain[shared...] {
            body.append("<g \(group.attributes)>")
            open.append(group)
        }
        body.append(element)
    }
}

@available(*, unavailable, message: "An SVGDocument isn't thread-safe; draw into it from one thread at a time.")
extension SVGDocument: @unchecked Sendable {}
