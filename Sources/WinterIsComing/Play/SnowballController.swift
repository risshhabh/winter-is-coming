import Cocoa
import SpriteKit
import WinterCore

/// Play mode: roll snowballs out of the snow, push them, carry them, stack three into a snowman.
///
/// Nothing here runs unless `enabled` is true. Outside Play mode no snowball is ever created and the
/// overlay never takes a click, so ordinary mouse movement cannot turn snow into anything.
///
/// There is one controller per display. Each only reacts while the cursor is on its own display, and
/// its snowballs live (and are drawn) there. All positions are global coordinates.
final class SnowballController {
    static let startRadius = 3.0     // a new snowball starts this small
    static let maxRadius = 28.0      // and stops growing at this size
    static let maxBalls = 20         // oldest resting snowballs are removed beyond this
    static let gravity = 900.0

    private unowned let scene: SnowScene
    private let ballTex = makeSnowballTexture()
    private let speckTex = makeSpeckTexture()
    private(set) var balls: [Snowball] = []
    private weak var activeBall: Snowball?
    private var lastMouseX = Double(NSEvent.mouseLocation.x)
    private var dragBall: Snowball?
    private var dragTarget = CGPoint.zero
    private var dragOffset = CGPoint.zero
    private var dragVX = 0.0
    private var dragVY = 0.0

    var enabled = false {
        didSet {
            guard !enabled else { return }
            activeBall = nil
            if let b = dragBall {
                dragBall = nil
                b.node.zPosition = 6.5
                b.drop(vx: 0, vy: 0)
            }
        }
    }

    init(scene: SnowScene) { self.scene = scene }

    private var surfaces: SurfaceManager { scene.model.surfaces }
    private var ground: Surface? { surfaces.surface(id: SurfaceManager.groundID(display: scene.displayID)) }
    private func rnd(_ a: Double, _ b: Double) -> Double { Double.random(in: a...b) }

    private func mouseOnThisDisplay() -> CGPoint? {
        let m = NSEvent.mouseLocation
        return scene.displayRect.contains(Double(m.x), Double(m.y)) ? m : nil
    }

    func step(_ dt: Double) {
        if enabled, dt > 0 {
            if let b = dragBall { stepDrag(b, dt) } else { updateRolling() }
        }
        if !balls.isEmpty, dt > 0 { stepBalls(dt) }
    }

    func clear() {
        for b in balls { b.node.removeFromParent() }
        balls.removeAll()
        dragBall = nil
        activeBall = nil
    }

    // MARK: Dragging & snowmen

    /// The overlay lets every click through. Only in Play mode, and only while the mouse is over a
    /// snowball (or dragging one), does it catch clicks so you can grab the ball.
    func updateMouseCapture(_ w: NSWindow?) {
        guard let w else { return }
        var capture = false
        if enabled {
            if dragBall != nil {
                capture = true
            } else if let m = mouseOnThisDisplay() {
                capture = ballAt(m) != nil
            }
        }
        if w.ignoresMouseEvents == capture { w.ignoresMouseEvents = !capture }
    }

    /// The visible, resting snowball under a point (top of a stack first)
    private func ballAt(_ m: CGPoint) -> Snowball? {
        let mx = Double(m.x), my = Double(m.y)
        var best: Snowball?
        for b in balls where !b.falling && !b.node.isHidden {
            let dx = mx - b.x, dy = my - b.y
            if dx * dx + dy * dy <= (b.r + 2) * (b.r + 2), best == nil || b.y > best!.y { best = b }
        }
        return best
    }

    private func above(_ b: Snowball) -> Snowball? { balls.first { $0.below === b } }

    private func base(of b: Snowball) -> Snowball {
        var x = b
        while let y = x.below { x = y }
        return x
    }

    /// Balls in a stack from the bottom up
    private func stack(from base: Snowball) -> [Snowball] {
        var out = [base]
        while let a = above(out.last!), out.count < 10 { out.append(a) }
        return out
    }

