import Foundation

/// Axis-aligned rectangle in scene coordinates (origin bottom-left, y up).
public struct Rect: Equatable {
    public var minX: Double
    public var minY: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        minX = x
        minY = y
        self.width = width
        self.height = height
    }

    public var maxX: Double { minX + width }
    public var maxY: Double { minY + height }

    @inline(__always) public func contains(_ x: Double, _ y: Double) -> Bool {
        x >= minX && x < minX + width && y >= minY && y < minY + height
    }
}

/// One on-screen window as seen by the simulation.
public struct WindowInfo: Equatable {
    public var id: Int
    public var rect: Rect

    public init(id: Int, rect: Rect) {
        self.id = id
        self.rect = rect
    }
}
