import XCTest
@testable import WinterCore

final class SnowFieldTests: XCTestCase {
    func makeField(width: Double = 600, seed: UInt64 = 1) -> SnowField {
        SnowField(minX: 100, topY: 400, width: width, maxH: 16, seed: seed)
    }

    func testDepositReportsExactlyWhatStuck() {
        var f = makeField()
        var rng = SeededRNG(seed: 2)
        var reported = 0.0
        for _ in 0..<5000 { reported += f.deposit(x: rng.range(100, 700), area: 3) }
        XCTAssertEqual(f.area, reported, accuracy: 1e-6)
        XCTAssertLessThanOrEqual(reported, 5000 * 3)
    }

    func testHeightsNeverExceedCapsAndLevelOffGradually() {
        var f = makeField()
        var rng = SeededRNG(seed: 3)
        var firstBatch = 0.0, lastBatch = 0.0
        for batch in 0..<60 {
            var stuck = 0.0
            for _ in 0..<2000 { stuck += f.deposit(x: rng.range(100, 700), area: 3) }
            f.relax()
            if batch == 0 { firstBatch = stuck }
            lastBatch = stuck
            for i in 0..<f.count {
                XCTAssertLessThanOrEqual(f.h[i], f.caps[i] + 1e-9)
                XCTAssertLessThanOrEqual(f.h[i], 16)
            }
        }
        XCTAssertLessThan(lastBatch, firstBatch * 0.05, "a nearly full pile should accept very little more")
    }

    func testOneFlakeNeverCausesAVisibleJump() {
        var f = makeField()
        let before = f.h
        f.deposit(x: 400, area: 2.0 * 6.6)        // the largest flake there is
        for i in 0..<f.count { XCTAssertLessThan(f.h[i] - before[i], 1.2) }
    }

    func testRelaxConservesSnowAndLimitsSlope() {
        var f = makeField()
        for _ in 0..<400 { f.deposit(x: 400, area: 3) }     // a spike in one place
        let before = f.area
        var passes = 0
        while f.relax() && passes < 5000 { passes += 1 }
        XCTAssertEqual(f.area, before, accuracy: 1e-6)
        for i in 0..<(f.count - 1) {
            let step = abs(f.h[i] - f.h[i + 1])
            let blocked = f.h[i] >= f.caps[i] - 1e-6 || f.h[i + 1] >= f.caps[i + 1] - 1e-6
            if !blocked { XCTAssertLessThan(step, 1.6) }
        }
    }

    func testPilesAreIrregularAndDifferBySeed() {
        let a = makeField(seed: 1), b = makeField(seed: 2)
        var different = 0
        for i in 0..<a.count where abs(a.caps[i] - b.caps[i]) > 0.5 { different += 1 }
        XCTAssertGreaterThan(different, a.count / 4)
        // Not mirror-symmetric either
        var asymmetric = 0
        for i in 0..<(a.count / 2) where abs(a.caps[i] - a.caps[a.count - 1 - i]) > 0.5 { asymmetric += 1 }
        XCTAssertGreaterThan(asymmetric, a.count / 10)
        // Ends taper so snow does not form a wall at the window corner
        XCTAssertLessThan(a.caps[0], a.caps[a.count / 2])
        XCTAssertLessThan(a.caps[a.count - 1], a.caps[a.count / 2])
    }

    func testMeltReportsRemovedAreaAndReachesZero() {
        var f = makeField()
        for k in 0..<200 { f.deposit(x: 100 + Double(k) * 3, area: 6) }
        let before = f.area
        let removed = f.melt(0.25)
        XCTAssertEqual(f.area, before - removed, accuracy: 1e-6)
        f.melt(100)
        XCTAssertEqual(f.area, 0, accuracy: 1e-9)
    }

    func testShedConservesSnow() {
        var f = makeField()
        for k in 0..<200 { f.deposit(x: 100 + Double(k) * 3, area: 6) }
        let before = f.area
        var shed = 0.0
        f.shed(fraction: 0.4) { _, _, _, area, _ in shed += area }
        XCTAssertEqual(shed, before * 0.4, accuracy: before * 0.01)
        XCTAssertEqual(f.area + shed, before, accuracy: 1e-6)
    }

    func testHiddenColumnsKeepTheirSnowAndTakeNoMore() {
        var f = makeField()
        for k in 0..<200 { f.deposit(x: 100 + Double(k) * 3, area: 6) }
        let before = f.area
        f.setVisible(false, fromX: 250, toX: 450)
        XCTAssertEqual(f.area, before, accuracy: 1e-9, "occlusion must not delete snow")
        XCTAssertFalse(f.visible[f.col(at: 350)!])
        XCTAssertTrue(f.visible[f.col(at: 200)!])
        let hiddenBefore = f.h[f.col(at: 350)!]
        f.deposit(x: 350, area: 6)
        XCTAssertEqual(f.h[f.col(at: 350)!], hiddenBefore)
        f.setAllVisible(true)
        XCTAssertEqual(f.area, before, accuracy: 1e-9)
    }

    func testResizeKeepsSnowInPlaceAndAccountsForTheRest() {
        var f = makeField(width: 600)
        for k in 0..<200 { f.deposit(x: 100 + Double(k) * 3, area: 6) }
        let before = f.area
        let probeX = 500.0
        let hAtProbe = f.h[f.col(at: probeX)!]

        // Drag the left edge inward by 150 px: the right part must not move on screen
        var cut = 0.0
        f.resize(minX: 250, width: 450) { _, _, area in cut += area }
        XCTAssertEqual(f.area + cut, before, accuracy: 1e-6)
        XCTAssertGreaterThan(cut, 0)
        XCTAssertEqual(f.h[f.col(at: probeX)!], hAtProbe, accuracy: 1e-9)
        XCTAssertGreaterThan(f.area, before * 0.5, "most of the snow survives a resize")

        // Growing the window loses nothing except what the new edge taper cannot hold
        let mid = f.area
        var cut2 = 0.0
        f.resize(minX: 250, width: 700) { _, _, area in cut2 += area }
        XCTAssertEqual(f.area + cut2, mid, accuracy: 1e-6)
        XCTAssertEqual(f.count, 234)
    }

    func testMoveCarriesSnow() {
        var f = makeField()
        for k in 0..<200 { f.deposit(x: 100 + Double(k) * 3, area: 6) }
        let h = f.h
        f.move(minX: 300, topY: 650)
        XCTAssertEqual(f.h, h)
        XCTAssertEqual(f.surface(10), 650 + h[10])
        XCTAssertEqual(f.col(at: 300 + 31), 10)
        XCTAssertNil(f.col(at: 299))
    }
}
