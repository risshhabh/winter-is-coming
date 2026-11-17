import XCTest
@testable import WinterCore

final class SimulationTests: XCTestCase {
    let W = 1500.0, H = 950.0

    struct World {
        var surfaces: SurfaceManager
        var wind: WindField
        var weather: Weather
        var flakes: FlakeSystem
        var powder: PowderSystem
        var env: FlakeEnvironment
        var time = 0.0

        init(width: Double, height: Double, preset: SnowPreset, seed: UInt64 = 42, capacity: Int = 1600) {
            surfaces = SurfaceManager(width: width, height: height, seed: seed)
            wind = WindField(width: width, height: height, seed: seed)
            weather = Weather(preset: preset, seed: seed)
            flakes = FlakeSystem(capacity: capacity, seed: seed)
            powder = PowderSystem(capacity: 2400, seed: seed)
            env = FlakeEnvironment(width: width, height: height)
        }

        mutating func run(seconds: Double, dt: Double = 1.0 / 60, windows: [WindowInfo]? = nil) {
            var t = 0.0
            while t < seconds {
                t += dt
                time += dt
                if let windows { surfaces.update(windows: windows, dt: dt, time: time, powder: &powder) { _, _ in .keep } }
                weather.step(dt: dt)
                wind.update(time: time, dt: dt, params: weather.wind)
                flakes.step(dt: dt, env: env, wind: wind, surfaces: surfaces, weather: weather.effective)
                powder.step(dt: dt, time: time, wind: wind, surfaces: surfaces)
            }
        }
    }

    // MARK: Flake lifecycle

    func testFlakeCountSettlesNearTargetAndStaysBounded() {
        for preset in SnowPreset.allCases {
            var w = World(width: W, height: H, preset: preset)
            w.run(seconds: 90)
            let target = WeatherParams.preset(preset).density * W * H / WeatherParams.referenceArea
            XCTAssertLessThanOrEqual(w.flakes.count, w.flakes.capacity)
            XCTAssertGreaterThan(Double(w.flakes.count), target * 0.45, "\(preset)")
            XCTAssertLessThan(Double(w.flakes.count), target * 1.6, "\(preset)")
        }
    }

    func testCapacityIsAHardLimit() {
        var w = World(width: W, height: H, preset: .storm, capacity: 120)
        w.run(seconds: 30)
        XCTAssertLessThanOrEqual(w.flakes.count, 120)
        XCTAssertGreaterThan(w.flakes.count, 60)
    }

    func testFlakeStateStaysFiniteAndOnScreen() {
        var w = World(width: W, height: H, preset: .storm)
        w.env.cursorActive = true
        w.env.cursorX = 700; w.env.cursorY = 500; w.env.cursorVX = 2000; w.env.cursorVY = -900
        w.run(seconds: 40)
        for i in 0..<w.flakes.count {
            XCTAssertTrue(w.flakes.x[i].isFinite && w.flakes.y[i].isFinite)
            XCTAssertTrue(w.flakes.x[i] >= -41 && w.flakes.x[i] <= W + 41)
            XCTAssertTrue(w.flakes.alpha[i] > 0 && w.flakes.alpha[i] <= 0.95)
            XCTAssertLessThan(abs(w.flakes.vx[i]), 1500)
        }
    }

    func testFlakesDoNotMoveInUnison() {
        var w = World(width: W, height: H, preset: .gentle)
        w.run(seconds: 20)
        // Horizontal velocities of same-sized flakes should be spread out, not one shared value
        var vxs: [Double] = []
        for i in 0..<w.flakes.count where w.flakes.kind[i] == FlakeKind.tuft.rawValue { vxs.append(w.flakes.vx[i]) }
        let mean = vxs.reduce(0, +) / Double(vxs.count)
        let sd = (vxs.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(vxs.count)).squareRoot()
        XCTAssertGreaterThan(sd, 5)
    }

    func testSizeMixKeepsLargeFlakesUncommon() {
        var w = World(width: W, height: H, preset: .gentle)
        w.run(seconds: 60)
        var counts = [0, 0, 0, 0]
        var maxRadius = 0.0
        for i in 0..<w.flakes.count {
            counts[Int(w.flakes.kind[i])] += 1
            maxRadius = max(maxRadius, w.flakes.size[i])
        }
        let n = Double(w.flakes.count)
        XCTAssertGreaterThan(Double(counts[0]) / n, 0.3, "specks dominate")
        XCTAssertLessThan(Double(counts[2] + counts[3]) / n, 0.2, "large flakes are uncommon")
        XCTAssertLessThan(maxRadius, 7, "no oversized particles")
    }

