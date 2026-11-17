import Foundation

public enum FlakeKind: UInt8, CaseIterable {
    /// Tiny powder-like grain; the bulk of any snowfall
    case speck = 0
    /// Small irregular clump of crystals
    case tuft = 1
    /// Big fluffy aggregate; uncommon
    case large = 2
    /// Recognisable six-armed crystal close to the viewer; rare
    case crystal = 3
}

/// What the flakes need to know about the world each step.
public struct FlakeEnvironment {
    /// The display this flake system covers, in global coordinates
    public var minX = 0.0
    public var minY = 0.0
    public var width: Double
    public var height: Double
    /// Index of that display in `SurfaceManager.displays`
    public var display = 0
    /// Multiplies the weather's density (adaptive quality)
    public var densityScale = 1.0
    /// How strongly the moving cursor disturbs nearby flakes: 0 off, 1 normal
    public var cursorStrength = 1.0
    public var cursorX = 0.0
    public var cursorY = 0.0
    public var cursorVX = 0.0
    public var cursorVY = 0.0
    /// False disables the cursor's air wake (Reduce Motion, or no cursor)
    public var cursorActive = false
    /// Share of small flakes that fall in front of windows instead of behind them (0...1)
    public var foregroundFraction = 0.25

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

/// Falling snowflakes.
///
/// Each flake has its own terminal fall speed and its own responsiveness to the air, and is pulled
/// toward the local wind velocity rather than being moved by a shared function of time. Small flakes
/// follow the air closely; big ones lag and sway. Storage is struct-of-arrays with a fixed capacity,
/// so stepping never allocates and the particle count is bounded by construction.
public struct FlakeSystem {
    /// Texture variants available per kind, indexed by `FlakeKind.rawValue`
    public static let variantCounts = [3, 4, 3, 3]
    static let margin = 40.0
    /// Mean of 1 / terminal speed over the depth range, used to turn a target count into a spawn rate
    static let meanInverseSpeed = 0.02044
    public static let dockGain = 2.5

    public let capacity: Int
    public private(set) var count = 0
    public private(set) var x: [Double]
    public private(set) var y: [Double]
    public private(set) var vx: [Double]
    public private(set) var vy: [Double]
    /// Visual radius in px
    public private(set) var size: [Double]
    public private(set) var alpha: [Double]
    /// 1 normally; drops to 0 as a flake passes behind a window, so it fades instead of popping
    public private(set) var fade: [Double]
    public private(set) var rot: [Double]
    public private(set) var rotSpeed: [Double]
    public private(set) var terminal: [Double]
    public private(set) var response: [Double]
    public private(set) var windFactor: [Double]
    public private(set) var phase: [Double]
    public private(set) var flutterFreq: [Double]
    public private(set) var flutterAmp: [Double]
    public private(set) var kind: [UInt8]
    public private(set) var variant: [UInt8]
    /// Depth band: 0 far, 1 middle, 2 near (drawn in front of the piles)
    public private(set) var band: [UInt8]
    public private(set) var front: [Bool]

    private var spawnDebt = 0.0
    private var rng: SeededRNG

    public private(set) var spawned = 0
    public private(set) var landed = 0
    public private(set) var skippedSpawns = 0

    public init(capacity: Int, seed: UInt64) {
        self.capacity = capacity
        rng = SeededRNG(seed: seed)
        let d = [Double](repeating: 0, count: capacity)
        x = d; y = d; vx = d; vy = d; size = d; alpha = d; fade = d; rot = d; rotSpeed = d
        terminal = d; response = d; windFactor = d; phase = d; flutterFreq = d; flutterAmp = d
        let b = [UInt8](repeating: 0, count: capacity)
        kind = b; variant = b; band = b
        front = [Bool](repeating: false, count: capacity)
    }

    /// How many flakes the weather wants in the air over this screen
    public func targetCount(env: FlakeEnvironment, weather w: WeatherParams) -> Double {
        min(Double(capacity), w.density * env.densityScale * env.width * env.height / WeatherParams.referenceArea)
    }

