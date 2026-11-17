import Foundation

/// Rare things that happen in the winter sky. Each one acts through the existing systems (weather,
/// wind, powder particles), so it obeys the same physics and looks like part of the same world.
public enum AtmosEvent: CaseIterable {
    case shootingStar, gust, formation, intensity, blownPowder
}

/// Decides when something rare happens. It keeps the sky quiet: events are minutes apart, never two
/// at once, and a Santa flyover has the stage to itself.
public struct EventDirector {
    /// Shortest time between any two happenings (s)
    public static let minimumGap = 25.0

    /// Small atmospheric events on or off
    public var eventsEnabled = true
    /// Mean time between small events (s)
    public var meanEventGap = 210.0
    /// Mean time between Santa flyovers (s); 0 switches them off
    public var flyoverGap = 0.0 { didSet { if flyoverGap != oldValue { nextFlyover = -1 } } }

    public enum Happening: Equatable {
        case event(AtmosEvent)
        case flyover
    }

    private var nextEvent = -1.0
    private var nextFlyover = -1.0
    private var quietUntil = 0.0
    private var rng: SeededRNG

    public init(seed: UInt64) { rng = SeededRNG(seed: seed) }

    /// Keep everything else away for `seconds` (a flyover is in progress)
    public mutating func hold(for seconds: Double, time: Double) { quietUntil = max(quietUntil, time + seconds) }

    public mutating func step(time: Double) -> Happening? {
        // Schedule lazily, with a wide random spread so nothing recurs like clockwork
        if nextEvent < 0 { nextEvent = time + meanEventGap * rng.range(0.5, 1.5) }
        if nextFlyover < 0, flyoverGap > 0 { nextFlyover = time + flyoverGap * rng.range(0.6, 1.4) }
        guard time >= quietUntil else { return nil }
        if flyoverGap > 0, time >= nextFlyover {
            nextFlyover = -1
            quietUntil = time + EventDirector.minimumGap
            return .flyover
        }
        if eventsEnabled, time >= nextEvent {
            nextEvent = -1
            quietUntil = time + EventDirector.minimumGap
            return .event(AtmosEvent.allCases[Int(rng.next() % UInt64(AtmosEvent.allCases.count))])
        }
        if !eventsEnabled { nextEvent = -1 }
        return nil
    }
}

/// Christmas light strings: pure layout and twinkle, shared by every display.
public enum Lights {
    /// x positions of the bulbs along an edge
    public static func count(length: Double, spacing: Double) -> Int { max(0, Int(length / spacing)) }

    /// How far a bulb hangs below the edge: the wire is pinned every `span` px and sags in between
    public static func sag(at offset: Double, span: Double = 110, depth: Double = 6) -> Double {
        let f = (offset / span).truncatingRemainder(dividingBy: 1)
        return depth * 4 * f * (1 - f)
    }

    /// Brightness of bulb `index` at `time`, 0.55...1. Each bulb follows its own slow rhythm, so the
    /// string shimmers without ever blinking in unison or flashing.
    public static func brightness(index: Int, time: Double) -> Double {
        let n = Noise.value3(time * 0.55, Double(index) * 7.31, 0.5, seed: 0x11687)
        return 0.775 + 0.225 * n
    }
}
