import Cocoa
import SpriteKit
import WinterCore

/// Lets the very first click reach the scene even though this app is never the active app
final class OverlaySKView: SKView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class OverlayWindow: NSPanel {
    // Stop macOS from pushing the window below the menu bar
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// One transparent, click-through overlay per connected display, kept in step with the display list.
final class OverlayController {
    struct Overlay {
        let window: OverlayWindow
        let view: OverlaySKView
        let scene: SnowScene
    }

    let model: SnowModel
    private(set) var overlays: [Int: Overlay] = [:]
    private(set) var paused = false

    init(model: SnowModel) {
        self.model = model
        syncScreens()
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    static func currentDisplays() -> [DisplayInfo] { NSScreen.screens.map { $0.displayInfo } }

    @objc private func screensChanged() { syncScreens() }

    /// Displays were connected, disconnected, rearranged or changed resolution or scaling
    func syncScreens() {
        let screens = NSScreen.screens
        model.setDisplays(screens.map { $0.displayInfo })

        let alive = Set(screens.map { $0.displayID })
        for (id, o) in overlays where !alive.contains(id) {
            o.window.orderOut(nil)
            overlays[id] = nil
        }
        for screen in screens {
            let id = screen.displayID
            if let o = overlays[id] {
                // Scenes work in points; SpriteKit picks up the display's scale factor by itself
                o.window.setFrame(screen.frame, display: true)
                o.scene.size = screen.frame.size
            } else {
                overlays[id] = makeOverlay(for: screen)
            }
        }
    }

    private func makeOverlay(for screen: NSScreen) -> Overlay {
        // A non-activating panel can take a click (to grab a snowball) without stealing focus from your apps
        let window = OverlayWindow(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                                   backing: .buffered, defer: false)
        window.hidesOnDeactivate = false
        window.becomesKeyOnlyIfNeeded = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true          // clicks pass straight through
        window.level = .floating                  // above normal windows, below the Dock and menu bar
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        let view = OverlaySKView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.allowsTransparency = true
        view.preferredFramesPerSecond = 60
        view.ignoresSiblingOrder = true
        let scene = SnowScene(size: screen.frame.size, model: model, displayID: screen.displayID)
        scene.scaleMode = .resizeFill
        scene.play.enabled = playMode
        view.presentScene(scene)
        view.isPaused = suspended || hidden
        window.contentView = view
        window.setFrame(screen.frame, display: true)
        if !hidden { window.orderFrontRegardless() }
        return Overlay(window: window, view: view, scene: scene)
    }

    // MARK: State shared by every overlay

    var playMode = false {
        didSet { for o in overlays.values { o.scene.play.enabled = playMode } }
    }

    /// Rendering stopped by the system (display asleep, screen locked)
    var suspended = false {
        didSet { for o in overlays.values { o.view.isPaused = suspended || hidden } }
    }

    /// Paused automatically (on battery or in Low Power Mode, if the user asked for that)
    private(set) var autoPaused = false

    /// Paused from the menu: overlays are taken off screen
    func setPaused(_ p: Bool) {
        paused = p
        applyVisibility()
    }

    func setAutoPaused(_ p: Bool) {
        guard p != autoPaused else { return }
        autoPaused = p
        applyVisibility()
    }

    /// True while nothing is drawn and nothing is simulated
    var hidden: Bool { paused || autoPaused }

    private func applyVisibility() {
        for o in overlays.values {
            o.view.isPaused = suspended || hidden
            if hidden { o.window.orderOut(nil) } else { o.window.orderFrontRegardless() }
        }
    }

    func clearAll() {
        model.clearAll()
        for o in overlays.values { o.scene.play.clear() }
    }

    var allClickThrough: Bool { overlays.values.allSatisfy { $0.window.ignoresMouseEvents } }
}
