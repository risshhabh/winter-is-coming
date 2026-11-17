import Foundation

/// A place snow can pile up: the top of a window, the Dock, or the bottom of a display.
public final class Surface {
    public enum Kind { case window, dock, ground }
    public enum State {
        /// On screen
        case present
        /// Just left the screen; not yet known whether it was closed, minimized or moved to another Space
        case limbo
        /// Off screen but alive (another Space); its snow is kept
        case hidden
    }

    public let id: Int
    public let kind: Kind
    public var field: SnowField
    /// The window's (or Dock's) rectangle; falling snow that is not in front disappears behind it
    public internal(set) var rect: Rect
    public internal(set) var state = State.present
    var kin = WindowKinematics()
    var slideCarry = 0.0
    var vanishedAt = 0.0
    /// How frosted the window's corners are, 0...1. Grows while the window sits still in the cold.
    public internal(set) var frost = 0.0

    /// Bumped each time the window shakes snow off; Play mode uses it to knock snowballs loose
    public internal(set) var shedSerial = 0
    public internal(set) var lastShedFraction = 0.0
    public internal(set) var releaseVX = 0.0
    public internal(set) var releaseVY = 0.0

    /// True while the surface is where the user can see it and snow can land on it
    public var onScreen: Bool { state == .present }

    init(id: Int, kind: Kind, field: SnowField, rect: Rect) {
        self.id = id
        self.kind = kind
        self.field = field
        self.rect = rect
    }
}

public enum Contact {
    case none
    /// Landed on a surface; the value is how much of its snow stuck (px²)
    case landed(Double)
    /// Passed behind a window
    case behind
}

/// One connected display, in global coordinates (origin bottom-left of the primary display, y up).
public struct DisplayInfo: Equatable {
    public var id: Int
    public var rect: Rect

    public init(id: Int, rect: Rect) {
        self.id = id
        self.rect = rect
    }
}

/// What to do with the snow of a window that has left the screen.
public enum VanishDecision {
    /// The window still exists somewhere (another Space): keep the snow for when it returns
    case keep
    /// The window is gone or put away (closed, minimized, app hidden): the snow falls
    case drop
    /// Not known yet; ask again on the next update
    case wait
}

/// Owns every snow surface across all displays, keeps them in step with the window list, and answers
/// "what does a falling particle hit?". All coordinates are global.
public final class SurfaceManager {
    public static let dockID = -2
    public static let windowPileMax = 16.0
    public static let groundPileMax = 34.0
    public static let dockPileMax = 18.0
    /// A window whose top is this close to the top of its display has no visible snow line,
    /// so flakes are not spawned above it at all.
    static let skyBlockBand = 60.0

    public static func groundID(display: Int) -> Int { -1000 - display }

    public private(set) var displays: [DisplayInfo] = []
    /// One per display, in the same order as `displays`
    public private(set) var grounds: [Surface] = []
    /// Bounding box of all displays
    public private(set) var bounds = Rect(x: 0, y: 0, width: 0, height: 0)
    /// Windows currently on screen, front to back
    public private(set) var windows: [Surface] = []
    /// Windows that have just left the screen and are still drawn while their fate is decided
    public private(set) var limbo: [Surface] = []
    public private(set) var dock: Surface?
    /// Bumped when window geometry or order changes
    public private(set) var layoutVersion = 0
    /// Number of updates that found nothing changed and skipped all work
    public private(set) var skippedUpdates = 0
    /// Corner radius given to new window surfaces
    public var cornerRadius = 0.0

    private var byID: [Int: Surface] = [:]
    private var hidden: [Int: Surface] = [:]
    private var skyBlocked: [(minX: Double, maxX: Double, display: Int)] = []
    private var scratch: [Surface] = []
    private var seen = Set<Int>()
    private var lastInfos: [WindowInfo] = []
    private var settling = false
    private let seed: UInt64

    public init(displays: [DisplayInfo], seed: UInt64) {
        self.seed = seed
        setDisplays(displays)
    }

