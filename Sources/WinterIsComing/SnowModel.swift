import Cocoa
import WinterCore

/// The one shared winter: weather, wind, every snow surface, loose powder, and a flake system per
/// display, all in global coordinates. Each display's scene only draws its part of it.
final class SnowModel {
    static let stepDt = 1.0 / 60.0
    static let meltRate = 0.03          // px of pile height per second when melting is on

    final class DisplayState {
        let id: Int
        var rect: Rect
        var flakes: FlakeSystem
        var env: FlakeEnvironment

        init(id: Int, rect: Rect, seed: UInt64) {
            self.id = id
            self.rect = rect
            // Budget: bigger displays get more flakes, up to a fixed ceiling
            let area = rect.width * rect.height
            flakes = FlakeSystem(capacity: min(2600, 300 + Int(area / WeatherParams.referenceArea * 1000)), seed: seed)
            env = FlakeEnvironment(width: rect.width, height: rect.height)
            env.minX = rect.minX
            env.minY = rect.minY
        }
    }

    /// Where the time goes, for the performance report
    struct Stats {
        var steps = 0, polls = 0, frames = 0
        var stepNs: UInt64 = 0, pollNs: UInt64 = 0, syncNs: UInt64 = 0
        var worstStepNs: UInt64 = 0, worstPollNs: UInt64 = 0
    }

    let surfaces: SurfaceManager
    var wind: WindField
    var weather: Weather
    var powder: PowderSystem
    private(set) var displays: [DisplayState] = []
    private(set) var time = 0.0
    private(set) var stats = Stats()
    private(set) var governor = QualityGovernor()

    // Festive cursor effects
    let cursor = CursorTracker()
    var cursorPreset = CursorPreset.none { didSet { if cursorPreset != oldValue { presetChanged() } } }
    /// 0.75 small, 1 medium, 1.35 large
    var companionSize = 1.0
    private(set) var companion = CursorCompanion()
    private(set) var companionAlpha = 0.0
    private var trailDebt = 0.0
    private var trailRNG = SeededRNG(seed: 0x7A11)
    /// Sleigh bells: the sequencer decides, the audio object plays. Both idle unless `soundOn`.
    var bellAudio: BellAudio?
    var soundOn = false { didSet { if !soundOn { silence() } } }
    private var bells = BellSequencer(variants: BellAudio.variants, seed: 0xBE11)

    var melting = false
    var snowInFront = true
    /// 0 = the cursor leaves the snow alone, 1 = normal, 2 = strong
    var cursorStrength = 1.0
    /// True when something other than the display link drives time (snapshot tool)
    var manualClock = false
    /// Overrides the system appearance (snapshot tool); nil follows the system
    var forceLightBackground: Bool?
    private(set) var lightBackground = false
    /// Low Power Mode or thermal pressure: render at 30 fps with thinner snow
    private(set) var constrained = false

    private let source: WindowSource
    private let dockTracker: DockTracker?
    private let seed: UInt64
    private var lastNow: TimeInterval = 0
    private var acc = 0.0
    private var pollAcc = 1.0
    private var dockAcc = 1.0
    private var settleAcc = 0.0
    private var slowAcc = 10.0
    private var pruneAcc = 0.0
    private var lastLayoutChange = 0.0
    private var windPhase = 0
    private var pendingSyncNs: UInt64 = 0
    private var reduceMotion = false

    /// `cornerRadius`: radius of window corners, which the snow line follows
    init(displays list: [DisplayInfo], source: WindowSource, dockTracker: DockTracker?, preset: SnowPreset, seed: UInt64,
         cornerRadius: Double) {
        self.source = source
        self.dockTracker = dockTracker
        self.seed = seed
        surfaces = SurfaceManager(displays: list, seed: seed)
        surfaces.cornerRadius = cornerRadius
        wind = WindField(width: 10, height: 10, seed: seed ^ 0x1)
        weather = Weather(preset: preset, seed: seed ^ 0x2)
        powder = PowderSystem(capacity: 2400, seed: seed ^ 0x4)
        setDisplays(list)
        pollWindows(dt: SnowModel.stepDt)
        wind.update(time: 0, dt: 0, params: weather.wind)
        for d in displays { d.flakes.populate(env: d.env, weather: weather.effective, surfaces: surfaces) }
    }

    func display(id: Int) -> DisplayState? { displays.first { $0.id == id } }

    /// Displays were connected, disconnected, resized or rearranged
    func setDisplays(_ list: [DisplayInfo]) {
        surfaces.setDisplays(list)
        var next: [DisplayState] = []
        for (k, info) in list.enumerated() {
            let state: DisplayState
            if let old = displays.first(where: { $0.id == info.id && $0.rect == info.rect }) {
                state = old
            } else {
                // New, moved or resized: its flakes are in the wrong place, so start that sky afresh
                state = DisplayState(id: info.id, rect: info.rect, seed: seed ^ (UInt64(truncatingIfNeeded: info.id) &* 0x51ED))
                if time > 0 { state.flakes.populate(env: state.env, weather: weather.effective, surfaces: surfaces) }
            }
            state.env.display = k
            next.append(state)
        }
        displays = next
        let b = surfaces.bounds
        wind.resize(minX: b.minX, minY: b.minY, width: b.width, height: b.height)
        wind.update(time: time, dt: 0, params: weather.wind)
        lastLayoutChange = time
    }

