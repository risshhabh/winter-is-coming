import Cocoa
import SpriteKit
import WinterCore

/// User choices, remembered between launches
enum Settings {
    private static let d = UserDefaults.standard

    static var preset: SnowPreset {
        get { SnowPreset(rawValue: d.string(forKey: "preset") ?? "") ?? .gentle }
        set { d.set(newValue.rawValue, forKey: "preset") }
    }
    static var melting: Bool {
        get { d.bool(forKey: "melting") }
        set { d.set(newValue, forKey: "melting") }
    }
    static var snowInFront: Bool {
        get { d.object(forKey: "snowInFront") == nil ? true : d.bool(forKey: "snowInFront") }
        set { d.set(newValue, forKey: "snowInFront") }
    }
    static var cursorPreset: CursorPreset {
        get { CursorPreset(rawValue: d.string(forKey: "cursorPreset") ?? "") ?? .none }
        set { d.set(newValue.rawValue, forKey: "cursorPreset") }
    }
    static var companionSize: Double {
        get { d.object(forKey: "companionSize") == nil ? 1 : d.double(forKey: "companionSize") }
        set { d.set(newValue, forKey: "companionSize") }
    }
    /// Sleigh bells are off until the user turns them on
    static var bells: Bool {
        get { d.bool(forKey: "bells") }
        set { d.set(newValue, forKey: "bells") }
    }
    static var muted: Bool {
        get { d.bool(forKey: "muted") }
        set { d.set(newValue, forKey: "muted") }
    }
    static var volume: Double {
        get { d.object(forKey: "volume") == nil ? 0.5 : d.double(forKey: "volume") }
        set { d.set(newValue, forKey: "volume") }
    }
    /// How strongly the cursor stirs falling snow: 0 off, 1 normal
    static var cursorStrength: Double {
        get { d.object(forKey: "cursorStrength") == nil ? 1 : d.double(forKey: "cursorStrength") }
        set { d.set(newValue, forKey: "cursorStrength") }
    }
}

// MARK: - Menu bar icon

final class AppDelegate: NSObject, NSApplicationDelegate {
    static let cursorChoices: [(title: String, strength: Double)] = [("Off", 0), ("Subtle", 0.5), ("Normal", 1), ("Strong", 2)]

    var model: SnowModel!
    var overlays: OverlayController!
    var statusItem: NSStatusItem!
    var pauseItem: NSMenuItem!
    var presetItems: [NSMenuItem] = []
    var cursorItems: [NSMenuItem] = []
    static let sizeChoices: [(title: String, size: Double)] = [("Small", 0.75), ("Medium", 1), ("Large", 1.35)]
    var effectItems: [NSMenuItem] = []
    var sizeItems: [NSMenuItem] = []
    var bellsItem: NSMenuItem!
    var muteItem: NSMenuItem!
    let audio = BellAudio()
    /// Smoke test: run for this many seconds, print statistics and quit. No permission prompt.
    var smokeSeconds: Double?
    var smokePreset: CursorPreset?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Window corners are rounder from macOS 26 on. The radius is not available from the system,
        // so this is the standard window's value; the snow line follows it.
        let corner = ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26 ? 16.0 : 10.0
        model = SnowModel(displays: OverlayController.currentDisplays(), source: SystemWindowSource(),
                          dockTracker: DockTracker(prompt: smokeSeconds == nil),
                          preset: Settings.preset, seed: UInt64(Date().timeIntervalSince1970), cornerRadius: corner)
        model.melting = Settings.melting
        model.snowInFront = Settings.snowInFront
        model.cursorStrength = Settings.cursorStrength
        model.cursorPreset = smokePreset ?? Settings.cursorPreset
        model.companionSize = Settings.companionSize
        model.bellAudio = audio
        audio.volume = Settings.volume
        applySound()
        overlays = OverlayController(model: model)

        setupMenu()

