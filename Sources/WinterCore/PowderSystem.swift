import Foundation

/// Loose snow in the air: what comes off a pile when its window moves, closes or resizes.
///
/// Almost all of it is fine powder: tiny specks with strong air drag that drift, spread and fade within
/// a couple of seconds, settling on whatever surface they reach first. Now and then a compact fragment
/// breaks off; it falls fast and lands with a small puff.
///
/// Storage is struct-of-arrays with a fixed capacity, so stepping never allocates.
public struct PowderSystem {
    public static let powderKind: UInt8 = 0
    public static let fragmentKind: UInt8 = 1
    public static let fragmentVariants = 2
    // Cursor-trail particles ride in the same system: weightless, short-lived, and they never settle
    public static let sparkleKind: UInt8 = 2
    public static let trailFlakeKind: UInt8 = 3
    public static let glowKind: UInt8 = 4
    /// Snow area (px²) carried by one powder particle unless a batch is too big for the budget
    public static let baseGrain = 2.5

    public let capacity: Int
    public private(set) var count = 0
    public private(set) var x: [Double]
    public private(set) var y: [Double]
    public private(set) var vx: [Double]
    public private(set) var vy: [Double]
    public private(set) var size: [Double]
    public private(set) var alpha: [Double]
    public private(set) var age: [Double]
    public private(set) var life: [Double]
    public private(set) var mass: [Double]
    public private(set) var rot: [Double]
    public private(set) var rotSpeed: [Double]
    public private(set) var kind: [UInt8]
    public private(set) var variant: [UInt8]
    private var source: [Int]
    private var ignoreUntil: [Double]

    private var grain = PowderSystem.baseGrain
    private var carry = 0.0
    private var rng: SeededRNG

    // Mass accounting (px²): emitted == airborne + settled + dispersed
    public private(set) var emittedMass = 0.0
    public private(set) var settledMass = 0.0
    public private(set) var dispersedMass = 0.0

    public init(capacity: Int, seed: UInt64) {
        self.capacity = capacity
        rng = SeededRNG(seed: seed)
        let d = [Double](repeating: 0, count: capacity)
        x = d; y = d; vx = d; vy = d; size = d; alpha = d; age = d; life = d; mass = d; rot = d; rotSpeed = d
        ignoreUntil = d
        kind = [UInt8](repeating: 0, count: capacity)
        variant = [UInt8](repeating: 0, count: capacity)
        source = [Int](repeating: 0, count: capacity)
    }

    public var airborneMass: Double {
        var m = carry
        for i in 0..<count { m += mass[i] }
        return m
    }

    // MARK: Emission

    /// Start releasing `totalArea` px² of snow. If that would need more particles than there is room
    /// for, each particle carries more snow instead, so nothing is lost and the count stays bounded.
    public mutating func beginBatch(totalArea: Double) {
        let budget = Double(max(1, min(700, capacity - count)))
        grain = max(PowderSystem.baseGrain, totalArea / budget)
    }

    /// Release `area` px² of snow from a column `height` tall whose base is at (x, y).
    /// `source` is the surface it came from; powder cannot land back on it for a moment.
    public mutating func add(x px: Double, y py: Double, height: Double, area: Double,
                             vx bvx: Double, vy bvy: Double, spread: Double, source src: Int, time: Double) {
        guard area > 0 else { return }
        emittedMass += area
        var a = area
        // Rare compact fragment, only from a reasonably deep column
        if a >= 12, count < capacity, rng.unit() < 0.05 {
            let m = min(a * 0.6, 16)
            a -= m
            let i = count
            count += 1
            x[i] = px; y[i] = py + height * 0.5
            vx[i] = bvx + rng.range(-0.5, 0.5) * spread
            vy[i] = bvy + rng.range(0, 0.4) * spread
            size[i] = (m / .pi).squareRoot() * rng.range(0.85, 1.1)
            alpha[i] = rng.range(0.85, 0.97)
            age[i] = 0; life[i] = 8
            mass[i] = m
            rot[i] = rng.range(0, 6.28); rotSpeed[i] = rng.range(-5, 5)
            kind[i] = PowderSystem.fragmentKind
            variant[i] = UInt8(rng.next() % UInt64(PowderSystem.fragmentVariants))
            source[i] = src; ignoreUntil[i] = time + 0.35
        }
        carry += a
        while carry >= grain {
            carry -= grain
            guard count < capacity else { dispersedMass += grain; continue }
            emitPowder(x: px + rng.range(-1.5, 1.5), y: py + rng.unit() * height,
                       vx: bvx + (rng.unit() + rng.unit() - 1) * spread,
                       vy: bvy + rng.range(-0.15, 0.55) * spread,
                       mass: grain, source: src, time: time)
        }
    }

