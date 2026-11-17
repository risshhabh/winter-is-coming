import XCTest
@testable import WinterCore

final class SettingsAndTuningTests: XCTestCase {
    typealias World = SimulationTests.World

    // MARK: Settings persistence

    func testSettingsRoundTripThroughUserDefaults() {
        let d = UserDefaults(suiteName: "wic.tests.\(UUID().uuidString)")!
        var s = AppSettings()
        s.weather = .storm; s.density = 1.7; s.companion = .hat; s.trail = .gold
        s.bells = true; s.bellVolume = 0.2; s.lights = .multi; s.frost = 0.6; s.frameRate = 30
        s.save(to: d)
        XCTAssertEqual(AppSettings.load(from: d), s)
    }

    func testDefaultsAreNaturalWinterAndSilent() {
        let s = AppSettings()
        XCTAssertEqual(s.weather, .gentle)
        XCTAssertEqual(s.companion, .none)
        XCTAssertEqual(s.trail, .none)
        XCTAssertFalse(s.bells)
        XCTAssertFalse(s.windAmbience)
        XCTAssertEqual(s.lights, .off)
        XCTAssertEqual(s.frost, 0)
        XCTAssertEqual(s.flyoverGap, 0)
        XCTAssertFalse(s.events)
        XCTAssertFalse(s.characters)
    }

    func testMissingKeysKeepDefaultsAndUnknownKeysAreIgnored() {
        let data = #"{"weather":"storm","bells":true,"someFutureSetting":3}"#.data(using: .utf8)!
        let s = AppSettings.decode(data)
        XCTAssertEqual(s.weather, .storm)
        XCTAssertTrue(s.bells)
        XCTAssertEqual(s.bellVolume, AppSettings().bellVolume)
        XCTAssertEqual(s.frameRate, 60)
    }

