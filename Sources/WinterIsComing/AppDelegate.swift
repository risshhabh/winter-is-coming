import Cocoa
import ServiceManagement
import WinterCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static let cursorChoices: [(String, Double)] = [("Off", 0), ("Subtle", 0.5), ("Normal", 1), ("Strong", 2)]
    static let sizeChoices: [(String, Double)] = [("Small", 0.75), ("Medium", 1), ("Large", 1.35)]
    static let densityChoices: [(String, Double)] = [("Sparse", 38), ("Normal", 26), ("Dense", 18)]
    static let frostChoices: [(String, Double)] = [("Off", 0), ("Light", 0.6), ("Heavy", 1)]
    static let flyoverChoices: [(String, Double)] = [("Off", 0), ("Rare (about hourly)", 3600),
                                                     ("Sometimes (about every 20 min)", 1200), ("Often (about every 5 min)", 300)]

    var model: SnowModel!
    var overlays: OverlayController!
    var statusItem: NSStatusItem!
    let audio = BellAudio()
    private var preferences: PreferencesWindow?
    private var dockTracker: DockTracker!
    private var environmentTimer: Timer?
    /// Why rendering is stopped by the system right now (display asleep, screen locked, user switched)
    private var suspendReasons = Set<String>()
    private var eventCursor = 0

    /// Smoke test: run for this many seconds, print statistics and quit. No permission prompt.
    var smokeSeconds: Double?
    var smokePreset: CursorPreset?
    /// Settings live here in memory while running (smoke tests never touch the stored ones)
    private var defaults = UserDefaults.standard

    /// Every change is saved at once and pushed into the running app
    var settings = AppSettings() {
        didSet {
            settings = settings.clamped()
            if smokeSeconds == nil { settings.save(to: defaults) }
            apply()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        settings = smokeSeconds == nil ? Self.loadSettings(defaults) : AppSettings()
        if let p = smokePreset { settings.companion = p }

        // Window corners are rounder from macOS 26 on. The radius is not available from the system,
        // so this is the standard window's value; the snow line follows it.
        let corner = ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26 ? 16.0 : 10.0
        // Never ask for Accessibility at launch: Dock snow is optional and asked for from Preferences
        dockTracker = DockTracker(prompt: false)
        model = SnowModel(displays: OverlayController.currentDisplays(), source: SystemWindowSource(),
                          dockTracker: dockTracker, preset: settings.weather,
                          seed: UInt64(Date().timeIntervalSince1970), cornerRadius: corner)
        model.bellAudio = audio
        overlays = OverlayController(model: model)
        apply()
        setupMenu()

        // Stop rendering and sound while nobody can see it
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self, selector: #selector(displaysSlept), name: NSWorkspace.screensDidSleepNotification, object: nil)
        ws.addObserver(self, selector: #selector(displaysWoke), name: NSWorkspace.screensDidWakeNotification, object: nil)
        ws.addObserver(self, selector: #selector(sessionResigned), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        ws.addObserver(self, selector: #selector(sessionActivated), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(self, selector: #selector(screenLocked), name: .init("com.apple.screenIsLocked"), object: nil)
        dnc.addObserver(self, selector: #selector(screenUnlocked), name: .init("com.apple.screenIsUnlocked"), object: nil)

        // Automatic pausing (battery, Low Power Mode) is checked every few seconds, also while paused
        environmentTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.checkAutoPause() }
        environmentTimer?.tolerance = 2
        checkAutoPause()

        if let seconds = smokeSeconds {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [self] in
                print("smoke: " + model.performanceReport())
                print(String(format: "smoke: %.1f model frames/s, %d windows tracked, snow %.0f px², click-through %@",
                             Double(model.stats.frames) / seconds, model.surfaces.windows.count, model.surfaces.totalArea,
                             overlays.allClickThrough ? "yes" : "NO"))
                NSApp.terminate(nil)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        environmentTimer?.invalidate()
        audio.stop()
        if smokeSeconds == nil { settings.save(to: defaults) }
    }

    /// Stored settings, or the ones from the previous version's separate keys on first launch after updating
    static func loadSettings(_ d: UserDefaults) -> AppSettings {
        if d.data(forKey: AppSettings.defaultsKey) != nil { return AppSettings.load(from: d) }
        var s = AppSettings()
        guard d.object(forKey: "preset") != nil || d.object(forKey: "cursorPreset") != nil else { return s }
        func num(_ k: String, _ f: Double) -> Double { d.object(forKey: k) == nil ? f : d.double(forKey: k) }
        s.weather = SnowPreset(rawValue: d.string(forKey: "preset") ?? "") ?? .gentle
        s.melting = d.bool(forKey: "melting")
        s.snowInFront = d.object(forKey: "snowInFront") == nil || d.bool(forKey: "snowInFront")
        s.cursorStir = num("cursorStrength", 1)
        switch d.string(forKey: "cursorPreset") ?? "" {
        case "sleigh": s.companion = .sleigh; s.trail = .festive
        case "hat": s.companion = .hat
        case "snowTrail": s.trail = .snow
        case "goldTrail": s.trail = .gold
        default: break
        }
        s.companionSize = num("companionSize", 1)
        s.bells = d.bool(forKey: "bells")
        s.muted = d.bool(forKey: "muted")
        s.bellVolume = num("volume", 0.5)
        s.lights = LightMode(rawValue: d.string(forKey: "lights") ?? "") ?? .off
        s.lightBrightness = num("lightBrightness", 1)
        s.lightSpacing = num("lightSpacing", 26)
        s.frost = num("frost", 0)
        s.flyoverGap = num("flyoverGap", 0)
        s.events = d.bool(forKey: "events")
        return s.clamped()
    }

    /// Push every setting into the running app
    func apply() {
        guard let model else { return }
        let s = settings
        if model.weather.preset != s.weather { model.weather.setPreset(s.weather) }   // eases over a few seconds
        var t = WeatherTuning()
        t.density = s.density
        t.flakeSize = s.flakeSize
        t.fallSpeed = s.fallSpeed
        t.wind = s.wind
        t.accumulation = s.accumulation ? s.accumulationSpeed : 0
        model.weather.tuning = t
        model.surfaces.heightScale = s.maxHeight
        model.melting = s.melting
        model.snowInFront = s.snowInFront
        model.cursorStrength = s.cursorStir

        model.cursorPreset = s.companion
        model.companionSize = s.companionSize
        model.animation = s.animation
        model.trail = s.trail
        model.trailIntensity = s.trailIntensity

        // Mute and switching sound off stop the engine at once
        model.bellsOn = s.bells && !s.muted
        model.ambienceOn = s.windAmbience && !s.muted
        audio.bellVolume = s.bellVolume
        audio.ambientVolume = s.ambientVolume
        if !model.bellsOn && !model.ambienceOn { audio.stop() }

        model.decor.lights = s.lights
        model.decor.lightBrightness = s.lightBrightness
        model.decor.lightSpacing = s.lightSpacing
        model.decor.frost = s.frost
        model.decor.characters = s.characters
        model.director.flyoverGap = s.flyoverGap
        model.director.eventsEnabled = s.events

        model.frameRate = s.frameRate
        model.particleBudget = s.particleBudget
        model.batterySaver = s.batterySaver
        model.respectReduceMotion = s.respectReduceMotion
        checkAutoPause()
        preferences?.refresh()
    }

    private func checkAutoPause() {
        guard let overlays else { return }
        let pause = (settings.pauseOnBattery && Power.onBattery) || (settings.pauseOnLowPower && Power.lowPower)
        if pause != overlays.autoPaused {
            overlays.setAutoPaused(pause)
            if pause { audio.stop() }
        }
    }

    // MARK: System events

    private func suspend(_ reason: String) {
        suspendReasons.insert(reason)
        overlays.suspended = true
        audio.stop()
    }

    private func resume(_ reason: String) {
        suspendReasons.remove(reason)
        if suspendReasons.isEmpty { overlays.suspended = false }
    }

    @objc func displaysSlept() { suspend("sleep") }
    @objc func displaysWoke() { resume("sleep") }
    @objc func sessionResigned() { suspend("session") }
    @objc func sessionActivated() { resume("session") }
    @objc func screenLocked() { suspend("lock") }
    @objc func screenUnlocked() { resume("lock") }

    // MARK: Launch at login

    /// Only an app bundle can be registered; running from the build folder it is unavailable
    static var canLaunchAtLogin: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                let alert = NSAlert()
                alert.messageText = "Could not change Launch at Login"
                alert.informativeText = error.localizedDescription
                    + "\n\nMove WinterIsComing.app to the Applications folder and try again, or check System Settings → General → Login Items."
                alert.runModal()
            }
        }
    }

    // MARK: Accessibility (Dock snow only)

    var dockAccess: Bool { AXIsProcessTrusted() }

    func requestDockAccess() {
        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    // MARK: Menu

    func setupMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let image = NSImage(systemSymbolName: "snowflake", accessibilityDescription: "WinterIsComing") {
            image.isTemplate = true
            statusItem.button?.image = image
        } else {
            statusItem.button?.title = "❄︎"
        }
        let menu = NSMenu()
        menu.delegate = self            // rebuilt each time it opens, so it always shows current settings
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        func item(_ title: String, _ action: Selector?, key: String = "", on: Bool = false, tag: Int = 0,
                  object: Any? = nil) -> NSMenuItem {
            let it = NSMenuItem(title: title, action: action, keyEquivalent: key)
            it.target = self
            it.state = on ? .on : .off
            it.tag = tag
            it.representedObject = object
            return it
        }
        func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
            let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let sub = NSMenu()
            for i in items { sub.addItem(i) }
            parent.submenu = sub
            return parent
        }
        let s = settings

        menu.addItem(item(overlays.paused ? "Resume Snow" : "Pause Snow", #selector(togglePause), key: "p"))
        if overlays.autoPaused {
            let note = NSMenuItem(title: "Paused automatically (power settings)", action: nil, keyEquivalent: "")
            note.isEnabled = false
            menu.addItem(note)
        }
        menu.addItem(.separator())
        menu.addItem(submenu("Theme", Theme.allCases.map { item($0.displayName, #selector(applyTheme(_:)), object: $0.rawValue) }))
        for preset in SnowPreset.allCases {
            menu.addItem(item(preset.displayName, #selector(setWeather(_:)), on: preset == s.weather, object: preset.rawValue))
        }
        menu.addItem(.separator())
        menu.addItem(submenu("Cursor Effect", CursorPreset.allCases.map {
            item($0.displayName, #selector(setCompanion(_:)), on: $0 == s.companion, object: $0.rawValue)
        }))
        menu.addItem(submenu("Cursor Trail", TrailStyle.allCases.map {
            item($0.displayName, #selector(setTrail(_:)), on: $0 == s.trail, object: $0.rawValue)
        }))
        menu.addItem(submenu("Christmas Lights", LightMode.allCases.map {
            item($0.displayName, #selector(setLights(_:)), on: $0 == s.lights, object: $0.rawValue)
        }))
        menu.addItem(item("Sleigh Bells", #selector(toggleBells), on: s.bells))
        menu.addItem(item("Mute All Sound", #selector(toggleMute), key: "m", on: s.muted))
        menu.addItem(.separator())
        menu.addItem(item("Fly Santa Now", #selector(flySantaNow)))
        menu.addItem(item("Show an Event Now", #selector(showEventNow)))
        menu.addItem(item("Play Mode (Snowballs)", #selector(togglePlay), on: overlays.playMode))
        menu.addItem(item("Clear Snow", #selector(clearSnow), key: "c"))
        menu.addItem(.separator())
        menu.addItem(item("Preferences…", #selector(showPreferences), key: ","))
        menu.addItem(NSMenuItem(title: "Quit WinterIsComing", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc func togglePause() {
        overlays.setPaused(!overlays.paused)
        // Nothing steps while paused, so sound would otherwise hold its last level
        if overlays.paused { audio.stop() }
    }

    @objc func applyTheme(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let theme = Theme(rawValue: raw) else { return }
        settings = theme.apply(to: settings)
    }

    @objc func setWeather(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let p = SnowPreset(rawValue: raw) else { return }
        settings.weather = p
    }

    @objc func setCompanion(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let p = CursorPreset(rawValue: raw) else { return }
        settings.companion = p
    }

    @objc func setTrail(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let t = TrailStyle(rawValue: raw) else { return }
        settings.trail = t
    }

    @objc func setLights(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let m = LightMode(rawValue: raw) else { return }
        settings.lights = m
    }

    @objc func toggleBells() { settings.bells.toggle() }
    @objc func toggleMute() { settings.muted.toggle() }
    @objc func flySantaNow() { model.startFlyover() }

    /// Cycles through the atmospheric events, for seeing how each looks
    @objc func showEventNow() {
        model.trigger(AtmosEvent.allCases[eventCursor % AtmosEvent.allCases.count])
        eventCursor += 1
    }

    @objc func togglePlay() { overlays.playMode.toggle() }
    @objc func clearSnow() { overlays.clearAll() }

    @objc func showPreferences() {
        if preferences == nil { preferences = PreferencesWindow(app: self) }
        preferences?.show()
    }
}
