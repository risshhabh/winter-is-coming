import SpriteKit
import WinterCore

/// Draws the cursor companion (sleigh and reindeer, or the hat) from `CursorCompanion`'s motion.
/// It only ever lives in the click-through overlay, so it cannot get between the user and a click.
final class CompanionRenderer {
    /// Base scale of the artwork at the "Medium" size setting
    static let baseScale = 0.6

    private final class Deer {
        let node = SKNode()
        var legs: [SKSpriteNode] = []
        init(body: SKTexture, leg: SKTexture) {
            // Legs first so the body covers their hinges: two at the back, two at the front
            for x in [-5.6, -3.4, 4.2, 6.2] as [CGFloat] {
                let l = SKSpriteNode(texture: leg, size: CGSize(width: 3, height: 9))
                l.anchorPoint = CGPoint(x: 0.5, y: 0.95)
                l.position = CGPoint(x: x, y: -4)
                l.zPosition = -0.1
                node.addChild(l)
                legs.append(l)
            }
            node.addChild(SKSpriteNode(texture: body, size: CGSize(width: 32, height: 26)))
        }
    }

    private let root = SKNode()
    private let sleighGroup = SKNode()
    private let sleigh: SKSpriteNode
    private var deer: [Deer] = []
    private let hat: SKSpriteNode

    init(parent: SKNode) {
        root.zPosition = 20
        root.isHidden = true
        parent.addChild(root)

        sleigh = SKSpriteNode(texture: FestiveArt.sleigh(), size: CGSize(width: 46, height: 34))
        sleigh.position = CGPoint(x: -24, y: 0)
        sleighGroup.addChild(sleigh)
        let leg = FestiveArt.leg()
        for (i, x) in ([20, 44] as [CGFloat]).enumerated() {
            let d = Deer(body: FestiveArt.reindeer(lead: i == 1), leg: leg)
            d.node.position = CGPoint(x: x, y: -2)
            sleighGroup.addChild(d.node)
            deer.append(d)
        }
        // Reins from Santa's mitten along both harnesses
        let pts: [CGPoint] = [CGPoint(x: -16.5, y: -2.6), CGPoint(x: 23.2, y: 1.2), CGPoint(x: 47.2, y: 1.2)]
        for k in 0..<2 {
            let a = pts[k], b = pts[k + 1]
            let rein = SKSpriteNode(color: NSColor(calibratedRed: 0.36, green: 0.22, blue: 0.12, alpha: 1),
                                    size: CGSize(width: hypot(b.x - a.x, b.y - a.y), height: 0.7))
            rein.position = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            rein.zRotation = atan2(b.y - a.y, b.x - a.x)
            rein.zPosition = 0.2
            sleighGroup.addChild(rein)
        }
        root.addChild(sleighGroup)

        hat = SKSpriteNode(texture: FestiveArt.hat(), size: CGSize(width: 24, height: 22))
        hat.anchorPoint = CGPoint(x: 0.45, y: 0.15)
        root.addChild(hat)
    }

    /// How far behind and above the cursor each companion rides, at a given size setting
    static func offset(_ preset: CursorPreset, size: Double) -> (x: Double, y: Double, stiffness: Double) {
        let s = baseScale * size
        switch preset {
        case .sleigh: return (62 * s + 16, 16 * s + 8, 7)        // the lead reindeer's nose stays clear of the pointer
        case .hat: return (-3, 9, 20)                            // perched just above the arrow's tip
        default: return (0, 0, 7)
        }
    }

    func hide() { root.isHidden = true }

    /// `animation` scales how lively it moves: 0 glides without galloping or tilting, 1 is normal
    func sync(_ c: CursorCompanion, preset: CursorPreset, size: Double, alpha: Double, animation: Double = 1) {
        guard preset != .none else { root.isHidden = true; return }
        root.isHidden = false
        root.alpha = CGFloat(alpha)
        root.position = CGPoint(x: c.x, y: c.y + c.hover * animation)
        let s = CGFloat(CompanionRenderer.baseScale * size)
        sleighGroup.isHidden = preset != .sleigh
        hat.isHidden = preset != .hat

        if preset == .sleigh {
            // Mirror through zero as it turns, so a change of direction reads as the team wheeling round
            let f = CGFloat(c.facing)
            root.xScale = (abs(f) < 0.12 ? (f < 0 ? -0.12 : 0.12) : f) * s
            root.yScale = s
            root.zRotation = CGFloat(c.tilt * animation) * (f < 0 ? -1 : 1)
            let stride = c.stride * animation
            for (i, d) in deer.enumerated() {
                let p = c.gallop + Double(i) * 1.1
                d.node.position.y = -2 + CGFloat(stride * 1.8 * sin(2 * p))
                d.node.zRotation = CGFloat(0.07 * stride * sin(p))
                // Front and back pairs swing against each other, the second leg of each pair a beat behind
                d.legs[0].zRotation = CGFloat(0.85 * stride * sin(p + 2.6))
                d.legs[1].zRotation = CGFloat(0.85 * stride * sin(p + 2.0))
                d.legs[2].zRotation = CGFloat(0.85 * stride * sin(p))
                d.legs[3].zRotation = CGFloat(0.85 * stride * sin(p - 0.6))
            }
            sleigh.position.y = CGFloat(0.9 * stride * sin(c.gallop * 2 + 0.8))
            sleigh.zRotation = CGFloat(0.03 * stride * sin(c.gallop + 0.5))
        } else {
            root.xScale = s * 1.25
            root.yScale = s * 1.25
            // The hat swings back as the cursor moves, like something loosely perched
            root.zRotation = CGFloat((max(-0.55, min(0.55, -c.vx / 650)) + 0.04 * sin(c.gallop)) * animation)
        }
    }
}