    // MARK: Spawning

    /// Fill the sky at start-up so the screen does not begin empty
    public mutating func populate(env: FlakeEnvironment, weather: WeatherParams, surfaces: SurfaceManager) {
        let n = Int(targetCount(env: env, weather: weather))
        for _ in 0..<n { spawn(env: env, weather: weather, surfaces: surfaces, y: env.minY + rng.range(0, env.height)) }
    }

    /// Create one flake above the screen (or at `y`). Returns false if there was no room, or if the
    /// flake would only have landed out of sight at the top of the screen.
    @discardableResult
    public mutating func spawn(env: FlakeEnvironment, weather w: WeatherParams, surfaces: SurfaceManager,
                               y startY: Double?) -> Bool {
        guard count < capacity else { return false }
        let px = env.minX + rng.range(-FlakeSystem.margin, env.width + FlakeSystem.margin)

        let pick = rng.unit() * (w.speck + w.tuft + w.large + w.crystal)
        let k: FlakeKind = pick < w.speck ? .speck
            : (pick < w.speck + w.tuft ? .tuft : (pick < w.speck + w.tuft + w.large ? .large : .crystal))

        // Depth: 0 = far away (small, faint, slow), 1 = close
        var z = rng.unit()
        var radius: Double
        var a: Double
        switch k {
        case .speck:
            radius = 0.7 + 0.8 * z + rng.range(0, 0.25)
            a = 0.30 + 0.50 * z
        case .tuft:
            radius = 1.5 + 1.6 * z + rng.range(0, 0.5)
            a = 0.36 + 0.50 * z
        case .large:
            z = 0.55 + 0.45 * z
            radius = 3.1 + rng.range(0, 1.6)
            a = 0.62 + 0.25 * z
        case .crystal:
            z = 0.7 + 0.3 * z
            radius = 4.2 + rng.range(0, 2.4)
            a = 0.78 + 0.15 * z
        }
        a = min(0.95, a + rng.range(-0.07, 0.07))

        let isFront = z < 0.6 && k.rawValue <= FlakeKind.tuft.rawValue && rng.unit() < env.foregroundFraction
        if startY == nil, !isFront, surfaces.isSkyBlocked(px, display: env.display) {
            skippedSpawns += 1
            return false
        }

        let i = count
        count += 1
        spawned += 1
        x[i] = px
        y[i] = startY ?? env.minY + env.height + rng.range(2, 30)
        // Big aggregates are fluffy and fall a little slower than their size suggests
        terminal[i] = (22 + 70 * z) * rng.range(0.85, 1.15) * w.fallSpeed * (k == .large ? 0.85 : 1)
        vx[i] = 0
        vy[i] = -terminal[i]
        size[i] = radius
        alpha[i] = a
        fade[i] = 1
        response[i] = 7 / (1 + radius * 0.8)
        windFactor[i] = 0.45 + 0.65 * z                 // parallax: distant air appears to move less
        phase[i] = rng.range(0, 6.283)
        flutterFreq[i] = rng.range(0.7, 2.3) / (1 + radius * 0.12)
        flutterAmp[i] = radius * rng.range(3.5, 9)
        rot[i] = rng.range(0, 6.283)
        rotSpeed[i] = k == .speck ? 0 : rng.range(-1.1, 1.1)
        kind[i] = k.rawValue
        variant[i] = UInt8(rng.next() % UInt64(FlakeSystem.variantCounts[Int(k.rawValue)]))
        band[i] = z >= 0.72 ? 2 : (z >= 0.4 ? 1 : 0)
        front[i] = isFront
        return true
    }

    private mutating func remove(at i: Int) {
        let j = count - 1
        if i != j {
            x[i] = x[j]; y[i] = y[j]; vx[i] = vx[j]; vy[i] = vy[j]; size[i] = size[j]; alpha[i] = alpha[j]
            fade[i] = fade[j]; rot[i] = rot[j]; rotSpeed[i] = rotSpeed[j]; terminal[i] = terminal[j]
            response[i] = response[j]; windFactor[i] = windFactor[j]; phase[i] = phase[j]
            flutterFreq[i] = flutterFreq[j]; flutterAmp[i] = flutterAmp[j]
            kind[i] = kind[j]; variant[i] = variant[j]; band[i] = band[j]; front[i] = front[j]
        }
        count = j
    }