    func mouseDown(at m: CGPoint) {
        guard enabled, let b = ballAt(m) else { return }
        // Anything stacked on top of the grabbed ball tumbles off
        var a = above(b)
        while let x = a {
            a = above(x)
            x.drop(vx: rnd(-50, 50), vy: rnd(40, 100))
        }
        removeDecor(stackOf: b)
        b.surface = nil
        b.below = nil
        b.dragging = true
        b.node.zPosition = 8                 // in front while dragging
        dragBall = b
        activeBall = nil
        dragOffset = CGPoint(x: b.x - Double(m.x), y: b.y - Double(m.y))
        dragTarget = m
        dragVX = 0
        dragVY = 0
    }

    func mouseDragged(to m: CGPoint) { dragTarget = m }

    func mouseUp() {
        guard let b = dragBall else { return }
        dragBall = nil
        b.dragging = false
        if let target = stackTarget(for: b) {
            b.below = target
            b.vx = 0
            b.vy = 0
            let st = stack(from: base(of: b))
            for (i, x) in st.enumerated() { x.node.zPosition = 6.5 + CGFloat(i) * 0.3 }
            if st.count == 3 { makeSnowman(st) }
        } else {
            b.node.zPosition = 6.5
            // Let go: it falls (with a bit of the throw) and lands on whatever is below
            b.drop(vx: max(-600, min(600, dragVX * 0.5)), vy: max(-400, min(400, dragVY * 0.5)))
        }
    }

    private func stepDrag(_ b: Snowball, _ dt: Double) {
        let tx = Double(dragTarget.x + dragOffset.x), ty = Double(dragTarget.y + dragOffset.y)
        dragVX = dragVX * 0.7 + (tx - b.x) / dt * 0.3
        dragVY = dragVY * 0.7 + (ty - b.y) / dt * 0.3
        b.specks.zRotation -= CGFloat((tx - b.x) / b.r)
        b.x = tx
        b.y = ty
        lastMouseX = Double(NSEvent.mouseLocation.x)
    }

    /// A ball dropped just above another ball (that isn't already a full snowman) gets stacked on it
    private func stackTarget(for b: Snowball) -> Snowball? {
        var best: Snowball?
        var bestDist = Double.greatestFiniteMagnitude
        for c in balls where c !== b && !c.falling && !c.dragging && !c.node.isHidden {
            guard above(c) == nil, stack(from: base(of: c)).count < 3 else { continue }
            let dx = abs(b.x - c.x), dy = b.y - c.y
            guard dx < c.r * 0.9 + b.r * 0.3, dy > 0, dy < c.r + b.r + 30 else { continue }
            if dx < bestDist { best = c; bestDist = dx }
        }
        return best
    }

    private func removeDecor(stackOf b: Snowball) {
        for x in stack(from: base(of: b)) {
            x.decor?.removeFromParent()
            x.decor = nil
        }
    }

