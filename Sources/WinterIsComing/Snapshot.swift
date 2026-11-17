import Cocoa
import Metal
import SpriteKit
import WinterCore

/// Scripted windows for the snapshot tool, in global coordinates. Window 2 is moved just before the
/// picture is taken (shaken, jerked or dragged slowly), window 3 closes, and window 4 hangs off the
/// left edge of the main display (onto the second display when there is one).
final class ScriptedWindowSource: WindowSource {
    enum Motion: String { case shake, jerk, slow, still }

    var time = 0.0
    var duration = 0.0
    var motion = Motion.shake
    /// How long before the picture the motion starts
    var lead = 0.45

    func onScreenWindows() -> [WindowInfo] {
        let since = time - (duration - lead)          // seconds since the motion began
        var dx = 0.0
        if since > 0 {
            switch motion {
            case .shake: if since < 0.45 { dx = 55 * sin(since * 2 * .pi * 4.5) }
            case .jerk: dx = min(since, 0.25) * 900
            case .slow: dx = since * 220
            case .still: break
            }
        }
        var out = [
            WindowInfo(id: 2, rect: Rect(x: 720 + dx, y: 300, width: 420, height: 260)),
            WindowInfo(id: 1, rect: Rect(x: 150, y: 230, width: 480, height: 330)),
            WindowInfo(id: 4, rect: Rect(x: -160, y: 380, width: 360, height: 240)),
        ]
        if exists(3) { out.append(WindowInfo(id: 3, rect: Rect(x: 330, y: 590, width: 260, height: 110))) }
        return out
    }

    func classify(_ id: Int, elapsed: Double) -> VanishDecision { .drop }

    func exists(_ id: Int) -> Bool { id != 3 || motion == .still || duration - time > lead + 0.35 }
}

/// Runs the real model and scenes headlessly and writes a PNG, so the look of the snow can be checked
/// without watching the live overlay:
///   WinterIsComing --snapshot out.png [--preset storm] [--seconds 240] [--light] [--melt]
///                  [--motion shake|jerk|slow|still] [--lead 1.2] [--displays 2] [--corner 16]
///                  [--cursor sleigh|hat|snowTrail|goldTrail] [--size 1.35] [--rest]
///                  [--trail snow|gold|festive] [--lights warm|multi] [--frost] [--flyover] [--events]
///                  [--characters]
enum Snapshot {
    static func run(_ args: [String]) -> Int32 {
        func value(_ flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        guard let path = value("--snapshot") else { return 2 }
        let preset = SnowPreset(rawValue: value("--preset") ?? "gentle") ?? .gentle
        let seconds = Double(value("--seconds") ?? "") ?? 240
        let light = args.contains("--light")
        let corner = Double(value("--corner") ?? "") ?? 16
        let scale = 2

        var displays = [DisplayInfo(id: 1, rect: Rect(x: 0, y: 0, width: 1280, height: 760))]
        if value("--displays") == "2" {
            // A smaller display to the left of the main one and raised, so both axes of the
            // global-to-local conversion are exercised
            displays.append(DisplayInfo(id: 2, rect: Rect(x: -900, y: 200, width: 900, height: 560)))
        }

        _ = NSApplication.shared
        let source = ScriptedWindowSource()
        source.duration = seconds
        source.motion = args.contains("--still") ? .still : (ScriptedWindowSource.Motion(rawValue: value("--motion") ?? "") ?? .shake)
        source.lead = Double(value("--lead") ?? "") ?? 0.45
        let model = SnowModel(displays: displays, source: source, dockTracker: nil, preset: preset,
                              seed: 20261116, cornerRadius: corner)
        model.manualClock = true
        model.forceLightBackground = light
        model.melting = args.contains("--melt")
        model.setDock(Rect(x: 400, y: 0, width: 480, height: 62))
        if let mode = LightMode(rawValue: value("--lights") ?? "") { model.decor.lights = mode }
        if args.contains("--frost") { model.decor.frost = 1 }
        model.decor.characters = args.contains("--characters")
        model.trail = TrailStyle(rawValue: value("--trail") ?? "") ?? .none
        model.director.eventsEnabled = false
        let showFlyover = args.contains("--flyover"), showEvents = args.contains("--events")
        if let preset = CursorPreset(rawValue: value("--cursor") ?? ""), preset != .none || model.trail != .none {
            // A cursor sweeping left to right in a shallow arc over the last three seconds,
            // or (with --rest) arriving and then sitting still
            model.cursorPreset = preset
            model.companionSize = Double(value("--size") ?? "") ?? 1
            let rest = args.contains("--rest")
            model.cursor.script = { t in
                let u = max(0, min(1, (t - (seconds - 3)) / (rest ? 1.2 : 3)))
                return (330 + 520 * u, 620 + 70 * sin(u * 3.0))
            }
        }

        let steps = Int(seconds * 60)
        for i in 0..<steps {
            source.time = Double(i) / 60
            if showFlyover, i == steps - 240 { model.startFlyover() }
            if showEvents, i == steps - 14 { model.trigger(.shootingStar) }
            if showEvents, i == steps - 30 { model.trigger(.formation) }
            model.advance(by: SnowModel.stepDt)
        }

        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            print("snapshot: no Metal device")
            return 1
        }
        let space = CGColorSpaceCreateDeviceRGB()
        let b = model.surfaces.bounds
        let cw = Int(b.width) * scale, ch = Int(b.height) * scale
        guard let ctx = CGContext(data: nil, width: cw, height: ch, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 1 }
        ctx.setFillColor(CGColor(gray: 0.35, alpha: 1))             // the gap between displays
        ctx.fill(CGRect(x: 0, y: 0, width: cw, height: ch))
        ctx.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        ctx.translateBy(x: -b.minX, y: -b.minY)                     // draw in global coordinates from here on

        // A stand-in desktop underneath, so the overlay is judged against windows and wallpaper
        ctx.saveGState()
        ctx.clip(to: displays.map { CGRect(x: $0.rect.minX, y: $0.rect.minY, width: $0.rect.width, height: $0.rect.height) })
        let sky = light
            ? [CGColor(red: 0.80, green: 0.86, blue: 0.93, alpha: 1), CGColor(red: 0.93, green: 0.95, blue: 0.97, alpha: 1)]
            : [CGColor(red: 0.05, green: 0.08, blue: 0.16, alpha: 1), CGColor(red: 0.16, green: 0.22, blue: 0.34, alpha: 1)]
        let grad = CGGradient(colorsSpace: space, colors: sky as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: b.maxY), end: CGPoint(x: 0, y: b.minY), options: [])
        let fills: [Int: CGColor] = [
            1: light ? CGColor(gray: 1, alpha: 1) : CGColor(gray: 0.13, alpha: 1),
            2: CGColor(gray: 0.98, alpha: 1),
            3: CGColor(gray: 0.45, alpha: 1),
            4: CGColor(red: 0.20, green: 0.24, blue: 0.30, alpha: 1),
        ]
        for w in model.surfaces.windows.reversed() {
            let r = CGRect(x: w.rect.minX, y: w.rect.minY, width: w.rect.width, height: w.rect.height)
            ctx.setFillColor(fills[w.id] ?? CGColor(gray: 0.5, alpha: 1))
            ctx.addPath(CGPath(roundedRect: r, cornerWidth: corner, cornerHeight: corner, transform: nil))
            ctx.fillPath()
        }
        ctx.setFillColor(CGColor(gray: light ? 0.75 : 0.3, alpha: 0.8))
        ctx.addPath(CGPath(roundedRect: CGRect(x: 400, y: 4, width: 480, height: 58), cornerWidth: 16, cornerHeight: 16, transform: nil))
        ctx.fillPath()
        ctx.restoreGState()

