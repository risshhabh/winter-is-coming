import XCTest
@testable import WinterCore

/// Windows, the Dock, several displays and the cursor.
final class InteractionTests: XCTestCase {
    let W = 1500.0, H = 950.0
    let dt = 1.0 / 60

    /// A manager with one window carrying a full-ish pile, built by depositing directly
    func loaded(width: Double = 600, corner: Double = 0) -> (SurfaceManager, PowderSystem) {
        let m = SurfaceManager(width: W, height: H, seed: 21)
        m.cornerRadius = corner
        var powder = PowderSystem(capacity: 2400, seed: 21)
        m.update(windows: [WindowInfo(id: 1, rect: Rect(x: 300, y: 300, width: width, height: 300))],
                 dt: dt, time: 0, powder: &powder) { _, _ in .keep }
        let s = m.surface(id: 1)!
        var rng = SeededRNG(seed: 4)
        for _ in 0..<6000 { s.field.deposit(x: rng.range(300, 300 + width), area: 4) }
        return (m, powder)
    }

    /// Move window 1 along `path(t)` for `seconds`, returning the fraction of snow left
    func drive(_ m: SurfaceManager, _ powder: inout PowderSystem, seconds: Double, path: (Double) -> Double) -> Double {
        let start = m.surface(id: 1)!.field.area
        var t = 0.0
        while t < seconds {
            t += dt
            m.update(windows: [WindowInfo(id: 1, rect: Rect(x: 300 + path(t), y: 300, width: 600, height: 300))],
                     dt: dt, time: t, powder: &powder) { _, _ in .keep }
        }
        return m.surface(id: 1)!.field.area / start
    }

    /// Smooth start and stop, like a hand on a trackpad
    func eased(_ distance: Double, over seconds: Double) -> (Double) -> Double {
        { t in
            let u = min(1, t / seconds)
            return distance * (u * u * (3 - 2 * u))
        }
    }

    // MARK: Window movement

    func testSlowMovementKeepsEverything() {
        var (m, powder) = loaded()
        let left = drive(m, &powder, seconds: 2.5) { self.eased(400, over: 2)($0) }      // peaks at 300 px/s
        XCTAssertGreaterThan(left, 0.99)
        XCTAssertEqual(powder.count, 0)
    }

    func testModerateMovementTricklesALittlePowder() {
        var (m, powder) = loaded()
        let left = drive(m, &powder, seconds: 1.6) { self.eased(1000, over: 1.2)($0) }   // peaks at 1250 px/s
        XCTAssertLessThan(left, 0.995, "some powder should come off")
        XCTAssertGreaterThan(left, 0.75, "but most of the pile stays")
        XCTAssertGreaterThan(powder.count, 0)
    }

    func testSuddenAccelerationBreaksSomeAway() {
        var (m, powder) = loaded()
        // Instant jump to 900 px/s, then steady
        let left = drive(m, &powder, seconds: 0.5) { 900 * $0 }
        XCTAssertLessThan(left, 0.9)
        XCTAssertGreaterThan(left, 0.35, "one jolt does not clear the pile")
    }

    func testRepeatedShakingScattersMoreEachTime() {
        var k = WindowKinematics()
        // The same jolt, three times in quick succession
        func jolt() -> Double {
            var total = 0.0
            total += k.update(dx: 12, dy: 0, dt: dt).fraction
            for _ in 0..<12 { total += k.update(dx: 0, dy: 0, dt: dt).fraction }
            return total
        }
        let first = jolt(), second = jolt(), third = jolt()
        XCTAssertGreaterThan(first, 0)
        XCTAssertGreaterThan(second, first * 1.05)
        XCTAssertGreaterThanOrEqual(third, second)
        // Left alone, the pile settles again
        for _ in 0..<240 { _ = k.update(dx: 0, dy: 0, dt: dt) }
        XCTAssertLessThan(k.looseness, 0.01)
        XCTAssertEqual(jolt(), first, accuracy: first * 0.05)

        var (m, powder) = loaded()
        let left = drive(m, &powder, seconds: 1.0) { 60 * sin($0 * 2 * .pi * 4) }
        XCTAssertLessThan(left, 0.1, "a second of shaking clears nearly everything")
    }

