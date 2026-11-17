import Foundation

public enum CursorPreset: String, CaseIterable {
    case none, sleigh, hat, snowTrail, goldTrail

    public var displayName: String {
        switch self {
        case .none: return "Normal Cursor"
        case .sleigh: return "Santa Sleigh"
        case .hat: return "Santa Hat"
        case .snowTrail: return "Snowflake Trail"
        case .goldTrail: return "Golden Sparkle Trail"
        }
    }

    public var hasCompanion: Bool { self == .sleigh || self == .hat }
    public var hasTrail: Bool { self == .sleigh || self == .snowTrail || self == .goldTrail }
}

/// Motion of the thing that accompanies the cursor (the sleigh, or the hat).
///
/// The real cursor is never touched. The companion is a separate object that chases a point beside
/// the cursor on a critically damped spring, so it arrives smoothly, a little late, without overshoot.
/// Everything the artwork needs to look alive is derived here from that motion: which way it faces,
/// how far it tilts, how fast the reindeer gallop, and a gentle hover when the cursor rests.
public struct CursorCompanion {
    public private(set) var x = 0.0
    public private(set) var y = 0.0
    public private(set) var vx = 0.0
    public private(set) var vy = 0.0
    /// Nose-up (+) or nose-down (-) lean, radians
    public private(set) var tilt = 0.0
    /// +1 facing right, -1 facing left; passes smoothly through 0 while turning round
    public private(set) var facing = 1.0
    /// Phase of the gallop cycle, radians
    public private(set) var gallop = 0.0
    /// 0 = standing, 1 = full gallop
    public private(set) var stride = 0.0
    /// Seconds the cursor has been at rest
    public private(set) var idleTime = 0.0
    /// Vertical hover offset (px) while idle
    public private(set) var hover = 0.0
    private var heading = 1.0
    private var clock = 0.0
    private var placed = false

    public init() {}

    public var speed: Double { hypot(vx, vy) }

    /// - Parameters:
    ///   - offsetX: how far behind the cursor (against the direction it faces) the companion rides
    ///   - offsetY: how far above the cursor
    ///   - stiffness: spring rate in rad/s; lower means a longer delay
    public mutating func update(dt: Double, cursorX: Double, cursorY: Double, offsetX: Double, offsetY: Double,
                                stiffness w: Double) {
        guard dt > 0 else { return }
        clock += dt
        let tx = cursorX - heading * offsetX, ty = cursorY + offsetY
        // First use, or the cursor jumped to another display: appear there instead of streaking across
        if !placed || hypot(tx - x, ty - y) > 2500 {
            x = tx; y = ty; vx = 0; vy = 0
            placed = true
        }
        let ax = w * w * (tx - x) - 2 * w * vx
        let ay = w * w * (ty - y) - 2 * w * vy
        vx += ax * dt
        vy += ay * dt
        x += vx * dt
        y += vy * dt

        let v = hypot(vx, vy)
        // Turn round only for a decided change of direction, so small jitters do not flip it
        if vx > 45 { heading = 1 } else if vx < -45 { heading = -1 }
        facing += (heading - facing) * min(1, dt / 0.14)

        // Lean into climbs and dives, and rock back a little when accelerating
        let lean = max(-0.35, min(0.35, atan2(vy, abs(vx) + 140) * 0.7 + ax * heading * 0.00004))
        tilt += (lean - tilt) * min(1, dt / 0.12)

        if v > 18 {
            idleTime = 0
            stride += (min(1, v / 260) - stride) * min(1, dt / 0.15)
            gallop += (5 + min(11, v / 70)) * dt
        } else {
            idleTime += dt
            // At rest: the team shifts its feet slowly and the whole thing hovers
            stride += (0.12 - stride) * min(1, dt / 0.4)
            gallop += 1.6 * dt
        }
        let rest = min(1, idleTime / 0.6)
        hover = sin(clock * 2.1) * 2.2 * rest
    }
}
