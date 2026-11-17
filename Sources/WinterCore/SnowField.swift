import Foundation

/// Accumulated snow on one surface: a height map with one value per 3 px column.
///
/// Snow is measured as area (px²): a column of height `h` holds `h * colW`. Every operation either
/// conserves that area or reports exactly how much it removed, so callers can turn it into powder.
public struct SnowField {
    public static let colW = 3.0

    public private(set) var minX: Double
    public private(set) var topY: Double
    public private(set) var width: Double
    public private(set) var maxH: Double
    public let seed: UInt64
    /// Radius of the window's top corners (0 for the Dock and the ground)
    public let cornerRadius: Double
    public private(set) var h: [Double]
    /// How far the supporting edge sits below `topY` in each column (0 or negative). Non-zero only
    /// inside a rounded corner, where the snow line follows the curve down.
    public private(set) var base: [Double]
    /// Most snow each column can hold. Tapers toward both ends and varies along the surface,
    /// so no two piles end up with the same outline.
    public private(set) var caps: [Double]
    /// How readily each column catches falling snow (about 0.45...1.5)
    public private(set) var catchFactor: [Double]
    /// False where a window in front covers this column. Hidden snow is kept, not deleted.
    public private(set) var visible: [Bool]
    /// Changes whenever heights, visibility or geometry change; renderers compare it to skip work.
    public private(set) var version: UInt64 = 1
    private var noiseOrigin = 0
    private var sweepRight = true

    // Where one landing flake's snow goes, relative to the column it hit. Sums to 1.
    private static let kernelOffsets = [0, -1, 1, -2, 2, -3, 3]
    private static let kernelWeights = [0.26, 0.20, 0.20, 0.11, 0.11, 0.06, 0.06]

    public init(minX: Double, topY: Double, width: Double, maxH: Double, seed: UInt64, cornerRadius: Double = 0) {
        self.minX = minX
        self.topY = topY
        self.width = width
        self.maxH = maxH
        self.seed = seed
        self.cornerRadius = cornerRadius
        let n = SnowField.columns(for: width)
        h = [Double](repeating: 0, count: n)
        visible = [Bool](repeating: true, count: n)
        (caps, catchFactor, base) = SnowField.makeProfile(count: n, maxH: maxH, seed: seed, origin: 0, cornerRadius: cornerRadius)
    }

    static func columns(for width: Double) -> Int { max(1, Int((width / colW).rounded(.up))) }

    /// Per-column cap and catch factor. Both come from coherent noise along the surface, sampled in
    /// screen-anchored columns so the pattern stays put when the surface is resized.
    static func makeProfile(count n: Int, maxH: Double, seed: UInt64, origin: Int, cornerRadius r: Double)
        -> (caps: [Double], catchFactor: [Double], base: [Double]) {
        var caps = [Double](repeating: 0, count: n)
        var catchFactor = [Double](repeating: 1, count: n)
        var base = [Double](repeating: 0, count: n)
        for i in 0..<n {
            let edge = min(Double(i) + 0.5, Double(n - i) - 0.5) * colW
            let taper = min(1, (edge + 3) / (maxH * 1.8)).squareRoot()
            let u = Double(i + origin) * colW
            // Three scales of unevenness: long swells, hummocks, and small lumps
            let broad = Noise.value3(u / 140, 0.37, 0.5, seed: seed)
            let mid = Noise.value3(u / 55, 5.1, 0.5, seed: seed ^ 0xABCD)
            let fine = Noise.value3(u / 21, 9.7, 0.5, seed: seed ^ 0x1234)
            let vary = min(1, max(0.42, 0.74 + 0.62 * (0.5 * broad + 0.3 * mid + 0.2 * fine)))
            caps[i] = maxH * taper * vary
            // Wind leaves more snow in some places than others, so a pile is uneven long before it is full
            let drift = Noise.value3(u / 80, 2.9, 0.5, seed: seed ^ 0x7777)
            let ripple = Noise.value3(u / 26, 7.3, 0.5, seed: seed ^ 0x4242)
            catchFactor[i] = min(1.5, max(0.45, 0.95 + 0.9 * (0.65 * drift + 0.35 * ripple)))
            // Rounded corner: the ledge curves away. Snow follows it down until it gets too steep to hold any.
            if r > 0, edge < r, n * 3 > Int(r) * 4 {
                let drop = r - (r * r - (r - edge) * (r - edge)).squareRoot()
                if drop > r * 0.45 {
                    caps[i] = 0
                    base[i] = -r * 0.45
                } else {
                    base[i] = -drop
                    caps[i] *= 1 - drop / (r * 0.45) * 0.6
                }
            }
        }
        return (caps, catchFactor, base)
    }