    func testJerkMakesSnowSlideOppositeToTheMotion() {
        var k = WindowKinematics()
        let right = k.update(dx: 10, dy: 0, dt: dt)
        XCTAssertLessThan(right.slide, 0, "window jerks right, snow lags to the left")
        XCTAssertGreaterThan(right.slideFraction, 0)
        k.reset()
        XCTAssertGreaterThan(k.update(dx: -10, dy: 0, dt: dt).slide, 0)
        k.reset()
        XCTAssertEqual(k.update(dx: 2, dy: 0, dt: dt).slide, 0, "a gentle start slides nothing")
    }

    func testSlideConservesSnow() {
        var f = SnowField(minX: 0, topY: 100, width: 600, maxH: 16, seed: 3)
        var rng = SeededRNG(seed: 1)
        for _ in 0..<3000 { f.deposit(x: rng.range(0, 600), area: 4) }
        let before = f.area
        let centreBefore = centroid(f)
        var cut = 0.0
        f.slide(columns: 5, fraction: 0.5) { _, _, area in cut += area }
        XCTAssertEqual(f.area + cut, before, accuracy: 1e-6)
        XCTAssertGreaterThan(centroid(f), centreBefore, "snow moved toward +x")
        for i in 0..<f.count { XCTAssertLessThanOrEqual(f.h[i], f.caps[i] + 1e-9) }
    }

    func centroid(_ f: SnowField) -> Double {
        var m = 0.0, mx = 0.0
        for i in 0..<f.count { m += f.h[i]; mx += f.h[i] * f.colX(i) }
        return mx / m
    }

    func testEverySnowflakeIsAccountedForWhileMoving() {
        var (m, powder) = loaded()
        let start = m.surface(id: 1)!.field.area
        _ = drive(m, &powder, seconds: 1.2) { 80 * sin($0 * 2 * .pi * 3) + 300 * $0 }
        XCTAssertEqual(m.surface(id: 1)!.field.area + powder.emittedMass, start, accuracy: 1e-6)
    }

    // MARK: Leaving the screen

    func testVanishedWindowWaitsThenDropsOrKeeps() {
        var (m, powder) = loaded()
        let area = m.surface(id: 1)!.field.area

        // Undecided: still drawn, nothing falls, no flakes land on it
        m.update(windows: [], dt: dt, time: 1, powder: &powder) { _, _ in .wait }
        XCTAssertEqual(m.limbo.count, 1)
        XCTAssertEqual(m.windows.count, 0)
        XCTAssertEqual(powder.count, 0)
        if case .landed = m.contact(x: 600, prevY: 700, y: 590, area: 1, windows: true, cull: true, ignore: Int.min, dockGain: 1) {
            XCTFail("a window in limbo should not catch snow")
        }

        // It comes back before a decision: nothing was lost
        m.update(windows: [WindowInfo(id: 1, rect: Rect(x: 300, y: 300, width: 600, height: 300))],
                 dt: dt, time: 1.1, powder: &powder) { _, _ in .wait }
        XCTAssertEqual(m.limbo.count, 0)
        XCTAssertEqual(m.surface(id: 1)!.field.area, area, accuracy: 1e-9)

        // Minimized (decision arrives after a wait): the snow falls
        var asked: [Double] = []
        m.update(windows: [], dt: dt, time: 2, powder: &powder) { _, e in asked.append(e); return .wait }
        m.update(windows: [], dt: dt, time: 2.5, powder: &powder) { _, e in asked.append(e); return e > 0.4 ? .drop : .wait }
        XCTAssertEqual(asked[0], 0, accuracy: 1e-9)
        XCTAssertEqual(asked[1], 0.5, accuracy: 1e-9)
        XCTAssertNil(m.surface(id: 1))
        XCTAssertEqual(powder.emittedMass, area, accuracy: 1e-6)
    }

    func testUnchangedWindowListCostsNothing() {
        var (m, powder) = loaded()
        let win = [WindowInfo(id: 1, rect: Rect(x: 300, y: 300, width: 600, height: 300))]
        let layout = m.layoutVersion
        let before = m.skippedUpdates
        for i in 0..<100 { m.update(windows: win, dt: dt, time: Double(i) * dt, powder: &powder) { _, _ in .keep } }
        XCTAssertEqual(m.skippedUpdates - before, 100)
        XCTAssertEqual(m.layoutVersion, layout)

        // After a move the fast path resumes once the window has come to rest
        let moved = [WindowInfo(id: 1, rect: Rect(x: 340, y: 300, width: 600, height: 300))]
        for i in 0..<120 { m.update(windows: moved, dt: dt, time: 2 + Double(i) * dt, powder: &powder) { _, _ in .keep } }
        XCTAssertGreaterThan(m.skippedUpdates - before, 150)
    }