    public mutating func endBatch() {
        dispersedMass += carry
        carry = 0
        grain = PowderSystem.baseGrain
    }

    /// Convenience for a single small release
    public mutating func burst(x: Double, y: Double, height: Double = 0, area: Double, vx: Double, vy: Double,
                               spread: Double, source: Int, time: Double) {
        beginBatch(totalArea: area)
        add(x: x, y: y, height: height, area: area, vx: vx, vy: vy, spread: spread, source: source, time: time)
        endBatch()
    }

    private mutating func emitPowder(x px: Double, y py: Double, vx pvx: Double, vy pvy: Double,
                                     mass m: Double, source src: Int, time: Double) {
        let i = count
        count += 1
        x[i] = px; y[i] = py; vx[i] = pvx; vy[i] = pvy
        size[i] = rng.range(0.5, 1.4)
        alpha[i] = rng.range(0.35, 0.8)
        age[i] = 0
        life[i] = rng.range(0.9, 2.4)
        mass[i] = m
        rot[i] = rng.range(0, 6.28); rotSpeed[i] = 0
        kind[i] = PowderSystem.powderKind
        variant[i] = UInt8(rng.next() % 3)
        source[i] = src; ignoreUntil[i] = time + 0.35
    }

    /// One cursor-trail particle. It carries no snow, drifts on the wind and fades within about a second.
    public mutating func emitTrail(kind k: UInt8, x px: Double, y py: Double, vx pvx: Double, vy pvy: Double) {
        guard count < capacity else { return }
        let i = count
        count += 1
        x[i] = px; y[i] = py; vx[i] = pvx; vy[i] = pvy
        age[i] = 0
        mass[i] = 0
        rot[i] = rng.range(0, 6.28)
        rotSpeed[i] = rng.range(-2.5, 2.5)
        kind[i] = k
        variant[i] = UInt8(rng.next() % 3)
        source[i] = Int.min; ignoreUntil[i] = 0
        switch k {
        case PowderSystem.sparkleKind:
            size[i] = rng.range(1.2, 2.6); alpha[i] = rng.range(0.7, 1); life[i] = rng.range(0.45, 0.9)
        case PowderSystem.glowKind:
            size[i] = rng.range(3.5, 5.5); alpha[i] = rng.range(0.3, 0.5); life[i] = rng.range(0.7, 1.1)
        default:
            size[i] = rng.range(1.3, 2.6); alpha[i] = rng.range(0.55, 0.9); life[i] = rng.range(0.7, 1.3)
        }
    }

    private mutating func remove(at i: Int) {
        let j = count - 1
        if i != j {
            x[i] = x[j]; y[i] = y[j]; vx[i] = vx[j]; vy[i] = vy[j]; size[i] = size[j]; alpha[i] = alpha[j]
            age[i] = age[j]; life[i] = life[j]; mass[i] = mass[j]; rot[i] = rot[j]; rotSpeed[i] = rotSpeed[j]
            kind[i] = kind[j]; variant[i] = variant[j]; source[i] = source[j]; ignoreUntil[i] = ignoreUntil[j]
        }
        count = j
    }

