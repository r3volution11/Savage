# Savage

Draw once with SwiftUI's graphics. Get the same picture live on screen and as a true-vector SVG.

You write a drawing once, against a small `Painter` protocol. In your app, `CanvasPainter` draws it in a SwiftUI `Canvas`. When you want a file, `SVGPainter` writes the same drawing as an SVG: paths, gradients, clip paths and masks. There are no pixels in it.

## Why

SwiftUI can draw almost anything in a `Canvas`, but it can't save that drawing as vectors. `ImageRenderer` turns a `Canvas` into pixels, even when it renders into a PDF. So an exported picture is a bitmap at one size.

Savage gives you an SVG instead. It stays sharp at any size, it's small, and you can open it in a browser or a vector editor. Both outputs come from the same drawing code, so they can't drift apart.

Savage started as the drawing layer for the welcome screen of [Vela](https://velairc.app), an IRC client for the Mac. The night scene there has about 400 shapes and 200 gradients, with clips, masks and a blur. Its SVG and its Canvas match to within about half a level of 255 per channel, on average.

## Requirements

- Swift 6 (Xcode 16 or later)
- macOS 13, iOS 16, tvOS 16, watchOS 9 or visionOS 1
- No other dependencies

## Installation

Add Savage with Swift Package Manager. In `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/r3volution11/Savage", from: "0.1.0"),
],
```

Then add `.product(name: "Savage", package: "Savage")` to your target's dependencies.

In Xcode, choose **File ▸ Add Package Dependencies…** and enter `https://github.com/r3volution11/Savage`.

## Quick start

**1. Write the drawing.** Make it generic over `Painter`. The calls work like `GraphicsContext`'s: points, origin at the top left, y pointing down.

```swift
import Savage
import SwiftUI

/// A sunset: a sky, a glowing sun and a hill.
struct Sunset {
    var sky = PaintColor(hex: 0x2B3A67)
    var sun = PaintColor(hex: 0xFFB86C)
    var hill = PaintColor(hex: 0x1B2A41)

    func draw<P: Painter>(_ painter: inout P, size: CGSize) {
        let w = size.width, h = size.height

        // The sky, lighter toward the horizon.
        painter.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
            PaintGradient(colors: [sky, sky.mix(with: sun, by: 0.6)]),
            startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))

        // The sun, with a soft glow around it.
        let center = CGPoint(x: w * 0.65, y: h * 0.62)
        let r = h * 0.1
        painter.fill(Path(ellipseIn: CGRect(x: center.x - 3 * r, y: center.y - 3 * r, width: 6 * r, height: 6 * r)),
                     with: .radialGradient(PaintGradient(colors: [sun.opacity(0.6), sun.opacity(0)]),
                                           center: center, startRadius: r, endRadius: 3 * r))
        painter.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)),
                     with: .color(sun))

        // A hill in front.
        var ground = Path()
        ground.move(to: CGPoint(x: 0, y: h * 0.78))
        ground.addQuadCurve(to: CGPoint(x: w, y: h * 0.72), control: CGPoint(x: w * 0.45, y: h * 0.58))
        ground.addLine(to: CGPoint(x: w, y: h))
        ground.addLine(to: CGPoint(x: 0, y: h))
        ground.closeSubpath()
        painter.fill(ground, with: .color(hill))
    }
}
```

**2. Show it.** Wrap the `Canvas`'s context in a `CanvasPainter`.

```swift
struct SunsetView: View {
    var body: some View {
        Canvas { context, size in
            var painter = CanvasPainter(context: context)
            Sunset().draw(&painter, size: size)
        }
    }
}
```

**3. Export it.** Draw into an `SVGDocument`.

```swift
func exportSunset(to url: URL) throws {
    let size = CGSize(width: 600, height: 380)
    let document = SVGDocument(size: size, title: "Sunset")
    document.draw { painter in
        Sunset().draw(&painter, size: size)
    }
    try document.write(to: url)  // or use document.svgString, document.svgData
}
```

The SVG has a `viewBox` of `0 0 600 380`, and `width` and `height` in points. Pass `includesSize: false` to leave the size out, so the SVG scales to whatever shows it.

## Layers

A layer is drawn on its own, then composited. `LayerStyle` can give it an opacity, a blur, a flat wash, cut-outs and fades. Here the sunset is mirrored in a lake:

```swift
/// The sunset upside down in a lake along the bottom: see-through,
/// blurred, and fading out toward the bottom.
func drawReflection<P: Painter>(_ painter: inout P, of sunset: Sunset, size: CGSize) {
    let water = CGRect(x: 0, y: size.height * 0.8, width: size.width, height: size.height * 0.2)
    let fadeOut = PaintGradient(colors: [.black, .black.opacity(0)])
    let style = LayerStyle(opacity: 0.5, blur: 2, fades: [
        .init(rect: water, paint: .linearGradient(fadeOut, startPoint: CGPoint(x: 0, y: water.minY),
                                                  endPoint: CGPoint(x: 0, y: water.maxY))),
    ])

    var lake = painter
    lake.clip(to: Path(water))
    lake.drawLayer(style) { layer in
        // Mirror the picture in the water's top edge.
        layer.translateBy(x: 0, y: 2 * water.minY)
        layer.scaleBy(x: 1, y: -1)
        sunset.draw(&layer, size: size)
    }
}
```

A painter is a value. `lake` is a copy, so its clip doesn't affect `painter`. That's how you scope clips and transforms.

The layer's effects apply in a fixed order: the wash, then cut-outs, then fades, then the blur over the finished layer, then the opacity. That's the order `GraphicsContext` gives when you build the same layer by hand with blend modes and a blur filter.

## What it draws

- **Fills,** with the nonzero or even-odd rule.
- **Strokes,** with width, caps, joins, miter limit and dashes (SwiftUI's `StrokeStyle`).
- **Paint:** a flat color with an opacity, a linear gradient, or a radial gradient with a start and end radius.
- **Clipping** to any path. Clips add up.
- **Transforms:** translate, scale, rotate, or any affine matrix.
- **Groups:** named parts of the drawing. In the SVG, each is a `<g>` with your name as its `id`.
- **Layers** with an opacity, a Gaussian blur, a wash, cut-outs and fades.

Colors are `PaintColor` values: sRGB components and an opacity, from 0 to 1. `PaintColor(hex: 0xFF8000)` reads a hex color, `mix(with:by:)` blends two colors, and `Color(_:)` turns one into a SwiftUI `Color`. Gradients are `PaintGradient`s, like SwiftUI's `Gradient`.

## What it doesn't do

Savage covers what SVG can match exactly. It leaves out:

- **Text.** Draw glyphs as paths if you need them.
- **Images.** The SVG has no embedded pictures.
- **Filters other than blur:** no shadows, color matrices or other effects.
- **Blend modes.** Shapes draw normally. Layers use blend modes inside, for their wash, cut-outs and fades.
- **Even-odd clipping.** Clips use the nonzero rule.
- **Conic gradients,** and gradient options such as repeat or mirror. Gradients continue in their end colors.
- **Display P3 and dynamic colors.** Colors are sRGB.
- **The rest of `GraphicsContext`:** `resolve`, symbols, shadows and so on. `CanvasPainter.context` is there if you need them on screen only.

And some viewers fall short:

- **macOS's own SVG renderer** (Preview, Quick Look, Finder, `NSImage`) doesn't draw filters, so blurs come out sharp there. Browsers draw them.
- **Dashes along curves** can land a little differently from one renderer to the next, because each one measures a curve's length its own way. Dashes along straight lines match.

## How drawing becomes SVG

| Drawing | SVG |
| --- | --- |
| `fill` | `<path>` with `fill`, `fill-opacity` and `fill-rule` |
| `stroke` | `<path fill="none">` with `stroke`, `stroke-width`, `stroke-linecap`, `stroke-linejoin`, `stroke-miterlimit`, `stroke-dasharray` and `stroke-dashoffset` |
| `.linearGradient`, `.radialGradient` | `<linearGradient>`, `<radialGradient>` in `<defs>`, with `gradientUnits="userSpaceOnUse"` |
| `clip(to:)` | a `<clipPath>`, and a `<g clip-path="…">` around what it clips |
| `translateBy`, `scaleBy`, `rotate`, `concatenate` | `transform="matrix(…)"` on each shape |
| `group(_:_:)` | `<g id="…">` |
| a layer's opacity and cut-outs | a luminance `<mask>` |
| a layer's fades | a luminance `<mask>` each |
| a layer's blur | a `<filter>` with `<feGaussianBlur>`, on the layer's outermost group |
| a layer's wash | mixed into the colors of the shapes in the layer |

Some details:

- **Gradients** blend premultiplied in a `Canvas`, so white fading to clear black stays white. Some SVG renderers blend without premultiplying, and that fade turns gray. Savage adds stops where it would show, so the SVG looks the same in both.
- **A radial gradient's start radius** becomes its stops' offsets, since SVG radii start at the center.
- **Masked groups** have a group just inside them with `opacity="0.9999"`. Apple's SVG renderers (WebKit, and `NSImage`) mask each shape in a group on its own, so overlapping shapes would come out too opaque. A group with an opacity is drawn as one, and 0.9999 is a change no one can see.
- **A wash over part of the picture** draws the layer twice: plain outside the wash's rect, washed inside it. The plain copy reaches a point into the rect so no seam opens. Where the layer is translucent, that overlap can show as a faint line.
- **Numbers** are rounded to a hundredth of a point on the page, with no trailing zeros. Under a transform that enlarges, they get more decimal places, so a drawing in unit coordinates keeps its precision.
- **The output is deterministic.** Definitions get ids from a counter (`lg1`, `clip2`, `mask3`), and group names are made valid and unique (`moon`, `moon-2`). The same drawing always gives the same bytes.
- **Text you pass in,** such as the title and group names, is escaped.

## Performance

- `CanvasPainter` is a struct that holds a `GraphicsContext`. Each call becomes the matching `GraphicsContext` call, inlined into your drawing. It adds no allocations of its own.
- Make your drawing generic (`<P: Painter>`), not `any Painter`. Then the compiler specializes it for each painter, and on screen it costs about what the same code written against `GraphicsContext` would. Vela's welcome scene (about 400 shapes) runs its drawing code in about 0.24 ms through Savage in a release build, within a few microseconds of the copy of this code it used before.
- `PaintColor.white` and `.black` are inlined too, so stop arrays built from them become constants rather than allocations.
- A `Canvas` redraws whenever SwiftUI asks. For a picture that doesn't change, keep its inputs stable, for example with an `Equatable` view.
- Gradient fills build a SwiftUI `Gradient` on each call, as `GraphicsContext` needs. Build paths and palettes once if you draw the same thing often.
- Writing an SVG takes time in proportion to the number of shapes. A wash over part of a layer draws that layer twice.
- An `SVGDocument` isn't thread-safe. Use each one from one thread at a time.

## Testing

`swift test` runs the suite:

- the SVG each feature writes, and the formatting of numbers, colors, text and ids;
- XML validity (with `XMLParser`), unique ids and resolved references, and determinism;
- fidelity: drawings rendered by SwiftUI through `CanvasPainter`, and from their SVG by macOS's renderer, offscreen, then compared pixel by pixel;
- the code in this README, compiled and run, and checked against this file word for word.

To look at the fidelity renders, run `SAVAGE_FIDELITY_OUTPUT=/some/folder swift test --filter Fidelity`.

## License

Savage is available under the MIT license. See [LICENSE](LICENSE).

<sub>Savage was made with the help of AI.</sub>