    /// A single display at the origin
    public convenience init(width: Double, height: Double, seed: UInt64) {
        self.init(displays: [DisplayInfo(id: 0, rect: Rect(x: 0, y: 0, width: width, height: height))], seed: seed)
    }

    /// The first display's ground
    public var ground: Surface { grounds[0] }
    public var hiddenCount: Int { hidden.count }

    public func surface(id: Int) -> Surface? {
        if id == SurfaceManager.dockID { return dock }
        if id <= -1000 { return grounds.first { $0.id == id } }
        return byID[id]
    }

    // MARK: Displays

    /// Displays were connected, disconnected, resized or rearranged. Ground snow on a display that is
    /// still there is kept (remapped if its width changed); window snow is untouched.
    public func setDisplays(_ list: [DisplayInfo]) {
        guard list != displays else { return }
        var newGrounds: [Surface] = []
        for d in list {
            let id = SurfaceManager.groundID(display: d.id)
            let rect = Rect(x: d.rect.minX, y: d.rect.minY - 1, width: d.rect.width, height: 1)
            if let g = grounds.first(where: { $0.id == id }) {
                // Keep the snow at the same distance from the display's left edge
                g.field.move(minX: d.rect.minX, topY: d.rect.minY)
                if abs(g.field.width - d.rect.width) > 0.5 {
                    g.field.resize(minX: d.rect.minX, width: d.rect.width) { _, _, _ in }
                }
                g.rect = rect
                newGrounds.append(g)
            } else {
                let field = SnowField(minX: d.rect.minX, topY: d.rect.minY, width: d.rect.width,
                                      maxH: SurfaceManager.groundPileMax,
                                      seed: seed ^ 0x6001 ^ (UInt64(truncatingIfNeeded: d.id) &* 0x9E37))
                newGrounds.append(Surface(id: id, kind: .ground, field: field, rect: rect))
            }
        }
        displays = list
        grounds = newGrounds
        if let first = list.first {
            var minX = first.rect.minX, minY = first.rect.minY, maxX = first.rect.maxX, maxY = first.rect.maxY
            for d in list.dropFirst() {
                minX = min(minX, d.rect.minX); minY = min(minY, d.rect.minY)
                maxX = max(maxX, d.rect.maxX); maxY = max(maxY, d.rect.maxY)
            }
            bounds = Rect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }
        recomputeOcclusion()
        layoutVersion += 1
    }

    // MARK: Following the window list

