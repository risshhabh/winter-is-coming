import Foundation

public struct WindParams: Equatable {
    /// Prevailing horizontal wind (px/s, signed)
    public var mean: Double
    /// Amplitude of the slowly swirling component (px/s)
    public var turbulence: Double
    /// Peak extra speed inside a travelling gust (px/s)
    public var gust: Double

    public init(mean: Double, turbulence: Double, gust: Double) {
        self.mean = mean
        self.turbulence = turbulence
        self.gust = gust
    }
}

/// Spatially varying air velocity.
///
/// Coherent noise is evaluated on a coarse grid once per step and flakes sample it bilinearly, so the
/// per-flake cost is a handful of multiplications. The noise pattern is carried downwind over time and
/// gusts travel across the screen as broad fronts, so neighbouring flakes move alike while flakes far
/// apart do not.
public struct WindField {
    public static let cell = 140.0
    static let margin = 1

    public private(set) var cols = 0
    public private(set) var rows = 0
    private var u: [Double] = []
    private var v: [Double] = []
    private var drift = 0.0
    public private(set) var originX = 0.0
    public private(set) var originY = 0.0
    public let seed: UInt64

    public init(width: Double, height: Double, seed: UInt64) {
        self.seed = seed
        resize(width: width, height: height)
    }

    /// Cover a different region (displays were added, removed or rearranged)
    public mutating func resize(minX: Double, minY: Double, width: Double, height: Double) {
        originX = minX
        originY = minY
        resize(width: width, height: height)
    }

    public mutating func resize(width: Double, height: Double) {
        cols = Int((width / WindField.cell).rounded(.up)) + 1 + 2 * WindField.margin
        rows = Int((height / WindField.cell).rounded(.up)) + 1 + 2 * WindField.margin
        u = [Double](repeating: 0, count: cols * rows)
        v = [Double](repeating: 0, count: cols * rows)
    }

    /// Recompute the grid for the given moment. `dt` only advances how far the pattern has been carried.
    public mutating func update(time: Double, dt: Double, params p: WindParams) {
        drift += p.mean * dt * 0.6
        // Direction factor that passes smoothly through zero when the prevailing wind turns around
        let dir = p.mean / (p.mean * p.mean + 25).squareRoot()
        let cell = WindField.cell
        for gy in 0..<rows {
            let wy = originY + Double(gy - WindField.margin) * cell
            for gx in 0..<cols {
                let wx = originX + Double(gx - WindField.margin) * cell
                let nx = (wx - drift) / 420
                let ny = wy / 420
                let broad = Noise.value3(nx, ny, time * 0.11, seed: seed)
                let fine = Noise.value3(nx * 2.3, ny * 2.3, time * 0.23, seed: seed ^ 0x51)
                let lift = Noise.value3(nx + 31.7, ny - 12.3, time * 0.13, seed: seed ^ 0xA7)
                let g = Noise.value3((wx - drift * 2.5) / 1100, wy / 1600, time * 0.07, seed: seed ^ 0xF3)
                // Only the upper lobes of the gust noise count, so gusts come and go with calm in between
                var gust = (g - 0.1) / 0.5
                gust = gust < 0 ? 0 : (gust > 1 ? 1 : gust)
                gust = gust * gust * (3 - 2 * gust)
                let k = gy * cols + gx
                u[k] = p.mean + (broad + 0.45 * fine) * p.turbulence + gust * p.gust * dir
                v[k] = lift * p.turbulence * 0.3
            }
        }
    }

    /// Air velocity at a point (px/s). Points outside the grid use the nearest edge value.
    @inline(__always) public func sample(x: Double, y: Double) -> (u: Double, v: Double) {
        let cell = WindField.cell
        var fx = (x - originX) / cell + Double(WindField.margin)
        var fy = (y - originY) / cell + Double(WindField.margin)
        let maxX = Double(cols - 1) - 0.001, maxY = Double(rows - 1) - 0.001
        fx = fx < 0 ? 0 : (fx > maxX ? maxX : fx)
        fy = fy < 0 ? 0 : (fy > maxY ? maxY : fy)
        let ix = Int(fx), iy = Int(fy)
        let tx = fx - Double(ix), ty = fy - Double(iy)
        let k = iy * cols + ix
        let u0 = u[k] + (u[k + 1] - u[k]) * tx
        let u1 = u[k + cols] + (u[k + cols + 1] - u[k + cols]) * tx
        let v0 = v[k] + (v[k + 1] - v[k]) * tx
        let v1 = v[k + cols] + (v[k + cols + 1] - v[k + cols]) * tx
        return (u0 + (u1 - u0) * ty, v0 + (v1 - v0) * ty)
    }
}
