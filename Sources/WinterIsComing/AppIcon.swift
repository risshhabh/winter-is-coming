import Cocoa

/// The app icon, drawn in code like everything else: a six-armed snowflake over a night-blue
/// rounded square with a drift of snow along the bottom.
enum AppIcon {
    static func draw(_ ctx: CGContext, size s: CGFloat) {
        let inset = s * 0.09
        let r = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
        let shape = CGPath(roundedRect: r, cornerWidth: r.width * 0.225, cornerHeight: r.width * 0.225, transform: nil)
        ctx.saveGState()
        ctx.addPath(shape)
        ctx.clip()
        let space = CGColorSpaceCreateDeviceRGB()
        let sky = [CGColor(red: 0.10, green: 0.18, blue: 0.38, alpha: 1), CGColor(red: 0.28, green: 0.45, blue: 0.72, alpha: 1)] as CFArray
        ctx.drawLinearGradient(CGGradient(colorsSpace: space, colors: sky, locations: [0, 1])!,
                               start: CGPoint(x: 0, y: r.maxY), end: CGPoint(x: 0, y: r.minY), options: [])
        // The drift: a soft hump of snow
        ctx.setFillColor(CGColor(red: 0.93, green: 0.96, blue: 1, alpha: 1))
        ctx.move(to: CGPoint(x: r.minX, y: r.minY))
        ctx.addLine(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.17))
        ctx.addCurve(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.12),
                     control1: CGPoint(x: r.minX + r.width * 0.35, y: r.minY + r.height * 0.30),
                     control2: CGPoint(x: r.minX + r.width * 0.65, y: r.minY + r.height * 0.05))
        ctx.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        ctx.fillPath()
        // A few small background flakes
        for (fx, fy, fr) in [(0.22, 0.78, 0.012), (0.80, 0.70, 0.015), (0.72, 0.88, 0.01), (0.18, 0.45, 0.01), (0.86, 0.40, 0.012)] {
            ctx.setFillColor(CGColor(gray: 1, alpha: 0.75))
            ctx.fillEllipse(in: CGRect(x: s * fx - s * fr, y: s * fy - s * fr, width: 2 * s * fr, height: 2 * s * fr))
        }
        // The snowflake
        let c = CGPoint(x: s * 0.5, y: s * 0.56), arm = s * 0.25
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 1))
        ctx.setLineCap(.round)
        ctx.setLineWidth(s * 0.032)
        for k in 0..<6 {
            let a = CGFloat(k) * .pi / 3 + .pi / 2
            let tip = CGPoint(x: c.x + cos(a) * arm, y: c.y + sin(a) * arm)
            ctx.move(to: c)
            ctx.addLine(to: tip)
            for (t, l) in [(0.5, 0.36), (0.75, 0.24)] as [(CGFloat, CGFloat)] {
                let p = CGPoint(x: c.x + cos(a) * arm * t, y: c.y + sin(a) * arm * t)
                for side in [-1.0, 1.0] as [CGFloat] {
                    let b = a + side * .pi / 3
                    ctx.move(to: p)
                    ctx.addLine(to: CGPoint(x: p.x + cos(b) * arm * l, y: p.y + sin(b) * arm * l))
                }
            }
        }
        ctx.strokePath()
        ctx.restoreGState()
    }

    /// Writes every size macOS wants into `path` (an `.iconset` folder) for `iconutil`
    static func writeIconset(to path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        for base in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let px = base * scale
                guard let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                draw(ctx, size: CGFloat(px))
                guard let image = ctx.makeImage(),
                      let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return false }
                let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
                do { try png.write(to: url.appendingPathComponent(name)) } catch { return false }
            }
        }
        return true
    }
}