    // MARK: Edges and corners

    func testSnowFollowsRoundedCorners() {
        let square = SnowField(minX: 0, topY: 100, width: 600, maxH: 16, seed: 3)
        let round = SnowField(minX: 0, topY: 100, width: 600, maxH: 16, seed: 3, cornerRadius: 16)
        XCTAssertEqual(square.base.min()!, 0)
        // The supporting line dips at both ends and is level in the middle
        XCTAssertLessThan(round.base[1], -1)
        XCTAssertLessThan(round.base[round.count - 2], -1)
        XCTAssertEqual(round.base[round.count / 2], 0)
        XCTAssertGreaterThanOrEqual(round.base.min()!, -16 * 0.45 - 1e-9)
        // The steepest part of the corner holds nothing
        XCTAssertEqual(round.caps[0], 0)
        XCTAssertGreaterThan(round.caps[4], 0)
        // Nothing sticks out past the curve: the surface never rises above the corner's own height + cap
        for i in 0..<round.count { XCTAssertLessThanOrEqual(round.surface(i), 100 + round.base[i] + round.caps[i] + 1e-9) }
        // Away from the corners both behave the same
        XCTAssertEqual(round.caps[100], square.caps[100], accuracy: 1e-9)
    }

    func testWindowPartlyOffScreenOnlyCollectsWhereVisible() {
        let m = SurfaceManager(width: W, height: H, seed: 2)
        var powder = PowderSystem(capacity: 100, seed: 2)
        m.update(windows: [WindowInfo(id: 1, rect: Rect(x: -200, y: 300, width: 600, height: 300))],
                 dt: dt, time: 0, powder: &powder) { _, _ in .keep }
        let f = m.surface(id: 1)!.field
        XCTAssertFalse(f.visible[f.col(at: -100)!])
        XCTAssertTrue(f.visible[f.col(at: 100)!])
        // A window dragged mostly below the menu bar's reach: top edge above the display
        m.update(windows: [WindowInfo(id: 1, rect: Rect(x: 100, y: 800, width: 600, height: 300))],
                 dt: dt, time: 1, powder: &powder) { _, _ in .keep }
        XCTAssertFalse(m.surface(id: 1)!.field.visible.contains(true))
    }

    // MARK: Dock

    func testDockOnAnyEdgeHiddenAndResized() {
        let m = SurfaceManager(width: W, height: H, seed: 2)
        var powder = PowderSystem(capacity: 2400, seed: 2)

        // Bottom Dock
        m.setDock(rect: Rect(x: 400, y: 0, width: 700, height: 70), powder: &powder, time: 0)
        for k in 0..<400 {
            _ = m.contact(x: 400 + Double(k) * 1.7, prevY: 200, y: 60, area: 3, windows: false, cull: false,
                          ignore: Int.min, dockGain: 1)
        }
        let area = m.dock!.field.area
        XCTAssertGreaterThan(area, 100)

        // Auto-hide: no landing while hidden, snow intact when it returns
        m.setDock(rect: nil, powder: &powder, time: 1)
        XCTAssertFalse(m.dock!.onScreen)
        if case .landed = m.contact(x: 700, prevY: 200, y: 60, area: 3, windows: false, cull: false,
                                    ignore: Int.min, dockGain: 1) {
            XCTFail("a hidden Dock should not catch snow")
        }
        m.setDock(rect: Rect(x: 400, y: 0, width: 700, height: 70), powder: &powder, time: 2)
        XCTAssertEqual(m.dock!.field.area, area, accuracy: 1e-9)

        // An app opens: the Dock grows by one icon, centred. Snow stays; nothing more than edge trimmings falls.
        m.setDock(rect: Rect(x: 365, y: 0, width: 770, height: 70), powder: &powder, time: 3)
        XCTAssertGreaterThan(m.dock!.field.area, area * 0.9)
        XCTAssertEqual(m.dock!.field.area + powder.emittedMass, area, accuracy: 1e-6)

        // Dock moved to the left edge: a short ledge on top of a tall strip
        m.setDock(rect: Rect(x: 0, y: 200, width: 72, height: 500), powder: &powder, time: 4)
        XCTAssertEqual(m.dock!.field.topY, 700)
        XCTAssertEqual(m.dock!.field.width, 72)
        if case .landed(let stuck) = m.contact(x: 30, prevY: 760, y: 695, area: 3, windows: false, cull: false,
                                               ignore: Int.min, dockGain: 1) {
            XCTAssertGreaterThanOrEqual(stuck, 0)
        } else {
            XCTFail("snow should land on top of a side Dock")
        }
        // And on the right edge
        m.setDock(rect: Rect(x: W - 72, y: 200, width: 72, height: 500), powder: &powder, time: 5)
        XCTAssertEqual(m.dock!.field.minX, W - 72)
    }