    public var count: Int { h.count }
    public var maxX: Double { minX + width }
    /// Total snow held (px²), including hidden columns
    public var area: Double { h.reduce(0, +) * SnowField.colW }

    @inline(__always) public func col(at x: Double) -> Int? {
        guard x >= minX else { return nil }
        let c = Int((x - minX) / SnowField.colW)
        return c < h.count ? c : nil
    }

    @inline(__always) public func colX(_ c: Int) -> Double { minX + (Double(c) + 0.5) * SnowField.colW }
    @inline(__always) public func surface(_ c: Int) -> Double { topY + base[c] + h[c] }

    /// The surface follows its window; the snow rides along.
    public mutating func move(minX: Double, topY: Double) {
        guard minX != self.minX || topY != self.topY else { return }
        self.minX = minX
        self.topY = topY
        version &+= 1
    }

    /// Add `area` px² of snow around `x`. Returns how much stuck.
    ///
    /// Snow sticks less and less as a column nears its cap, so piles level off gradually instead of
    /// hitting a hard ceiling. What does not stick (full columns, hidden columns, past the edge) is
    /// simply not deposited; it is the caller's loss to account for.
    @discardableResult
    public mutating func deposit(x: Double, area: Double) -> Double {
        guard area > 0, let c = col(at: min(max(x, minX), maxX - 0.001)) else { return 0 }
        var stuck = 0.0
        for k in 0..<SnowField.kernelOffsets.count {
            let i = c + SnowField.kernelOffsets[k]
            guard i >= 0, i < h.count, visible[i] else { continue }
            let cap = caps[i]
            guard cap > 0 else { continue }
            let fill = h[i] / cap
            let dh = min(area * SnowField.kernelWeights[k] / SnowField.colW * catchFactor[i] * (1 - fill * fill), cap - h[i])
            guard dh > 0 else { continue }
            h[i] += dh
            stuck += dh
        }
        if stuck > 0 { version &+= 1 }
        return stuck * SnowField.colW
    }

    /// One pass of slumping: snow slides to the lower neighbour wherever the slope is steeper than
    /// `maxStep` px per column. Conserves area exactly. Returns true while snow is still moving.
    @discardableResult
    public mutating func relax(maxStep: Double = 1.5, rate: Double = 0.35) -> Bool {
        let n = h.count
        guard n > 1 else { return false }
        var moved = false
        sweepRight.toggle()             // alternate direction so slumping has no left/right bias
        var k = 0
        while k < n - 1 {
            let i = sweepRight ? k : n - 2 - k
            k += 1
            let d = h[i] - h[i + 1]
            let excess = abs(d) - maxStep
            guard excess > 0 else { continue }
            var m = excess * rate
            if d > 0 {
                m = min(m, h[i], max(0, caps[i + 1] - h[i + 1]))
                h[i] -= m
                h[i + 1] += m
            } else {
                m = min(m, h[i + 1], max(0, caps[i] - h[i]))
                h[i + 1] -= m
                h[i] += m
            }
            if m > 0.01 { moved = true }
        }
        if moved { version &+= 1 }
        return moved
    }

    /// Lower every column by `dh`. Returns the area removed.
    @discardableResult
    public mutating func melt(_ dh: Double) -> Double {
        guard dh > 0 else { return 0 }
        var removed = 0.0
        for i in 0..<h.count where h[i] > 0 {
            let r = min(h[i], dh)
            h[i] -= r
            removed += r
        }
        if removed > 0 { version &+= 1 }
        return removed * SnowField.colW
    }

    /// Remove `fraction` of every column. `body` is told where each piece came from:
    /// (x, base y, height before removal, area removed, column was visible).
    public mutating func shed(fraction: Double, _ body: (Double, Double, Double, Double, Bool) -> Void) {
        let f = min(1, max(0, fraction))
        guard f > 0 else { return }
        var any = false
        for i in 0..<h.count where h[i] > 0.02 {
            let before = h[i]
            let r = before * f
            h[i] = before - r
            any = true
            body(colX(i), topY + base[i], before, r * SnowField.colW, visible[i])
        }
        if any { version &+= 1 }
    }

    public mutating func clear() {
        for i in 0..<h.count { h[i] = 0 }
        version &+= 1
    }

