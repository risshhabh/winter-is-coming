import Cocoa
import SpriteKit
import WinterCore

/// Draws every snow texture in code and packs them into one atlas, so all flakes and powder batch
/// into a handful of draw calls.
///
/// Nothing here is a plain radial-gradient disc. Specks are small off-round grains, tufts and large
/// flakes are lumpy aggregates of several grains, and crystals are six-armed dendrites.
struct SnowTextures {
    /// Indexed by `FlakeKind.rawValue`, then variant
    let flakes: [[SKTexture]]
    /// Compact snow fragments
    let fragments: [SKTexture]
    /// Cursor trail: golden sparkle and soft glow
    let sparkle: SKTexture
    let glow: SKTexture
    /// How much bigger the sprite is than the flake's nominal diameter, per kind (texture padding)
    static let spriteScale: [CGFloat] = [2.0, 1.45, 1.25, 1.2]

    init(seed: UInt64 = 0x5EED) {
        var rng = SeededRNG(seed: seed)
        var images: [String: NSImage] = [:]

        for v in 0..<FlakeSystem.variantCounts[0] {
            images["speck\(v)"] = SnowTextures.image(24) { ctx, s in
                let c = s / 2
                // One grain, never quite round, with a much smaller second grain beside it
                SnowTextures.grain(ctx, x: c, y: c, rx: s * 0.30, ry: s * CGFloat(rng.range(0.19, 0.27)),
                                   angle: CGFloat(rng.range(0, 3.14)), alpha: 1)
                if v > 0 {
                    let a = CGFloat(rng.range(0, 6.28))
                    SnowTextures.grain(ctx, x: c + cos(a) * s * 0.17, y: c + sin(a) * s * 0.17,
                                       rx: s * 0.15, ry: s * 0.12, angle: a, alpha: 0.8)
                }
            }
        }
        for v in 0..<FlakeSystem.variantCounts[1] {
            images["tuft\(v)"] = SnowTextures.image(40) { ctx, s in
                SnowTextures.aggregate(ctx, size: s, grains: 4 + v % 3, reach: 0.20, grainSize: 0.15...0.24, rng: &rng)
            }
        }
        for v in 0..<FlakeSystem.variantCounts[2] {
            images["large\(v)"] = SnowTextures.image(56) { ctx, s in
                SnowTextures.aggregate(ctx, size: s, grains: 8 + v * 2, reach: 0.27, grainSize: 0.10...0.19, rng: &rng)
            }
        }
        for v in 0..<FlakeSystem.variantCounts[3] {
            images["crystal\(v)"] = SnowTextures.image(72) { ctx, s in
                SnowTextures.crystal(ctx, size: s, variant: v, rng: &rng)
            }
        }
        for v in 0..<PowderSystem.fragmentVariants {
            images["fragment\(v)"] = SnowTextures.image(32) { ctx, s in
                SnowTextures.fragment(ctx, size: s, rng: &rng)
            }
        }

        images["sparkle"] = FestiveArt.sparkle()
        images["glow"] = FestiveArt.glow()

        let atlas = SKTextureAtlas(dictionary: images)
        let names = ["speck", "tuft", "large", "crystal"]
        flakes = names.enumerated().map { k, name in
            (0..<FlakeSystem.variantCounts[k]).map { atlas.textureNamed("\(name)\($0)") }
        }
        fragments = (0..<PowderSystem.fragmentVariants).map { atlas.textureNamed("fragment\($0)") }
        sparkle = atlas.textureNamed("sparkle")
        glow = atlas.textureNamed("glow")
    }

    // MARK: Drawing

    static func image(_ px: Int, _ draw: (CGContext, CGFloat) -> Void) -> NSImage {
        let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setShouldAntialias(true)
        draw(ctx, CGFloat(px))
        return NSImage(cgImage: ctx.makeImage()!, size: NSSize(width: px, height: px))
    }

