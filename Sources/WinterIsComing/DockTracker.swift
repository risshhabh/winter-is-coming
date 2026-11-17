import Cocoa
import WinterCore

// MARK: - Find the Dock (needs Accessibility permission)

final class DockTracker {
    private var trusted = false
    private var warned = false
    private var lastStatus = ""
    var lastError = ""

    /// `prompt`: on first run macOS shows a dialog asking you to grant the permission
    init(prompt: Bool) {
        let opts = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        trusted = AXIsProcessTrustedWithOptions(opts)
    }

    /// Frame of the Dock icon area (window-server coordinates, origin top-left); nil if unavailable
    func frame() -> CGRect? {
        if !trusted {
            trusted = AXIsProcessTrusted()
            if !trusted {
                if !warned {
                    warned = true
                    print("❄︎ For snow on the Dock: System Settings → Privacy & Security → Accessibility, enable WinterIsComing (or the terminal you run it from), then restart.")
                }
                lastError = "no Accessibility permission"
                return nil
            }
        }
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            lastError = "Dock process not found"
            return nil
        }
        let axApp = AXUIElementCreateApplication(dock.processIdentifier)
        // This runs on the main thread; never let a busy Dock stall rendering for long
        AXUIElementSetMessagingTimeout(axApp, 0.25)
        var childrenRef: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(axApp, kAXChildrenAttribute as CFString, &childrenRef)
        guard err == .success, let children = childrenRef as? [AXUIElement] else {
            lastError = "could not read Dock children (AXError \(err.rawValue))"
            return nil
        }
        var roles: [String] = []
        for child in children {
            var roleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleRef)
            let role = (roleRef as? String) ?? "?"
            roles.append(role)
            guard role == kAXListRole else { continue }
            var posRef: CFTypeRef?
            var sizeRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(child, kAXPositionAttribute as CFString, &posRef) == .success,
                  AXUIElementCopyAttributeValue(child, kAXSizeAttribute as CFString, &sizeRef) == .success,
                  let pv = posRef, let sv = sizeRef,
                  CFGetTypeID(pv) == AXValueGetTypeID(), CFGetTypeID(sv) == AXValueGetTypeID() else { continue }
            var pos = CGPoint.zero
            var sz = CGSize.zero
            AXValueGetValue(pv as! AXValue, .cgPoint, &pos)
            AXValueGetValue(sv as! AXValue, .cgSize, &sz)
            return CGRect(origin: pos, size: sz)
        }
        lastError = "no AXList among Dock children (roles: \(roles))"
        return nil
    }

    /// Where snow can sit on the Dock, in global coordinates; nil while the Dock is hidden or unreadable.
    ///
    /// Works for a Dock on the bottom, left or right of any display: snow lies along the top edge of
    /// the icon area, which is a long ledge for a bottom Dock and a short cap on a side Dock.
    func snowRect(displays: [DisplayInfo]) -> Rect? {
        let pad = 4.0              // extra width of the Dock pile on each side of the icon area
        let topOffset = -1.0       // lower it if the snow floats above the Dock, raise it if it sinks in
        var result: Rect?
        var status: String
        if let f = frame() {
            var r = Rect(x: f.minX - pad, y: primaryDisplayHeight() - f.maxY, width: f.width + 2 * pad, height: f.height)
            // The display the Dock is on is the one it overlaps most. A Dock tucked away by auto-hide is
            // reported beyond the screen edge, so it overlaps none of them enough to count.
            var best: DisplayInfo?
            var bestOverlap = 0.0
            for d in displays {
                let w = min(r.maxX, d.rect.maxX) - max(r.minX, d.rect.minX)
                let h = min(r.maxY, d.rect.maxY) - max(r.minY, d.rect.minY)
                if w > 0, h > 0, w * h > bestOverlap { bestOverlap = w * h; best = d }
            }
            if let d = best, bestOverlap >= 0.6 * r.width * r.height {
                let bottom = r.width >= r.height
                if bottom, let screen = NSScreen.screens.first(where: { $0.displayID == d.id }) {
                    // The AX frame can reach a bit above the visible Dock shelf. When the Dock is always
                    // shown, the space macOS reserves for it (bottom of visibleFrame) is a better top edge.
                    let reserved = Double(screen.visibleFrame.minY - screen.frame.minY)
                    if reserved > 10 && d.rect.minY + reserved < r.maxY { r.height = d.rect.minY + reserved - r.minY }
                }
                r.height += topOffset
                result = r
                let edge = bottom ? "bottom" : (r.minX - d.rect.minX < d.rect.maxX - r.maxX ? "left" : "right")
                status = "found on the \(edge) of display \(d.id)"
            } else {
                status = "hidden"
            }
        } else {
            status = "not found: \(lastError)"
        }
        // Log only when the status changes, so the terminal doesn't get flooded
        if status != lastStatus {
            print("❄︎ Dock " + status)
            lastStatus = status
        }
        return result
    }
}