    // MARK: Displays

    func twoDisplays() -> [DisplayInfo] {
        // A smaller display to the left of and higher than the primary, as in the Displays arrangement pane
        [DisplayInfo(id: 1, rect: Rect(x: 0, y: 0, width: 1500, height: 950)),
         DisplayInfo(id: 2, rect: Rect(x: -1280, y: 300, width: 1280, height: 720))]
    }

    func testEachDisplayHasItsOwnGround() {
        let m = SurfaceManager(displays: twoDisplays(), seed: 6)
        XCTAssertEqual(m.grounds.count, 2)
        XCTAssertEqual(m.grounds[1].field.minX, -1280)
        XCTAssertEqual(m.grounds[1].field.topY, 300)
        XCTAssertEqual(m.bounds, Rect(x: -1280, y: 0, width: 2780, height: 1020))

        // A flake over the second display lands on that display's floor, not on y = 0
        guard case .landed = m.contact(x: -600, prevY: 302, y: 299, area: 3, windows: true, cull: true,
                                       ignore: Int.min, dockGain: 1, display: 1) else { return XCTFail() }
        XCTAssertGreaterThan(m.grounds[1].field.area, 0)
        XCTAssertEqual(m.grounds[0].field.area, 0)
        // Powder finds the right floor by position
        guard case .landed = m.contact(x: 700, prevY: 2, y: -1, area: 3, windows: true, cull: false,
                                       ignore: Int.min, dockGain: 1, display: -1) else { return XCTFail() }
        XCTAssertGreaterThan(m.grounds[0].field.area, 0)
    }

    func testWindowStraddlingTwoDisplaysIsVisibleOnBoth() {
        let m = SurfaceManager(displays: twoDisplays(), seed: 6)
        var powder = PowderSystem(capacity: 100, seed: 6)
        // Top edge at y = 800: on both displays. Spans x = -300...300.
        m.update(windows: [WindowInfo(id: 1, rect: Rect(x: -300, y: 500, width: 600, height: 300))],
                 dt: dt, time: 0, powder: &powder) { _, _ in .keep }
        var f = m.surface(id: 1)!.field
        XCTAssertTrue(f.visible[f.col(at: -200)!])
        XCTAssertTrue(f.visible[f.col(at: 200)!])
        // Top edge at y = 250: below the second display's floor, so only the primary's half shows
        m.update(windows: [WindowInfo(id: 1, rect: Rect(x: -300, y: 50, width: 600, height: 200))],
                 dt: dt, time: 1, powder: &powder) { _, _ in .keep }
        f = m.surface(id: 1)!.field
        XCTAssertFalse(f.visible[f.col(at: -200)!])
        XCTAssertTrue(f.visible[f.col(at: 200)!])
    }

