import SpriteKit
import WinterCore

// MARK: - Snowball

final class Snowball {
    let node = SKNode()
    let body: SKSpriteNode
    let specks: SKSpriteNode
    var x = 0.0
    var y = 0.0
    var r = SnowballController.startRadius
    weak var surface: Surface?   // the surface it rests on (nil while falling, dragged or stacked)
    weak var below: Snowball?    // the ball it is stacked on (snowman), if any
    var falling = false
    var dragging = false
    var vx = 0.0
    var vy = 0.0
    var decor: SKNode?           // snowman face / scarf / buttons drawn on this ball
    var shedSeen = 0             // last shake of the surface this ball has reacted to

    init(body bodyTex: SKTexture, specks speckTex: SKTexture) {
        body = SKSpriteNode(texture: bodyTex)
        specks = SKSpriteNode(texture: speckTex)
        specks.zPosition = 0.1
        specks.zRotation = CGFloat.random(in: 0...6.28)
        node.zPosition = 6.5
        node.addChild(body)
        node.addChild(specks)
    }

    func layout() {
        node.position = CGPoint(x: x, y: y)
        let d = CGSize(width: r * 2, height: r * 2)
        body.size = d
        specks.size = d
    }

    func rest(on s: Surface) {
        surface = s
        shedSeen = s.shedSerial
    }

    func drop(vx: Double, vy: Double) {
        falling = true
        dragging = false
        surface = nil
        below = nil
        self.vx = vx
        self.vy = vy
    }
}
