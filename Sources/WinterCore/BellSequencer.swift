import Foundation

/// One bell to play.
public struct BellEvent: Equatable {
    /// Which recorded variant
    public var variant: Int
    /// 0...1 before the master volume
    public var gain: Double
    /// -1 left ... 1 right
    public var pan: Double

    public init(variant: Int, gain: Double, pan: Double) {
        self.variant = variant
        self.gain = gain
        self.pan = pan
    }
}

/// Turns cursor movement into sleigh-bell activity. Pure logic: it decides *when* and *how loud*;
/// playing the sounds is someone else's job.
///
/// There are two layers. A continuous, very quiet shimmer whose level follows how fast the cursor is
/// moving, with slow attack and release so it never clicks in or out. And single bells, earned by
/// distance travelled at speed, never by individual mouse events, and held back by a minimum gap and
/// a token budget so a long burst of movement thins out instead of machine-gunning.
public struct BellSequencer {
    public static let maxTokens = 5.0
    /// Speed (px/s) below which no single bell rings
    public static let bellSpeed = 260.0

    public let variants: Int
    /// 0...1 level for the shimmer layer
    public private(set) var shimmerGain = 0.0
    public private(set) var tokens = BellSequencer.maxTokens
    private var distance = 0.0
    private var nextDistance = 700.0
    private var sinceLast = 10.0
    private var gap = 0.3
    private var lastVariant = -1
    private var rng: SeededRNG

    public init(variants: Int, seed: UInt64) {
        self.variants = max(1, variants)
        rng = SeededRNG(seed: seed)
    }

    /// Silence at once (effect switched off)
    public mutating func reset() {
        shimmerGain = 0
        distance = 0
        sinceLast = 10
    }

    /// Advance by `dt` with the cursor moving at `speed` px/s. `pan` is where the cursor is across the
    /// screen (-1...1). Returns a bell to play now, if any.
    public mutating func step(dt: Double, speed: Double, pan: Double) -> BellEvent? {
        // Shimmer follows speed: nothing below a slow drift, full by a brisk sweep
        var target = (speed - 60) / 840
        target = target < 0 ? 0 : (target > 1 ? 1 : target)
        target = target * target * (3 - 2 * target)
        let tau = target > shimmerGain ? 0.22 : 0.55
        shimmerGain += (target - shimmerGain) * min(1, dt / tau)
        if shimmerGain < 0.0005 { shimmerGain = 0 }

        tokens = min(BellSequencer.maxTokens, tokens + 0.7 * dt)
        sinceLast += dt
        guard speed > BellSequencer.bellSpeed else {
            distance = max(0, distance - 300 * dt)          // a pause forgets part of the run-up
            return nil
        }
        distance += speed * dt
        guard distance >= nextDistance, sinceLast >= gap, tokens >= 1 else { return nil }

        tokens -= 1
        distance = 0
        sinceLast = 0
        nextDistance = rng.range(520, 1150)                 // irregular spacing: no mechanical rhythm
        gap = rng.range(0.16, 0.42)
        var v = Int(rng.next() % UInt64(variants))
        if v == lastVariant { v = (v + 1 + Int(rng.next() % UInt64(max(1, variants - 1)))) % variants }
        lastVariant = v
        let energy = min(1, speed / 1800)
        return BellEvent(variant: v, gain: (0.45 + 0.4 * energy) * rng.range(0.75, 1),
                         pan: max(-1, min(1, pan * 0.7 + rng.range(-0.15, 0.15))))
    }
}

/// Original synthesized sounds: no recordings, nothing licensed.
///
/// A sleigh bell is a small metal shell with a loose pellet, so each "ring" is two or three tiny
/// strikes a few hundredths of a second apart, each exciting a handful of high, inharmonic partials
/// that die away quickly.
public enum BellSynth {
    public static let sampleRate = 44_100.0

    static func strike(into out: inout [Float], at start: Double, f0: Double, amp: Double, decay: Double,
                       rng: inout SeededRNG, wrap: Bool) {
        let ratios = [1.0, 1.52, 2.11, 2.83, 3.44]
        let amps = [1.0, 0.6, 0.45, 0.3, 0.2]
        let n = out.count
        let len = Int(decay * 7 * sampleRate)
        let s0 = Int(start * sampleRate)
        for p in 0..<ratios.count {
            let f = f0 * ratios[p] * rng.range(0.995, 1.005)
            guard f < sampleRate * 0.45 else { continue }
            let d = decay / (1 + Double(p) * 0.45)
            let phase = rng.range(0, 2 * .pi)
            for k in 0..<len {
                var i = s0 + k
                if i >= n { if wrap { i %= n } else { break } }
                let t = Double(k) / sampleRate
                // 1 ms attack so the strike has no click
                let attack = min(1, t / 0.001)
                out[i] += Float(amp * amps[p] * attack * exp(-t / d) * sin(2 * .pi * f * t + phase))
            }
        }
    }

    static func normalize(_ out: inout [Float], peak: Float) {
        var m: Float = 0
        for s in out { m = max(m, abs(s)) }
        guard m > 0 else { return }
        let g = peak / m
        for i in 0..<out.count { out[i] *= g }
    }

    /// One bell, about 0.7 s. Variants differ in pitch, decay and the timing of the pellet's rattle.
    public static func bell(variant: Int) -> [Float] {
        var rng = SeededRNG(seed: 0xBE11 &+ UInt64(variant) &* 7919)
        var out = [Float](repeating: 0, count: Int(0.7 * sampleRate))
        let f0 = 2100 + 190 * Double(variant % 8) + rng.range(-40, 40)
        let decay = rng.range(0.07, 0.11)
        strike(into: &out, at: 0, f0: f0, amp: 1, decay: decay, rng: &rng, wrap: false)
        strike(into: &out, at: rng.range(0.018, 0.04), f0: f0 * rng.range(0.99, 1.01), amp: 0.55, decay: decay * 0.9, rng: &rng, wrap: false)
        if variant % 3 != 0 {
            strike(into: &out, at: rng.range(0.06, 0.1), f0: f0 * rng.range(0.99, 1.01), amp: 0.33, decay: decay * 0.8, rng: &rng, wrap: false)
        }
        // Fade the tail to exact silence
        let fade = Int(0.02 * sampleRate)
        for k in 0..<fade { out[out.count - 1 - k] *= Float(k) / Float(fade) }
        normalize(&out, peak: 0.5)
        return out
    }

    /// A seamless loop of faint, scattered jingles: the bed that swells and fades with movement
    public static func shimmerLoop(seconds: Double = 4) -> [Float] {
        var rng = SeededRNG(seed: 0x5117)
        var out = [Float](repeating: 0, count: Int(seconds * sampleRate))
        for _ in 0..<Int(seconds * 9) {
            strike(into: &out, at: rng.range(0, seconds), f0: rng.range(3000, 5600), amp: rng.range(0.15, 0.45),
                   decay: rng.range(0.03, 0.07), rng: &rng, wrap: true)
        }
        normalize(&out, peak: 0.3)
        return out
    }
}
