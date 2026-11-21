// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2026 Doug C. Hardester

import Foundation
import Testing

/// An element of a parsed SVG, for tests to look into.
final class Element {
    let name: String
    let attributes: [String: String]
    var children: [Element] = []
    var text = ""
    weak var parent: Element?

    init(name: String, attributes: [String: String]) {
        self.name = name
        self.attributes = attributes
    }

    subscript(_ attribute: String) -> String? { attributes[attribute] }

    /// Direct children named `name`.
    func children(_ name: String) -> [Element] { children.filter { $0.name == name } }

    /// Every element named `name` below this one, in document order.
    func all(_ name: String) -> [Element] {
        children.flatMap { ($0.name == name ? [$0] : []) + $0.all(name) }
    }

    /// Every element below this one.
    var descendants: [Element] { children.flatMap { [$0] + $0.descendants } }
}

struct XMLParseError: Error, CustomStringConvertible {
    let description: String
}

/// Parses `text` with Foundation's XMLParser, which fails on anything that
/// isn't well-formed XML.
func parseXML(_ text: String) throws -> Element {
    let builder = TreeBuilder()
    let parser = XMLParser(data: Data(text.utf8))
    parser.delegate = builder
    guard parser.parse(), let root = builder.root else {
        throw XMLParseError(description: "Not well-formed XML: \(parser.parserError.map { "\($0)" } ?? "no root") at line \(parser.lineNumber)")
    }
    return root
}

/// Parses an SVG and checks what every Savage document must be: an `svg`
/// root in the SVG namespace with a viewBox, unique ids, and every
/// `url(#…)` reference resolving to one of them.
func parseSVG(_ text: String, sourceLocation: SourceLocation = #_sourceLocation) throws -> Element {
    let root = try parseXML(text)
    #expect(root.name == "svg", sourceLocation: sourceLocation)
    #expect(root["xmlns"] == "http://www.w3.org/2000/svg", sourceLocation: sourceLocation)
    #expect(root["viewBox"] != nil, sourceLocation: sourceLocation)
    var ids = Set<String>()
    for element in root.descendants {
        if let id = element["id"] {
            #expect(ids.insert(id).inserted, "duplicate id \(id)", sourceLocation: sourceLocation)
        }
    }
    for match in text.matches(of: /url\(#([^)]+)\)/) {
        #expect(ids.contains(String(match.1)), "unresolved reference \(match.1)", sourceLocation: sourceLocation)
    }
    return root
}

private final class TreeBuilder: NSObject, XMLParserDelegate {
    var root: Element?
    private var stack: [Element] = []

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let element = Element(name: elementName, attributes: attributeDict)
        if let parent = stack.last {
            element.parent = parent
            parent.children.append(element)
        } else {
            root = element
        }
        stack.append(element)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        stack.removeLast()
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        stack.last?.text += string
    }
}
