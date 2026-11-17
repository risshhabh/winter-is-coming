import Cocoa
import WinterCore

/// The Preferences window: plain AppKit controls in tabs, each bound to one field of `AppSettings`.
/// Every change applies immediately and is saved; there is no OK button.
final class PreferencesWindow: NSObject, NSWindowDelegate {
    private unowned let app: AppDelegate
    private var window: NSWindow!
    /// Re-read every control from the settings (after a theme or "Restore Defaults")
    private var refreshers: [() -> Void] = []
    /// Closures behind the controls' target/action
    private var actions: [Action] = []

    private final class Action: NSObject {
        let run: (Any) -> Void
        init(_ run: @escaping (Any) -> Void) { self.run = run }
        @objc func fire(_ sender: Any) { run(sender) }
    }

    init(app: AppDelegate) {
        self.app = app
        super.init()
        build()
    }

    func show() {
        refresh()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func refresh() { for r in refreshers { r() } }

    // MARK: Controls

    private func action(_ run: @escaping (Any) -> Void) -> Action {
        let a = Action(run)
        actions.append(a)
        return a
    }

    private func label(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.alignment = .right
        return l
    }

    private func slider(_ title: String, _ kp: WritableKeyPath<AppSettings, Double>, _ lo: Double, _ hi: Double,
                        low: String, high: String) -> [NSView] {
        let s = NSSlider(value: app.settings[keyPath: kp], minValue: lo, maxValue: hi, target: nil, action: nil)
        let a = action { [unowned self] in self.app.settings[keyPath: kp] = ($0 as! NSSlider).doubleValue }
        s.target = a
        s.action = #selector(Action.fire(_:))
        s.widthAnchor.constraint(equalToConstant: 200).isActive = true
        refreshers.append { [unowned self] in s.doubleValue = self.app.settings[keyPath: kp] }
        let lowL = NSTextField(labelWithString: low), highL = NSTextField(labelWithString: high)
        for l in [lowL, highL] { l.font = .systemFont(ofSize: NSFont.smallSystemFontSize); l.textColor = .secondaryLabelColor }
        let row = NSStackView(views: [lowL, s, highL])
        row.spacing = 6
        return [label(title), row]
    }

    private func toggle(_ title: String, _ kp: WritableKeyPath<AppSettings, Bool>) -> [NSView] {
        let b = NSButton(checkboxWithTitle: title, target: nil, action: nil)
        let a = action { [unowned self] in self.app.settings[keyPath: kp] = ($0 as! NSButton).state == .on }
        b.target = a
        b.action = #selector(Action.fire(_:))
        refreshers.append { [unowned self] in b.state = self.app.settings[keyPath: kp] ? .on : .off }
        return [NSGridCell.emptyContentView, b]
    }

    private func popup<T: Equatable>(_ title: String, _ kp: WritableKeyPath<AppSettings, T>, _ options: [(String, T)]) -> [NSView] {
        let p = NSPopUpButton(frame: .zero, pullsDown: false)
        p.addItems(withTitles: options.map { $0.0 })
        let a = action { [unowned self] in
            let i = ($0 as! NSPopUpButton).indexOfSelectedItem
            if i >= 0 { self.app.settings[keyPath: kp] = options[i].1 }
        }
        p.target = a
        p.action = #selector(Action.fire(_:))
        refreshers.append { [unowned self] in
            let v = self.app.settings[keyPath: kp]
            p.selectItem(at: options.firstIndex { $0.1 == v } ?? -1)
        }
        return [label(title), p]
    }

    private func button(_ title: String, _ run: @escaping () -> Void) -> NSButton {
        let a = action { _ in run() }
        return NSButton(title: title, target: a, action: #selector(Action.fire(_:)))
    }

    private func note(_ text: String) -> [NSView] {
        let l = NSTextField(wrappingLabelWithString: text)
        l.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        l.textColor = .secondaryLabelColor
        l.preferredMaxLayoutWidth = 330
        return [NSGridCell.emptyContentView, l]
    }

    private func tab(_ title: String, _ rows: [[NSView]]) -> NSTabViewItem {
        let grid = NSGridView(views: rows)
        grid.rowSpacing = 9
        grid.columnSpacing = 10
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        grid.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView()
        container.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: container.topAnchor, constant: 18),
            grid.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            grid.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -18),
        ])
        let item = NSTabViewItem(identifier: title)
        item.label = title
        item.view = container
        return item
    }

    // MARK: Layout

    private func build() {
        let tabs = NSTabView()
        tabs.addTabViewItem(tab("Snow", [
            popup("Weather:", \.weather, SnowPreset.allCases.map { ($0.displayName, $0) }),
            slider("Density:", \.density, 0.3, 2, low: "Sparse", high: "Heavy"),
            slider("Flake size:", \.flakeSize, 0.6, 1.6, low: "Fine", high: "Large"),
            slider("Falling speed:", \.fallSpeed, 0.5, 1.8, low: "Drifting", high: "Fast"),
            slider("Wind:", \.wind, 0, 2, low: "Still", high: "Blustery"),
            toggle("Snow piles up on windows, the Dock and the ground", \.accumulation),
            slider("Accumulation speed:", \.accumulationSpeed, 0.25, 3, low: "Slow", high: "Fast"),
            slider("Maximum height:", \.maxHeight, 0.25, 1, low: "Thin", high: "Deep"),
            toggle("Gradual melting", \.melting),
            toggle("Some snow falls in front of windows", \.snowInFront),
            popup("Cursor stirs snow:", \.cursorStir, AppDelegate.cursorChoices),
        ]))
        tabs.addTabViewItem(tab("Cursor", [
            popup("Companion:", \.companion, CursorPreset.allCases.map { ($0.displayName, $0) }),
            slider("Companion size:", \.companionSize, 0.6, 1.6, low: "Small", high: "Large"),
            slider("Animation:", \.animation, 0, 1.5, low: "Calm", high: "Lively"),
            popup("Trail:", \.trail, TrailStyle.allCases.map { ($0.displayName, $0) }),
            slider("Trail intensity:", \.trailIntensity, 0.25, 2, low: "Faint", high: "Rich"),
            note("The real pointer is never replaced: the companion follows beside it and fades while you type."),
        ]))
        tabs.addTabViewItem(tab("Audio", [
            toggle("Sleigh bells when the cursor moves and Santa flies over", \.bells),
            slider("Bell volume:", \.bellVolume, 0, 1, low: "Quiet", high: "Louder"),
            toggle("Wind ambience", \.windAmbience),
            slider("Ambient volume:", \.ambientVolume, 0, 1, low: "Quiet", high: "Louder"),
            toggle("Mute all sound", \.muted),
            note("All sound is synthesized in the app, plays at a low ceiling and stops a few seconds after it goes quiet."),
        ]))
        tabs.addTabViewItem(tab("Decorations", [
            popup("Christmas lights:", \.lights, LightMode.allCases.map { ($0.displayName, $0) }),
            slider("Light brightness:", \.lightBrightness, 0.4, 1.5, low: "Dim", high: "Bright"),
            popup("Light density:", \.lightSpacing, AppDelegate.densityChoices),
            popup("Window frost:", \.frost, AppDelegate.frostChoices),
            popup("Santa flyovers:", \.flyoverGap, AppDelegate.flyoverChoices),
            toggle("Atmospheric events (shooting stars, gusts, …)", \.events),
            toggle("Animated characters (a penguin on the snow)", \.characters),
            [NSGridCell.emptyContentView, NSStackView(views: [
                button("Fly Santa Now") { [unowned self] in self.app.flySantaNow() },
                button("Show an Event") { [unowned self] in self.app.showEventNow() },
            ])],
        ]))
        tabs.addTabViewItem(tab("Performance", [
            popup("Frame rate:", \.frameRate, [("30 fps", 30), ("60 fps", 60)]),
            slider("Particle budget:", \.particleBudget, 0.25, 1, low: "Light", high: "Full"),
            toggle("Battery saver: 30 fps and thinner snow on battery", \.batterySaver),
            toggle("Pause on battery power", \.pauseOnBattery),
            toggle("Pause in Low Power Mode", \.pauseOnLowPower),
            toggle("Follow the system's Reduce Motion setting", \.respectReduceMotion),
            note("Snow also pauses while displays sleep or the screen is locked, and thins out by itself if frames get expensive."),
        ]))
        tabs.addTabViewItem(generalTab())

        // Themes and reset sit above the tabs
        let themes = NSPopUpButton(frame: .zero, pullsDown: true)
        themes.addItem(withTitle: "Apply a Theme")
        for t in Theme.allCases { themes.addItem(withTitle: t.displayName) }
        let themeAction = action { [unowned self] in
            let i = ($0 as! NSPopUpButton).indexOfSelectedItem - 1
            if i >= 0 { self.app.settings = Theme.allCases[i].apply(to: self.app.settings) }
        }
        themes.target = themeAction
        themes.action = #selector(Action.fire(_:))
        let reset = button("Restore Defaults") { [unowned self] in self.app.settings = AppSettings() }
        let top = NSStackView(views: [themes, reset])
        top.spacing = 10

        let root = NSStackView(views: [top, tabs])
        root.orientation = .vertical
        root.alignment = .leading
        root.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 16, right: 16)
        root.spacing = 10
        tabs.widthAnchor.constraint(equalToConstant: 560).isActive = true
        tabs.heightAnchor.constraint(equalToConstant: 470).isActive = true

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 592, height: 540),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "WinterIsComing Preferences"
        window.contentView = root
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        refresh()
    }

    private func generalTab() -> NSTabViewItem {
        let login = NSButton(checkboxWithTitle: "Launch at login", target: nil, action: nil)
        let loginAction = action { [unowned self] in self.app.launchAtLogin = ($0 as! NSButton).state == .on; self.refresh() }
        login.target = loginAction
        login.action = #selector(Action.fire(_:))
        login.isEnabled = AppDelegate.canLaunchAtLogin
        refreshers.append { [unowned self] in login.state = AppDelegate.canLaunchAtLogin && self.app.launchAtLogin ? .on : .off }

        let dockStatus = NSTextField(labelWithString: "")
        let dockButton = button("Allow Dock Snow…") { [unowned self] in self.app.requestDockAccess() }
        refreshers.append { [unowned self] in
            let ok = self.app.dockAccess
            dockStatus.stringValue = ok ? "Snow on the Dock: on" : "Snow on the Dock: needs Accessibility access"
            dockButton.isHidden = ok
        }
        var rows: [[NSView]] = [
            [NSGridCell.emptyContentView, login],
            note(AppDelegate.canLaunchAtLogin ? "Starts quietly in the menu bar when you log in."
                 : "Available when running WinterIsComing.app (build it with Scripts/bundle.sh)."),
            [NSGridCell.emptyContentView, dockStatus],
            [NSGridCell.emptyContentView, dockButton],
            note("Accessibility access is used only to read where the Dock is. Everything else works without it. After granting it, quit and reopen the app."),
        ]
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development build"
        rows.append(note("WinterIsComing \(version). Based on WINTER_IS_COMING by Shi Yike."))
        return tab("General", rows)
    }

    // Keep the refreshed state in sync when the window comes back
    func windowDidBecomeKey(_ notification: Notification) { refresh() }

    /// Renders every tab to `<prefix>-<tab>.png` without showing anything on screen (layout checks)
    func snapshotTabs(prefix: String) {
        guard let root = window.contentView, let tabs = root.subviews.compactMap({ $0 as? NSTabView }).first else { return }
        window.appearance = NSAppearance(named: .aqua)
        for item in tabs.tabViewItems {
            tabs.selectTabViewItem(item)
            root.layoutSubtreeIfNeeded()
            guard let rep = root.bitmapImageRepForCachingDisplay(in: root.bounds) else { continue }
            root.cacheDisplay(in: root.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(prefix)-\(item.label).png"))
        }
    }

    /// Hand focus back to whatever the user was working in
    func windowWillClose(_ notification: Notification) { NSApp.deactivate() }
}