    /// Three stacked balls become a snowman: face and scarf on the head, buttons and stick arms on the body
    private func makeSnowman(_ st: [Snowball]) {
        let body = st[1], head = st[2]
        removeDecor(stackOf: head)
        let R = CGFloat(head.r)

        let h = SKNode()
        h.zPosition = 0.5
        for sx in [-1.0, 1.0] as [CGFloat] {
            let eye = SKShapeNode(circleOfRadius: max(1, R * 0.09))
            eye.fillColor = NSColor(calibratedWhite: 0.08, alpha: 1)
            eye.strokeColor = .clear
            eye.position = CGPoint(x: sx * R * 0.3, y: R * 0.22)
            h.addChild(eye)
        }
        let nose = CGMutablePath()
        nose.move(to: CGPoint(x: R * 0.02, y: R * 0.06))
        nose.addLine(to: CGPoint(x: R * 0.75, y: -R * 0.04))
        nose.addLine(to: CGPoint(x: R * 0.02, y: -R * 0.12))
        nose.closeSubpath()
        let carrot = SKShapeNode(path: nose)
        carrot.fillColor = NSColor(calibratedRed: 0.96, green: 0.52, blue: 0.13, alpha: 1)
        carrot.strokeColor = .clear
        h.addChild(carrot)
        for k in 0..<5 {
            let a = CGFloat.pi * (1.2 + 0.15 * CGFloat(k))
            let dot = SKShapeNode(circleOfRadius: max(0.7, R * 0.05))
            dot.fillColor = NSColor(calibratedWhite: 0.1, alpha: 1)
            dot.strokeColor = .clear
            dot.position = CGPoint(x: cos(a) * R * 0.42, y: sin(a) * R * 0.42 - R * 0.05)
            h.addChild(dot)
        }
        let red = NSColor(calibratedRed: 0.82, green: 0.16, blue: 0.18, alpha: 1)
        let scarf = SKShapeNode(rect: CGRect(x: -R * 0.85, y: -R * 0.98, width: R * 1.7, height: R * 0.3),
                                cornerRadius: R * 0.12)
        scarf.fillColor = red
        scarf.strokeColor = .clear
        h.addChild(scarf)
        let tail = SKShapeNode(rect: CGRect(x: R * 0.3, y: -R * 1.55, width: R * 0.28, height: R * 0.7),
                               cornerRadius: R * 0.08)
        tail.fillColor = red
        tail.strokeColor = .clear
        tail.zRotation = -0.15
        h.addChild(tail)
        head.node.addChild(h)
        head.decor = h

        let B = CGFloat(body.r)
        let bd = SKNode()
        bd.zPosition = 0.5
        for k in 0..<3 {
            let btn = SKShapeNode(circleOfRadius: max(0.8, B * 0.07))
            btn.fillColor = NSColor(calibratedWhite: 0.08, alpha: 1)
            btn.strokeColor = .clear
            btn.position = CGPoint(x: 0, y: B * (0.35 - 0.33 * CGFloat(k)))
            bd.addChild(btn)
        }
        let brown = NSColor(calibratedRed: 0.42, green: 0.28, blue: 0.16, alpha: 1)
        for sx in [-1.0, 1.0] as [CGFloat] {
            let arm = CGMutablePath()
            arm.move(to: CGPoint(x: sx * B * 0.85, y: B * 0.15))
            arm.addLine(to: CGPoint(x: sx * B * 1.75, y: B * 0.65))
            arm.move(to: CGPoint(x: sx * B * 1.4, y: B * 0.45))
            arm.addLine(to: CGPoint(x: sx * B * 1.55, y: B * 0.85))
            let stick = SKShapeNode(path: arm)
            stick.strokeColor = brown
            stick.lineWidth = max(1.2, B * 0.09)
            stick.lineCap = .round
            bd.addChild(stick)
        }
        body.node.addChild(bd)
        body.decor = bd
    }

    // MARK: Snowballs

    /// Is the mouse inside the snow band of this surface (a bit below the edge up to a bit above the snow)?
    private func mouseOver(_ s: Surface, _ mx: Double, _ my: Double) -> Bool {
        guard let c = s.field.col(at: mx), s.field.visible[c] else { return false }
        return my >= s.field.topY - 6 && my <= s.field.surface(c) + 14
    }

    /// Which snow surface is the mouse hovering over? Dock first, then windows front to back, then the ground.
    private func surfaceUnderMouse(_ mx: Double, _ my: Double) -> Surface? {
        // Hovering over a snowball counts as hovering over the snow it sits on. Without this, a big ball
        // stops rolling as soon as the cursor rises above the thin snow band, which makes pushing jerky.
        for b in balls where !b.falling && !b.dragging && !b.node.isHidden && b.below == nil {
            guard let s = b.surface, abs(mx - b.x) < b.r + 8 else { continue }
            if my >= s.field.topY - 6 && my <= s.field.topY + 2 * b.r + 8 { return s }
        }
        if let d = surfaces.dock, d.onScreen {
            if mouseOver(d, mx, my) { return d }
            if d.rect.contains(mx, my) { return nil }
        }
        for s in surfaces.windows {
            if mouseOver(s, mx, my) { return s }
            if s.rect.contains(mx, my) { return nil }      // over a window's content
        }
        if let g = ground, mouseOver(g, mx, my) { return g }
        return nil
    }

