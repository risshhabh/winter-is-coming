import XCTest
@testable import WinterCore

final class AtmosphereTests: XCTestCase {
    func testDirectorKeepsHappeningsRareAndApart() {
        var d = EventDirector(seed: 5)
        d.flyoverGap = 1200
        var times: [Double] = []
        var flyovers = 0, events = 0
        var t = 0.0
        while t < 8 * 3600 {                         // a working day
            t += 0.25
            if let h = d.step(time: t) {
                times.append(t)
                if h == .flyover { flyovers += 1; d.hold(for: 12, time: t) } else { events += 1 }
            }
        }
        for i in 1..<times.count { XCTAssertGreaterThanOrEqual(times[i] - times[i - 1], EventDirector.minimumGap) }
        XCTAssertTrue((14...36).contains(flyovers), "about one flyover every 20 minutes, got \(flyovers)")
        XCTAssertTrue((90...200).contains(events), "a small event every few minutes, got \(events)")
    }

    func testDirectorDoesNothingWhenSwitchedOff() {
        var d = EventDirector(seed: 5)
        d.eventsEnabled = false
        var t = 0.0
        while t < 3600 { t += 0.5; XCTAssertNil(d.step(time: t)) }
    }

    func testLightsTwinkleGentlyAndIndependently() {
        var a: [Double] = [], b: [Double] = []
        var last = Lights.brightness(index: 3, time: 0)
        for k in 0..<1200 {
            let t = Double(k) / 60
            let v = Lights.brightness(index: 3, time: t)
            XCTAssertTrue(v >= 0.55 && v <= 1.0)
            XCTAssertLessThan(abs(v - last), 0.02, "no flashing: brightness changes slowly")
            last = v
            a.append(v); b.append(Lights.brightness(index: 4, time: t))
        }
        XCTAssertGreaterThan(a.max()! - a.min()!, 0.15, "it does twinkle")
        var diff = 0.0
        for k in 0..<a.count { diff += abs(a[k] - b[k]) }
        XCTAssertGreaterThan(diff / Double(a.count), 0.05, "neighbouring bulbs do not twinkle in unison")
        XCTAssertEqual(Lights.sag(at: 0), 0)
        XCTAssertEqual(Lights.sag(at: 55), 6, accuracy: 1e-9)
        XCTAssertEqual(Lights.count(length: 520, spacing: 26), 20)
    }

    func testFrostFormsWithTheWeatherAndCracksOffWhenShaken() {
        let m = SurfaceManager(width: 1500, height: 950, seed: 3)
        var powder = PowderSystem(capacity: 2400, seed: 3)
        let win = [WindowInfo(id: 1, rect: Rect(x: 300, y: 300, width: 600, height: 300))]
        m.update(windows: win, dt: 1.0 / 60, time: 0, powder: &powder) { _, _ in .keep }
        let s = m.surface(id: 1)!
        for _ in 0..<60 { m.settle(dt: 1, meltRate: 0, frostRate: 0.003) }
        let light = s.frost
        XCTAssertGreaterThan(light, 0.1)
        XCTAssertLessThan(light, 0.3, "frost forms gradually")
        for _ in 0..<600 { m.settle(dt: 1, meltRate: 0, frostRate: 0.004) }
        XCTAssertEqual(s.frost, 1, accuracy: 1e-9)
        // Melting on: it thaws back to a thin rim
        for _ in 0..<600 { m.settle(dt: 1, meltRate: 0.03, frostRate: 0.004) }
        XCTAssertEqual(s.frost, 0.4, accuracy: 0.01)
        // A hard shake knocks it back
        var rng = SeededRNG(seed: 1)
        for _ in 0..<3000 { s.field.deposit(x: rng.range(300, 900), area: 4) }
        var t = 0.0
        for _ in 0..<30 {
            t += 1.0 / 60
            m.update(windows: [WindowInfo(id: 1, rect: Rect(x: 300 + 60 * sin(t * 2 * .pi * 4), y: 300, width: 600, height: 300))],
                     dt: 1.0 / 60, time: t, powder: &powder) { _, _ in .keep }
        }
        XCTAssertLessThan(s.frost, 0.25)
        // Frost switched off: it fades away
        for _ in 0..<60 { m.settle(dt: 1, meltRate: 0, frostRate: 0) }
        XCTAssertEqual(s.frost, 0)
    }

    func testWeatherEventsPassAndLeaveNoTrace() {
        var w = Weather(preset: .gentle, seed: 2)
        var calm = Weather(preset: .gentle, seed: 2)
        w.triggerGust()
        w.shiftIntensity(0.45)
        XCTAssertGreaterThan(w.effective.gust, calm.effective.gust * 2)
        XCTAssertGreaterThan(w.effective.density, calm.effective.density * 1.2)
        for _ in 0..<(60 * 10) { w.step(dt: 1.0 / 60); calm.step(dt: 1.0 / 60) }
        XCTAssertEqual(w.effective.gust, calm.effective.gust, accuracy: calm.effective.gust * 0.1, "a gust is over in seconds")
        for _ in 0..<(60 * 300) { w.step(dt: 1.0 / 60); calm.step(dt: 1.0 / 60) }
        XCTAssertEqual(w.effective.density, calm.effective.density, accuracy: calm.effective.density * 0.01)
    }

    func testWindBlownPowderTakesALittleAndConservesIt() {
        let m = SurfaceManager(width: 1500, height: 950, seed: 3)
        var powder = PowderSystem(capacity: 2400, seed: 3)
        XCTAssertFalse(m.blowPowder(windU: 30, pick: 0, powder: &powder, time: 0), "nothing to lift from bare ground")
        var rng = SeededRNG(seed: 1)
        for _ in 0..<3000 { m.ground.field.deposit(x: rng.range(0, 1500), area: 4) }
        let before = m.ground.field.area
        XCTAssertTrue(m.blowPowder(windU: 30, pick: 0, powder: &powder, time: 0))
        XCTAssertEqual(m.ground.field.area, before * 0.95, accuracy: before * 0.001)
        XCTAssertEqual(m.ground.field.area + powder.emittedMass, before, accuracy: 1e-6)
    }
}
