import SpriteKit
import WinterCore

/// Snow is tinted slightly blue-grey over a light desktop so it stays visible on white windows.
struct SnowTint: Equatable {
    var color: NSColor
    var blend: CGFloat

    static let dark = SnowTint(color: .white, blend: 0)
    static let light = SnowTint(color: NSColor(calibratedRed: 0.50, green: 0.60, blue: 0.78, alpha: 1), blend: 0.85)
}

/// Mirrors `FlakeSystem` into a pool of sprites. Sprite `i` always shows flake `i`; because the system
/// removes by swapping, a slot can change flake, so texture and depth are re-applied only when they differ.
final class FlakeRenderer {
    static let bandZ: [CGFloat] = [1, 2, 7]

    private let parent: SKNode
    private let textures: SnowTextures
    private var sprites: [SKSpriteNode] = []
    private var keys: [UInt16] = []
    private var shown = 0
    var tint = SnowTint.dark { didSet { if tint != oldValue { applyTint() } } }

    init(parent: SKNode, textures: SnowTextures) {
        self.parent = parent
        self.textures = textures
    }

    private func applyTint() {
        for s in sprites {
            s.color = tint.color
            s.colorBlendFactor = tint.blend
        }
    }

    func sync(_ f: FlakeSystem) {
        let n = f.count
        while sprites.count < n {
            let s = SKSpriteNode(texture: textures.flakes[0][0])
            s.color = tint.color
            s.colorBlendFactor = tint.blend
            s.isHidden = true
            parent.addChild(s)
            sprites.append(s)
            keys.append(.max)
        }
        for i in 0..<n {
            let s = sprites[i]
            let kind = Int(f.kind[i])
            let key = UInt16(f.kind[i]) << 8 | UInt16(f.variant[i]) << 2 | UInt16(f.band[i])
            if keys[i] != key {
                keys[i] = key
                s.texture = textures.flakes[kind][Int(f.variant[i])]
                s.zPosition = FlakeRenderer.bandZ[Int(f.band[i])]
            }
            let side = CGFloat(f.size[i]) * 2 * SnowTextures.spriteScale[kind]
            s.size = CGSize(width: side, height: side)
            s.position = CGPoint(x: f.x[i], y: f.y[i])
            s.zRotation = CGFloat(f.rot[i])
            s.alpha = CGFloat(f.alpha[i] * f.fade[i])
            s.isHidden = false
        }
        if shown > n { for i in n..<shown { sprites[i].isHidden = true } }
        shown = n
    }
}

/// Mirrors `PowderSystem`: fine specks for powder, angular lumps for the rare fragment.
final class PowderRenderer {
    private let parent: SKNode
    private let textures: SnowTextures
    private var sprites: [SKSpriteNode] = []
    private var keys: [UInt8] = []
    private var shown = 0
    var tint = SnowTint.dark { didSet { if tint != oldValue { applyTint() } } }

    init(parent: SKNode, textures: SnowTextures) {
        self.parent = parent
        self.textures = textures
    }

    private func applyTint() {
        for s in sprites { s.color = tint.color }
        for i in 0..<keys.count { keys[i] = .max }      // re-apply per-kind blending on the next sync
    }

    func sync(_ p: PowderSystem) {
        let n = p.count
        while sprites.count < n {
            let s = SKSpriteNode(texture: textures.flakes[0][0])
            s.color = tint.color
            s.colorBlendFactor = tint.blend
            s.zPosition = 6
            s.isHidden = true
            parent.addChild(s)
            sprites.append(s)
            keys.append(.max)
        }
        for i in 0..<n {
            let s = sprites[i]
            let kind = p.kind[i]
            let frag = kind == PowderSystem.fragmentKind
            let key = kind << 4 | p.variant[i]
            if keys[i] != key {
                keys[i] = key
                switch kind {
                case PowderSystem.fragmentKind: s.texture = textures.fragments[Int(p.variant[i])]
                case PowderSystem.sparkleKind: s.texture = textures.sparkle
                case PowderSystem.glowKind: s.texture = textures.glow
                case PowderSystem.trailFlakeKind: s.texture = textures.flakes[3][Int(p.variant[i])]      // tiny crystals
                default: s.texture = textures.flakes[0][Int(p.variant[i])]
                }
                // Gold keeps its own colour; snow takes the light-desktop tint
                let golden = kind == PowderSystem.sparkleKind || kind == PowderSystem.glowKind
                s.colorBlendFactor = golden ? 0 : tint.blend
                s.zPosition = kind >= PowderSystem.sparkleKind ? 19 : 6
            }
            let side = CGFloat(p.size[i]) * 2 * (frag ? 1.25 : (kind >= PowderSystem.sparkleKind ? 1.6 : SnowTextures.spriteScale[0]))
            s.size = CGSize(width: side, height: side)
            s.position = CGPoint(x: p.x[i], y: p.y[i])
            s.zRotation = CGFloat(p.rot[i])
            // Sparkles twinkle as they fade
            let twinkle = kind == PowderSystem.sparkleKind ? 0.65 + 0.35 * sin(p.age[i] * 34 + Double(i)) : 1
            s.alpha = CGFloat(p.opacity(i) * twinkle)
            s.isHidden = false
        }
        if shown > n { for i in n..<shown { sprites[i].isHidden = true } }
        shown = n
    }
}