    public mutating func removeAll() {
        for i in 0..<count { dispersedMass += mass[i] }
        count = 0
    }

    // MARK: Simulation

    /// Opacity to draw particle `i` with: powder fades out over the second half of its life
    @inline(__always) public func opacity(_ i: Int) -> Double {
        let t = age[i] / life[i]
        // Trail particles fade over their whole life; a sparkle is brightest the moment it appears
        let start = kind[i] == PowderSystem.fragmentKind ? 0.9 : (kind[i] >= PowderSystem.sparkleKind ? 0.05 : 0.4)
        return t < start ? alpha[i] : alpha[i] * max(0, 1 - (t - start) / (1 - start))
    }

    public mutating func step(dt: Double, time: Double, wind: WindField, surfaces: SurfaceManager) {
        let bounds = surfaces.bounds
        let powderK = 1 - exp(-4.5 * dt)
        let fragmentK = 1 - exp(-0.5 * dt)
        let jitter = 420 * dt.squareRoot()
        var i = count - 1
        while i >= 0 {
            defer { i -= 1 }
            age[i] += dt
            if age[i] >= life[i] {
                dispersedMass += mass[i]
                remove(at: i)
                continue
            }
            let frag = kind[i] == PowderSystem.fragmentKind
            let air = wind.sample(x: x[i], y: y[i])
            if kind[i] >= PowderSystem.sparkleKind {
                // Trail: nearly weightless, carried by the same wind as the snow
                let k = 1 - exp(-3.0 * dt)
                vy[i] -= (kind[i] == PowderSystem.glowKind ? 15 : 55) * dt
                vx[i] += (air.u - vx[i]) * k
                vy[i] += (air.v - vy[i]) * k
                x[i] += vx[i] * dt
                y[i] += vy[i] * dt
                rot[i] += rotSpeed[i] * dt
                continue
            }
            let k = frag ? fragmentK : powderK
            // Powder is light: drag dominates and it settles at 80-130 px/s. Fragments just fall.
            // Finer grains hang in the air longer, which is what turns a sheet of snow into a cloud.
            vy[i] -= (frag ? 900 : 230 + 270 * size[i]) * dt
            vx[i] += (air.u - vx[i]) * k
            vy[i] += (air.v - vy[i]) * k
            if !frag {
                // Small-scale turbulence the wind grid is too coarse to carry
                vx[i] += (rng.unit() - 0.5) * jitter
                vy[i] += (rng.unit() - 0.5) * jitter
            }
            let prevY = y[i]
            x[i] += vx[i] * dt
            y[i] += vy[i] * dt
            rot[i] += rotSpeed[i] * dt

            if y[i] < prevY {
                let ignore = time < ignoreUntil[i] ? source[i] : Int.min
                if case .landed(let stuck) = surfaces.contact(x: x[i], prevY: prevY, y: y[i], area: mass[i],
                                                             windows: true, cull: false, ignore: ignore, dockGain: 1, display: -1) {
                    settledMass += stuck
                    dispersedMass += mass[i] - stuck
                    let px = x[i], py = y[i], radius = size[i]
                    remove(at: i)
                    if frag { puff(x: px, y: py + 1, strength: radius, time: time) }
                    continue
                }
            }
            if y[i] < bounds.minY - 20 || x[i] < bounds.minX - 80 || x[i] > bounds.maxX + 80 {
                dispersedMass += mass[i]
                remove(at: i)
            }
        }
    }

    /// A few weightless specks kicked up where a fragment lands
    private mutating func puff(x px: Double, y py: Double, strength: Double, time: Double) {
        let n = min(6, capacity - count)
        guard n > 0 else { return }
        for _ in 0..<n {
            emitPowder(x: px + rng.range(-strength, strength), y: py,
                       vx: rng.range(-60, 60), vy: rng.range(30, 110), mass: 0, source: Int.min, time: time)
        }
    }
}
