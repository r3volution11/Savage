# ``Savage``

Draw once with SwiftUI's graphics. Get the same picture live on screen and as a true-vector SVG.

## Overview

You write a drawing once, generic over a ``Painter``. ``CanvasPainter`` draws it in a SwiftUI `Canvas`. ``SVGPainter`` writes the same drawing into an ``SVGDocument``: paths, gradients, clip paths, masks and blur filters, with no embedded images.

SwiftUI can't do this on its own. `ImageRenderer` turns a `Canvas` into pixels, even when it renders a PDF.

```swift
func drawBadge<P: Painter>(_ painter: inout P, size: CGSize) {
    let frame = CGRect(origin: .zero, size: size)
    painter.fill(Path(ellipseIn: frame), with: .color(PaintColor(hex: 0x3366CC)))
    painter.stroke(Path(ellipseIn: frame.insetBy(dx: 4, dy: 4)), with: .color(.white), lineWidth: 2)
}

// On screen
Canvas { context, size in
    var painter = CanvasPainter(context: context)
    drawBadge(&painter, size: size)
}

// As SVG
let document = SVGDocument(size: CGSize(width: 64, height: 64), title: "Badge")
document.draw { painter in drawBadge(&painter, size: document.size) }
try document.write(to: url)
```

The painter has what you'd expect from `GraphicsContext`: fills and strokes with a color or a gradient, clipping, transforms, and layers with an opacity, a blur, a wash, cut-outs and fades. It leaves out what SVG can't match exactly, such as text, images and most filters.

## Topics

### Drawing

- ``Painter``
- ``CanvasPainter``
- ``SVGPainter``
- ``SVGDocument``

### Colors and paints

- ``PaintColor``
- ``PaintGradient``
- ``Paint``

### Layers

- ``LayerStyle``
