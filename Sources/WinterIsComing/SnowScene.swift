import Cocoa
import SpriteKit
import WinterCore

// MARK: - Scene

/// One display's view of the shared `SnowModel`. It owns no simulation state: each frame it asks the
/// model to advance and mirrors the part that falls on its display into SpriteKit.
final class SnowScene: SKScene {
    let model: SnowModel
    let displayID: Int
    /// Everything in here is positioned in global coordinates; the node itself is shifted so the
    /// display's corner lands on the scene's origin.
    let world = SKNode()

    private let textures = SnowTextures()
    private var flakeRenderer: FlakeRenderer!
    private var powderRenderer: PowderRenderer!
    private var pileRenderer: PileRenderer!
    private var companionRenderer: CompanionRenderer!
    private var flyoverRenderer: CompanionRenderer!
    private var lightsRenderer: LightsRenderer!
    private var frostRenderer: FrostRenderer!
    private(set) var play: SnowballController!
    private var lastT: TimeInterval = 0

    init(size: CGSize, model: SnowModel, displayID: Int) {
        self.model = model
        self.displayID = displayID
        super.init(size: size)
        backgroundColor = .clear
        addChild(world)
        flakeRenderer = FlakeRenderer(parent: world, textures: textures)
        powderRenderer = PowderRenderer(parent: world, textures: textures)
        pileRenderer = PileRenderer(parent: world)
        companionRenderer = CompanionRenderer(parent: world)
        flyoverRenderer = CompanionRenderer(parent: world)
        lightsRenderer = LightsRenderer(parent: world, glow: textures.glow)
        frostRenderer = FrostRenderer(parent: world)
        play = SnowballController(scene: self)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// This display's rectangle in global coordinates
    var displayRect: Rect {
        model.display(id: displayID)?.rect ?? Rect(x: 0, y: 0, width: Double(size.width), height: Double(size.height))
    }

    // MARK: Per-frame update

    override func update(_ currentTime: TimeInterval) {
        guard !model.manualClock else { return }
        model.advance(now: currentTime)
        let dt = lastT == 0 ? 0 : min(currentTime - lastT, 0.1)
        lastT = currentTime
        render(frameDt: dt)
        play.updateMouseCapture(view?.window)
        // Half the frame rate while the system is short of power or running hot
        let fps = model.constrained ? 30 : 60
        if let view, view.preferredFramesPerSecond != fps { view.preferredFramesPerSecond = fps }
    }

    /// Mirror the model into sprites
    func render(frameDt: Double) {
        guard let d = model.display(id: displayID) else { return }
        let t0 = DispatchTime.now().uptimeNanoseconds
        world.position = CGPoint(x: -d.rect.minX, y: -d.rect.minY)
        let tint = model.lightBackground ? SnowTint.light : SnowTint.dark
        flakeRenderer.tint = tint
        powderRenderer.tint = tint
        pileRenderer.lightBackground = model.lightBackground
        flakeRenderer.sync(d.flakes)
        powderRenderer.sync(model.powder)
        pileRenderer.sync(model.surfaces, display: d.rect)
        companionRenderer.sync(model.companion, preset: model.companionAlpha > 0.01 ? model.cursorPreset : .none,
                               size: model.companionSize, alpha: model.companionAlpha)
        flyoverRenderer.sync(model.flyer, preset: model.flyoverActive ? .sleigh : .none, size: 1.15, alpha: 1)
        // Lights hang just below the menu bar; its height comes from the screen this scene is on
        var topInset = 24.0
        if let screen = view?.window?.screen { topInset = Double(screen.frame.maxY - screen.visibleFrame.maxY) }
        lightsRenderer.sync(model, display: d.rect, topInset: max(topInset, 2))
        frostRenderer.sync(model, display: d.rect)
        play.step(frameDt)
        model.addSyncTime(DispatchTime.now().uptimeNanoseconds - t0)
    }

    // MARK: Mouse (Play mode only; the overlay ignores clicks otherwise)

    private func globalPoint(_ event: NSEvent) -> CGPoint {
        let p = event.location(in: self)
        let r = displayRect
        return CGPoint(x: p.x + r.minX, y: p.y + r.minY)
    }

    override func mouseDown(with event: NSEvent) { play.mouseDown(at: globalPoint(event)) }
    override func mouseDragged(with event: NSEvent) { play.mouseDragged(to: globalPoint(event)) }
    override func mouseUp(with event: NSEvent) { play.mouseUp() }
}