    /// Bring surfaces in line with the current on-screen windows (front to back, global coordinates).
    ///
    /// - A moved window carries its snow; how much comes off depends on its velocity and acceleration.
    /// - A resized window keeps the snow that still has a surface under it.
    /// - A window that leaves the screen is held briefly, then `classify(id, secondsSinceItLeft)`
    ///   decides whether its snow is kept for later or falls.
    ///
    /// When the list is identical to the previous one and nothing is still in motion, this returns
    /// immediately.
    public func update(windows infos: [WindowInfo], dt: Double, time: Double, powder: inout PowderSystem,
                       classify: (Int, Double) -> VanishDecision) {
        if !settling, limbo.isEmpty, infos == lastInfos {
            skippedUpdates += 1
            return
        }
        lastInfos = infos
        settling = false
        var changed = false
        seen.removeAll(keepingCapacity: true)
        scratch.removeAll(keepingCapacity: true)

        for info in infos {
            guard seen.insert(info.id).inserted else { continue }
            let r = info.rect
            if let s = byID[info.id] {
                if s.state != .present {
                    // Back from another Space, or reappeared before its fate was decided
                    if s.state == .hidden { hidden[info.id] = nil }
                    s.state = .present
                    s.kin.reset()
                    s.slideCarry = 0
                    if abs(s.rect.width - r.width) <= 0.5 { s.rect = r }
                    s.field.move(minX: r.minX, topY: r.maxY)
                    changed = true
                }
                let old = s.rect
                if abs(old.width - r.width) > 0.5 {
                    powder.beginBatch(totalArea: s.field.area)
                    s.field.resize(minX: r.minX, width: r.width) { x, y, area in
                        powder.add(x: x, y: y, height: 0, area: area, vx: 0, vy: 10, spread: 30,
                                   source: info.id, time: time)
                    }
                    powder.endBatch()
                    s.field.move(minX: r.minX, topY: r.maxY)
                    s.kin.reset()
                    changed = true
                } else {
                    let dx = r.minX - old.minX, dy = r.maxY - old.maxY
                    let result = s.kin.update(dx: dx, dy: dy, dt: dt)
                    if dx != 0 || dy != 0 {
                        s.field.move(minX: r.minX, topY: r.maxY)
                        changed = true
                    }
                    apply(result, to: s, powder: &powder, time: time)
                    if s.kin.speed > 1 { settling = true }
                }
                if old != r { changed = true }
                s.rect = r
                scratch.append(s)
            } else {
                let field = SnowField(minX: r.minX, topY: r.maxY, width: r.width, maxH: SurfaceManager.windowPileMax,
                                      seed: seed ^ (UInt64(truncatingIfNeeded: info.id) &* 0x9E37_79B9),
                                      cornerRadius: cornerRadius)
                let s = Surface(id: info.id, kind: .window, field: field, rect: r)
                byID[info.id] = s
                scratch.append(s)
                changed = true
            }
        }

        // Windows that were on screen last time and are not now
        for s in windows where !seen.contains(s.id) {
            s.state = .limbo
            s.vanishedAt = time
            limbo.append(s)
            changed = true
        }
        if !limbo.isEmpty {
            limbo.removeAll { s in
                if s.state == .present { return true }          // it came back
                switch classify(s.id, time - s.vanishedAt) {
                case .wait:
                    return false
                case .keep:
                    s.state = .hidden
                    hidden[s.id] = s
                case .drop:
                    shed(s, fraction: 1, vx: 0, vy: 0, powder: &powder, time: time)
                    byID[s.id] = nil
                }
                return true
            }
        }

        if !changed, scratch.count == windows.count {
            for i in 0..<scratch.count where scratch[i] !== windows[i] { changed = true; break }
        } else {
            changed = true
        }
        swap(&windows, &scratch)
        if changed {
            recomputeOcclusion()
            layoutVersion += 1
        }
    }

    /// Forget hidden windows that no longer exist (closed while on another Space)
    public func pruneHidden(stillExists: (Int) -> Bool) {
        for id in Array(hidden.keys) where !stillExists(id) {
            hidden[id] = nil
            byID[id] = nil
        }
    }

    /// Tell the manager where the Dock is (nil = hidden or unknown). Snow sits along the top edge of the
    /// rectangle, wherever the Dock is: a wide ledge for a bottom Dock, a short one on top of a side
    /// Dock. A hidden Dock keeps its snow; a Dock that changes size keeps what still fits.
    public func setDock(rect: Rect?, powder: inout PowderSystem, time: Double) {
        guard let r = rect else {
            dock?.state = .hidden
            return
        }
        if let d = dock {
            d.state = .present
            if abs(d.rect.width - r.width) > 0.5 {
                powder.beginBatch(totalArea: d.field.area)
                d.field.resize(minX: r.minX, width: r.width) { x, y, area in
                    powder.add(x: x, y: y, height: 0, area: area, vx: 0, vy: 10, spread: 30,
                               source: SurfaceManager.dockID, time: time)
                }
                powder.endBatch()
            }
            d.field.move(minX: r.minX, topY: r.maxY)
            d.rect = r
        } else {
            let field = SnowField(minX: r.minX, topY: r.maxY, width: r.width, maxH: SurfaceManager.dockPileMax,
                                  seed: seed ^ 0xD0C4)
            dock = Surface(id: SurfaceManager.dockID, kind: .dock, field: field, rect: r)
        }
    }