    func clearAll() {
        surfaces.clearAll()
        powder.removeAll()
    }

    // MARK: Time

    /// Called by every display's scene each frame; whichever comes first does the work.
    func advance(now: TimeInterval) {
        if lastNow == 0 { lastNow = now }
        let dt = min(now - lastNow, 0.1)
        guard dt > 0 else { return }
        lastNow = now
        advance(by: dt)
    }

    /// Advance by wall-clock `dt` using fixed simulation steps. The simulation behaves the same at any
    /// frame rate; after a long stall it drops time, not accuracy.
    func advance(by dt: Double) {
        acc += dt
        var steps = 0
        var spent: UInt64 = 0
        while acc >= SnowModel.stepDt - 1e-9 && steps < 4 {
            let t0 = DispatchTime.now().uptimeNanoseconds
            step(SnowModel.stepDt)
            let ns = DispatchTime.now().uptimeNanoseconds - t0
            spent += ns
            stats.stepNs += ns
            stats.worstStepNs = max(stats.worstStepNs, ns)
            stats.steps += 1
            acc -= SnowModel.stepDt
            steps += 1
        }
        if steps == 4 { acc = 0 }
        guard steps > 0 else { return }
        stats.frames += 1
        governor.report(frameCostMs: Double(spent + pendingSyncNs) / 1e6, dt: Double(steps) * SnowModel.stepDt,
                        constrained: constrained)
        pendingSyncNs = 0
    }

    /// Scenes report how long mirroring into sprites took, so adaptive quality sees the whole frame
    func addSyncTime(_ ns: UInt64) {
        pendingSyncNs += ns
        stats.syncNs += ns
    }

    private func step(_ dt: Double) {
        time += dt

        // Window tracking is the one expensive system call here, so its rate follows what is going on:
        // every frame while something is being dragged, 30 Hz for a second after any change, 10 Hz at rest.
        pollAcc += dt
        let dragging = !manualClock && NSEvent.pressedMouseButtons != 0
        let interval = manualClock || dragging ? 1.0 / 60 : (time - lastLayoutChange < 1 ? 1.0 / 30 : 1.0 / 10)
        if pollAcc >= interval - 1e-9 {
            let t0 = DispatchTime.now().uptimeNanoseconds
            pollWindows(dt: pollAcc)
            pollAcc = 0
            let ns = DispatchTime.now().uptimeNanoseconds - t0
            stats.pollNs += ns
            stats.worstPollNs = max(stats.worstPollNs, ns)
            stats.polls += 1
        }

        slowAcc += dt
        if slowAcc >= 2 {
            slowAcc = 0
            updateEnvironment()
        }

        updateCursor(dt)
        weather.step(dt: dt)
        let w = weather.effective
        // The wind changes over seconds; refreshing its grid 20 times a second is plenty
        windPhase += 1
        if windPhase >= 3 {
            wind.update(time: time, dt: dt * Double(windPhase), params: weather.wind)
            windPhase = 0
        }
        for d in displays {
            d.env.densityScale = governor.scale
            d.env.foregroundFraction = snowInFront ? 0.25 : 0
            d.flakes.step(dt: dt, env: d.env, wind: wind, surfaces: surfaces, weather: w)
        }
        powder.step(dt: dt, time: time, wind: wind, surfaces: surfaces)

        settleAcc += dt
        if settleAcc >= 1.0 / 15 {
            surfaces.settle(dt: settleAcc, meltRate: melting ? SnowModel.meltRate : 0)
            settleAcc = 0
        }
    }

    private func updateCursor(_ dt: Double) {
        // Global AppKit coordinates, the same space the whole model lives in
        cursor.update(dt: dt, time: time)
        let active = (!manualClock || cursor.script != nil) && !reduceMotion && cursorStrength > 0
        for d in displays {
            d.env.cursorActive = active
            d.env.cursorStrength = cursorStrength
            d.env.cursorX = cursor.x
            d.env.cursorY = cursor.y
            d.env.cursorVX = cursor.vx
            d.env.cursorVY = cursor.vy
        }
        updateFestive(dt)
    }

    // MARK: Festive cursor

    private func presetChanged() {
        companion = CursorCompanion()
        companionAlpha = 0
        trailDebt = 0
        if cursorPreset == .none { silence() }
    }

    private func silence() {
        bells.reset()
        bellAudio?.stop()
    }

