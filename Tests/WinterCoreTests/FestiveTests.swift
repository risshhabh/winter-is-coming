import XCTest
@testable import WinterCore

final class FestiveTests: XCTestCase {
    let dt = 1.0 / 60

    // MARK: Companion

    func testCompanionFollowsWithADelayAndNoOvershoot() {
        var c = CursorCompanion()
        for _ in 0..<60 { c.update(dt: dt, cursorX: 100, cursorY: 100, offsetX: 0, offsetY: 0, stiffness: 7) }
        XCTAssertEqual(c.x, 100, accuracy: 0.5)
        // The cursor jumps 300 px to the right
        var maxX = 0.0
        var xAfterTenth = 0.0
        for i in 0..<180 {
            c.update(dt: dt, cursorX: 400, cursorY: 100, offsetX: 0, offsetY: 0, stiffness: 7)
            if i == 5 { xAfterTenth = c.x }
            maxX = max(maxX, c.x)
        }
        XCTAssertLessThan(xAfterTenth, 200, "it should lag behind, not teleport")
        XCTAssertLessThanOrEqual(maxX, 401, "critically damped: no overshoot")
        XCTAssertEqual(c.x, 400, accuracy: 1)
    }

    func testCompanionFacesItsDirectionOfTravelAndTiltsWhenClimbing() {
        var c = CursorCompanion()
        var x = 0.0, y = 0.0
        for _ in 0..<90 { x += 500 * dt; c.update(dt: dt, cursorX: x, cursorY: y, offsetX: 40, offsetY: 10, stiffness: 7) }
        XCTAssertGreaterThan(c.facing, 0.9)
        XCTAssertGreaterThan(c.stride, 0.8, "fast movement means a full gallop")
        XCTAssertLessThan(c.x, x, "it rides behind the cursor")
        let levelTilt = c.tilt
        for _ in 0..<60 { x += 300 * dt; y += 400 * dt; c.update(dt: dt, cursorX: x, cursorY: y, offsetX: 40, offsetY: 10, stiffness: 7) }
        XCTAssertGreaterThan(c.tilt, levelTilt + 0.1)
        XCTAssertLessThanOrEqual(abs(c.tilt), 0.36, "tilt stays subtle")
        for _ in 0..<90 { x -= 500 * dt; c.update(dt: dt, cursorX: x, cursorY: y, offsetX: 40, offsetY: 10, stiffness: 7) }
        XCTAssertLessThan(c.facing, -0.9)
        XCTAssertGreaterThan(c.x, x, "after turning round it is behind the cursor on the other side")
    }

    func testSmallJittersDoNotFlipTheCompanion() {
        var c = CursorCompanion()
        var x = 0.0
        for _ in 0..<60 { x += 400 * dt; c.update(dt: dt, cursorX: x, cursorY: 0, offsetX: 40, offsetY: 0, stiffness: 7) }
        for i in 0..<120 { c.update(dt: dt, cursorX: x + (i % 2 == 0 ? 1.5 : -1.5), cursorY: 0, offsetX: 40, offsetY: 0, stiffness: 7) }
        XCTAssertGreaterThan(c.facing, 0.9)
    }

    func testCompanionIdlesWhenTheCursorStops() {
        var c = CursorCompanion()
        var x = 0.0
        for _ in 0..<60 { x += 500 * dt; c.update(dt: dt, cursorX: x, cursorY: 0, offsetX: 40, offsetY: 0, stiffness: 7) }
        var hovers: [Double] = []
        let phase = c.gallop
        for _ in 0..<240 { c.update(dt: dt, cursorX: x, cursorY: 0, offsetX: 40, offsetY: 0, stiffness: 7); hovers.append(c.hover) }
        XCTAssertGreaterThan(c.idleTime, 2)
        XCTAssertLessThan(c.stride, 0.2)
        XCTAssertGreaterThan(c.stride, 0.05, "the team still shifts its feet")
        XCTAssertGreaterThan(c.gallop, phase)
        XCTAssertGreaterThan(hovers.max()! - hovers.min()!, 2, "a gentle hover")
        XCTAssertLessThan(hovers.max()!, 3)
    }

    func testCompanionAppearsAtTheCursorAfterAJump() {
        var c = CursorCompanion()
        c.update(dt: dt, cursorX: 100, cursorY: 100, offsetX: 0, offsetY: 0, stiffness: 7)
        c.update(dt: dt, cursorX: 6000, cursorY: 100, offsetX: 0, offsetY: 0, stiffness: 7)
        XCTAssertEqual(c.x, 6000, accuracy: 1, "moving to a far display should not streak across the screens")
    }

    // MARK: Bells

    func testSilentWhileTheCursorRests() {
        var s = BellSequencer(variants: 8, seed: 1)
        for _ in 0..<600 { XCTAssertNil(s.step(dt: dt, speed: 0, pan: 0)) }
        XCTAssertEqual(s.shimmerGain, 0)
        for _ in 0..<600 { XCTAssertNil(s.step(dt: dt, speed: 40, pan: 0), "a slow drift rings nothing") }
        XCTAssertEqual(s.shimmerGain, 0)
    }

