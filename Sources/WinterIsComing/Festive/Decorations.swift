import Cocoa
import SpriteKit
import WinterCore

/// What the user chose for the decorations. Everything defaults to off: Natural Winter stays natural.
struct DecorationSettings {
    var lights = LightMode.off
    /// 0.5 dim, 1 normal, 1.4 bright
    var lightBrightness = 1.0
    /// Distance between bulbs (px): 38 sparse, 26 normal, 18 dense
    var lightSpacing = 26.0
    /// 0 off, 0.6 light, 1 heavy
    var frost = 0.0
    /// A penguin wanders along the snow at the bottom of each display
    var characters = false
}

// MARK: - Christmas lights

/// Strings of lights along the top of each display (just under the menu bar) and along the top edge of
/// the frontmost window, where they hang in front of that window's snow.
///
/// Each bulb is a small coloured sprite plus a soft additive glow. The glow spills onto whatever is
/// nearby, which is how the lights tint the snow piled next to them. Bulbs hang at most 8 px below
/// the edge and skip the first 80 px of a window, so they stay clear of its controls and title.
final class LightsRenderer {
    private let parent: SKNode
    private let bulbTex: SKTexture
    private let glowTex: SKTexture
    private var bulbs: [SKSpriteNode] = []
    private var glows: [SKSpriteNode] = []
    private var wires: [SKSpriteNode] = []
    private var used = 0

    static let multi: [NSColor] = [
        NSColor(calibratedRed: 1.0, green: 0.25, blue: 0.22, alpha: 1), NSColor(calibratedRed: 0.25, green: 0.85, blue: 0.35, alpha: 1),
        NSColor(calibratedRed: 1.0, green: 0.78, blue: 0.25, alpha: 1), NSColor(calibratedRed: 0.3, green: 0.55, blue: 1.0, alpha: 1),
        NSColor(calibratedRed: 1.0, green: 0.45, blue: 0.75, alpha: 1),
    ]
    static let warm = NSColor(calibratedRed: 1.0, green: 0.84, blue: 0.55, alpha: 1)

    init(parent: SKNode, glow: SKTexture) {
        self.parent = parent
        glowTex = glow
        // A small bulb: bright teardrop with a dark cap where it meets the wire
        bulbTex = FestiveArt.texture(6, 9) { ctx in
            FestiveArt.ellipse(ctx, 3, 3.4, 2.4, 3.2, CGColor(gray: 1, alpha: 1))
            FestiveArt.ellipse(ctx, 2.3, 4.2, 0.8, 1.2, CGColor(gray: 1, alpha: 1))
            ctx.setFillColor(CGColor(red: 0.12, green: 0.25, blue: 0.14, alpha: 1))
            ctx.fill(CGRect(x: 1.9, y: 6.4, width: 2.2, height: 2.2))
        }
    }

    private func slot() -> Int {
        if used == bulbs.count {
            let g = SKSpriteNode(texture: glowTex)
            g.blendMode = .add
            g.colorBlendFactor = 1
            g.zPosition = 8
            let b = SKSpriteNode(texture: bulbTex, size: CGSize(width: 5, height: 7.5))
            b.colorBlendFactor = 0.85
            b.anchorPoint = CGPoint(x: 0.5, y: 0.95)
            b.zPosition = 9
            let w = SKSpriteNode(color: NSColor(calibratedRed: 0.10, green: 0.22, blue: 0.13, alpha: 0.9), size: CGSize(width: 1, height: 1))
            w.zPosition = 8.5
            for n in [g, b, w] { parent.addChild(n) }
            glows.append(g); bulbs.append(b); wires.append(w)
        }
        used += 1
        return used - 1
    }

