import AppIntents
import PulseKit

// Every intent runs inside the app's own process, so they talk to the same Metronome the UI does:
// a tempo change from Siri moves the on-screen number and the live audio at the next beat.

private func bpmText(_ v: Double) -> String { "\(Int(v.rounded()))" }

// MARK: - Transport

struct StartMetronomeIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Metronome"
    static let description = IntentDescription("Starts the metronome, optionally at a given tempo.", categoryName: "Transport")
    static let openAppWhenRun = true

    @Parameter(title: "Tempo (BPM)", inclusiveRange: (20, 400))
    var tempo: Int?

    static var parameterSummary: some ParameterSummary { Summary("Start the metronome") { \.$tempo } }

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let m = Metronome.shared
        if let tempo { m.setBPM(Double(tempo)) }
        m.start()
        return .result(dialog: "Playing at \(bpmText(m.settings.bpm)) BPM.")
    }
}

struct StopMetronomeIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Metronome"
    static let description = IntentDescription("Stops the metronome.", categoryName: "Transport")

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        Metronome.shared.stop()
        return .result(dialog: "Stopped.")
    }
}

struct ToggleMetronomeIntent: AppIntent {
    static let title: LocalizedStringResource = "Start or Stop Metronome"
    static let description = IntentDescription("Starts the metronome if it is stopped, stops it if it is playing. Handy for the Action Button.", categoryName: "Transport")
    static let openAppWhenRun = true

    @MainActor func perform() async throws -> some IntentResult {
        Metronome.shared.toggle()
        return .result()
    }
}

// MARK: - Tempo

struct SetTempoIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Tempo"
    static let description = IntentDescription("Sets the tempo in beats per minute.", categoryName: "Tempo")

    @Parameter(title: "Tempo (BPM)", description: "20 to 400", inclusiveRange: (20, 400), requestValueDialog: "What tempo?")
    var tempo: Int

    static var parameterSummary: some ParameterSummary { Summary("Set tempo to \(\.$tempo) BPM") }

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        Metronome.shared.setBPM(Double(tempo))
        return .result(dialog: "Tempo is \(bpmText(Metronome.shared.settings.bpm)) BPM.")
    }
}

struct ChangeTempoIntent: AppIntent {
    static let title: LocalizedStringResource = "Change Tempo"
    static let description = IntentDescription("Speeds the metronome up or slows it down by a number of BPM or a percentage.", categoryName: "Tempo")

    @Parameter(title: "Direction", default: .faster)
    var direction: TempoDirection

    @Parameter(title: "Amount", default: 5, inclusiveRange: (1, 200))
    var amount: Int

    @Parameter(title: "Unit", default: .bpm)
    var unit: TempoUnit

    static var parameterSummary: some ParameterSummary {
        Summary("Make the metronome \(\.$direction) by \(\.$amount) \(\.$unit)")
    }

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let m = Metronome.shared
        let sign: Double = direction == .faster ? 1 : -1
        switch unit {
        case .bpm: m.nudge(sign * Double(amount))
        case .percent: m.scaleBPM(by: 1 + sign * Double(amount) / 100)
        }
        return .result(dialog: "Now \(bpmText(m.settings.bpm)) BPM.")
    }
}

struct SpeedUpIntent: AppIntent {
    static let title: LocalizedStringResource = "Speed Up"
    static let description = IntentDescription("Raises the tempo.", categoryName: "Tempo")

    @Parameter(title: "Amount (BPM)", default: 5, inclusiveRange: (1, 100))
    var amount: Int

    static var parameterSummary: some ParameterSummary { Summary("Speed up by \(\.$amount) BPM") }

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        Metronome.shared.nudge(Double(amount))
        return .result(dialog: "Now \(bpmText(Metronome.shared.settings.bpm)) BPM.")
    }
}

struct SlowDownIntent: AppIntent {
    static let title: LocalizedStringResource = "Slow Down"
    static let description = IntentDescription("Lowers the tempo.", categoryName: "Tempo")

    @Parameter(title: "Amount (BPM)", default: 5, inclusiveRange: (1, 100))
    var amount: Int

