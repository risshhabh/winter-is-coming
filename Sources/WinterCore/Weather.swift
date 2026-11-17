import Foundation

public enum SnowPreset: String, CaseIterable {
    case light, gentle, storm

    public var displayName: String {
        switch self {
        case .light: return "Light Snow"
        case .gentle: return "Gentle Snowfall"
        case .storm: return "Snowstorm"
        }
    }
}

/// Everything about the weather that the particle systems read.
public struct WeatherParams: Equatable {
    /// Screen area (px²) that `density` refers to
    public static let referenceArea = 1_500_000.0

    /// Airborne flakes per reference area
    public var density: Double
    /// Mix of flake kinds; the four weights sum to 1
    public var speck: Double
    public var tuft: Double
    public var large: Double
    public var crystal: Double
    /// Fall speed multiplier
    public var fallSpeed: Double
    /// Prevailing wind speed (px/s, magnitude)
    public var windMean: Double
    public var turbulence: Double
    public var gust: Double
    /// How much snow one landing flake contributes
    public var accumulation: Double

    public static func preset(_ p: SnowPreset) -> WeatherParams {
        switch p {
        case .light:
            return WeatherParams(density: 140, speck: 0.62, tuft: 0.335, large: 0.04, crystal: 0.005,
                                 fallSpeed: 0.8, windMean: 6, turbulence: 9, gust: 4, accumulation: 0.8)
        case .gentle:
            return WeatherParams(density: 340, speck: 0.50, tuft: 0.41, large: 0.075, crystal: 0.015,
                                 fallSpeed: 1.0, windMean: 14, turbulence: 16, gust: 14, accumulation: 1.0)
        case .storm:
            // A storm is dense, fine and fast, not big and fluffy
            return WeatherParams(density: 800, speck: 0.64, tuft: 0.32, large: 0.036, crystal: 0.004,
                                 fallSpeed: 1.55, windMean: 70, turbulence: 38, gust: 75, accumulation: 1.35)
        }
    }

    public static func lerp(_ a: WeatherParams, _ b: WeatherParams, _ t: Double) -> WeatherParams {
        func m(_ x: Double, _ y: Double) -> Double { x + (y - x) * t }
        return WeatherParams(density: m(a.density, b.density), speck: m(a.speck, b.speck), tuft: m(a.tuft, b.tuft),
                             large: m(a.large, b.large), crystal: m(a.crystal, b.crystal),
                             fallSpeed: m(a.fallSpeed, b.fallSpeed), windMean: m(a.windMean, b.windMean),
                             turbulence: m(a.turbulence, b.turbulence), gust: m(a.gust, b.gust),
                             accumulation: m(a.accumulation, b.accumulation))
    }
}

/// Eases between presets and adds slow natural variation on top, so the snowfall is never static.
public struct Weather {
    public private(set) var preset: SnowPreset
    /// Preset values after easing, before natural variation
    public private(set) var current: WeatherParams
    public private(set) var time = 0.0
    /// Seconds for a preset change to be about two-thirds complete
    public var transitionTau = 3.5
    /// Calm mode (Reduce Motion): little wind, no gusts, sparser snow
    public var calm = false
    private var calmBlend = 0.0
    /// A passing gust (atmospheric event): 1 at its peak, gone within seconds
    public private(set) var gustBoost = 0.0
    /// A spell of heavier or lighter snow (atmospheric event): eases back over about a minute
    public private(set) var intensityShift = 0.0
    public let seed: UInt64

    public init(preset: SnowPreset, seed: UInt64) {
        self.preset = preset
        self.seed = seed
        current = .preset(preset)
    }

    public mutating func setPreset(_ p: SnowPreset, immediate: Bool = false) {
        preset = p
        if immediate { current = .preset(p) }
    }

    /// A brief gust sweeps through
    public mutating func triggerGust() { gustBoost = 1 }
    /// The snowfall thickens (positive) or thins (negative) for a while
    public mutating func shiftIntensity(_ amount: Double) { intensityShift = max(-0.4, min(0.5, amount)) }

    public mutating func step(dt: Double) {
        time += dt
        gustBoost *= exp(-dt / 2.5)
        intensityShift *= exp(-dt / 45)
        let k = 1 - exp(-dt / transitionTau)
        current = .lerp(current, .preset(preset), k)
        calmBlend += ((calm ? 1 : 0) - calmBlend) * k
    }

    /// Slow drift of overall intensity, about ±30% over a few minutes
    public var intensity: Double {
        1 + 0.22 * Noise.value1(time / 95, seed: seed) + 0.09 * Noise.value1(time / 31, seed: seed ^ 0x11) + intensityShift
    }

    /// Prevailing wind direction and strength in -1...1; turns around slowly and passes through calm
    public var windDirection: Double {
        let d = Noise.value1(time / 180 + 0.37, seed: seed ^ 0x22) * 2.6
        return d < -1 ? -1 : (d > 1 ? 1 : d)
    }

    /// Parameters for this moment: eased preset, natural variation, calm mode
    public var effective: WeatherParams {
        var p = current
        p.density *= intensity * (1 - 0.4 * calmBlend)
        p.windMean *= 1 - 0.7 * calmBlend
        p.turbulence *= 1 - 0.7 * calmBlend
        p.gust *= 1 - calmBlend
        p.windMean *= 1 + 1.2 * gustBoost
        p.turbulence *= 1 + 0.8 * gustBoost
        p.gust = p.gust * (1 + 1.5 * gustBoost) + 25 * gustBoost * (1 - calmBlend)
        return p
    }

    public var wind: WindParams {
        let p = effective
        return WindParams(mean: p.windMean * windDirection, turbulence: p.turbulence, gust: p.gust)
    }
}