        // Stop rendering while the display sleeps or the screen is locked; otherwise SpriteKit
        // logs "no drawables available" because nothing is being shown.
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            ws.addObserver(self, selector: #selector(suspendRendering), name: name, object: nil)
        }
        for name in [NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            ws.addObserver(self, selector: #selector(resumeRendering), name: name, object: nil)
        }

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

    @objc func suspendRendering() { overlays.suspended = true }
    @objc func resumeRendering() { overlays.suspended = false }

    func setupMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "❄︎"
        let menu = NSMenu()

        pauseItem = NSMenuItem(title: "Pause Snow", action: #selector(togglePause), keyEquivalent: "p")
        pauseItem.target = self
        menu.addItem(pauseItem)
        menu.addItem(.separator())

        for preset in SnowPreset.allCases {
            let it = NSMenuItem(title: preset.displayName, action: #selector(setPreset(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = preset.rawValue
            it.state = preset == Settings.preset ? .on : .off
            menu.addItem(it)
            presetItems.append(it)
        }
        menu.addItem(.separator())

        let front = NSMenuItem(title: "Snow in Front of Windows", action: #selector(toggleFront(_:)), keyEquivalent: "")
        front.target = self
        front.state = Settings.snowInFront ? .on : .off
        menu.addItem(front)

        let melt = NSMenuItem(title: "Gradual Melting", action: #selector(toggleMelting(_:)), keyEquivalent: "")
        melt.target = self
        melt.state = Settings.melting ? .on : .off
        menu.addItem(melt)

        let cursor = NSMenuItem(title: "Cursor Stirs Snow", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for (i, choice) in AppDelegate.cursorChoices.enumerated() {
            let it = NSMenuItem(title: choice.title, action: #selector(setCursorStrength(_:)), keyEquivalent: "")
            it.target = self
            it.tag = i
            it.state = choice.strength == Settings.cursorStrength ? .on : .off
            sub.addItem(it)
            cursorItems.append(it)
        }
        cursor.submenu = sub
        menu.addItem(cursor)

        menu.addItem(.separator())
        let effect = NSMenuItem(title: "Cursor Effect", action: nil, keyEquivalent: "")
        let effectMenu = NSMenu()
        for (i, preset) in CursorPreset.allCases.enumerated() {
            let it = NSMenuItem(title: preset.displayName, action: #selector(setCursorPreset(_:)), keyEquivalent: i == 0 ? "0" : "")
            it.target = self
            it.representedObject = preset.rawValue
            it.state = preset == Settings.cursorPreset ? .on : .off
            effectMenu.addItem(it)
            effectItems.append(it)
        }
        effect.submenu = effectMenu
        menu.addItem(effect)

        let size = NSMenuItem(title: "Companion Size", action: nil, keyEquivalent: "")
        let sizeMenu = NSMenu()
        for (i, choice) in AppDelegate.sizeChoices.enumerated() {
            let it = NSMenuItem(title: choice.title, action: #selector(setCompanionSize(_:)), keyEquivalent: "")
            it.target = self
            it.tag = i
            it.state = choice.size == Settings.companionSize ? .on : .off
            sizeMenu.addItem(it)
            sizeItems.append(it)
        }
        size.submenu = sizeMenu
        menu.addItem(size)

        bellsItem = NSMenuItem(title: "Sleigh Bells", action: #selector(toggleBells), keyEquivalent: "")
        bellsItem.target = self
        bellsItem.state = Settings.bells ? .on : .off
        menu.addItem(bellsItem)
        muteItem = NSMenuItem(title: "Mute", action: #selector(toggleMute), keyEquivalent: "m")
        muteItem.target = self
        muteItem.state = Settings.muted ? .on : .off
        menu.addItem(muteItem)
        let volumeItem = NSMenuItem()
        let box = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 28))
        let label = NSTextField(labelWithString: "Volume")
        label.frame = NSRect(x: 20, y: 5, width: 56, height: 18)
        label.font = .menuFont(ofSize: 0)
        let slider = NSSlider(value: Settings.volume, minValue: 0, maxValue: 1, target: self, action: #selector(volumeChanged(_:)))
        slider.frame = NSRect(x: 78, y: 4, width: 126, height: 20)
        box.addSubview(label)
        box.addSubview(slider)
        volumeItem.view = box
        menu.addItem(volumeItem)
        menu.addItem(.separator())

        // Play mode always starts off: snowballs are something you ask for, never a side effect
        let playItem = NSMenuItem(title: "Play Mode (Snowballs)", action: #selector(togglePlay(_:)), keyEquivalent: "")
        playItem.target = self
        menu.addItem(playItem)

        let clear = NSMenuItem(title: "Clear Snow", action: #selector(clearSnow), keyEquivalent: "c")
        clear.target = self
        menu.addItem(clear)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc func togglePause() {
        overlays.setPaused(!overlays.paused)
        pauseItem.title = overlays.paused ? "Resume Snow" : "Pause Snow"
    }

    @objc func setPreset(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let preset = SnowPreset(rawValue: raw) else { return }
        Settings.preset = preset
        model.weather.setPreset(preset)           // eases over a few seconds
        for it in presetItems { it.state = (it === sender) ? .on : .off }
    }

    @objc func toggleFront(_ sender: NSMenuItem) {
        Settings.snowInFront.toggle()
        model.snowInFront = Settings.snowInFront
        sender.state = Settings.snowInFront ? .on : .off
    }

    @objc func toggleMelting(_ sender: NSMenuItem) {
        Settings.melting.toggle()
        model.melting = Settings.melting
        sender.state = Settings.melting ? .on : .off
    }

    @objc func setCursorStrength(_ sender: NSMenuItem) {
        let strength = AppDelegate.cursorChoices[sender.tag].strength
        Settings.cursorStrength = strength
        model.cursorStrength = strength
        for it in cursorItems { it.state = (it === sender) ? .on : .off }
    }

    /// Bells sound only when switched on, not muted, and a cursor effect is active.
    /// Turning any of those off stops the audio engine at once.
    func applySound() { model.soundOn = Settings.bells && !Settings.muted && Settings.cursorPreset != .none }

    @objc func setCursorPreset(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let preset = CursorPreset(rawValue: raw) else { return }
        Settings.cursorPreset = preset
        model.cursorPreset = preset
        applySound()
        for it in effectItems { it.state = (it === sender) ? .on : .off }
    }

    @objc func setCompanionSize(_ sender: NSMenuItem) {
        let size = AppDelegate.sizeChoices[sender.tag].size
        Settings.companionSize = size
        model.companionSize = size
        for it in sizeItems { it.state = (it === sender) ? .on : .off }
    }

    @objc func toggleBells() {
        Settings.bells.toggle()
        bellsItem.state = Settings.bells ? .on : .off
        applySound()
    }

    @objc func toggleMute() {
        Settings.muted.toggle()
        muteItem.state = Settings.muted ? .on : .off
        applySound()
    }

    @objc func volumeChanged(_ sender: NSSlider) {
        Settings.volume = sender.doubleValue
        audio.volume = sender.doubleValue
    }

    @objc func togglePlay(_ sender: NSMenuItem) {
        overlays.playMode.toggle()
        sender.state = overlays.playMode ? .on : .off
    }

    @objc func clearSnow() { overlays.clearAll() }
}