    func testCursorWakeDisplacesNearbyFlakesOnly() {
        var a = World(width: W, height: H, preset: .gentle, seed: 7)
        var b = World(width: W, height: H, preset: .gentle, seed: 7)
        a.run(seconds: 10); b.run(seconds: 10)
        b.env.cursorActive = true
        b.env.cursorX = 750; b.env.cursorY = 500; b.env.cursorVX = 1800; b.env.cursorVY = 0
        a.run(seconds: 0.1); b.run(seconds: 0.1)
        XCTAssertEqual(a.flakes.count, b.flakes.count)
        var nearMoved = 0, farMoved = 0
        for i in 0..<a.flakes.count {
            let moved = abs(a.flakes.vx[i] - b.flakes.vx[i]) > 1
            let d = hypot(a.flakes.x[i] - 750, a.flakes.y[i] - 500)
            if d < 60 && moved { nearMoved += 1 }
            if d > 200 && moved { farMoved += 1 }
        }
        XCTAssertEqual(farMoved, 0)
        XCTAssertGreaterThan(nearMoved, 0)
    }

    // MARK: Landing

    func testSnowAccumulatesOnWindowsAndGround() {
        var w = World(width: W, height: H, preset: .gentle)
        let win = [WindowInfo(id: 5, rect: Rect(x: 300, y: 200, width: 600, height: 400))]
        w.run(seconds: 120, windows: win)
        let pile = w.surfaces.windows[0].field
        XCTAssertGreaterThan(pile.area, 100)
        XCTAssertGreaterThan(w.surfaces.ground.field.area, 100)
        XCTAssertGreaterThan(w.flakes.landed, 100)
        for i in 0..<pile.count { XCTAssertLessThanOrEqual(pile.h[i], pile.caps[i] + 1e-9) }
    }

    func testStormAccumulatesFasterThanLightSnow() {
        func areaAfter(_ preset: SnowPreset) -> Double {
            var w = World(width: W, height: H, preset: preset)
            w.run(seconds: 60, windows: [WindowInfo(id: 5, rect: Rect(x: 300, y: 200, width: 600, height: 400))])
            return w.surfaces.windows[0].field.area
        }
        let light = areaAfter(.light), gentle = areaAfter(.gentle), storm = areaAfter(.storm)
        XCTAssertLessThan(light, gentle)
        XCTAssertLessThan(gentle, storm)
    }

    func testNoTunnellingAtLowFrameRate() {
        // At 20 fps a fast flake moves several pixels per step; it must still land on a thin pile.
        var w = World(width: W, height: H, preset: .storm)
        let win = [WindowInfo(id: 5, rect: Rect(x: 0, y: 0, width: W, height: 600))]
        w.env.foregroundFraction = 0
        w.run(seconds: 60, dt: 1.0 / 20, windows: win)
        for i in 0..<w.flakes.count where w.flakes.fade[i] >= 1 && w.flakes.x[i] >= 0 && w.flakes.x[i] < W {
            // Nothing should be drifting, fully visible, inside the window's rectangle
            XCTAssertFalse(w.flakes.y[i] < 560, "flake inside window at y=\(w.flakes.y[i])")
        }
        XCTAssertEqual(w.surfaces.ground.field.area, 0, accuracy: 1e-9, "the window covers the whole width")
    }

    func testMaximizedWindowStopsSpawningInsteadOfChurning() {
        var w = World(width: W, height: H, preset: .gentle)
        w.env.foregroundFraction = 0
        let win = [WindowInfo(id: 5, rect: Rect(x: 0, y: 0, width: W, height: H - 30))]
        w.run(seconds: 5, windows: win)
        let before = w.flakes.spawned
        w.run(seconds: 30, windows: win)
        // Only the 40 px margins either side of the screen are open sky
        XCTAssertLessThan(w.flakes.spawned - before, 120)
        XCTAssertGreaterThan(w.flakes.skippedSpawns, 300)
    }

    // MARK: Windows

    func testOcclusionMatchesBruteForce() {
        var rng = SeededRNG(seed: 99)
        for _ in 0..<40 {
            let m = SurfaceManager(width: W, height: H, seed: 1)
            var powder = PowderSystem(capacity: 10, seed: 1)
            var wins: [WindowInfo] = []
            for id in 1...8 {
                wins.append(WindowInfo(id: id, rect: Rect(x: rng.range(-100, 1300), y: rng.range(0, 700),
                                                         width: rng.range(120, 700), height: rng.range(80, 500))))
            }
            m.update(windows: wins, dt: 1.0 / 30, time: 0, powder: &powder) { _, _ in .keep }
            for (i, s) in m.windows.enumerated() {
                for c in 0..<s.field.count {
                    let px = s.field.colX(c), py = s.field.topY + 1
                    var expect = px >= 0 && px <= W && py <= H
                    for j in 0..<i where m.windows[j].rect.contains(px, py) { expect = false }
                    XCTAssertEqual(s.field.visible[c], expect, "window \(i) column \(c)")
                }
            }
        }
    }