    private func apply(_ result: ShedResult, to s: Surface, powder: inout PowderSystem, time: Double) {
        if result.slide != 0 {
            s.slideCarry += result.slide
            let cols = Int((s.slideCarry / SnowField.colW).rounded(.towardZero))
            if cols != 0 {
                s.slideCarry -= Double(cols) * SnowField.colW
                let id = s.id
                let vx = s.kin.prevVX * 0.5
                s.field.slide(columns: cols, fraction: result.slideFraction) { x, y, area in
                    powder.burst(x: x, y: y, area: area, vx: vx, vy: 15, spread: 45, source: id, time: time)
                }
            }
        }
        if result.fraction > 0.0005 {
            shed(s, fraction: result.fraction, vx: s.kin.prevVX * 0.6, vy: s.kin.prevVY * 0.6,
                 powder: &powder, time: time)
        }
    }

    private func shed(_ s: Surface, fraction: Double, vx: Double, vy: Double, powder: inout PowderSystem, time: Double) {
        if fraction > 0.3 { s.frost *= 0.5 }                 // a good shake cracks the frost off too
        if fraction > 0.02 {
            s.shedSerial += 1
            s.lastShedFraction = fraction
            s.releaseVX = vx
            s.releaseVY = vy
        }
        let spread = 70 + min(260, hypot(vx, vy) * 0.25)
        powder.beginBatch(totalArea: s.field.area * fraction)
        let id = s.id
        s.field.shed(fraction: fraction) { x, baseY, heightBefore, area, visible in
            // Snow hidden behind another window comes off without a visible cloud
            guard visible else { return }
            powder.add(x: x, y: baseY, height: heightBefore, area: area, vx: vx, vy: vy + 12, spread: spread,
                       source: id, time: time)
        }
        powder.endBatch()
    }

    // MARK: Slow processes

    /// Slumping and optional melting; call a few times a second. `meltRate` is px of height per second.
    /// `frostRate` is frost growth per second (0 = frost off); it should follow the weather.
    public func settle(dt: Double, meltRate: Double, frostRate: Double = 0) {
        let dh = meltRate * dt
        // With melting on, frost thaws back to a thin rim instead of covering the corner
        let frostCap = meltRate > 0 ? 0.4 : 1.0
        for s in windows {
            if frostRate > 0 {
                s.frost = s.frost < frostCap ? min(frostCap, s.frost + frostRate * dt) : max(frostCap, s.frost - 0.004 * dt)
            } else {
                s.frost = max(0, s.frost - 0.02 * dt)
            }
            s.field.relax()
            if dh > 0 { s.field.melt(dh) }
        }
        for s in hidden.values where dh > 0 { s.field.melt(dh) }
        for g in grounds {
            g.field.relax()
            if dh > 0 { g.field.melt(dh) }
        }
        if let d = dock {
            d.field.relax()
            if dh > 0 { d.field.melt(dh) }
        }
    }

    /// The wind lifts a little loose snow off one pile (atmospheric event). Returns false if there was
    /// nothing worth lifting.
    public func blowPowder(windU: Double, pick: Int, powder: inout PowderSystem, time: Double) -> Bool {
        var candidates = windows.filter { $0.field.area > 150 }
        candidates.append(contentsOf: grounds.filter { $0.field.area > 150 })
        guard !candidates.isEmpty else { return false }
        let s = candidates[abs(pick) % candidates.count]
        shed(s, fraction: 0.05, vx: windU * 2.5 + (windU < 0 ? -60 : 60), vy: 25, powder: &powder, time: time)
        return true
    }

    public func clearAll() {
        for s in byID.values { s.field.clear(); s.frost = 0 }
        for g in grounds { g.field.clear() }
        dock?.field.clear()
    }

    /// Total snow lying on every surface (px²)
    public var totalArea: Double {
        var a = dock?.field.area ?? 0
        for g in grounds { a += g.field.area }
        for s in byID.values { a += s.field.area }
        return a
    }

    // MARK: Occlusion