    /// Change how high this pile may grow (a user preference). Snow above the new limit is removed.
    public mutating func setMaxH(_ newMaxH: Double) {
        guard newMaxH != maxH else { return }
        maxH = newMaxH
        (caps, catchFactor, base) = SnowField.makeProfile(count: h.count, maxH: maxH, seed: seed, origin: noiseOrigin, cornerRadius: cornerRadius)
        for j in 0..<h.count where h[j] > caps[j] { h[j] = caps[j] }
        version &+= 1
    }

    /// The surface changed width (window resized). Snow stays where it is on screen; columns that no
    /// longer exist, and snow above the new caps, are reported to `cut` as (x, y, area).
    public mutating func resize(minX newMinX: Double, width newWidth: Double, cut: (Double, Double, Double) -> Void) {
        let shift = Int(((newMinX - minX) / SnowField.colW).rounded())
        let n = SnowField.columns(for: newWidth)
        var nh = [Double](repeating: 0, count: n)
        for i in 0..<h.count where h[i] > 0 {
            let j = i - shift
            if j >= 0 && j < n {
                nh[j] = h[i]
            } else {
                cut(colX(i), topY + h[i] * 0.5, h[i] * SnowField.colW)
            }
        }
        noiseOrigin += shift            // keeps the cap pattern anchored on screen, not to the left edge
        minX = newMinX
        width = newWidth
        (caps, catchFactor, base) = SnowField.makeProfile(count: n, maxH: maxH, seed: seed, origin: noiseOrigin, cornerRadius: cornerRadius)
        for j in 0..<n where nh[j] > caps[j] {
            cut(colX(j), topY + caps[j], (nh[j] - caps[j]) * SnowField.colW)
            nh[j] = caps[j]
        }
        h = nh
        visible = [Bool](repeating: true, count: n)
        version &+= 1
    }

    /// Part of the snow lags behind when its window jerks sideways: `fraction` of every column moves
    /// `columns` along the surface (positive = toward +x). Whatever is pushed off the end, or lands
    /// where there is no room for it, is reported to `cut` as (x, y, area).
    public mutating func slide(columns k: Int, fraction: Double, cut: (Double, Double, Double) -> Void) {
        let f = min(1, max(0, fraction))
        guard k != 0, f > 0 else { return }
        let n = h.count
        var moved = [Double](repeating: 0, count: n)
        for i in 0..<n where h[i] > 0 {
            let m = h[i] * f
            h[i] -= m
            let j = i + k
            if j >= 0 && j < n {
                moved[j] += m
            } else {
                cut(colX(j < 0 ? 0 : n - 1), topY + base[i] + m * 0.5, m * SnowField.colW)
            }
        }
        for j in 0..<n where moved[j] > 0 {
            let room = max(0, caps[j] - h[j])
            let stay = min(room, moved[j])
            h[j] += stay
            if moved[j] > stay { cut(colX(j), topY + base[j] + h[j], (moved[j] - stay) * SnowField.colW) }
        }
        version &+= 1
    }

    // MARK: Visibility (occlusion by windows in front)

    public mutating func setAllVisible(_ v: Bool) {
        for i in 0..<visible.count { visible[i] = v }
        version &+= 1
    }

    /// Mark the columns whose centre lies in `fromX..<toX` as hidden or visible
    public mutating func setVisible(_ v: Bool, fromX: Double, toX: Double) {
        guard toX > minX, fromX < maxX else { return }
        let c0 = max(0, Int(((fromX - minX) / SnowField.colW - 0.5).rounded(.up)))
        let c1 = min(h.count - 1, Int(((toX - minX) / SnowField.colW - 0.5).rounded(.up)) - 1)
        guard c0 <= c1 else { return }
        for i in c0...c1 { visible[i] = v }
        version &+= 1
    }

    // MARK: Direct edits used by Play mode (snowballs)

    /// Take `fraction` of one column's snow; returns the height taken
    public mutating func take(col c: Int, fraction: Double) -> Double {
        let t = h[c] * min(1, max(0, fraction))
        guard t > 0 else { return 0 }
        h[c] -= t
        version &+= 1
        return t
    }

    /// Add height to one column, limited by its cap; returns the height added
    @discardableResult
    public mutating func addHeight(col c: Int, _ dh: Double) -> Double {
        let a = min(max(0, dh), caps[c] - h[c])
        guard a > 0 else { return 0 }
        h[c] += a
        version &+= 1
        return a
    }
}