    static var parameterSummary: some ParameterSummary { Summary("Slow down by \(\.$amount) BPM") }

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        Metronome.shared.nudge(-Double(amount))
        return .result(dialog: "Now \(bpmText(Metronome.shared.settings.bpm)) BPM.")
    }
}

struct ScaleTempoIntent: AppIntent {
    static let title: LocalizedStringResource = "Double or Halve Tempo"
    static let description = IntentDescription("Doubles, halves or otherwise scales the tempo.", categoryName: "Tempo")

    @Parameter(title: "Change", default: .double)
    var scale: TempoScale

    static var parameterSummary: some ParameterSummary { Summary("Set the tempo to \(\.$scale)") }

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        Metronome.shared.scaleBPM(by: scale.factor)
        return .result(dialog: "Now \(bpmText(Metronome.shared.settings.bpm)) BPM.")
    }
}

struct GetTempoIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Metronome Settings"
    static let description = IntentDescription("Tells you the tempo and time signature, and returns the tempo in BPM.", categoryName: "Tempo")

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        let m = Metronome.shared
        return .result(value: Int(m.displayBPM.rounded()), dialog: "\(m.settings.summary).")
    }
}

// MARK: - Meter, subdivision, sound

struct SetTimeSignatureIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Time Signature"
    static let description = IntentDescription("Chooses a time signature, including odd and compound meters.", categoryName: "Rhythm")

    @Parameter(title: "Time Signature", requestValueDialog: "Which time signature?")
    var signature: TimeSignatureOption

    static var parameterSummary: some ParameterSummary { Summary("Set time signature to \(\.$signature)") }

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let p = signature.parts
        Metronome.shared.setTimeSignature(numerator: p.numerator, denominator: p.denominator)
        return .result(dialog: "\(Metronome.shared.settings.firstMeter.longName).")
    }
}

struct SetCustomTimeSignatureIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Custom Time Signature"
    static let description = IntentDescription("Sets any time signature, with an optional grouping such as 3+3+2.", categoryName: "Rhythm")

    @Parameter(title: "Beats per bar", inclusiveRange: (1, 32), requestValueDialog: "How many beats per bar?")
    var beats: Int

    @Parameter(title: "Note value", default: .quarter)
    var noteValue: NoteValueOption

    @Parameter(title: "Grouping", description: "For example 2+2+3. Leave empty for the usual grouping.")
    var grouping: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Set \(\.$beats) over \(\.$noteValue)") { \.$grouping }
    }

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        var group: [Int]?
        if let grouping, !grouping.isEmpty { group = Meter.parseGrouping(grouping, numerator: beats) }
        Metronome.shared.setTimeSignature(numerator: beats, denominator: noteValue.rawValue, grouping: group)
        let note = (grouping?.isEmpty == false && group == nil) ? " That grouping doesn't add up to \(beats), so I used the usual one." : ""
        return .result(dialog: "\(Metronome.shared.settings.firstMeter.longName).\(note)")
    }
}

struct SetSubdivisionIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Subdivision"
    static let description = IntentDescription("Chooses how each beat is subdivided.", categoryName: "Rhythm")

    @Parameter(title: "Subdivision", requestValueDialog: "Which subdivision?")
    var subdivision: SubdivisionOption

    static var parameterSummary: some ParameterSummary { Summary("Subdivide into \(\.$subdivision)") }

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        Metronome.shared.setSubdivision(subdivision.subdivision)
        return .result(dialog: "Subdivision: \(subdivision.subdivision.name).")
    }
}

struct SetSoundIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Metronome Sound"
    static let description = IntentDescription("Chooses the click sound.", categoryName: "Sound")

    @Parameter(title: "Sound", requestValueDialog: "Which sound?")
    var sound: SoundKitOption

    static var parameterSummary: some ParameterSummary { Summary("Use the \(\.$sound) sound") }

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        Metronome.shared.applyKit(sound.kit)
        return .result(dialog: "\(sound.kit.name).")
    }
}