    public mutating func removeAll() { count = 0 }

    // MARK: Simulation

    public mutating func step(dt: Double, env: FlakeEnvironment, wind: WindField, surfaces: SurfaceManager,
                              weather w: WeatherParams) {
        // Spawn at the rate that keeps the target number airborne over open sky. Because this is a
        // rate and not "top up to N", a screen covered by a maximized window costs almost nothing.
        let rate = targetCount(env: env, weather: w) * w.fallSpeed / (env.height * FlakeSystem.meanInverseSpeed)
        spawnDebt = min(spawnDebt + rate * dt, 40)
        while spawnDebt >= 1 {
            spawnDebt -= 1
            spawn(env: env, weather: w, surfaces: surfaces, y: nil)
        }

        let cursorSpeed = min(2500, hypot(env.cursorVX, env.cursorVY))
        let wake = env.cursorActive && env.cursorStrength > 0 && cursorSpeed > 60
        let wakeRadius = 80.0
        let wakeGain = min(1, dt * 8) * env.cursorStrength
        let left = env.minX - FlakeSystem.margin, right = env.minX + env.width + FlakeSystem.margin
        let floor = env.minY - 20, ceiling = env.minY + env.height + 120
        let wrap = env.width + 2 * FlakeSystem.margin

        var i = count - 1
        while i >= 0 {
            defer { i -= 1 }
            let air = wind.sample(x: x[i], y: y[i])
            phase[i] += flutterFreq[i] * dt
            // Two incommensurate harmonics: a flake never repeats the same sway twice
            let flutter = (sin(phase[i]) + 0.4 * sin(phase[i] * 2.3 + 1.1)) * flutterAmp[i]
            let k = 1 - exp(-response[i] * dt)
            vx[i] += (air.u * windFactor[i] + flutter - vx[i]) * k
            vy[i] += (air.v * windFactor[i] - terminal[i] - vy[i]) * k

            if wake {
                let dx = x[i] - env.cursorX, dy = y[i] - env.cursorY
                let d2 = dx * dx + dy * dy
                if d2 < wakeRadius * wakeRadius {
                    let d = d2.squareRoot()
                    var f = 1 - d / wakeRadius
                    f *= f * wakeGain
                    // Dragged along a little, and pushed aside a little
                    vx[i] += env.cursorVX * 0.25 * f + (d > 1 ? dx / d : 0) * cursorSpeed * 0.08 * f
                    vy[i] += env.cursorVY * 0.25 * f + (d > 1 ? dy / d : 0) * cursorSpeed * 0.08 * f
                }
            }

            let prevY = y[i]
            x[i] += vx[i] * dt
            y[i] += vy[i] * dt
            rot[i] += rotSpeed[i] * dt
            if x[i] < left { x[i] += wrap } else if x[i] > right { x[i] -= wrap }

            let isFront = front[i]
            var behind = false
            if y[i] < prevY {
                switch surfaces.contact(x: x[i], prevY: prevY, y: y[i], area: w.accumulation * 2.0 * size[i],
                                        windows: !isFront, cull: !isFront, ignore: Int.min,
                                        dockGain: FlakeSystem.dockGain, display: env.display) {
                case .landed:
                    landed += 1
                    remove(at: i)
                    continue
                case .behind:
                    behind = true
                case .none:
                    break
                }
            }
            if behind {
                fade[i] -= dt / 0.15
                if fade[i] <= 0 { remove(at: i); continue }
            } else if fade[i] < 1 {
                fade[i] = min(1, fade[i] + dt / 0.3)
            }
            if y[i] < floor || y[i] > ceiling { remove(at: i) }
        }
    }
}