    /// A soft-edged elliptical grain: solid through most of its body, then a short fade.
    /// (The original flake faded from the very centre, which is what made it look like a bubble.)
    static func grain(_ ctx: CGContext, x: CGFloat, y: CGFloat, rx: CGFloat, ry: CGFloat, angle: CGFloat, alpha: CGFloat) {
        let colors = [
            CGColor(red: 1, green: 1, blue: 1, alpha: alpha),
            CGColor(red: 1, green: 1, blue: 1, alpha: alpha * 0.92),
            CGColor(red: 1, green: 1, blue: 1, alpha: 0),
        ] as CFArray
        let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.55, 1])!
        ctx.saveGState()
        ctx.translateBy(x: x, y: y)
        ctx.rotate(by: angle)
        ctx.scaleBy(x: rx, y: ry)
        ctx.drawRadialGradient(grad, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 1, options: [])
        ctx.restoreGState()
    }

    /// Several grains stuck together off-centre: reads as a clump of crystals, not a ball
    static func aggregate(_ ctx: CGContext, size s: CGFloat, grains: Int, reach: CGFloat,
                          grainSize: ClosedRange<Double>, rng: inout SeededRNG) {
        let c = s / 2
        for g in 0..<grains {
            let a = CGFloat(rng.range(0, 6.28))
            let d = g == 0 ? 0 : s * reach * CGFloat(rng.range(0.35, 1))
            let r = s * CGFloat(rng.range(grainSize.lowerBound, grainSize.upperBound))
            grain(ctx, x: c + cos(a) * d, y: c + sin(a) * d, rx: r, ry: r * CGFloat(rng.range(0.6, 0.95)),
                  angle: CGFloat(rng.range(0, 3.14)), alpha: CGFloat(rng.range(0.6, 0.95)))
        }
    }

    /// Six-armed dendrite with side branches. Thin strokes, no glow.
    static func crystal(_ ctx: CGContext, size s: CGFloat, variant: Int, rng: inout SeededRNG) {
        let c = s / 2
        let arm = s * 0.42
        let b1 = CGFloat(rng.range(0.38, 0.5)), b2 = CGFloat(rng.range(0.62, 0.76))
        let l1 = arm * CGFloat(rng.range(0.26, 0.36)), l2 = arm * CGFloat(rng.range(0.14, 0.22))
        ctx.saveGState()
        ctx.translateBy(x: c, y: c)
        ctx.setLineCap(.round)
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
        for k in 0..<6 {
            ctx.saveGState()
            ctx.rotate(by: CGFloat(k) * .pi / 3)
            ctx.setLineWidth(s * 0.05)
            ctx.move(to: .zero)
            ctx.addLine(to: CGPoint(x: 0, y: arm))
            ctx.strokePath()
            ctx.setLineWidth(s * 0.038)
            for (at, len) in [(b1, l1), (b2, l2)] {
                for side in [-1.0, 1.0] as [CGFloat] {
                    ctx.move(to: CGPoint(x: 0, y: arm * at))
                    ctx.addLine(to: CGPoint(x: side * len * 0.866, y: arm * at + len * 0.5))
                }
            }
            if variant == 2 {       // plate-like tips on one variant
                ctx.move(to: CGPoint(x: -s * 0.035, y: arm * 0.93))
                ctx.addLine(to: CGPoint(x: s * 0.035, y: arm * 0.93))
            }
            ctx.strokePath()
            ctx.restoreGState()
        }
        ctx.restoreGState()
        grain(ctx, x: c, y: c, rx: s * 0.09, ry: s * 0.09, angle: 0, alpha: 0.9)
    }

    /// An angular lump of packed snow, lit from above
    static func fragment(_ ctx: CGContext, size s: CGFloat, rng: inout SeededRNG) {
        let c = s / 2
        let path = CGMutablePath()
        let n = 7
        for k in 0..<n {
            let a = CGFloat(k) / CGFloat(n) * 2 * .pi + CGFloat(rng.range(-0.25, 0.25))
            let r = s * 0.40 * CGFloat(rng.range(0.62, 1))
            let p = CGPoint(x: c + cos(a) * r, y: c + sin(a) * r)
            if k == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        let colors = [CGColor(red: 1, green: 1, blue: 1, alpha: 1),
                      CGColor(red: 0.80, green: 0.86, blue: 0.96, alpha: 1)] as CFArray
        let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
        ctx.drawLinearGradient(grad, start: CGPoint(x: c, y: s), end: CGPoint(x: c, y: 0), options: [])
        ctx.restoreGState()
    }
}

// MARK: - Snowball textures (Play mode)

// Snowball body: lit from the top-left, bluish shade at the bottom-right (this part never rotates)
func makeSnowballTexture() -> SKTexture {
    SKTexture(image: SnowTextures.image(128) { ctx, s in
        ctx.addEllipse(in: CGRect(x: 1, y: 1, width: s - 2, height: s - 2))
        ctx.clip()
        let colors = [
            CGColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 1),
            CGColor(red: 0.94, green: 0.96, blue: 1.00, alpha: 1),
            CGColor(red: 0.68, green: 0.75, blue: 0.88, alpha: 1),
        ] as CFArray
        let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.55, 1])!
        ctx.drawRadialGradient(grad,
                               startCenter: CGPoint(x: s * 0.38, y: s * 0.64), startRadius: 0,
                               endCenter: CGPoint(x: s * 0.5, y: s * 0.5), endRadius: s * 0.55,
                               options: [.drawsAfterEndLocation])
    })
}

// Little grey-blue specks on top of the body; this layer rotates so you can see the ball roll
func makeSpeckTexture() -> SKTexture {
    SKTexture(image: SnowTextures.image(128) { ctx, s in
        ctx.addEllipse(in: CGRect(x: 6, y: 6, width: s - 12, height: s - 12))
        ctx.clip()
        for _ in 0..<30 {
            let d = CGFloat.random(in: 3...8)
            ctx.setFillColor(CGColor(red: 0.66, green: 0.73, blue: 0.87, alpha: CGFloat.random(in: 0.25...0.55)))
            ctx.fillEllipse(in: CGRect(x: CGFloat.random(in: 6...(s - 14)), y: CGFloat.random(in: 6...(s - 14)),
                                       width: d, height: d))
        }
    })
}