struct SetVolumeIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Metronome Volume"
    static let description = IntentDescription("Sets the metronome's volume.", categoryName: "Sound")

    @Parameter(title: "Volume (%)", inclusiveRange: (0, 100), requestValueDialog: "What volume?")
    var percent: Int

    static var parameterSummary: some ParameterSummary { Summary("Set volume to \(\.$percent) percent") }

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        Metronome.shared.commit { $0.volume = Double(percent) / 100 }
        return .result(dialog: "Volume \(percent) percent.")
    }
}

struct SetPolyrhythmIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Polyrhythm"
    static let description = IntentDescription("Adds a second layer of evenly spaced clicks across each bar, such as 3 against 4. Turn it off to remove.", categoryName: "Rhythm")

    @Parameter(title: "Clicks per bar", default: 3, inclusiveRange: (2, 16))
    var clicks: Int

    @Parameter(title: "On", default: true)
    var enabled: Bool

    static var parameterSummary: some ParameterSummary { Summary("Polyrhythm \(\.$clicks) per bar, on: \(\.$enabled)") }

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        Metronome.shared.commit {
            $0.poly.enabled = enabled
            $0.poly = PolyLayer(enabled: enabled, clicks: clicks, sound: $0.poly.sound, volume: $0.poly.volume)
        }
        let m = Metronome.shared.settings
        return .result(dialog: enabled ? "\(m.poly.clicks) against \(m.firstMeter.numerator)." : "Polyrhythm off.")
    }
}

// MARK: - Practice

struct SetCountInIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Count-In"
    static let description = IntentDescription("Sets how many bars of count-in play before the metronome starts. 0 turns it off.", categoryName: "Practice")

    @Parameter(title: "Bars", inclusiveRange: (0, 4), requestValueDialog: "How many bars?")
    var bars: Int

    static var parameterSummary: some ParameterSummary { Summary("Count in \(\.$bars) bars") }

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        Metronome.shared.commit { $0.countInBars = bars }
        return .result(dialog: bars == 0 ? "Count-in off." : "Count-in: \(bars) bar\(bars == 1 ? "" : "s").")
    }
}

struct StartSpeedTrainerIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Speed Trainer"
    static let description = IntentDescription("Starts at one tempo and steadily moves to another.", categoryName: "Practice")
    static let openAppWhenRun = true

    @Parameter(title: "From (BPM)", inclusiveRange: (20, 400), requestValueDialog: "Start at what tempo?")
    var from: Int

    @Parameter(title: "To (BPM)", inclusiveRange: (20, 400), requestValueDialog: "Build up to what tempo?")
    var to: Int

    @Parameter(title: "Step (BPM)", default: 4, inclusiveRange: (1, 50))
    var step: Int

    @Parameter(title: "Every (bars)", default: 4, inclusiveRange: (1, 64))
    var everyBars: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Go from \(\.$from) to \(\.$to) BPM") { \.$step; \.$everyBars }
    }

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let m = Metronome.shared
        if m.isPlaying { m.stop() }
        m.commit {
            $0.setBPM(Double(from))
            $0.trainer = SpeedTrainer(enabled: true, targetBPM: Double(to), stepBPM: Double(step), everyBars: everyBars)
        }
        m.start()
        return .result(dialog: "Going from \(from) to \(to), \(step) every \(everyBars) bars.")
    }
}

struct StopSpeedTrainerIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Speed Trainer"
    static let description = IntentDescription("Turns the speed trainer off and holds the current tempo.", categoryName: "Practice")

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        Metronome.shared.commit { $0.trainer.enabled = false }
        return .result(dialog: "Holding \(bpmText(Metronome.shared.settings.bpm)) BPM.")
    }
}

struct StartPresetIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Preset"
    static let description = IntentDescription("Loads one of your presets (or a built-in one) and starts it.", categoryName: "Presets")
    static let openAppWhenRun = true

    @Parameter(title: "Preset", requestValueDialog: "Which preset?")
    var preset: PresetEntity

    static var parameterSummary: some ParameterSummary { Summary("Start \(\.$preset)") }

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let m = Metronome.shared
        guard m.load(presetID: preset.id) else {
            return .result(dialog: "I couldn't find that preset.")
        }
        m.start()
        return .result(dialog: "\(preset.name): \(m.settings.summary).")
    }
}

