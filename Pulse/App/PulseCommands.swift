import SwiftUI

/// Lets menu commands open a sheet in the focused window.
struct OpenSheetKey: FocusedValueKey { typealias Value = (SheetKind) -> Void }
extension FocusedValues {
    var openSheet: ((SheetKind) -> Void)? {
        get { self[OpenSheetKey.self] }
        set { self[OpenSheetKey.self] = newValue }
    }
}

/// Menu-bar commands on the Mac, and the shortcut sheet on iPad (hold ⌘).
struct PulseCommands: Commands {
    let m: Metronome
    @FocusedValue(\.openSheet) private var openSheet

    var body: some Commands {
        CommandMenu("Metronome") {
            Button(m.isPlaying ? "Stop" : "Start") { m.toggle() }
                .keyboardShortcut(.return, modifiers: .command)
            Button("Tap Tempo") { m.tapTempo() }
                .keyboardShortcut("t", modifiers: .command)
            Divider()
            Button("Faster") { m.nudge(1) }.keyboardShortcut(.upArrow, modifiers: .command)
            Button("Slower") { m.nudge(-1) }.keyboardShortcut(.downArrow, modifiers: .command)
            Button("Much Faster (+10)") { m.nudge(10) }.keyboardShortcut(.upArrow, modifiers: [.command, .shift])
            Button("Much Slower (−10)") { m.nudge(-10) }.keyboardShortcut(.downArrow, modifiers: [.command, .shift])
            Button("Double Tempo") { m.scaleBPM(by: 2) }.keyboardShortcut("]", modifiers: .command)
            Button("Half Tempo") { m.scaleBPM(by: 0.5) }.keyboardShortcut("[", modifiers: .command)
            Divider()
            Button("Meter…") { openSheet?(.meter) }.keyboardShortcut("m", modifiers: [.command, .option])
            Button("Subdivision…") { openSheet?(.subdivision) }.keyboardShortcut("d", modifiers: [.command, .option])
            Button("Sounds…") { openSheet?(.sounds) }.keyboardShortcut("s", modifiers: [.command, .option])
            Button("Practice…") { openSheet?(.practice) }.keyboardShortcut("p", modifiers: [.command, .option])
            Button("Presets…") { openSheet?(.presets) }.keyboardShortcut("l", modifiers: [.command, .option])
        }
        CommandMenu("Visual") {
            ForEach(Array(VisualMode.allCases.enumerated()), id: \.element) { index, mode in
                Button(mode.name) { m.prefs.visualMode = mode }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
        }
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { openSheet?(.settings) }.keyboardShortcut(",", modifiers: .command)
        }
    }
}