    func testCorruptOrWrongTypedDataFallsBackToDefaults() {
        XCTAssertEqual(AppSettings.decode("not json".data(using: .utf8)), AppSettings())
        XCTAssertEqual(AppSettings.decode(nil), AppSettings())
        XCTAssertEqual(AppSettings.decode(#"{"weather":"hail"}"#.data(using: .utf8)), AppSettings())
    }

    func testOutOfRangeValuesAreClamped() {
        let data = #"{"density":50,"bellVolume":-3,"maxHeight":0,"frameRate":240,"flyoverGap":5}"#.data(using: .utf8)!
        let s = AppSettings.decode(data)
        XCTAssertEqual(s.density, 2)
        XCTAssertEqual(s.bellVolume, 0)
        XCTAssertEqual(s.maxHeight, 0.25)
        XCTAssertEqual(s.frameRate, 60)
        XCTAssertEqual(s.flyoverGap, 120)
        var n = AppSettings()
        n.wind = .nan
        XCTAssertEqual(n.clamped().wind, 0)
    }

    // MARK: Themes

    func testThemesKeepSoundAndPerformanceChoices() {
        var s = AppSettings()
        s.bells = true; s.bellVolume = 0.9; s.muted = true; s.frameRate = 30; s.pauseOnBattery = true
        for theme in Theme.allCases {
            let t = theme.apply(to: s)
            XCTAssertTrue(t.bells, theme.displayName)
            XCTAssertEqual(t.bellVolume, 0.9)
            XCTAssertTrue(t.muted)
            XCTAssertEqual(t.frameRate, 30)
            XCTAssertTrue(t.pauseOnBattery)
            XCTAssertEqual(t, t.clamped(), "\(theme.displayName) must stay within the tuned ranges")
        }
    }

    func testThemesAreDistinctAndCoherent() {
        let all = Theme.allCases.map { $0.apply(to: AppSettings()) }
        XCTAssertEqual(Set(all.map { $0.encoded() }).count, all.count)
        let quiet = Theme.quietWinter.apply(to: AppSettings())
        XCTAssertEqual(quiet.companion, .none)
        XCTAssertEqual(quiet.lights, .off)
        XCTAssertEqual(quiet.flyoverGap, 0)
        let workshop = Theme.santasWorkshop.apply(to: AppSettings())
        XCTAssertEqual(workshop.companion, .sleigh)
        XCTAssertNotEqual(workshop.lights, .off)
        XCTAssertGreaterThan(workshop.flyoverGap, 0)
    }

    // MARK: Weather tuning

    func testWindTuningScalesAndCanStopTheWind() {
        var w = Weather(preset: .storm, seed: 1)
        w.step(dt: 1)
        let normal = w.effective.windMean
        w.tuning.wind = 0
        XCTAssertEqual(w.effective.windMean, 0)
        XCTAssertEqual(w.effective.gust, 0)
        w.tuning.wind = 2
        XCTAssertEqual(w.effective.windMean, normal * 2, accuracy: 1e-9)
    }

    func testAccumulationOffLeavesNoSnow() {
        var world = World(width: 1200, height: 800, preset: .storm)
        world.weather.tuning.accumulation = 0
        world.run(seconds: 30, windows: [WindowInfo(id: 1, rect: Rect(x: 200, y: 200, width: 600, height: 300))])
        XCTAssertEqual(world.surfaces.totalArea, 0)
        XCTAssertGreaterThan(world.flakes.count, 0)
    }

    func testFasterAccumulationBuildsMoreSnow() {
        func area(_ speed: Double) -> Double {
            var world = World(width: 1200, height: 800, preset: .gentle)
            world.weather.tuning.accumulation = speed
            world.run(seconds: 20, windows: [WindowInfo(id: 1, rect: Rect(x: 200, y: 200, width: 600, height: 300))])
            return world.surfaces.totalArea
        }
        XCTAssertGreaterThan(area(2.5), area(1) * 1.8)
    }

    func testFlakeSizeTuningScalesFlakes() {
        func meanSize(_ k: Double) -> Double {
            var world = World(width: 1200, height: 800, preset: .gentle)
            world.weather.tuning.flakeSize = k
            world.run(seconds: 8)
            let f = world.flakes
            return (0..<f.count).map { f.size[$0] }.reduce(0, +) / Double(max(1, f.count))
        }
        XCTAssertEqual(meanSize(1.5) / meanSize(1), 1.5, accuracy: 0.15)
    }

    // MARK: Particle budget

    func testParticleBudgetScalesTheFlakeCount() {
        var full = World(width: 1500, height: 950, preset: .storm)
        var half = World(width: 1500, height: 950, preset: .storm)
        half.env.densityScale = 0.5
        full.run(seconds: 15)
        half.run(seconds: 15)
        let ratio = Double(half.flakes.count) / Double(full.flakes.count)
        XCTAssertEqual(ratio, 0.5, accuracy: 0.15)
        XCTAssertLessThanOrEqual(Double(half.flakes.count), half.flakes.targetCount(env: half.env, weather: half.weather.effective) * 1.1 + 5)
    }

    func testBudgetNeverExceedsCapacityEvenWhenOverDriven() {
        var world = World(width: 1500, height: 950, preset: .storm, capacity: 300)
        world.weather.tuning.density = 2
        world.env.densityScale = 3
        for _ in 0..<20 {
            world.run(seconds: 0.5)
            XCTAssertLessThanOrEqual(world.flakes.count, 300)
        }
    }

    // MARK: Maximum pile height

    func testLoweringMaximumHeightTrimsEveryPile() {
        var world = World(width: 1200, height: 800, preset: .storm)
        world.run(seconds: 120, windows: [WindowInfo(id: 1, rect: Rect(x: 200, y: 200, width: 600, height: 300))])
        guard let s = world.surfaces.surface(id: 1) else { return XCTFail("no window pile") }
        let before = s.field.h.max() ?? 0
        XCTAssertGreaterThan(before, SurfaceManager.windowPileMax * 0.3)
        world.surfaces.heightScale = 0.25
        XCTAssertLessThanOrEqual(s.field.h.max() ?? 0, SurfaceManager.windowPileMax * 0.25 + 1e-9)
        for g in world.surfaces.grounds { XCTAssertLessThanOrEqual(g.field.h.max() ?? 0, SurfaceManager.groundPileMax * 0.25 + 1e-9) }
        // New piles respect it from the start
        world.run(seconds: 1, windows: [WindowInfo(id: 1, rect: Rect(x: 200, y: 200, width: 600, height: 300)),
                                        WindowInfo(id: 2, rect: Rect(x: 850, y: 100, width: 200, height: 200))])
        XCTAssertEqual(world.surfaces.surface(id: 2)?.field.maxH ?? 0, SurfaceManager.windowPileMax * 0.25, accuracy: 1e-9)
    }

    // MARK: Characters and sound

    func testWandererStaysInBoundsAndDoesEverything() {
        var w = Wanderer(x: 500, seed: 9)
        var modes = Set<String>()
        for _ in 0..<(60 * 600) {
            w.step(dt: 1.0 / 60, minX: 100, maxX: 900)
            XCTAssertGreaterThanOrEqual(w.x, 100)
            XCTAssertLessThanOrEqual(w.x, 900)
            modes.insert("\(w.mode)")
        }
        XCTAssertEqual(modes, ["walk", "pause", "slide"])
    }

    func testWindLoopIsQuietBoundedAndSeamless() {
        let loop = BellSynth.windLoop(seconds: 4)
        XCTAssertEqual(loop.count, Int(4 * BellSynth.sampleRate))
        XCTAssertLessThanOrEqual(loop.map { abs($0) }.max() ?? 1, 0.5 + 1e-4)
        XCTAssertFalse(loop.contains { !$0.isFinite })
        // The jump across the loop point is no bigger than an ordinary step between samples
        var biggest: Float = 0
        for i in 1..<loop.count { biggest = max(biggest, abs(loop[i] - loop[i - 1])) }
        XCTAssertLessThanOrEqual(abs(loop[0] - loop[loop.count - 1]), biggest * 1.5)
    }
}