    private func updateRolling() {
        guard let m = mouseOnThisDisplay() else { activeBall = nil; return }
        let mx = Double(m.x), my = Double(m.y)
        let dx = mx - lastMouseX
        lastMouseX = mx
        guard let s = surfaceUnderMouse(mx, my) else { activeBall = nil; return }
        guard abs(dx) > 0.2 else { return }

        // Keep rolling the current ball, pick up a resting one under the mouse, or start a new one
        if let b = activeBall, b.surface === s, above(b) == nil, abs(b.x - (mx - dx)) < b.r + 25 {   // ball was at the previous mouse x
            // keep it
        } else if let b = balls.first(where: { !$0.falling && $0.surface === s && abs($0.x - mx) < $0.r + 10 }) {
            guard above(b) == nil else { activeBall = nil; return }   // don't roll the bottom of a snowman
            activeBall = b
        } else if let c = s.field.col(at: mx), s.field.h[c] > 1.5 {
            let b = Snowball(body: ballTex, specks: speckTex)
            b.x = mx
            b.rest(on: s)
            b.y = s.field.topY + b.r - 1.5
            b.layout()
            scene.world.addChild(b.node)
            balls.append(b)
            activeBall = b
            trimBalls()
        } else {
            activeBall = nil
            return
        }
        guard let b = activeBall else { return }

        // Move the ball to the mouse, staying on the surface
        let lo = s.field.minX + b.r, hi = s.field.maxX - b.r
        let newX = lo < hi ? min(max(mx, lo), hi) : b.x
        let moved = newX - b.x
        guard abs(moved) > 0.01 else { return }
        let oldX = b.x
        roll(b, on: s, to: newX)
        push(from: b, oldX: oldX, dir: moved > 0 ? 1 : -1, on: s)
    }

    /// Roll a ball to newX: it picks up snow from the columns it passes over and grows
    private func roll(_ b: Snowball, on s: Surface, to newX: Double) {
        let moved = newX - b.x
        guard abs(moved) > 0.01 else { return }
        if b.r < SnowballController.maxRadius {
            var collected = 0.0
            let from = min(b.x, newX) - b.r * 0.8
            let to = max(b.x, newX) + b.r * 0.8
            let frac = min(0.6, 0.6 * abs(moved) / (1.6 * b.r))
            if let c0 = s.field.col(at: max(from, s.field.minX)),
               let c1 = s.field.col(at: min(to, s.field.maxX - 0.1)), c0 <= c1 {
                for c in c0...c1 where s.field.visible[c] {
                    collected += s.field.take(col: c, fraction: frac)
                }
            }
            // Ball area grows by the snow area it picked up
            let area = Double.pi * b.r * b.r + collected * SnowField.colW * 0.8
            b.r = min(SnowballController.maxRadius, (area / .pi).squareRoot())
        }
        b.x = newX
        b.specks.zRotation -= CGFloat(moved / b.r)     // roll
    }

    /// The moving ball pushes any ball it touches in front of it; that ball can push the next one, and so on.
    /// A ball pushed past the end of a surface falls off.
    private func push(from b: Snowball, oldX: Double, dir: Double, on s: Surface) {
        // Look for balls ahead of where the pusher *was*: after a fast mouse move it may already have
        // jumped past a ball, and that ball must still be pushed instead of being passed through.
        let ahead = balls
            .filter { $0 !== b && !$0.falling && !$0.dragging && $0.surface === s && ($0.x - oldX) * dir > 0 }
            .sorted { abs($0.x - oldX) < abs($1.x - oldX) }
        var pusher = b
        for o in ahead {
            let need = pusher.x + dir * (pusher.r + o.r)     // where o must be to just touch the pusher
            guard (need - o.x) * dir > 0 else { break }       // not touching: the chain stops here
            let lo = s.field.minX + o.r, hi = s.field.maxX - o.r
            if need < lo || need > hi {
                o.x = need
                o.drop(vx: dir * 140, vy: 40)                 // pushed off the edge
            } else {
                roll(o, on: s, to: need)
            }
            pusher = o
        }
    }

    private func trimBalls() {
        while balls.count > SnowballController.maxBalls,
              let i = balls.firstIndex(where: { !$0.falling && !$0.dragging && $0.decor == nil && $0 !== activeBall }) {
            balls[i].node.removeFromParent()
            balls.remove(at: i)
        }
    }

