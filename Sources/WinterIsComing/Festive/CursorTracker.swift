import Cocoa

/// Where the cursor is and how fast it is moving, in global coordinates.
///
/// It only reads state (`NSEvent.mouseLocation`, time since the last key press). It installs no event
/// tap or monitor, needs no permission, and cannot delay or swallow an event.
final class CursorTracker {
    private(set) var x = Double(NSEvent.mouseLocation.x)
    private(set) var y = Double(NSEvent.mouseLocation.y)
    private(set) var vx = 0.0
    private(set) var vy = 0.0
    /// True for a moment after each key press, so effects can step back while the user types
    private(set) var typing = false
    private var typingAcc = 0.0
    /// When set, replaces the real cursor (snapshot tool): time -> position
    var script: ((Double) -> (Double, Double))?

    var speed: Double { hypot(vx, vy) }

    func update(dt: Double, time: Double) {
        let p: (Double, Double)
        if let script {
            p = script(time)
        } else {
            let m = NSEvent.mouseLocation
            p = (Double(m.x), Double(m.y))
            typingAcc += dt
            if typingAcc >= 0.1 {
                typingAcc = 0
                typing = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown) < 1.2
            }
        }
        let k = min(1, dt * 20)
        vx += ((p.0 - x) / dt - vx) * k
        vy += ((p.1 - y) / dt - vy) * k
        x = p.0
        y = p.1
    }
}