    func testSnowFallsOnEveryDisplayInItsOwnBounds() {
        let displays = twoDisplays()
        let m = SurfaceManager(displays: displays, seed: 6)
        var wind = WindField(width: 10, height: 10, seed: 6)
        wind.resize(minX: m.bounds.minX, minY: m.bounds.minY, width: m.bounds.width, height: m.bounds.height)
        var weather = Weather(preset: .gentle, seed: 6)
        var systems = [FlakeSystem(capacity: 1200, seed: 1), FlakeSystem(capacity: 1200, seed: 2)]
        var envs: [FlakeEnvironment] = []
        for (k, d) in displays.enumerated() {
            var e = FlakeEnvironment(width: d.rect.width, height: d.rect.height)
            e.minX = d.rect.minX; e.minY = d.rect.minY; e.display = k
            envs.append(e)
        }
        var t = 0.0
        for _ in 0..<(60 * 60) {
            t += dt
            weather.step(dt: dt)
            wind.update(time: t, dt: dt, params: weather.wind)
            for k in 0..<2 { systems[k].step(dt: dt, env: envs[k], wind: wind, surfaces: m, weather: weather.effective) }
        }
        for (k, d) in displays.enumerated() {
            XCTAssertGreaterThan(systems[k].count, 50)
            for i in 0..<systems[k].count {
                XCTAssertTrue(systems[k].x[i] >= d.rect.minX - 41 && systems[k].x[i] <= d.rect.maxX + 41)
                XCTAssertTrue(systems[k].y[i] >= d.rect.minY - 21 && systems[k].y[i] <= d.rect.maxY + 121)
            }
            XCTAssertGreaterThan(m.grounds[k].field.area, 10)
        }
        // Density is per area, so the smaller display carries fewer flakes
        XCTAssertLessThan(systems[1].count, systems[0].count)
    }

    func testDisplayChangesKeepGroundSnow() {
        let m = SurfaceManager(displays: twoDisplays(), seed: 6)
        for k in 0..<300 {
            _ = m.contact(x: Double(k) * 4, prevY: 2, y: -1, area: 4, windows: false, cull: false, ignore: Int.min, dockGain: 1, display: 0)
            _ = m.contact(x: -1200 + Double(k) * 4, prevY: 302, y: 299, area: 4, windows: false, cull: false, ignore: Int.min, dockGain: 1, display: 1)
        }
        let a0 = m.grounds[0].field.area, a1 = m.grounds[1].field.area
        XCTAssertGreaterThan(a0, 100); XCTAssertGreaterThan(a1, 100)

        // Rearranged: the second display moves to the right of the primary
        m.setDisplays([DisplayInfo(id: 1, rect: Rect(x: 0, y: 0, width: 1500, height: 950)),
                       DisplayInfo(id: 2, rect: Rect(x: 1500, y: 0, width: 1280, height: 720))])
        XCTAssertEqual(m.grounds[1].field.area, a1, accuracy: 1e-9)
        XCTAssertEqual(m.grounds[1].field.minX, 1500)

        // Disconnected, then reconnected: the primary is untouched; the returning display starts clean
        m.setDisplays([DisplayInfo(id: 1, rect: Rect(x: 0, y: 0, width: 1500, height: 950))])
        XCTAssertEqual(m.grounds.count, 1)
        XCTAssertEqual(m.grounds[0].field.area, a0, accuracy: 1e-9)
        m.setDisplays(twoDisplays())
        XCTAssertEqual(m.grounds[1].field.area, 0)

        // Resolution change on the primary: snow that still has ground under it stays
        m.setDisplays([DisplayInfo(id: 1, rect: Rect(x: 0, y: 0, width: 1800, height: 1100))])
        XCTAssertGreaterThan(m.grounds[0].field.area, a0 * 0.9)
    }

    // MARK: Cursor

    struct Sky {
        var surfaces: SurfaceManager
        var wind: WindField
        var weather: Weather
        var flakes: FlakeSystem
        var env: FlakeEnvironment
        var t = 0.0

        init(seed: UInt64) {
            surfaces = SurfaceManager(width: 1500, height: 950, seed: seed)
            wind = WindField(width: 1500, height: 950, seed: seed)
            weather = Weather(preset: .gentle, seed: seed)
            flakes = FlakeSystem(capacity: 1600, seed: seed)
            env = FlakeEnvironment(width: 1500, height: 950)
        }

        mutating func run(_ seconds: Double) {
            let dt = 1.0 / 60
            for _ in 0..<Int((seconds / dt).rounded()) {
                t += dt
                weather.step(dt: dt)
                wind.update(time: t, dt: dt, params: weather.wind)
                flakes.step(dt: dt, env: env, wind: wind, surfaces: surfaces, weather: weather.effective)
            }
        }
    }

