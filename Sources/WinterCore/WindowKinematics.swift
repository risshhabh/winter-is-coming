import Foundation

/// What one update of a moving window does to the snow on it.
public struct ShedResult: Equatable {
    /// Fraction of the pile that leaves the window as powder (0...0.9)
    public var fraction = 0.0
    /// How far part of the pile slides along the window (px, signed; opposite to the acceleration)
    public var slide = 0.0
    /// Fraction of the pile that takes part in the slide
    public var slideFraction = 0.0
}

/// Decides how much snow a moving window loses, from its velocity and acceleration.
///
/// Snow rides along with its window. What dislodges it:
/// - nothing, while the window moves slowly and steadily;
/// - a thin trickle of powder at moderate speed;
/// - a sideways jerk makes part of the pile lag behind and slide along the top;
/// - hard acceleration (a sudden start, an abrupt stop) breaks some of it away;
/// - shaking loosens the pile, so each further jolt throws more than the last.
///
/// Raw mouse-driven window positions are far too noisy to differentiate twice, so velocity is low-pass
/// filtered first.
public struct WindowKinematics {
    /// Below this filtered acceleration (px/s²) nothing breaks away
    public static let accelStart = 5_000.0
    /// At this acceleration a settled pile loses the most a single jolt can take
    public static let accelFull = 26_000.0
    /// Sideways acceleration (px/s²) above which snow starts to slide
    public static let slideStart = 2_500.0
    /// Speed (px/s) above which powder starts to trickle off
    public static let trickleStart = 500.0
    /// Sustained speed (px/s) above which snow streams off
    public static let streamStart = 1_400.0

    public var tau = 0.08
    public private(set) var vx = 0.0
    public private(set) var vy = 0.0
    /// Filtered velocity before the latest update: what loose snow keeps when the window jerks away
    public private(set) var prevVX = 0.0
    public private(set) var prevVY = 0.0
    /// 0 = settled, 1 = thoroughly shaken. Rises with every jolt, relaxes over about a second.
    public private(set) var looseness = 0.0

    public init() {}

    public var speed: Double { hypot(vx, vy) }

    public mutating func reset() {
        vx = 0; vy = 0; prevVX = 0; prevVY = 0; looseness = 0
    }

    /// Feed one displacement sample.
    public mutating func update(dx: Double, dy: Double, dt: Double) -> ShedResult {
        var out = ShedResult()
        guard dt > 0 else { return out }
        let k = 1 - exp(-dt / tau)
        let nvx = vx + (dx / dt - vx) * k
        let nvy = vy + (dy / dt - vy) * k
        let ax = (nvx - vx) / dt
        let accel = hypot(nvx - vx, nvy - vy) / dt
        prevVX = vx
        prevVY = vy
        vx = nvx
        vy = nvy
        looseness *= exp(-dt / 0.7)

        let start = WindowKinematics.accelStart * (1 - 0.4 * looseness)
        if accel > start {
            let t = min(1, (accel - start) / (WindowKinematics.accelFull - start))
            out.fraction += 0.6 * t * (1 + 1.5 * looseness)
            looseness = min(1, looseness + 0.1 + 0.45 * t)
        }
        if abs(ax) > WindowKinematics.slideStart {
            out.slide = (ax > 0 ? -1 : 1) * min(18, (abs(ax) - WindowKinematics.slideStart) / 900)
            out.slideFraction = min(0.6, 0.15 + abs(ax) / 40_000)
        }
        let v = hypot(vx, vy)
        if v > WindowKinematics.trickleStart {
            out.fraction += min(0.25, (v - WindowKinematics.trickleStart) / 4000) * dt
        }
        if v > WindowKinematics.streamStart {
            out.fraction += min(0.5, (v - WindowKinematics.streamStart) / 3000) * dt * 4
        }
        out.fraction = min(0.9, out.fraction)
        return out
    }
}