    private func updateFestive(_ dt: Double) {
        let preset = reduceMotion ? CursorPreset.none : cursorPreset
        guard preset != .none else {
            companionAlpha = 0
            return
        }
        var emitX = cursor.x, emitY = cursor.y, emitVX = cursor.vx, emitVY = cursor.vy
        if preset.hasCompanion {
            let o = CompanionRenderer.offset(preset, size: companionSize)
            companion.update(dt: dt, cursorX: cursor.x, cursorY: cursor.y, offsetX: o.x, offsetY: o.y, stiffness: o.stiffness)
            // Step back while the user is typing, so it never sits over the text being written
            companionAlpha += ((cursor.typing ? 0.2 : 1) - companionAlpha) * min(1, dt / 0.25)
            // The trail leaves from the back of the sleigh
            let s = CompanionRenderer.baseScale * companionSize
            emitX = companion.x - companion.facing * 44 * s
            emitY = companion.y - 4 * s
            emitVX = companion.vx
            emitVY = companion.vy
        }
        if preset.hasTrail {
            // Emission follows speed and is capped low: a slow cursor leaves almost nothing behind
            let v = hypot(emitVX, emitVY)
            trailDebt += v < 50 ? 0 : min(preset == .sleigh ? 26 : 34, v / 28) * dt
            while trailDebt >= 1 {
                trailDebt -= 1
                let r = trailRNG.unit()
                let kind: UInt8
                switch preset {
                case .snowTrail: kind = PowderSystem.trailFlakeKind
                case .goldTrail: kind = r < 0.85 ? PowderSystem.sparkleKind : PowderSystem.glowKind
                default: kind = r < 0.5 ? PowderSystem.sparkleKind : (r < 0.9 ? PowderSystem.trailFlakeKind : PowderSystem.glowKind)
                }
                powder.emitTrail(kind: kind, x: emitX + trailRNG.range(-5, 5), y: emitY + trailRNG.range(-5, 5),
                                 vx: emitVX * 0.12 + trailRNG.range(-22, 22), vy: emitVY * 0.12 + trailRNG.range(-22, 22))
            }
        }
        if soundOn, let audio = bellAudio {
            let b = surfaces.bounds
            let pan = b.width > 0 ? (cursor.x - b.minX) / b.width * 2 - 1 : 0
            let event = bells.step(dt: dt, speed: cursor.typing ? 0 : cursor.speed, pan: pan)
            audio.update(dt: dt, shimmerGain: bells.shimmerGain, event: event)
        }
    }

    /// Follow light/dark appearance, Reduce Motion, Low Power Mode and thermal state
    private func updateEnvironment() {
        if let forced = forceLightBackground {
            lightBackground = forced
        } else {
            lightBackground = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) != .darkAqua
        }
        guard !manualClock else { return }
        reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        weather.calm = reduceMotion
        let info = ProcessInfo.processInfo
        constrained = info.isLowPowerModeEnabled || info.thermalState == .serious || info.thermalState == .critical
    }

    private func pollWindows(dt: Double) {
        let layout = surfaces.layoutVersion
        surfaces.update(windows: source.onScreenWindows(), dt: dt, time: time, powder: &powder) { [source] id, elapsed in
            source.classify(id, elapsed: elapsed)
        }
        if surfaces.layoutVersion != layout || !surfaces.limbo.isEmpty { lastLayoutChange = time }

        // The Dock rarely changes; checking twice a second is enough
        dockAcc += dt
        if dockAcc >= 0.5, let tracker = dockTracker {
            dockAcc = 0
            surfaces.setDock(rect: tracker.snowRect(displays: surfaces.displays), powder: &powder, time: time)
        }
        pruneAcc += dt
        if pruneAcc >= 5 {
            pruneAcc = 0
            surfaces.pruneHidden { [source] id in source.exists(id) }
        }
    }

    /// Scripted Dock for the snapshot tool
    func setDock(_ rect: Rect?) { surfaces.setDock(rect: rect, powder: &powder, time: time) }

    /// One line per system: average and worst time
    func performanceReport() -> String {
        func ms(_ ns: UInt64, _ n: Int) -> Double { n > 0 ? Double(ns) / Double(n) / 1e6 : 0 }
        var flakes = 0
        for d in displays { flakes += d.flakes.count }
        return String(format: "step %.3f ms avg (worst %.2f), window poll %.3f ms avg (worst %.2f) x %d of which %d skipped unchanged, sprite sync %.3f ms per frame, quality %.2f, %d flakes on %d display(s), %d powder",
                      ms(stats.stepNs - stats.pollNs, stats.steps), Double(stats.worstStepNs) / 1e6,
                      ms(stats.pollNs, stats.polls), Double(stats.worstPollNs) / 1e6, stats.polls, surfaces.skippedUpdates,
                      ms(stats.syncNs, stats.frames), governor.scale, flakes, displays.count, powder.count)
    }
}