    /// Which columns of each pile can be seen (on some display, not covered by a window in front), and
    /// where flakes should not spawn. Works on x-intervals, so the cost is proportional to the number
    /// of window pairs, and it only runs when the layout changed.
    func recomputeOcclusion() {
        skyBlocked.removeAll(keepingCapacity: true)
        for (i, s) in windows.enumerated() {
            let py = s.field.topY + 1
            // Visible only where the top edge lies on a display (handles windows partly off screen
            // and windows straddling two displays)
            s.field.setAllVisible(false)
            for d in displays where py > d.rect.minY && py <= d.rect.maxY {
                s.field.setVisible(true, fromX: d.rect.minX, toX: d.rect.maxX)
            }
            for j in 0..<i {
                let r = windows[j].rect
                if py >= r.minY && py < r.maxY { s.field.setVisible(false, fromX: r.minX, toX: r.maxX) }
            }
            for (k, d) in displays.enumerated()
            where s.rect.maxY >= d.rect.maxY - SurfaceManager.skyBlockBand && s.rect.minY < d.rect.maxY
                && s.rect.maxX > d.rect.minX && s.rect.minX < d.rect.maxX {
                skyBlocked.append((s.rect.minX, s.rect.maxX, k))
            }
        }
        for (k, g) in grounds.enumerated() {
            let py = displays[k].rect.minY + 1
            g.field.setAllVisible(true)
            for s in windows where s.rect.minY <= py && s.rect.maxY > py {
                g.field.setVisible(false, fromX: s.rect.minX, toX: s.rect.maxX)
            }
        }
    }

    /// True if a flake spawned above display `display` at `x` would land straight away on snow nobody can see
    @inline(__always) public func isSkyBlocked(_ x: Double, display: Int = 0) -> Bool {
        for b in skyBlocked where b.display == display && x >= b.minX && x < b.maxX { return true }
        return false
    }

    // MARK: Collision

    /// What a particle hits when it falls from `prevY` to `y` at `x`.
    ///
    /// Order: the Dock (always in front), then window tops front to back, then the ground of display
    /// `display` (-1 = whichever display the particle is over). With `cull`, a particle inside a
    /// window's rectangle is reported as `.behind`. `ignore` names one surface the particle cannot
    /// land on (the one it just came off).
    public func contact(x: Double, prevY: Double, y: Double, area: Double,
                        windows hitWindows: Bool, cull: Bool, ignore: Int, dockGain: Double,
                        display: Int = 0) -> Contact {
        if let d = dock, d.state == .present, d.id != ignore, x >= d.field.minX, x < d.field.maxX,
           let c = d.field.col(at: x) {
            let s = d.field.surface(c)
            if prevY >= s && y < s { return .landed(d.field.deposit(x: x, area: area * dockGain)) }
        }
        if hitWindows || cull {
            for s in windows {
                let minX = s.field.minX
                if x < minX || x >= minX + s.field.width { continue }
                let top = s.field.topY
                if hitWindows, s.id != ignore, prevY >= top - s.field.cornerRadius, y < top + s.field.maxH,
                   let c = s.field.col(at: x), s.field.visible[c] {
                    let surf = s.field.surface(c)
                    if prevY >= surf && y < surf { return .landed(s.field.deposit(x: x, area: area)) }
                }
                if cull && s.rect.contains(x, y) { return .behind }
            }
        }
        var k = display
        if k < 0 {
            for (i, d) in displays.enumerated() where x >= d.rect.minX && x < d.rect.maxX && prevY >= d.rect.minY {
                // Of the displays under this x, the one whose floor is nearest below the particle
                if k < 0 || d.rect.minY > displays[k].rect.minY { k = i }
            }
        }
        if k >= 0, k < grounds.count {
            let g = grounds[k]
            if let c = g.field.col(at: x), y < g.field.surface(c) {
                return .landed(g.field.visible[c] ? g.field.deposit(x: x, area: area) : 0)
            }
        }
        return .none
    }
}
