import Cocoa
import WinterCore

/// Where the model learns about other apps' windows. The real source asks the window server; the
/// snapshot tool supplies a scripted one.
protocol WindowSource: AnyObject {
    /// Normal windows currently on screen, front to back, in global coordinates
    /// (origin bottom-left of the primary display, y up)
    func onScreenWindows() -> [WindowInfo]
    /// A window left the screen `elapsed` seconds ago: what should happen to its snow?
    func classify(_ id: Int, elapsed: Double) -> VanishDecision
    /// Does this window still exist anywhere (another Space, minimized)?
    func exists(_ id: Int) -> Bool
}

/// Height of the display that carries the global origin; used to flip between the window server's
/// top-left coordinates and AppKit's bottom-left ones.
func primaryDisplayHeight() -> Double { Double(CGDisplayBounds(CGMainDisplayID()).height) }

final class SystemWindowSource: WindowSource {
    /// How long a vanished window's snow is held while waiting to learn why it vanished
    static let decisionWindow = 0.6

    private let myPID = getpid()
    private var lastSpaceChange = -100.0

    init() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(spaceChanged), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
    }

    @objc private func spaceChanged() { lastSpaceChange = CACurrentMediaTime() }

    // Read all window frames (the window server's origin is top-left, ours is bottom-left, so flip y)
    func onScreenWindows() -> [WindowInfo] {
        var out: [WindowInfo] = []
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return out }
        let H = primaryDisplayHeight()
        for w in info {
            guard let layerN = w[kCGWindowLayer as String] as? NSNumber, layerN.intValue == 0,
                  let pidN = w[kCGWindowOwnerPID as String] as? NSNumber, pidN.int32Value != myPID,
                  let numN = w[kCGWindowNumber as String] as? NSNumber,
                  let bd = w[kCGWindowBounds as String] as? NSDictionary,
                  let b = CGRect(dictionaryRepresentation: bd as CFDictionary) else { continue }
            let alpha = (w[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            if alpha < 0.05 || b.width < 80 || b.height < 40 { continue }
            out.append(WindowInfo(id: numN.intValue,
                                  rect: Rect(x: b.minX, y: H - b.maxY, width: b.width, height: b.height)))
        }
        return out
    }

    /// macOS does not say why a window left the screen, so this infers it:
    /// - the window no longer exists: closed, the snow falls;
    /// - the active Space changed around the same moment: it is on another Space, keep the snow;
    /// - otherwise, after a short wait: minimized or its app was hidden, the snow falls.
    func classify(_ id: Int, elapsed: Double) -> VanishDecision {
        if !exists(id) { return .drop }
        if CACurrentMediaTime() - lastSpaceChange < 1.5 { return .keep }
        return elapsed < SystemWindowSource.decisionWindow ? .wait : .drop
    }

    func exists(_ id: Int) -> Bool {
        guard let info = CGWindowListCopyWindowInfo([.optionIncludingWindow], CGWindowID(id)) as? [[String: Any]] else {
            return false
        }
        return !info.isEmpty
    }
}

extension NSScreen {
    /// The CoreGraphics display ID, stable while the display stays connected
    var displayID: Int {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.intValue ?? 0
    }

    var displayInfo: DisplayInfo {
        DisplayInfo(id: displayID, rect: Rect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height))
    }
}
