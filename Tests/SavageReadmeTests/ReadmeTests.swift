// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2026 Doug C. Hardester

import Foundation
import Savage
import SwiftUI
import Testing

/// The README's examples compile (they're in ReadmeExamples.swift), match
/// the README word for word, and work.
@Suite("README")
struct ReadmeTests {
    private static let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// Code blocks with trailing spaces and surrounding blank lines removed.
    private static func normalized(_ block: String) -> String {
        block.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.replacing(/\s+$/, with: "") }
            .joined(separator: "\n")
            .trimmingCharacters(in: .newlines)
    }

    @Test func theReadmeShowsTheCompiledExamples() throws {
        let readme = try String(contentsOf: Self.root.appending(path: "README.md"), encoding: .utf8)
        let examples = try String(contentsOf: URL(filePath: #filePath).deletingLastPathComponent().appending(path: "ReadmeExamples.swift"), encoding: .utf8)
        // Every Swift block but the manifest fragment under Installation.
        let shown = readme.matches(of: /```swift\n([\s\S]*?)```/).map { Self.normalized(String($0.1)) }
            .filter { !$0.hasPrefix("dependencies: [") }
        let compiled = examples.matches(of: /\/\/ README: begin\n([\s\S]*?)\/\/ README: end/).map { Self.normalized(String($0.1)) }
        #expect(!compiled.isEmpty)
        #expect(shown == compiled, "Update README.md or ReadmeExamples.swift so their Swift code matches.")
    }

    @Test func theSunsetExportsAsSVG() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "Savage-Sunset-\(UUID().uuidString).svg")
        defer { try? FileManager.default.removeItem(at: url) }
        try exportSunset(to: url)
        let data = try Data(contentsOf: url)
        let parser = XMLParser(data: data)
        #expect(parser.parse())
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains(#"viewBox="0 0 600 380""#))
        #expect(text.contains("<title>Sunset</title>"))
        #expect(text.contains("<radialGradient"))
    }

    @Test func theReflectionWritesALayer() throws {
        let size = CGSize(width: 600, height: 380)
        let document = SVGDocument(size: size)
        document.draw { painter in
            Sunset().draw(&painter, size: size)
            drawReflection(&painter, of: Sunset(), size: size)
        }
        let text = document.svgString
        #expect(XMLParser(data: document.svgData).parse())
        #expect(text.contains("<feGaussianBlur"))
        #expect(text.contains("<mask"))
        #expect(text.contains("<clipPath"))
    }

    @MainActor
    @Test func theViewDraws() throws {
        let renderer = ImageRenderer(content: SunsetView().frame(width: 300, height: 190))
        let image = try #require(renderer.cgImage)
        #expect(image.width == 300)
        // The sun is in the middle of the right half.
        let context = try #require(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = try #require(context.data).bindMemory(to: UInt8.self, capacity: image.width * image.height * 4)
        let sun = (Int(190 * 0.62) * image.width + Int(300 * 0.65)) * 4
        #expect(bytes[sun] == 0xFF && bytes[sun + 1] == 0xB8 && bytes[sun + 2] == 0x6C)
    }
}