    /// Mean speed difference between a disturbed sky and an identical undisturbed one, near the cursor
    func disturbance(strength: Double, cursorSpeed: Double, settle: Double = 0) -> Double {
        var calm = Sky(seed: 31), stirred = Sky(seed: 31)
        calm.run(10); stirred.run(10)
        stirred.env.cursorActive = true
        stirred.env.cursorStrength = strength
        stirred.env.cursorX = 750; stirred.env.cursorY = 500; stirred.env.cursorVX = cursorSpeed
        calm.run(0.15); stirred.run(0.15)
        stirred.env.cursorVX = 0
        calm.run(settle); stirred.run(settle)
        XCTAssertEqual(calm.flakes.count, stirred.flakes.count)
        var sum = 0.0, n = 0.0
        for i in 0..<calm.flakes.count where hypot(calm.flakes.x[i] - 750, calm.flakes.y[i] - 500) < 120 {
            sum += hypot(calm.flakes.vx[i] - stirred.flakes.vx[i], calm.flakes.vy[i] - stirred.flakes.vy[i])
            n += 1
        }
        return n > 0 ? sum / n : 0
    }

    func testFasterCursorDisturbsMoreAndStrengthScalesIt() {
        let slow = disturbance(strength: 1, cursorSpeed: 300)
        let fast = disturbance(strength: 1, cursorSpeed: 1800)
        XCTAssertGreaterThan(slow, 0)
        XCTAssertGreaterThan(fast, slow * 2)
        XCTAssertEqual(disturbance(strength: 0, cursorSpeed: 1800), 0, "strength 0 switches the effect off")
        XCTAssertGreaterThan(disturbance(strength: 2, cursorSpeed: 1800), fast * 1.5)
        XCTAssertLessThan(disturbance(strength: 0.5, cursorSpeed: 1800), fast * 0.75)
    }

    func testDisturbanceFadesAndFlakesReturnToNaturalMotion() {
        let during = disturbance(strength: 1, cursorSpeed: 1800)
        let halfSecond = disturbance(strength: 1, cursorSpeed: 1800, settle: 0.5)
        let later = disturbance(strength: 1, cursorSpeed: 1800, settle: 2.5)
        XCTAssertLessThan(halfSecond, during * 0.6)
        XCTAssertLessThan(later, during * 0.05)
    }

    func testDisturbanceIsSubtle() {
        // Even a very fast sweep must not fling flakes across the screen
        var sky = Sky(seed: 8)
        sky.run(10)
        sky.env.cursorActive = true
        sky.env.cursorStrength = 2
        sky.env.cursorX = 750; sky.env.cursorY = 500; sky.env.cursorVX = 4000; sky.env.cursorVY = 3000
        sky.run(0.5)
        for i in 0..<sky.flakes.count { XCTAssertLessThan(hypot(sky.flakes.vx[i], sky.flakes.vy[i]), 1200) }
    }

    // MARK: Adaptive quality

    func testGovernorThinsUnderLoadAndRecovers() {
        var g = QualityGovernor()
        for _ in 0..<600 { g.report(frameCostMs: 9, dt: dt, constrained: false) }
        XCTAssertLessThan(g.scale, 0.5)
        XCTAssertGreaterThanOrEqual(g.scale, QualityGovernor.minimumScale)
        for _ in 0..<3600 { g.report(frameCostMs: 0.5, dt: dt, constrained: false) }
        XCTAssertEqual(g.scale, 1, accuracy: 1e-9)
        // Low Power Mode caps it without any load
        for _ in 0..<300 { g.report(frameCostMs: 0.5, dt: dt, constrained: true) }
        XCTAssertEqual(g.scale, QualityGovernor.constrainedScale, accuracy: 1e-9)
        // Costs inside the budget leave it alone
        var steady = QualityGovernor()
        for _ in 0..<600 { steady.report(frameCostMs: 3, dt: dt, constrained: false) }
        XCTAssertEqual(steady.scale, 1)
    }

    func testDensityScaleReducesFlakeCount() {
        var full = Sky(seed: 5), thin = Sky(seed: 5)
        thin.env.densityScale = 0.4
        full.run(60); thin.run(60)
        XCTAssertLessThan(Double(thin.flakes.count), Double(full.flakes.count) * 0.6)
    }
}