        // Each display's scene, rendered offscreen and placed where that display sits
        for d in displays {
            let size = CGSize(width: d.rect.width, height: d.rect.height)
            let scene = SnowScene(size: size, model: model, displayID: d.id)
            scene.render(frameDt: 0)
            let pw = Int(size.width) * scale, ph = Int(size.height) * scale
            let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: pw, height: ph, mipmapped: false)
            desc.usage = [.renderTarget, .shaderRead]
            guard let target = device.makeTexture(descriptor: desc) else { return 1 }
            let renderer = SKRenderer(device: device)
            renderer.scene = scene
            renderer.ignoresSiblingOrder = true
            // Render twice: the first pass uploads textures and compiles the pile shader
            for _ in 0..<2 {
                let pass = MTLRenderPassDescriptor()
                pass.colorAttachments[0].texture = target
                pass.colorAttachments[0].loadAction = .clear
                pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
                pass.colorAttachments[0].storeAction = .store
                guard let cb = queue.makeCommandBuffer() else { return 1 }
                renderer.update(atTime: 0)
                renderer.render(withViewport: CGRect(x: 0, y: 0, width: pw, height: ph), commandBuffer: cb, renderPassDescriptor: pass)
                cb.commit()
                cb.waitUntilCompleted()
            }
            var pixels = [UInt8](repeating: 0, count: pw * ph * 4)
            target.getBytes(&pixels, bytesPerRow: pw * 4, from: MTLRegionMake2D(0, 0, pw, ph), mipmapLevel: 0)
            let bgra = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
            guard let overlay = pixels.withUnsafeMutableBytes({ buf -> CGImage? in
                CGContext(data: buf.baseAddress, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: pw * 4,
                          space: space, bitmapInfo: bgra)?.makeImage()
            }) else { return 1 }
            ctx.draw(overlay, in: CGRect(x: d.rect.minX, y: d.rect.minY, width: d.rect.width, height: d.rect.height))
        }

        guard let image = ctx.makeImage(),
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return 1 }
        do {
            try data.write(to: URL(fileURLWithPath: path))
        } catch {
            print("snapshot: \(error.localizedDescription)")
            return 1
        }
        print(String(format: "snapshot: %@ after %.0f s of %@, snow %.0f px²", path, seconds, preset.displayName,
                     model.surfaces.totalArea))
        print("snapshot: " + model.performanceReport())
        return 0
    }
}
