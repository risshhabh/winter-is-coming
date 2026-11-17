import Foundation

/// Adaptive quality: thins the snowfall when frames cost too much, and restores it when there is room.
///
/// The only knob is a density scale. Fewer flakes means less simulation and fewer sprites, and thinner
/// snow is far less noticeable than a stuttering desktop.
public struct QualityGovernor {
    public static let minimumScale = 0.35
    /// Scale ceiling while the system is constrained (Low Power Mode, thermal pressure)
    public static let constrainedScale = 0.6

    /// CPU time per frame (ms) the app allows itself for simulation plus sprite updates
    public var budgetMs = 4.0
    public private(set) var scale = 1.0
    public private(set) var smoothedCostMs = 0.0

    public init() {}

    /// Report one frame's cost. `dt` is the time since the last report.
    public mutating func report(frameCostMs: Double, dt: Double, constrained: Bool) {
        guard dt > 0 else { return }
        smoothedCostMs += (frameCostMs - smoothedCostMs) * min(1, dt / 0.75)
        let ceiling = constrained ? QualityGovernor.constrainedScale : 1.0
        if smoothedCostMs > budgetMs {
            scale -= 0.15 * dt                  // back off within a few seconds
        } else if smoothedCostMs < budgetMs * 0.6 {
            scale += 0.05 * dt                  // recover slowly, so it does not oscillate
        }
        if scale > ceiling { scale = max(ceiling, scale - 0.3 * dt) }
        scale = min(1, max(QualityGovernor.minimumScale, scale))
    }
}