    func testGentleMovementGivesShimmerOnlyAndItFadesInAndOut() {
        var s = BellSequencer(variants: 8, seed: 1)
        var last = 0.0
        for _ in 0..<120 {
            XCTAssertNil(s.step(dt: dt, speed: 220, pan: 0))
            XCTAssertLessThan(s.shimmerGain - last, 0.02, "no step change in level")
            last = s.shimmerGain
        }
        XCTAssertGreaterThan(s.shimmerGain, 0.02)
        XCTAssertLessThan(s.shimmerGain, 0.2, "gentle movement stays very quiet")
        for _ in 0..<30 { _ = s.step(dt: dt, speed: 0, pan: 0) }
        XCTAssertGreaterThan(s.shimmerGain, 0, "release is gradual")
        for _ in 0..<300 { _ = s.step(dt: dt, speed: 0, pan: 0) }
        XCTAssertEqual(s.shimmerGain, 0)
    }

    func testBellsAreRateLimitedVariedAndNotOnePerEvent() {
        var s = BellSequencer(variants: 8, seed: 3)
        var events: [BellEvent] = []
        var times: [Double] = []
        // A full minute of frantic movement, 60 "mouse events" a second
        for i in 0..<3600 {
            if let e = s.step(dt: dt, speed: 2400, pan: sin(Double(i) / 200)) { events.append(e); times.append(Double(i) * dt) }
        }
        XCTAssertGreaterThan(events.count, 20)
        XCTAssertLessThan(events.count, 60, "the budget allows well under one bell a second")
        for i in 1..<events.count {
            XCTAssertNotEqual(events[i].variant, events[i - 1].variant, "never the same bell twice running")
            XCTAssertGreaterThanOrEqual(times[i] - times[i - 1], 0.15)
        }
        let gaps = zip(times.dropFirst(), times).map { $0 - $1 }
        XCTAssertGreaterThan(gaps.max()! - gaps.min()!, 0.1, "irregular spacing")
        for e in events {
            XCTAssertTrue(e.gain > 0 && e.gain <= 0.86)
            XCTAssertTrue(e.pan >= -1 && e.pan <= 1)
        }
        XCTAssertGreaterThan(Set(events.map { $0.variant }).count, 4)
        s.reset()
        XCTAssertEqual(s.shimmerGain, 0, "switching off silences at once")
    }

    func testSynthesizedSoundsAreCleanAndDistinct() {
        let loop = BellSynth.shimmerLoop()
        XCTAssertEqual(loop.count, Int(4 * BellSynth.sampleRate))
        XCTAssertLessThanOrEqual(loop.map { abs($0) }.max()!, 0.3001)
        XCTAssertLessThan(abs(loop.first! - loop.last!), 0.05, "the loop point has no click")
        var previous: [Float] = []
        for v in 0..<8 {
            let b = BellSynth.bell(variant: v)
            XCTAssertTrue(b.allSatisfy { $0.isFinite })
            XCTAssertEqual(b.map { abs($0) }.max()!, 0.5, accuracy: 0.001)
            XCTAssertEqual(b.last!, 0, accuracy: 1e-4, "the tail ends in silence")
            XCTAssertLessThan(abs(b[0]), 0.02, "no click at the start")
            // Most of the energy is over within a quarter of a second: a jingle, not a chime
            let early = b.prefix(Int(0.25 * BellSynth.sampleRate)).reduce(0) { $0 + $1 * $1 }
            let total = b.reduce(0) { $0 + $1 * $1 }
            XCTAssertGreaterThan(early / total, 0.9)
            XCTAssertNotEqual(b, previous)
            previous = b
        }
    }

    // MARK: Trail

    func testTrailParticlesFadeQuicklyAndNeverBecomeSnow() {
        var powder = PowderSystem(capacity: 400, seed: 2)
        let surfaces = SurfaceManager(width: 1500, height: 950, seed: 2)
        var wind = WindField(width: 1500, height: 950, seed: 2)
        wind.update(time: 0, dt: 0, params: WindParams(mean: 40, turbulence: 0, gust: 0))
        for k in 0..<300 {
            let kind = [PowderSystem.sparkleKind, PowderSystem.trailFlakeKind, PowderSystem.glowKind][k % 3]
            powder.emitTrail(kind: kind, x: 700, y: 3, vx: 0, vy: 0)      // right above the ground pile
        }
        XCTAssertEqual(powder.count, 300)
        var opacities: [Double] = []
        for step in 0..<30 {
            powder.step(dt: dt, time: Double(step) * dt, wind: wind, surfaces: surfaces)
            if powder.count > 0 { opacities.append(powder.opacity(0)) }
        }
        var meanVX = 0.0
        for i in 0..<powder.count { meanVX += powder.vx[i] }
        XCTAssertGreaterThan(meanVX / Double(powder.count), 20, "the trail drifts with the wind")
        for step in 30..<90 { powder.step(dt: dt, time: Double(step) * dt, wind: wind, surfaces: surfaces) }
        XCTAssertEqual(powder.count, 0, "gone within a second and a half")
        XCTAssertEqual(surfaces.ground.field.area, 0, "trail particles carry no snow")
        XCTAssertEqual(powder.emittedMass, 0)
        // Capacity is shared with the powder and is a hard limit
        for _ in 0..<1000 { powder.emitTrail(kind: PowderSystem.sparkleKind, x: 0, y: 500, vx: 0, vy: 0) }
        XCTAssertEqual(powder.count, 400)
    }
}
