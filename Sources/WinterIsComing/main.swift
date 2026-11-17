// WinterIsComing — snow on your Mac desktop.
// Snow falls behind your windows on every display, piles up on top of them, on the Dock and at the
// bottom of the screen, rides along when you move a window and comes off as powder when you shake it.
// See README.md.
// Run:   swift run -c release   (a ❄︎ icon appears in the menu bar)

import Cocoa
import WinterCore

let arguments = CommandLine.arguments
if arguments.contains("--snapshot") {
    exit(Snapshot.run(arguments))
}
if let i = arguments.firstIndex(of: "--make-icon"), i + 1 < arguments.count {
    // Used by Scripts/bundle.sh: writes the app icon as an .iconset folder
    exit(AppIcon.writeIconset(to: arguments[i + 1]) ? 0 : 1)
}

let app = NSApplication.shared
if let i = arguments.firstIndex(of: "--audition") {
    // Listening test: every bell variant, then the shimmer swelling and fading. Optional volume 0...1.
    let player = BellAudio()
    player.bellVolume = i + 1 < arguments.count ? Double(arguments[i + 1]) ?? 0.5 : 0.5
    player.audition { print("audition finished"); exit(0) }
    app.run()
}
let delegate = AppDelegate()
if let i = arguments.firstIndex(of: "--preferences-snapshot"), i + 1 < arguments.count {
    // Layout check: renders each Preferences tab with default settings, touching no stored settings
    delegate.smokeSeconds = 0
    PreferencesWindow(app: delegate).snapshotTabs(prefix: arguments[i + 1])
    exit(0)
}
if let i = arguments.firstIndex(of: "--smoke") {
    delegate.smokeSeconds = i + 1 < arguments.count ? Double(arguments[i + 1]) ?? 8 : 8
}
if let i = arguments.firstIndex(of: "--cursor"), i + 1 < arguments.count {
    delegate.smokePreset = CursorPreset(rawValue: arguments[i + 1])
}
app.delegate = delegate
app.setActivationPolicy(.accessory)   // no Dock icon
app.run()
