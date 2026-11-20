import SwiftUI

@main
struct PulseApp: App {
    @State private var metronome = Metronome.shared

    init() {
        PulseShortcuts.updateAppShortcutParameters()
        #if DEBUG
        DebugLaunch.apply(to: Metronome.shared)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(metronome)
                .preferredColorScheme(metronome.prefs.theme.isDark ? .dark : .light)
                .tint(metronome.prefs.theme.strongColor)
        }
        .commands { PulseCommands(m: metronome) }
        #if os(macOS)
        .defaultSize(width: 1000, height: 680)
        .windowResizability(.contentMinSize)
        #endif
    }
}

#if DEBUG
/// Launch arguments for screenshots and manual testing, e.g.
/// `-pulse.demo.preset builtin.seven-eight -pulse.demo.visual orbit -pulse.demo.play YES`
@MainActor
enum DebugLaunch {
    static func apply(to m: Metronome) {
        let d = UserDefaults.standard
        if let id = d.string(forKey: "pulse.demo.preset") { _ = m.load(presetID: id) }
        if let v = d.string(forKey: "pulse.demo.visual"), let mode = VisualMode(rawValue: v) { m.prefs.visualMode = mode }
        if let t = d.string(forKey: "pulse.demo.theme") { m.prefs.themeID = t }
        if d.double(forKey: "pulse.demo.bpm") > 0 { m.setBPM(d.double(forKey: "pulse.demo.bpm")) }
        if d.bool(forKey: "pulse.demo.play") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { m.start() }
        }
    }
}
#endif