struct LoadPresetIntent: AppIntent {
    static let title: LocalizedStringResource = "Load Preset"
    static let description = IntentDescription("Loads a preset without starting it.", categoryName: "Presets")

    @Parameter(title: "Preset", requestValueDialog: "Which preset?")
    var preset: PresetEntity

    static var parameterSummary: some ParameterSummary { Summary("Load \(\.$preset)") }

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let ok = Metronome.shared.load(presetID: preset.id)
        return .result(dialog: ok ? "Loaded \(preset.name)." : "I couldn't find that preset.")
    }
}

// MARK: - Look

struct SetVisualModeIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Visual Mode"
    static let description = IntentDescription("Chooses the on-screen visual: pendulum, pulse, orbit or bounce.", categoryName: "Look")

    @Parameter(title: "Visual", requestValueDialog: "Which visual?")
    var mode: VisualMode

    static var parameterSummary: some ParameterSummary { Summary("Show the \(\.$mode) visual") }

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        Metronome.shared.prefs.visualMode = mode
        return .result(dialog: "\(mode.name).")
    }
}

// MARK: - Siri phrases

struct PulseShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor { .orange }

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartMetronomeIntent(),
            phrases: ["Start \(.applicationName)", "Start the metronome in \(.applicationName)", "Play \(.applicationName)"],
            shortTitle: "Start", systemImageName: "play.fill")
        AppShortcut(
            intent: StopMetronomeIntent(),
            phrases: ["Stop \(.applicationName)", "Stop the metronome in \(.applicationName)"],
            shortTitle: "Stop", systemImageName: "stop.fill")
        AppShortcut(
            intent: SpeedUpIntent(),
            phrases: ["Speed up \(.applicationName)", "Make \(.applicationName) faster", "Faster in \(.applicationName)"],
            shortTitle: "Speed Up", systemImageName: "hare.fill")
        AppShortcut(
            intent: SlowDownIntent(),
            phrases: ["Slow down \(.applicationName)", "Make \(.applicationName) slower", "Slower in \(.applicationName)"],
            shortTitle: "Slow Down", systemImageName: "tortoise.fill")
        AppShortcut(
            intent: SetTempoIntent(),
            phrases: ["Set the tempo in \(.applicationName)", "Change the tempo in \(.applicationName)"],
            shortTitle: "Set Tempo", systemImageName: "gauge.with.dots.needle.50percent")
        AppShortcut(
            intent: SetTimeSignatureIntent(),
            phrases: ["Set \(.applicationName) to \(\.$signature)", "Change the time signature in \(.applicationName) to \(\.$signature)"],
            shortTitle: "Time Signature", systemImageName: "music.note.list")
        AppShortcut(
            intent: SetSubdivisionIntent(),
            phrases: ["Subdivide \(.applicationName) into \(\.$subdivision)", "Set \(.applicationName) subdivision to \(\.$subdivision)"],
            shortTitle: "Subdivision", systemImageName: "divide")
        AppShortcut(
            intent: SetSoundIntent(),
            phrases: ["Change the sound in \(.applicationName) to \(\.$sound)", "Use \(\.$sound) in \(.applicationName)"],
            shortTitle: "Sound", systemImageName: "speaker.wave.2.fill")
        AppShortcut(
            intent: StartPresetIntent(),
            phrases: ["Start \(\.$preset) in \(.applicationName)", "Play \(\.$preset) in \(.applicationName)"],
            shortTitle: "Start Preset", systemImageName: "square.stack.fill")
        AppShortcut(
            intent: ScaleTempoIntent(),
            phrases: ["Double the tempo in \(.applicationName)", "Half time in \(.applicationName)", "Change \(.applicationName) to \(\.$scale)"],
            shortTitle: "Double or Halve", systemImageName: "arrow.up.arrow.down")
    }
}
