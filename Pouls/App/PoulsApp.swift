import SwiftUI

@main
struct PoulsApp: App {
    @State private var metronome = Metronome.shared

    init() {
        PoulsShortcuts.updateAppShortcutParameters()
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
    }
}

#if DEBUG
/// Launch arguments for screenshots and manual testing, e.g.
/// `-pouls.demo.preset builtin.seven-eight -pouls.demo.visual orbit -pouls.demo.play YES`
@MainActor
enum DebugLaunch {
    static func apply(to m: Metronome) {
        let d = UserDefaults.standard
        if let id = d.string(forKey: "pouls.demo.preset") { _ = m.load(presetID: id) }
        if let v = d.string(forKey: "pouls.demo.visual"), let mode = VisualMode(rawValue: v) { m.prefs.visualMode = mode }
        if let t = d.string(forKey: "pouls.demo.theme") { m.prefs.themeID = t }
        if d.double(forKey: "pouls.demo.bpm") > 0 { m.setBPM(d.double(forKey: "pouls.demo.bpm")) }
        if d.bool(forKey: "pouls.demo.play") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { m.start() }
        }
    }
}
#endif