    private func stepBalls(_ dt: Double) {
        let bounds = scene.displayRect
        var i = balls.count - 1
        while i >= 0 {
            let b = balls[i]
            var gone = false
            if b.falling {
                if b.decor != nil { b.decor?.removeFromParent(); b.decor = nil }
                b.node.zPosition = 6.5
                let prevBottom = b.y - b.r
                b.vy -= SnowballController.gravity * dt
                b.x += b.vx * dt
                b.y += b.vy * dt
                b.specks.zRotation -= CGFloat(b.vx * dt / b.r)
                if b.vy < 0, let s = landingSurface(x: b.x, from: prevBottom, to: b.y - b.r) {
                    splat(b, on: s)                  // falling snowballs burst into a heap of snow
                    gone = true
                } else if b.y < bounds.minY - b.r * 2 || b.x < bounds.minX - 100 || b.x > bounds.maxX + 100 {
                    gone = true
                }
            } else if b.dragging {
                // position is set by stepDrag
            } else if let under = b.below {
                if under.falling || under.dragging {
                    b.drop(vx: under.vx + rnd(-40, 40), vy: max(under.vy, 0) + rnd(30, 80))
                } else {
                    b.x = under.x
                    b.y = under.y + under.r + b.r * 0.82   // sits slightly sunk into the ball below
                    b.node.isHidden = under.node.isHidden
                }
            } else if let s = b.surface {
                if s.shedSerial != b.shedSeen {
                    // The window was shaken hard enough to throw snow: the ball goes with it
                    b.shedSeen = s.shedSerial
                    if s.lastShedFraction > 0.3 {
                        b.drop(vx: s.releaseVX + rnd(-30, 30), vy: s.releaseVY + rnd(20, 80))
                    }
                }
                if !b.falling {
                    if s.onScreen, let c = s.field.col(at: b.x) {
                        b.node.isHidden = !s.field.visible[c]     // hidden behind a window in front
                    } else {
                        b.node.isHidden = true
                    }
                    b.y = s.field.topY + b.r - 1.5           // sits slightly sunk into the snow
                }
            } else {
                b.drop(vx: 0, vy: 0)               // lost its support (window closed, ball below removed)
            }
            if gone {
                b.node.removeFromParent()
                balls.remove(at: i)
            } else {
                b.layout()
            }
            i -= 1
        }
    }

    /// First surface a falling ball hits between two heights: the Dock, then window tops (front to back),
    /// then the bottom of the screen. Returns nil if it hits nothing this frame.
    private func landingSurface(x: Double, from top: Double, to bottom: Double) -> Surface? {
        func crosses(_ s: Surface) -> Bool {
            guard let c = s.field.col(at: x), s.field.visible[c] else { return false }
            let y = s.field.surface(c)
            return top >= y && bottom < y
        }
        if let d = surfaces.dock, d.onScreen, crosses(d) { return d }
        for s in surfaces.windows where crosses(s) { return s }
        // The ground catches everything that reaches the bottom, even where a window covers it
        if let g = ground, let c = g.field.col(at: x), bottom < g.field.surface(c) { return g }
        return nil
    }

    /// A falling ball bursts where it lands: its snow becomes a mound on that surface, plus a puff of powder
    private func splat(_ b: Snowball, on s: Surface) {
        if let c0 = s.field.col(at: b.x) {
            let snow = Double.pi * b.r * b.r * 0.7 / SnowField.colW     // ball area -> total column height
            let half = max(2, Int(b.r * 1.4 / SnowField.colW))
            var sum = 0.0
            for o in -half...half { sum += 1 - abs(Double(o)) / Double(half + 1) }
            for o in -half...half {
                let i = c0 + o
                guard i >= 0, i < s.field.count, s.field.visible[i] else { continue }
                s.field.addHeight(col: i, snow * (1 - abs(Double(o)) / Double(half + 1)) / sum)
            }
        }
        scene.model.powder.burst(x: b.x, y: b.y - b.r * 0.5, height: b.r * 0.5, area: 6 + b.r * 2.5,
                                 vx: b.vx * 0.2, vy: 90, spread: 110, source: Int.min, time: scene.model.time)
    }
}