    func testReorderingAndSpaceSwitchLoseNoSnow() {
        var w = World(width: W, height: H, preset: .storm)
        let a = WindowInfo(id: 1, rect: Rect(x: 200, y: 200, width: 500, height: 300))
        let b = WindowInfo(id: 2, rect: Rect(x: 400, y: 300, width: 500, height: 300))
        w.run(seconds: 60, windows: [a, b])
        let areaA = w.surfaces.surface(id: 1)!.field.area
        XCTAssertGreaterThan(areaA, 50)

        // Bring b in front of a, then a back in front
        w.surfaces.update(windows: [b, a], dt: 1.0 / 30, time: w.time, powder: &w.powder) { _, _ in .keep }
        w.surfaces.update(windows: [a, b], dt: 1.0 / 30, time: w.time, powder: &w.powder) { _, _ in .keep }
        XCTAssertEqual(w.surfaces.surface(id: 1)!.field.area, areaA, accuracy: 1e-9)

        // Both leave the screen but still exist (Space switch), then come back
        w.surfaces.update(windows: [], dt: 1.0 / 30, time: w.time, powder: &w.powder) { _, _ in .keep }
        XCTAssertEqual(w.surfaces.windows.count, 0)
        XCTAssertEqual(w.surfaces.hiddenCount, 2)
        XCTAssertEqual(w.powder.count, 0, "nothing should fall when a window merely goes off screen")
        w.surfaces.update(windows: [a, b], dt: 1.0 / 30, time: w.time, powder: &w.powder) { _, _ in .keep }
        XCTAssertEqual(w.surfaces.surface(id: 1)!.field.area, areaA, accuracy: 1e-9)

        // Closing really does drop the snow
        w.surfaces.update(windows: [b], dt: 1.0 / 30, time: w.time, powder: &w.powder) { _, _ in .drop }
        XCTAssertNil(w.surfaces.surface(id: 1))
        XCTAssertGreaterThan(w.powder.count, 0)
    }

    func testSlowDragKeepsSnowAndShakeShedsIt() {
        func filled() -> World {
            var w = World(width: W, height: H, preset: .storm)
            w.run(seconds: 90, windows: [WindowInfo(id: 1, rect: Rect(x: 300, y: 300, width: 600, height: 300))])
            return w
        }
        // Slow drag: 300 px/s for one second, starting and stopping abruptly, with jittery samples
        var w = filled()
        var rng = SeededRNG(seed: 5)
        let start = w.surfaces.surface(id: 1)!.field.area
        var x = 300.0
        let dt = 1.0 / 60
        for step in 0..<90 {
            if step < 60 { x += 300 * dt + rng.range(-0.8, 0.8) }
            w.surfaces.update(windows: [WindowInfo(id: 1, rect: Rect(x: x, y: 300, width: 600, height: 300))],
                              dt: dt, time: w.time, powder: &w.powder) { _, _ in .keep }
        }
        let s = w.surfaces.surface(id: 1)!
        XCTAssertGreaterThanOrEqual(s.field.area, start * 0.95)
        XCTAssertEqual(s.field.minX, x, accuracy: 1e-9, "the pile rides with the window")

        // Shake: three fast reversals
        var v = filled()
        let start2 = v.surfaces.surface(id: 1)!.field.area
        var t = 0.0
        for _ in 0..<36 {
            t += dt
            let sx = 300 + 70 * sin(t * 2 * .pi * 5)
            v.surfaces.update(windows: [WindowInfo(id: 1, rect: Rect(x: sx, y: 300, width: 600, height: 300))],
                              dt: dt, time: v.time, powder: &v.powder) { _, _ in .keep }
        }
        XCTAssertLessThan(v.surfaces.surface(id: 1)!.field.area, start2 * 0.25)
        XCTAssertGreaterThan(v.powder.count, 50)
    }

    // MARK: Powder

    func testPowderMassIsAccountedFor() {
        var w = World(width: W, height: H, preset: .storm)
        let win = WindowInfo(id: 1, rect: Rect(x: 300, y: 300, width: 600, height: 300))
        w.run(seconds: 90, windows: [win])
        let pile = w.surfaces.surface(id: 1)!.field.area
        w.surfaces.update(windows: [], dt: 1.0 / 60, time: w.time, powder: &w.powder) { _, _ in .drop }
        XCTAssertEqual(w.powder.emittedMass, pile, accuracy: 1e-6)
        XCTAssertLessThanOrEqual(w.powder.count, w.powder.capacity)
        for _ in 0..<5 {
            w.run(seconds: 1)
            XCTAssertEqual(w.powder.emittedMass, w.powder.airborneMass + w.powder.settledMass + w.powder.dispersedMass,
                           accuracy: 1e-6)
        }
        w.run(seconds: 10)
        XCTAssertEqual(w.powder.count, 0, "powder settles or fades; it never lingers")
    }