    /// One string from `minX` to `maxX` hanging from `y`. `visible` says whether a bulb at x may be drawn.
    private func string(minX: Double, maxX: Double, y: Double, s: DecorationSettings, time: Double, wind: Double,
                        seedIndex: Int, visible: (Double) -> Bool) {
        let n = Lights.count(length: maxX - minX, spacing: s.lightSpacing)
        var prev: CGPoint?
        for i in 0...max(0, n) {
            let offset = Double(i) * s.lightSpacing
            let x = minX + offset
            guard x <= maxX, visible(x) else { prev = nil; continue }
            // The string stirs a little in the wind
            let sway = sin(time * 1.3 + Double(i) * 0.7) * min(1.6, 0.4 + abs(wind) / 60)
            let p = CGPoint(x: x + sway, y: y - 1 - Lights.sag(at: offset))
            let k = slot()
            let color = s.lights == .warm ? LightsRenderer.warm : LightsRenderer.multi[(i + seedIndex) % LightsRenderer.multi.count]
            let level = Lights.brightness(index: i + seedIndex * 31, time: time) * s.lightBrightness
            bulbs[k].position = p
            bulbs[k].color = color
            bulbs[k].alpha = CGFloat(min(1, 0.55 + 0.45 * level))
            bulbs[k].zRotation = CGFloat(sway * 0.05)
            bulbs[k].isHidden = false
            glows[k].position = CGPoint(x: p.x, y: p.y - 4)
            glows[k].color = color
            glows[k].size = CGSize(width: 30, height: 30)
            glows[k].alpha = CGFloat(min(0.6, 0.3 * level))
            glows[k].isHidden = false
            if let q = prev {
                wires[k].position = CGPoint(x: (p.x + q.x) / 2, y: (p.y + q.y) / 2)
                wires[k].size = CGSize(width: hypot(p.x - q.x, p.y - q.y), height: 0.8)
                wires[k].zRotation = atan2(p.y - q.y, p.x - q.x)
                wires[k].isHidden = false
            } else {
                wires[k].isHidden = true
            }
            prev = p
        }
    }

    func sync(_ model: SnowModel, display: Rect, topInset: Double) {
        used = 0
        let s = model.decor
        if s.lights != .off {
            let wind = model.wind.sample(x: display.minX + display.width / 2, y: display.maxY - 40).u
            string(minX: display.minX + 10, maxX: display.maxX - 10, y: display.maxY - topInset, s: s,
                   time: model.time, wind: wind, seedIndex: 0) { _ in true }
            if let w = model.surfaces.windows.first, w.rect.maxY < display.maxY - topInset - 20, w.rect.width > 220 {
                let f = w.field
                string(minX: w.rect.minX + 80, maxX: w.rect.maxX - 18, y: w.rect.maxY - 1, s: s,
                       time: model.time, wind: wind, seedIndex: 2) { x in
                    guard x >= display.minX, x < display.maxX, let c = f.col(at: x) else { return false }
                    return f.visible[c]
                }
            }
        }
        for i in used..<bulbs.count {
            bulbs[i].isHidden = true; glows[i].isHidden = true; wires[i].isHidden = true
        }
    }
}

// MARK: - Frost

/// Branching frost that creeps in from the bottom corners of windows that have been sitting still.
///
/// The pattern is grown once in code (a fern-like dendrite) and reused. How far it has spread on each
/// window comes from `Surface.frost`, which rises with the weather and is knocked back when the window
/// is shaken. Each needle is a pale core inside a thin icy-blue edge, so it reads on white windows as
/// well as dark ones. It stays within about 100 pt of the corner, so it frames content without covering it.
final class FrostRenderer {
    private let parent: SKNode
    private var textures: [SKTexture] = []
    private var nodes: [Int: (left: SKSpriteNode, right: SKSpriteNode)] = [:]
    static let size = 100.0

    init(parent: SKNode) {
        self.parent = parent
        var rng = SeededRNG(seed: 0xF057)
        for _ in 0..<3 { textures.append(FrostRenderer.makeTexture(&rng)) }
    }

    /// Ice ferns growing out of the bottom-left corner
    static func makeTexture(_ rng: inout SeededRNG) -> SKTexture {
        FestiveArt.texture(64, 64) { ctx in
            // Collect the needles first, then draw every edge before every core so cores stay on top
            var segments: [(CGPoint, CGPoint, CGFloat, CGFloat)] = []
            func branch(_ x: CGFloat, _ y: CGFloat, _ angle: CGFloat, _ length: CGFloat, _ width: CGFloat, _ depth: Int) {
                guard depth > 0, length > 1.5 else { return }
                let ex = x + cos(angle) * length, ey = y + sin(angle) * length
                // Fainter the further it gets from the corner
                segments.append((CGPoint(x: x, y: y), CGPoint(x: ex, y: ey), width, max(0, 1 - hypot(ex, ey) / 64)))
                // Side needles at the crystal angle of 60 degrees, alternating, shrinking toward the tip
                let steps = Int(length / 3.2)
                for k in 1..<max(2, steps) {
                    let t = CGFloat(k) / CGFloat(steps)
                    let side: CGFloat = k % 2 == 0 ? 1 : -1
                    let l = length * 0.42 * (1 - t * 0.7) * CGFloat(rng.range(0.6, 1.1))
                    branch(x + (ex - x) * t, y + (ey - y) * t, angle + side * .pi / 3, l, width * 0.7, depth - 1)
                }
            }
            for k in 0..<5 {
                let a = CGFloat(0.08 + Double(k) * 0.35 + rng.range(-0.08, 0.08))
                branch(0, 0, a, CGFloat(rng.range(30, 56)), 1.1, 3)
            }
            // A soft rime right in the corner, faintly blue so it shows on white
            let colors = [CGColor(red: 0.86, green: 0.93, blue: 1, alpha: 0.75), CGColor(red: 0.86, green: 0.93, blue: 1, alpha: 0)] as CFArray
            let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            ctx.drawRadialGradient(grad, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 30, options: [])
            for pass in 0..<2 {
                for (a, b, w, fade) in segments {
                    ctx.setStrokeColor(pass == 0
                        ? CGColor(red: 0.42, green: 0.60, blue: 0.82, alpha: 0.55 * fade + 0.08)
                        : CGColor(red: 0.97, green: 0.99, blue: 1, alpha: 0.9 * fade + 0.1))
                    ctx.setLineWidth(pass == 0 ? w + 0.9 : w)
                    ctx.move(to: a)
                    ctx.addLine(to: b)
                    ctx.strokePath()
                }
            }
        }
    }

