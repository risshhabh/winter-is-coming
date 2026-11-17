import Cocoa
import SpriteKit

/// The festive artwork, drawn in code at four times its display size so it stays crisp on Retina
/// displays. Everything faces right; the renderer mirrors it. Colours are flat with one soft shade,
/// to sit alongside the snow.
enum FestiveArt {
    static let red = CGColor(red: 0.78, green: 0.12, blue: 0.14, alpha: 1)
    static let darkRed = CGColor(red: 0.56, green: 0.07, blue: 0.10, alpha: 1)
    static let gold = CGColor(red: 0.95, green: 0.76, blue: 0.28, alpha: 1)
    static let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
    static let snowShade = CGColor(red: 0.80, green: 0.86, blue: 0.95, alpha: 1)
    static let brown = CGColor(red: 0.52, green: 0.34, blue: 0.19, alpha: 1)
    static let darkBrown = CGColor(red: 0.33, green: 0.21, blue: 0.12, alpha: 1)
    static let cream = CGColor(red: 0.88, green: 0.80, blue: 0.68, alpha: 1)
    static let skin = CGColor(red: 0.97, green: 0.80, blue: 0.68, alpha: 1)

    /// A texture `w` x `h` points, drawn in point coordinates (origin bottom-left)
    static func texture(_ w: CGFloat, _ h: CGFloat, _ draw: (CGContext) -> Void) -> SKTexture {
        let k: CGFloat = 4
        let ctx = CGContext(data: nil, width: Int(w * k), height: Int(h * k), bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.scaleBy(x: k, y: k)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        draw(ctx)
        return SKTexture(cgImage: ctx.makeImage()!)
    }

    static func ellipse(_ ctx: CGContext, _ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat, _ color: CGColor,
                        rotate: CGFloat = 0) {
        ctx.saveGState()
        ctx.translateBy(x: cx, y: cy)
        ctx.rotate(by: rotate)
        ctx.setFillColor(color)
        ctx.fillEllipse(in: CGRect(x: -rx, y: -ry, width: rx * 2, height: ry * 2))
        ctx.restoreGState()
    }

    static func line(_ ctx: CGContext, _ pts: [(CGFloat, CGFloat)], _ color: CGColor, _ width: CGFloat) {
        ctx.setStrokeColor(color)
        ctx.setLineWidth(width)
        ctx.move(to: CGPoint(x: pts[0].0, y: pts[0].1))
        for p in pts.dropFirst() { ctx.addLine(to: CGPoint(x: p.0, y: p.1)) }
        ctx.strokePath()
    }

    // MARK: Penguin (18 x 22), facing right, with a red scarf

    static func penguin() -> SKTexture {
        texture(18, 22) { ctx in
            let black = CGColor(red: 0.09, green: 0.10, blue: 0.13, alpha: 1)
            let orange = CGColor(red: 0.96, green: 0.58, blue: 0.16, alpha: 1)
            ellipse(ctx, 6.5, 1.2, 3, 1.1, orange)                  // feet
            ellipse(ctx, 11.5, 1.2, 3, 1.1, orange)
            ellipse(ctx, 9, 9.5, 6.4, 8.4, black)                    // body
            ellipse(ctx, 9, 15.5, 4.6, 4.6, black)                   // head
            ellipse(ctx, 10.2, 8.6, 4.2, 6.6, white)                 // belly
            ellipse(ctx, 11.2, 15.6, 2.4, 2.6, white)                // face
            ellipse(ctx, 12.0, 16.4, 0.75, 0.8, black)               // eye
            ctx.setFillColor(orange)                                 // beak
            ctx.move(to: CGPoint(x: 13.2, y: 15.6))
            ctx.addLine(to: CGPoint(x: 17, y: 14.8))
            ctx.addLine(to: CGPoint(x: 13.2, y: 14.1))
            ctx.fillPath()
            ellipse(ctx, 4.2, 8.5, 1.8, 5, black, rotate: -0.25)     // flipper
            line(ctx, [(4.2, 12.4), (13.6, 12.4)], red, 1.8)          // scarf
            line(ctx, [(5.2, 12.2), (3.6, 8.6)], darkRed, 1.6)
        }
    }

    // MARK: Reindeer (32 x 26), legs separate so they can gallop

    static func reindeer(lead: Bool) -> SKTexture {
        texture(32, 26) { ctx in
            ellipse(ctx, 4.4, 13.4, 1.7, 1.3, cream)                               // tail
            ellipse(ctx, 13.5, 12, 8.6, 4.6, brown)                                // body
            ctx.setFillColor(brown)                                                 // neck
            ctx.move(to: CGPoint(x: 17.5, y: 9.4))
            ctx.addLine(to: CGPoint(x: 21.5, y: 10.5))
            ctx.addLine(to: CGPoint(x: 27, y: 18.6))
            ctx.addLine(to: CGPoint(x: 23.2, y: 21))
            ctx.addLine(to: CGPoint(x: 16.5, y: 15.6))
            ctx.closePath()
            ctx.fillPath()
            ellipse(ctx, 13, 9.5, 6.2, 1.7, CGColor(red: 0.88, green: 0.80, blue: 0.68, alpha: 0.6))   // pale belly
            ellipse(ctx, 21.5, 14, 2.2, 3.4, CGColor(red: 0.88, green: 0.80, blue: 0.68, alpha: 0.45), rotate: -0.6) // chest
            // antlers, behind the head
            line(ctx, [(24.6, 21.4), (23.5, 25.3)], cream, 0.9)
            line(ctx, [(24.1, 23.2), (22.2, 24.3)], cream, 0.8)
            line(ctx, [(23.8, 24.3), (25.2, 25.5)], cream, 0.8)
            line(ctx, [(26, 21.6), (26.9, 25.1)], cream, 0.9)
            line(ctx, [(26.5, 23.5), (28.2, 24.5)], cream, 0.8)
            ellipse(ctx, 23.4, 21.5, 1.7, 0.85, darkBrown, rotate: 0.7)            // ear
            ellipse(ctx, 26.2, 19.6, 3.4, 2.4, brown, rotate: -0.25)               // head
            ellipse(ctx, 28.9, 18.7, 1.9, 1.5, CGColor(red: 0.62, green: 0.44, blue: 0.28, alpha: 1))  // muzzle
            ellipse(ctx, 30.4, 18.7, 1.05, 1.05, lead ? CGColor(red: 0.93, green: 0.14, blue: 0.14, alpha: 1) : darkBrown)
            if lead { ellipse(ctx, 30.1, 19.05, 0.35, 0.3, CGColor(red: 1, green: 0.8, blue: 0.8, alpha: 0.9)) }
            ellipse(ctx, 26.7, 20.3, 0.5, 0.55, CGColor(gray: 0.08, alpha: 1))     // eye
            line(ctx, [(18.3, 8.0), (19.3, 12), (18.9, 16.4)], red, 1.3)           // harness
            ellipse(ctx, 18.4, 8.1, 0.95, 0.95, gold)                              // bell
        }
    }

    /// One leg (3 x 9), hinged at the top
    static func leg() -> SKTexture {
        texture(3, 9) { ctx in
            ctx.setFillColor(brown)
            ctx.addPath(CGPath(roundedRect: CGRect(x: 0.8, y: 1, width: 1.4, height: 8), cornerWidth: 0.7, cornerHeight: 0.7, transform: nil))
            ctx.fillPath()
            ctx.setFillColor(darkBrown)
            ctx.addPath(CGPath(roundedRect: CGRect(x: 0.6, y: 0, width: 1.8, height: 1.8), cornerWidth: 0.5, cornerHeight: 0.5, transform: nil))
            ctx.fillPath()
        }
    }

    // MARK: Sleigh with Santa and his sack (46 x 34)

    static func sleigh() -> SKTexture {
        texture(46, 34) { ctx in
            // Sack and Santa first; the sleigh's side is drawn over their lower halves so they sit inside
            ellipse(ctx, 12.4, 16.5, 4.8, 5.4, CGColor(red: 0.44, green: 0.31, blue: 0.18, alpha: 1))
            ellipse(ctx, 13.2, 21.6, 1.6, 1.0, CGColor(red: 0.36, green: 0.25, blue: 0.14, alpha: 1))
            ellipse(ctx, 21, 15.5, 5.3, 6.1, red)                                  // coat
            line(ctx, [(23.2, 10.5), (23.6, 20.5)], white, 1.3)                    // fur front
            ctx.saveGState()                                                        // belt, clipped to the coat
            ctx.addEllipse(in: CGRect(x: 15.7, y: 9.4, width: 10.6, height: 12.2))
            ctx.clip()
            ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
            ctx.fill(CGRect(x: 14, y: 13.2, width: 14, height: 1.5))
            ctx.restoreGState()
            ellipse(ctx, 23.5, 13.95, 0.95, 0.95, gold)                            // buckle
            line(ctx, [(21.8, 17.6), (29.3, 14.6)], red, 2.7)                      // arm reaching for the reins
            ellipse(ctx, 30.1, 14.3, 1.4, 1.4, white)                              // mitten
            ellipse(ctx, 22.6, 23.2, 3.0, 3.0, skin)                               // head
            ellipse(ctx, 23.5, 21, 3.1, 2.7, white)                                // beard
            ellipse(ctx, 21, 20.4, 1.8, 1.6, white)
            ellipse(ctx, 25.4, 22.9, 0.65, 0.6, CGColor(red: 0.93, green: 0.6, blue: 0.55, alpha: 1))  // nose
            ellipse(ctx, 24.1, 23.9, 0.42, 0.45, CGColor(gray: 0.1, alpha: 1))     // eye
            ctx.setFillColor(red)                                                   // hat, tip streaming back
            ctx.move(to: CGPoint(x: 19.4, y: 24.8))
            ctx.addQuadCurve(to: CGPoint(x: 14.6, y: 29.2), control: CGPoint(x: 18.6, y: 30.4))
            ctx.addQuadCurve(to: CGPoint(x: 25.4, y: 25), control: CGPoint(x: 22.6, y: 30.6))
            ctx.closePath()
            ctx.fillPath()
            line(ctx, [(19.4, 25.3), (25.7, 24.7)], white, 1.8)                    // brim
            ellipse(ctx, 14.4, 29.3, 1.55, 1.55, white)                            // pom

            // Runner and struts
            ctx.setStrokeColor(gold)
            ctx.setLineWidth(1.3)
            ctx.move(to: CGPoint(x: 5, y: 2.2))
            ctx.addLine(to: CGPoint(x: 34, y: 2.2))
            ctx.addQuadCurve(to: CGPoint(x: 41.4, y: 9), control: CGPoint(x: 41.4, y: 2.2))
            ctx.addQuadCurve(to: CGPoint(x: 38.8, y: 10.6), control: CGPoint(x: 41.4, y: 11.4))
            ctx.strokePath()
            line(ctx, [(12, 2.2), (12, 6.6)], gold, 1.1)
            line(ctx, [(29, 2.2), (29, 6.6)], gold, 1.1)

            // Sleigh body: low front with a curl, high swept back
            let body = CGMutablePath()
            body.move(to: CGPoint(x: 7, y: 6.5))
            body.addLine(to: CGPoint(x: 33, y: 6.5))
            body.addQuadCurve(to: CGPoint(x: 39.5, y: 14.5), control: CGPoint(x: 40, y: 6.5))
            body.addQuadCurve(to: CGPoint(x: 36.2, y: 15.2), control: CGPoint(x: 38.6, y: 17.4))
            body.addQuadCurve(to: CGPoint(x: 31, y: 11.8), control: CGPoint(x: 35.8, y: 11.8))
            body.addLine(to: CGPoint(x: 13, y: 11.8))
            body.addQuadCurve(to: CGPoint(x: 8.6, y: 21), control: CGPoint(x: 9.2, y: 12))
            body.addQuadCurve(to: CGPoint(x: 4.8, y: 20.2), control: CGPoint(x: 6.3, y: 23.4))
            body.addQuadCurve(to: CGPoint(x: 7, y: 6.5), control: CGPoint(x: 3.6, y: 10))
            body.closeSubpath()
            ctx.addPath(body)
            ctx.setFillColor(red)
            ctx.fillPath()
            ctx.saveGState()
            ctx.addPath(body)
            ctx.clip()
            ctx.setFillColor(darkRed)
            ctx.fill(CGRect(x: 0, y: 6, width: 46, height: 2.4))
            ctx.restoreGState()
            ctx.setStrokeColor(gold)                                                // trim along the top edge
            ctx.setLineWidth(0.8)
            ctx.move(to: CGPoint(x: 36.2, y: 15.2))
            ctx.addQuadCurve(to: CGPoint(x: 31, y: 11.8), control: CGPoint(x: 35.8, y: 11.8))
            ctx.addLine(to: CGPoint(x: 13, y: 11.8))
            ctx.addQuadCurve(to: CGPoint(x: 8.6, y: 21), control: CGPoint(x: 9.2, y: 12))
            ctx.strokePath()
        }
    }

    // MARK: Santa hat (24 x 22)

    static func hat() -> SKTexture {
        texture(24, 22) { ctx in
            let cone = CGMutablePath()
            cone.move(to: CGPoint(x: 4.2, y: 6))
            cone.addQuadCurve(to: CGPoint(x: 13, y: 19.4), control: CGPoint(x: 5, y: 16.5))
            cone.addQuadCurve(to: CGPoint(x: 21.4, y: 12), control: CGPoint(x: 20, y: 20.5))
            cone.addQuadCurve(to: CGPoint(x: 18.8, y: 6), control: CGPoint(x: 15, y: 13.5))
            cone.closeSubpath()
            ctx.addPath(cone)
            ctx.setFillColor(red)
            ctx.fillPath()
            ctx.saveGState()                                                        // soft shade on the far side
            ctx.addPath(cone)
            ctx.clip()
            ellipse(ctx, 18, 9, 5, 9, CGColor(red: 0.56, green: 0.07, blue: 0.10, alpha: 0.55), rotate: 0.5)
            ctx.restoreGState()
            ctx.setFillColor(snowShade)                                             // brim with a cool underside
            ctx.addPath(CGPath(roundedRect: CGRect(x: 2.4, y: 2.6, width: 18.4, height: 4.4), cornerWidth: 2.2, cornerHeight: 2.2, transform: nil))
            ctx.fillPath()
            ctx.setFillColor(white)
            ctx.addPath(CGPath(roundedRect: CGRect(x: 2.4, y: 3.5, width: 18.4, height: 4.2), cornerWidth: 2.1, cornerHeight: 2.1, transform: nil))
            ctx.fillPath()
            ellipse(ctx, 21.3, 10.8, 2.5, 2.5, snowShade)                           // pom
            ellipse(ctx, 21.1, 11.2, 2.3, 2.3, white)
        }
    }

    // MARK: Trail particles

    /// Four-pointed golden sparkle (16 x 16)
    static func sparkle() -> NSImage {
        SnowTextures.image(48) { ctx, s in
            let c = s / 2
            ctx.setFillColor(CGColor(red: 1.0, green: 0.84, blue: 0.38, alpha: 1))
            for (long, short) in [(s * 0.46, s * 0.07), (s * 0.07, s * 0.46)] {
                ctx.move(to: CGPoint(x: c - long, y: c))
                ctx.addQuadCurve(to: CGPoint(x: c, y: c + short), control: CGPoint(x: c, y: c))
                ctx.addQuadCurve(to: CGPoint(x: c + long, y: c), control: CGPoint(x: c, y: c))
                ctx.addQuadCurve(to: CGPoint(x: c, y: c - short), control: CGPoint(x: c, y: c))
                ctx.addQuadCurve(to: CGPoint(x: c - long, y: c), control: CGPoint(x: c, y: c))
                ctx.fillPath()
            }
            ctx.setFillColor(CGColor(red: 1, green: 0.97, blue: 0.85, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: c - s * 0.08, y: c - s * 0.08, width: s * 0.16, height: s * 0.16))
        }
    }

    /// Soft warm glow
    static func glow() -> NSImage {
        SnowTextures.image(48) { ctx, s in
            let colors = [CGColor(red: 1, green: 0.9, blue: 0.6, alpha: 0.9),
                          CGColor(red: 1, green: 0.82, blue: 0.4, alpha: 0.3),
                          CGColor(red: 1, green: 0.8, blue: 0.35, alpha: 0)] as CFArray
            let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.4, 1])!
            let c = CGPoint(x: s / 2, y: s / 2)
            ctx.drawRadialGradient(grad, startCenter: c, startRadius: 0, endCenter: c, endRadius: s / 2, options: [])
        }
    }
}