    func testPowderIsMostlyFineAndSlowsQuickly() {
        var powder = PowderSystem(capacity: 2400, seed: 3)
        let surfaces = SurfaceManager(width: W, height: H, seed: 3)
        var wind = WindField(width: W, height: H, seed: 3)
        wind.update(time: 0, dt: 0, params: WindParams(mean: 0, turbulence: 0, gust: 0))
        powder.beginBatch(totalArea: 200 * 30)
        for k in 0..<200 {
            powder.add(x: 400 + Double(k) * 3, y: 600, height: 10, area: 30, vx: 900, vy: 0, spread: 60,
                       source: 1, time: 0)
        }
        powder.endBatch()
        var fragments = 0
        for i in 0..<powder.count where powder.kind[i] == PowderSystem.fragmentKind { fragments += 1 }
        XCTAssertGreaterThan(powder.count, 500)
        XCTAssertLessThan(Double(fragments) / Double(powder.count), 0.03, "compact fragments are rare")
        for i in 0..<powder.count where powder.kind[i] == PowderSystem.powderKind {
            XCTAssertLessThan(powder.size[i], 1.5, "powder is fine")
        }
        for step in 0..<30 {
            powder.step(dt: 1.0 / 60, time: Double(step) / 60, wind: wind, surfaces: surfaces)
        }
        var meanVX = 0.0, n = 0.0
        for i in 0..<powder.count where powder.kind[i] == PowderSystem.powderKind { meanVX += powder.vx[i]; n += 1 }
        XCTAssertLessThan(meanVX / n, 900 * 0.2, "air drag should have taken most of the throw within half a second")
    }

    func testHugeReleaseStaysWithinCapacity() {
        var powder = PowderSystem(capacity: 300, seed: 3)
        powder.beginBatch(totalArea: 500 * 48)
        for k in 0..<500 {
            powder.add(x: Double(k) * 3, y: 600, height: 16, area: 48, vx: 0, vy: 0, spread: 40, source: 1, time: 0)
        }
        powder.endBatch()
        XCTAssertLessThanOrEqual(powder.count, 300)
        XCTAssertEqual(powder.emittedMass, powder.airborneMass + powder.dispersedMass, accuracy: 1e-6)
        XCTAssertGreaterThan(powder.airborneMass, powder.emittedMass * 0.9, "the budget is met by heavier grains, not lost snow")
    }

    // MARK: Long runs and cost

    func testMeltingReachesSteadyState() {
        var w = World(width: W, height: H, preset: .gentle)
        let win = [WindowInfo(id: 1, rect: Rect(x: 300, y: 300, width: 600, height: 300))]
        var samples: [Double] = []
        for _ in 0..<40 {
            for _ in 0..<15 {
                w.run(seconds: 2, dt: 1.0 / 30, windows: win)
                w.surfaces.settle(dt: 2, meltRate: 0.03)
            }
            samples.append(w.surfaces.surface(id: 1)!.field.area)
        }
        let cap = w.surfaces.surface(id: 1)!.field.caps.reduce(0, +) * SnowField.colW
        let late = samples.suffix(10)
        XCTAssertGreaterThan(late.min()!, 0)
        XCTAssertLessThan(late.max()!, cap * 0.9, "with melting on, piles should not saturate")
        XCTAssertLessThan(late.max()! - late.min()!, cap * 0.35)
    }

    func testSimulationStepIsCheap() {
        var w = World(width: W, height: H, preset: .storm)
        var rng = SeededRNG(seed: 8)
        var wins: [WindowInfo] = []
        for id in 1...40 {
            wins.append(WindowInfo(id: id, rect: Rect(x: rng.range(0, 1200), y: rng.range(0, 700),
                                                     width: rng.range(150, 500), height: rng.range(100, 400))))
        }
        w.run(seconds: 20, windows: wins)
        XCTAssertGreaterThan(w.flakes.count, 100)
        let steps = 600
        let t0 = Date()
        for _ in 0..<steps {
            w.time += 1.0 / 60
            w.wind.update(time: w.time, dt: 1.0 / 60, params: w.weather.wind)
            w.flakes.step(dt: 1.0 / 60, env: w.env, wind: w.wind, surfaces: w.surfaces, weather: w.weather.effective)
            w.powder.step(dt: 1.0 / 60, time: w.time, wind: w.wind, surfaces: w.surfaces)
        }
        let perStep = Date().timeIntervalSince(t0) / Double(steps)
        print("simulation step with \(w.flakes.count) flakes and 40 windows: \(perStep * 1000) ms")
        #if !DEBUG
        XCTAssertLessThan(perStep, 0.0005)
        #endif
    }
}
