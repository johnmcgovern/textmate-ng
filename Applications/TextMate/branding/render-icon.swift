import AppKit

// TextMate-NG app icon renderer (macOS 26 / "Liquid Glass" style).
// Keeps TextMate's heritage purple daisy; modernizes the container to a
// full-bleed superellipse (squircle) tile with a teal liquid-glass gradient +
// sheen + NG badge. Teal was chosen to make NG instantly distinguishable from
// upstream TextMate's white/lavender icon in the Dock.

let size: CGFloat = 1024
let args = CommandLine.arguments
let flowerPath = args.count > 1 ? args[1] : "flower.png"
let outPath    = args.count > 2 ? args[2] : "TextMate-NG_1024.png"

func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r/255, green: g/255, blue: b/255, alpha: a)
}

// A glossy rounded pill badge with auto font-fit, drawn on the current context.
func drawBadge(_ rect: CGRect, colors: [NSColor], text: String) {
    let pill = NSBezierPath(roundedRect: rect, xRadius: rect.height/2, yRadius: rect.height/2)
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -size*0.006), blur: size*0.03,
                 color: c(20,0,20,0.38).cgColor)
    pill.addClip()
    NSGradient(colors: colors, atLocations: [0.0, 1.0], colorSpace: .sRGB)!.draw(in: rect, angle: -90)
    NSGradient(colors: [c(255,255,255,0.38), c(255,255,255,0.0)], atLocations: [0.0, 1.0], colorSpace: .sRGB)!
        .draw(in: CGRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height/2), angle: -90)
    cg.restoreGState()

    func mkfont(_ s: CGFloat) -> NSFont {
        let b = NSFont.systemFont(ofSize: s, weight: .heavy)
        let d = b.fontDescriptor.withDesign(.rounded) ?? b.fontDescriptor
        return NSFont(descriptor: d, size: s) ?? b
    }
    let para = NSMutableParagraphStyle(); para.alignment = .center
    var attrs: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.white, .paragraphStyle: para]
    var fs = rect.height*0.60
    while fs > 8 {
        attrs[.font] = mkfont(fs)
        if NSAttributedString(string: text, attributes: attrs).size().width <= rect.width*0.82 { break }
        fs -= 4
    }
    attrs[.font] = mkfont(fs)
    let str = NSAttributedString(string: text, attributes: attrs)
    let tsz = str.size()
    str.draw(at: NSPoint(x: rect.midX - tsz.width/2, y: rect.midY - tsz.height/2))
}

// Superellipse (squircle) path: |x/a|^n + |y/a|^n = 1, n≈5 ≈ Apple's continuous corner.
func squircle(_ rect: CGRect, n: CGFloat = 5) -> NSBezierPath {
    let p = NSBezierPath()
    let cx = rect.midX, cy = rect.midY
    let a = rect.width/2, b = rect.height/2
    let steps = 720
    for i in 0...steps {
        let t = CGFloat(i)/CGFloat(steps) * 2 * .pi
        let ct = cos(t), st = sin(t)
        let x = cx + a * CGFloat(copysign(pow(abs(Double(ct)), 2.0/Double(n)), Double(ct)))
        let y = cy + b * CGFloat(copysign(pow(abs(Double(st)), 2.0/Double(n)), Double(st)))
        if i == 0 { p.move(to: NSPoint(x: x, y: y)) } else { p.line(to: NSPoint(x: x, y: y)) }
    }
    p.close()
    return p
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
let gctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = gctx
let cg = gctx.cgContext

let full = CGRect(x: 0, y: 0, width: size, height: size)
// Slight inset so the squircle isn't clipped by the pixel edge.
let tileRect = full.insetBy(dx: size*0.008, dy: size*0.008)
let tile = squircle(tileRect)

// 1) Tile background gradient (luminous teal liquid-glass; complements the purple).
cg.saveGState()
tile.setClip()
let bg = NSGradient(colors: [c(150,236,228), c(42,187,186), c(10,122,138)],
                    atLocations: [0.0, 0.58, 1.0], colorSpace: .sRGB)!
bg.draw(in: tileRect, angle: -90)

// 2) Soft radial glass sheen, upper area.
let sheen = NSGradient(colors: [c(255,255,255,0.55), c(255,255,255,0.0)], atLocations: [0.0, 1.0], colorSpace: .sRGB)!
sheen.draw(fromCenter: NSPoint(x: size*0.5, y: size*0.80), radius: 0,
           toCenter: NSPoint(x: size*0.5, y: size*0.72), radius: size*0.62, options: [])

// 3) Very subtle bottom inner vignette for depth.
let vignette = NSGradient(colors: [c(0,45,65,0.0), c(0,45,65,0.16)],
                          atLocations: [0.5, 1.0], colorSpace: .sRGB)!
vignette.draw(in: tileRect, angle: -90)

// 3b) Faint refracted rim light along the bottom edge (liquid-glass cue).
let rim = NSGradient(colors: [c(210,255,250,0.32), c(210,255,250,0.0)],
                     atLocations: [0.0, 1.0], colorSpace: .sRGB)!
rim.draw(fromCenter: NSPoint(x: size*0.5, y: -size*0.30), radius: 0,
         toCenter: NSPoint(x: size*0.5, y: -size*0.30), radius: size*0.62, options: [])
cg.restoreGState()

// 4) The heritage flower, centered, with a soft grounded shadow.
if let flower = NSImage(contentsOfFile: flowerPath) {
    let scale: CGFloat = 0.90
    let w = size*scale, h = size*scale
    let fr = CGRect(x: (size-w)/2, y: (size-h)/2 + size*0.015, width: w, height: h)
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -size*0.012), blur: size*0.045,
                 color: c(0,35,50,0.38).cgColor)
    flower.draw(in: fr, from: .zero, operation: .sourceOver, fraction: 1.0)
    cg.restoreGState()
}

// 5) Badges: purple "NG" bottom-right (matches the flower); red "Alpha" top-right.
drawBadge(CGRect(x: size*0.635, y: size*0.075, width: size*0.300, height: size*0.155),
          colors: [c(150,70,246), c(120,40,220)], text: "NG")
drawBadge(CGRect(x: size*0.575, y: size*0.775, width: size*0.360, height: size*0.150),
          colors: [c(255,69,58), c(198,18,24)], text: "Alpha")

// 6) Crisp 1px inner edge on the tile for definition.
cg.saveGState()
tile.lineWidth = size*0.004
c(255,255,255,0.5).setStroke()
tile.stroke()
cg.restoreGState()

NSGraphicsContext.restoreGraphicsState()

guard let data = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("PNG encode failed\n".data(using: .utf8)!); exit(1)
}
try! data.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
