import Foundation

public enum LightMode: String, CaseIterable, Codable {
    case off, warm, multi
    public var displayName: String { self == .off ? "Off" : (self == .warm ? "Warm White" : "Multicolored") }
}

/// What the cursor (or its companion) leaves behind
public enum TrailStyle: String, CaseIterable, Codable {
    case none, snow, gold, festive
    public var displayName: String {
        switch self {
        case .none: return "None"
        case .snow: return "Snowflakes"
        case .gold: return "Golden Sparkles"
        case .festive: return "Festive Mix"
        }
    }
}

/// Every user choice, in one value. The defaults are Natural Winter: snow only, no sound, no decorations.
public struct AppSettings: Codable, Equatable {
    // Snow
    public var weather = SnowPreset.gentle
    /// Multipliers on the chosen weather
    public var density = 1.0
    public var flakeSize = 1.0
    public var fallSpeed = 1.0
    public var wind = 1.0
    public var accumulation = true
    public var accumulationSpeed = 1.0
    /// Fraction of the built-in maximum pile height
    public var maxHeight = 1.0
    public var melting = false
    public var snowInFront = true
    /// How strongly the cursor stirs falling snow: 0 off, 1 normal, 2 strong
    public var cursorStir = 1.0

    // Cursor
    public var companion = CursorPreset.none
    public var companionSize = 1.0
    public var animation = 1.0
    public var trail = TrailStyle.none
    public var trailIntensity = 1.0

    // Audio: nothing sounds until the user turns it on
    public var bells = false
    public var bellVolume = 0.5
    public var windAmbience = false
    public var ambientVolume = 0.4
    public var muted = false

    // Decorations
    public var lights = LightMode.off
    public var lightBrightness = 1.0
    /// Distance between bulbs (px)
    public var lightSpacing = 26.0
    /// 0 off ... 1 heavy
    public var frost = 0.0
    /// Mean seconds between Santa flyovers; 0 = never
    public var flyoverGap = 0.0
    public var events = false
    public var characters = false

    // Performance
    public var frameRate = 60
    /// Fraction of the full flake budget
    public var particleBudget = 1.0
    /// On battery: 30 fps and thinner snow
    public var batterySaver = true
    public var pauseOnBattery = false
    public var pauseOnLowPower = false
    public var respectReduceMotion = true

    public init() {}

    /// Keep every number inside the range the simulation was tuned for
    public func clamped() -> AppSettings {
        func c(_ v: Double, _ lo: Double, _ hi: Double) -> Double { v.isFinite ? min(hi, max(lo, v)) : lo }
        var s = self
        s.density = c(density, 0.3, 2)
        s.flakeSize = c(flakeSize, 0.6, 1.6)
        s.fallSpeed = c(fallSpeed, 0.5, 1.8)
        s.wind = c(wind, 0, 2)
        s.accumulationSpeed = c(accumulationSpeed, 0.25, 3)
        s.maxHeight = c(maxHeight, 0.25, 1)
        s.cursorStir = c(cursorStir, 0, 2)
        s.companionSize = c(companionSize, 0.6, 1.6)
        s.animation = c(animation, 0, 1.5)
        s.trailIntensity = c(trailIntensity, 0.25, 2)
        s.bellVolume = c(bellVolume, 0, 1)
        s.ambientVolume = c(ambientVolume, 0, 1)
        s.lightBrightness = c(lightBrightness, 0.4, 1.5)
        s.lightSpacing = c(lightSpacing, 16, 44)
        s.frost = c(frost, 0, 1)
        s.flyoverGap = flyoverGap <= 0 ? 0 : c(flyoverGap, 120, 7200)
        s.frameRate = frameRate <= 30 ? 30 : 60
        s.particleBudget = c(particleBudget, 0.25, 1)
        return s
    }

    // MARK: Persistence

    public func encoded() -> Data { (try? JSONEncoder().encode(self)) ?? Data() }

    /// Decode stored settings. Keys missing from `data` (settings added by a newer version) keep
    /// their defaults, and unreadable data gives the defaults instead of failing.
    public static func decode(_ data: Data?) -> AppSettings {
        guard let data,
              let stored = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var merged = try? JSONSerialization.jsonObject(with: AppSettings().encoded()) as? [String: Any] else {
            return AppSettings()
        }
        for (k, v) in stored where merged[k] != nil { merged[k] = v }
        guard let json = try? JSONSerialization.data(withJSONObject: merged),
              let s = try? JSONDecoder().decode(AppSettings.self, from: json) else { return AppSettings() }
        return s.clamped()
    }

    public static let defaultsKey = "settings.v3"

    public static func load(from defaults: UserDefaults) -> AppSettings { decode(defaults.data(forKey: defaultsKey)) }
    public func save(to defaults: UserDefaults) { defaults.set(encoded(), forKey: AppSettings.defaultsKey) }
}

/// Ready-made combinations. Choosing one rewrites the look (snow, cursor, decorations); sound and
/// performance choices are left as the user set them, and everything can be adjusted afterwards.
public enum Theme: String, CaseIterable {
    case quietWinter, christmasEve, santasWorkshop, winterNight, winterPlayground

    public var displayName: String {
        switch self {
        case .quietWinter: return "Quiet Winter"
        case .christmasEve: return "Christmas Eve"
        case .santasWorkshop: return "Santa's Workshop"
        case .winterNight: return "Winter Night"
        case .winterPlayground: return "Winter Playground"
        }
    }

    public func apply(to old: AppSettings) -> AppSettings {
        var s = AppSettings()
        // Not part of a theme: sound and performance
        s.bells = old.bells; s.bellVolume = old.bellVolume; s.windAmbience = old.windAmbience
        s.ambientVolume = old.ambientVolume; s.muted = old.muted
        s.frameRate = old.frameRate; s.particleBudget = old.particleBudget; s.batterySaver = old.batterySaver
        s.pauseOnBattery = old.pauseOnBattery; s.pauseOnLowPower = old.pauseOnLowPower
        s.respectReduceMotion = old.respectReduceMotion
        switch self {
        case .quietWinter:
            s.weather = .light; s.wind = 0.7; s.melting = true; s.cursorStir = 0.5
        case .christmasEve:
            s.weather = .gentle; s.lights = .warm; s.frost = 0.6; s.flyoverGap = 1200; s.events = true
        case .santasWorkshop:
            s.weather = .gentle; s.companion = .sleigh; s.trail = .festive
            s.lights = .multi; s.lightBrightness = 1.3; s.lightSpacing = 20
            s.flyoverGap = 300; s.events = true; s.characters = true
        case .winterNight:
            s.weather = .gentle; s.density = 0.8; s.fallSpeed = 0.8; s.wind = 0.6
            s.frost = 1; s.events = true; s.trail = .gold; s.trailIntensity = 0.6
        case .winterPlayground:
            s.weather = .gentle; s.density = 1.3; s.flakeSize = 1.2; s.accumulationSpeed = 2.5
            s.companion = .hat; s.trail = .snow; s.characters = true
        }
        return s
    }
}
