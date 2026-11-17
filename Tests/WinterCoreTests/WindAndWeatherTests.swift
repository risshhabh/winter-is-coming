import XCTest
@testable import WinterCore

final class WindAndWeatherTests: XCTestCase {
    func testNoiseIsBoundedAndDeterministic() {
        for i in 0..<2000 {
            let x = Double(i) * 0.173, y = Double(i) * 0.071, z = Double(i) * 0.013
            let a = Noise.value3(x, y, z, seed: 7)
            XCTAssertEqual(a, Noise.value3(x, y, z, seed: 7))
            XCTAssertTrue(a >= -1 && a <= 1)
        }
    }

    func testWindStaysWithinItsEnvelope() {
        var wind = WindField(width: 1600, height: 1000, seed: 3)
        let p = WindParams(mean: 70, turbulence: 38, gust: 75)
        var t = 0.0
        for _ in 0..<600 {
            t += 1.0 / 60
            wind.update(time: t, dt: 1.0 / 60, params: p)
            for k in 0..<40 {
                let s = wind.sample(x: Double(k) * 41, y: Double(k) * 23)
                XCTAssertTrue(s.u.isFinite && s.v.isFinite)
                XCTAssertLessThanOrEqual(abs(s.u), 70 + 38 * 1.45 + 75 + 1e-9)
                XCTAssertLessThanOrEqual(abs(s.v), 38 * 0.3 + 1e-9)
            }
        }
    }

    func testWindVariesSmoothlyInSpaceAndTime() {
        var wind = WindField(width: 1600, height: 1000, seed: 11)
        let p = WindParams(mean: 14, turbulence: 16, gust: 14)
        var t = 0.0
        var previous: [Double] = []
        for step in 0..<300 {
            t += 1.0 / 60
            wind.update(time: t, dt: 1.0 / 60, params: p)
            var now: [Double] = []
            for k in 0..<60 {
                let x = Double(k) * 26, y = 500.0
                let a = wind.sample(x: x, y: y).u
                let b = wind.sample(x: x + 4, y: y).u
                XCTAssertLessThan(abs(a - b), 1.5, "neighbouring points 4 px apart should feel nearly the same wind")
                now.append(a)
            }
            if step > 0 {
                for k in 0..<now.count {
                    XCTAssertLessThan(abs(now[k] - previous[k]), 1.0, "wind must not jump between frames")
                }
            }
            previous = now
        }
    }

    func testWindDiffersAcrossTheScreen() {
        var wind = WindField(width: 1600, height: 1000, seed: 5)
        wind.update(time: 12, dt: 1.0 / 60, params: WindParams(mean: 14, turbulence: 16, gust: 14))
        var lo = Double.infinity, hi = -Double.infinity
        for k in 0..<200 {
            let u = wind.sample(x: Double(k % 20) * 80, y: Double(k / 20) * 100).u
            lo = min(lo, u); hi = max(hi, u)
        }
        XCTAssertGreaterThan(hi - lo, 6, "the field should not be one global value")
    }

    func testCalmerWeatherMeansCalmerWind() {
        func spread(_ preset: SnowPreset) -> Double {
            var weather = Weather(preset: preset, seed: 9)
            var wind = WindField(width: 1600, height: 1000, seed: 9)
            var sum = 0.0, n = 0.0, t = 0.0
            for _ in 0..<1200 {
                t += 1.0 / 30
                weather.step(dt: 1.0 / 30)
                wind.update(time: t, dt: 1.0 / 30, params: weather.wind)
                for k in 0..<20 { sum += abs(wind.sample(x: Double(k) * 80, y: 400).u); n += 1 }
            }
            return sum / n
        }
        let light = spread(.light), gentle = spread(.gentle), storm = spread(.storm)
        XCTAssertLessThan(light, gentle)
        XCTAssertLessThan(gentle, storm)
    }

    func testPresetTransitionIsGradual() {
        var weather = Weather(preset: .light, seed: 1)
        weather.setPreset(.storm)
        var last = weather.current.density
        let start = last
        for _ in 0..<(60 * 20) {
            weather.step(dt: 1.0 / 60)
            let d = weather.current.density
            XCTAssertGreaterThanOrEqual(d, last)
            XCTAssertLessThan(d - last, 5, "density must not jump")
            last = d
        }
        let goal = WeatherParams.preset(.storm).density
        XCTAssertGreaterThan(last, start + 0.95 * (goal - start), "should have arrived after 20 s")
        XCTAssertLessThanOrEqual(last, goal)
    }

    func testPresetsAreOrderedAndMixesSumToOne() {
        let l = WeatherParams.preset(.light), g = WeatherParams.preset(.gentle), s = WeatherParams.preset(.storm)
        XCTAssertLessThan(l.density, g.density); XCTAssertLessThan(g.density, s.density)
        XCTAssertLessThan(l.fallSpeed, g.fallSpeed); XCTAssertLessThan(g.fallSpeed, s.fallSpeed)
        XCTAssertLessThan(l.accumulation, g.accumulation); XCTAssertLessThan(g.accumulation, s.accumulation)
        for p in [l, g, s] {
            XCTAssertEqual(p.speck + p.tuft + p.large + p.crystal, 1, accuracy: 1e-9)
            XCTAssertLessThan(p.large + p.crystal, 0.1, "large flakes stay uncommon")
        }
    }

    func testCalmModeRemovesGusts() {
        var weather = Weather(preset: .storm, seed: 4)
        weather.calm = true
        for _ in 0..<(60 * 30) { weather.step(dt: 1.0 / 60) }
        XCTAssertLessThan(weather.effective.gust, 0.1)
        XCTAssertLessThan(weather.effective.windMean, WeatherParams.preset(.storm).windMean * 0.35)
    }
}
