import Foundation

/// Small, fast, seedable generator (SplitMix64) so simulations are reproducible in tests.
public struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64

    public init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in 0..<1
    @inline(__always) public mutating func unit() -> Double {
        Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }

    @inline(__always) public mutating func range(_ a: Double, _ b: Double) -> Double {
        a + (b - a) * unit()
    }
}

/// Coherent value noise. Output is in -1...1 and is continuous (C2) in every argument.
public enum Noise {
    @inline(__always) static func hash(_ x: Int, _ y: Int, _ z: Int, _ seed: UInt64) -> Double {
        var h = seed
        h ^= UInt64(bitPattern: Int64(x)) &* 0x9E37_79B9_7F4A_7C15
        h ^= UInt64(bitPattern: Int64(y)) &* 0xC2B2_AE3D_27D4_EB4F
        h ^= UInt64(bitPattern: Int64(z)) &* 0x1656_67B1_9E37_79F9
        h ^= h >> 31
        h = h &* 0xBF58_476D_1CE4_E5B9
        h ^= h >> 29
        h = h &* 0x94D0_49BB_1331_11EB
        h ^= h >> 32
        return Double(h >> 11) * (2.0 / 9_007_199_254_740_992.0) - 1.0
    }

    @inline(__always) static func fade(_ t: Double) -> Double { t * t * t * (t * (t * 6 - 15) + 10) }

    public static func value3(_ x: Double, _ y: Double, _ z: Double, seed: UInt64) -> Double {
        let fx = x.rounded(.down), fy = y.rounded(.down), fz = z.rounded(.down)
        let ix = Int(fx), iy = Int(fy), iz = Int(fz)
        let u = fade(x - fx), v = fade(y - fy), w = fade(z - fz)
        func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
        let x00 = lerp(hash(ix, iy, iz, seed), hash(ix + 1, iy, iz, seed), u)
        let x10 = lerp(hash(ix, iy + 1, iz, seed), hash(ix + 1, iy + 1, iz, seed), u)
        let x01 = lerp(hash(ix, iy, iz + 1, seed), hash(ix + 1, iy, iz + 1, seed), u)
        let x11 = lerp(hash(ix, iy + 1, iz + 1, seed), hash(ix + 1, iy + 1, iz + 1, seed), u)
        return lerp(lerp(x00, x10, v), lerp(x01, x11, v), w)
    }

    public static func value1(_ x: Double, seed: UInt64) -> Double { value3(x, 0.5, 0.5, seed: seed) }
}