    func sync(_ model: SnowModel, display: Rect) {
        let intensity = model.decor.frost
        let windows = model.surfaces.windows
        for (id, n) in nodes where model.surfaces.surface(id: id)?.onScreen != true || intensity <= 0 {
            n.left.removeFromParent(); n.right.removeFromParent()
            nodes[id] = nil
        }
        guard intensity > 0 else { return }
        for (i, w) in windows.enumerated() {
            var n = nodes[w.id]
            if n == nil {
                let t = textures[abs(w.id) % textures.count], t2 = textures[abs(w.id + 1) % textures.count]
                let l = SKSpriteNode(texture: t), r = SKSpriteNode(texture: t2)
                for s in [l, r] { s.anchorPoint = .zero; s.zPosition = 4; parent.addChild(s) }
                n = (l, r)
                nodes[w.id] = n
            }
            guard let pair = n else { continue }
            // Grows outward from the corner as the frost level rises; Heavy reaches further than Light.
            // Fainter on the window in use, so it never sits heavily over what you are working on.
            let side = CGFloat(FrostRenderer.size * (0.3 + 0.7 * w.frost) * (0.6 + 0.4 * intensity))
            let alpha = CGFloat(w.frost <= 0.01 ? 0 : min(0.95, (0.35 + 0.65 * w.frost) * (i == 0 ? 0.6 : 0.95)))
            // Start a little inside the corner so the pattern does not poke out past its rounding
            let inset = max(1, w.field.cornerRadius * 0.3)
            let corners = [(pair.left, w.rect.minX + inset, 1.0), (pair.right, w.rect.maxX - inset, -1.0)]
            for (sprite, x, flip) in corners {
                let y = w.rect.minY + inset
                // Not where a window in front covers the corner, and not off this display
                var hidden = alpha < 0.02 || !display.contains(x, y)
                if !hidden { for j in 0..<i where windows[j].rect.contains(x, y) { hidden = true; break } }
                sprite.isHidden = hidden
                sprite.position = CGPoint(x: x, y: y)
                sprite.size = CGSize(width: side, height: side)
                sprite.xScale = abs(sprite.xScale) * CGFloat(flip)
                sprite.alpha = alpha
            }
        }
    }
}

// MARK: - Characters

/// The penguin that wanders along the snow at the bottom of a display. Its motion comes from
/// `Wanderer`; here it is only drawn: a waddle while walking, flat on its belly while sliding. It
/// stands on the snow surface beneath it and disappears wherever a window covers that snow.
final class CharacterRenderer {
    private let sprite: SKSpriteNode

    init(parent: SKNode) {
        sprite = SKSpriteNode(texture: FestiveArt.penguin(), size: CGSize(width: 18, height: 22))
        sprite.anchorPoint = CGPoint(x: 0.5, y: 0.04)
        sprite.zPosition = 7
        sprite.isHidden = true
        parent.addChild(sprite)
    }

    func sync(_ model: SnowModel, displayID: Int) {
        guard let w = model.walkers[displayID],
              let g = model.surfaces.grounds.first(where: { $0.id == SurfaceManager.groundID(display: displayID) }),
              let c = g.field.col(at: w.x), g.field.visible[c] else {
            sprite.isHidden = true
            return
        }
        sprite.isHidden = false
        let a = model.animation
        var y = g.field.surface(c) - 1
        var rotation = 0.0
        switch w.mode {
        case .walk:
            rotation = sin(w.phase) * 0.16 * a
            y += abs(sin(w.phase)) * 1.2 * a
        case .slide:
            rotation = -w.dir * .pi / 2 * 0.92
            y += 4
        case .pause:
            break
        }
        sprite.position = CGPoint(x: w.x, y: y)
        sprite.zRotation = CGFloat(rotation)
        sprite.xScale = CGFloat(w.dir)
    }
}
