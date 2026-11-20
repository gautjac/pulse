import SwiftUI
import PulseKit

enum SheetKind: String, Identifiable {
    case meter, subdivision, sounds, practice, presets, settings
    var id: String { rawValue }
}

struct ContentView: View {
    @Environment(Metronome.self) private var m
    @State private var sheet: SheetKind?
    @State private var stage = false
    @State private var showTempoEntry = false
    @State private var tempoText = ""

    var body: some View {
        let theme = m.prefs.theme
        ZStack {
            theme.background.ignoresSafeArea()
            GeometryReader { geo in
                if geo.size.width > geo.size.height {
                    landscape(theme)
                } else {
                    portrait(theme)
                }
            }
        }
        .foregroundStyle(theme.inkColor)
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 620)
        #endif
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(keys: [.space, .upArrow, .downArrow, .rightArrow, .leftArrow, KeyEquivalent("t")], phases: [.down, .repeat]) { press in
            handleKey(press)
        }
        .focusedSceneValue(\.openSheet, { sheet = $0 })
        .sheet(item: $sheet) { kind in
            Group {
                switch kind {
                case .meter: MeterSheet()
                case .subdivision: SubdivisionSheet()
                case .sounds: SoundsSheet()
                case .practice: PracticeSheet()
                case .presets: PresetsSheet()
                case .settings: SettingsSheet()
                }
            }
            .sheetSizing(large: kind == .settings || kind == .presets)
        }
        .alert("Set tempo", isPresented: $showTempoEntry) {
            TextField("BPM", text: $tempoText).numberPadKeyboard()
            Button("Set") { if let v = Double(tempoText) { m.setBPM(v) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Type a tempo from 20 to 400.")
        }
        .alert("Audio problem", isPresented: Binding(get: { m.lastError != nil }, set: { if !$0 { m.lastError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(m.lastError ?? "")
        }
    }

    /// Hardware keyboard (Mac, iPad): space starts and stops, arrows change the tempo (shift for ±10), T taps.
    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        let step: Double = press.modifiers.contains(.shift) ? 10 : 1
        switch press.key {
        case .space:
            guard press.phase == .down else { return .handled }
            m.toggle()
        case .upArrow, .rightArrow: m.nudge(step)
        case .downArrow, .leftArrow: m.nudge(-step)
        default:
            guard press.characters.lowercased() == "t" else { return .ignored }
            guard press.phase == .down else { return .handled }
            m.tapTempo()
        }
        return .handled
    }

    // MARK: Layouts

    private func portrait(_ theme: Theme) -> some View {
        VStack(spacing: 12) {
            if !stage { header(theme) }
            VisualStage(stage: $stage)
                .frame(maxHeight: .infinity)
                .frame(minHeight: 150)
            if !stage {
                controls(theme)
            }
            TransportBar()
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
        .animation(.snappy, value: stage)
    }

    private func landscape(_ theme: Theme) -> some View {
        HStack(spacing: 16) {
            VisualStage(stage: $stage)
                .padding(.vertical, 8)
            if !stage {
                ScrollView {
                    VStack(spacing: 12) {
                        header(theme)
                        controls(theme)
                    }
                }
                .scrollIndicators(.hidden)
                .frame(width: 380)
            }
            VStack { Spacer(); TransportBar(compact: true); Spacer() }
        }
        .padding(.horizontal, 16)
        .animation(.snappy, value: stage)
    }

    private func controls(_ theme: Theme) -> some View {
        VStack(spacing: 12) {
            BeatGridView()
            TempoPanel { tempoText = String(Int(m.settings.bpm.rounded())); showTempoEntry = true }
            chipRow(theme)
        }
    }

    // MARK: Pieces

    private func header(_ theme: Theme) -> some View {
        HStack {
            Button { sheet = .presets } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.stack.fill")
                    Text(m.activePreset?.name ?? "Presets")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                }
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(Capsule().fill(theme.surface))
            }
            .accessibilityLabel("Presets")
            Spacer()
            Button { sheet = .settings } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 42, height: 40)
                    .background(Capsule().fill(theme.surface))
            }
            .accessibilityLabel("Settings")
        }
        .buttonStyle(.plain)
    }

    private func chipRow(_ theme: Theme) -> some View {
        let s = m.settings
        let meterTitle = s.isMixedMeter ? "\(s.bars.count) bars" : s.firstMeter.name
        let meterSub = s.isMixedMeter ? s.bars.map { $0.meter.name }.joined(separator: "→") : (s.firstMeter.grouping.count > 1 && s.firstMeter.grouping.contains { $0 > 1 } ? s.firstMeter.groupingString : "meter")
        let practiceOn = s.trainer.enabled || s.gap.enabled || s.countInBars > 0
        return HStack(spacing: 8) {
            Chip(title: meterTitle, subtitle: meterSub, symbol: "music.note.list", theme: theme) { sheet = .meter }
            Chip(title: s.subdivision.isNone ? "Off" : shortSub(s.subdivision), subtitle: "subdivide", symbol: "divide", active: !s.subdivision.isNone, theme: theme) { sheet = .subdivision }
            Chip(title: (s.sounds.matchingKit?.name ?? "Custom").components(separatedBy: " ").first ?? "Sound", subtitle: s.poly.enabled ? "+ \(s.poly.clicks):\(s.firstMeter.numerator)" : "sound", symbol: "speaker.wave.2.fill", active: s.poly.enabled, theme: theme) { sheet = .sounds }
            Chip(title: practiceOn ? "On" : "Practice", subtitle: practiceSubtitle(s), symbol: "target", active: practiceOn, theme: theme) { sheet = .practice }
        }
    }

    private func shortSub(_ s: Subdivision) -> String {
        switch s {
        case .eighths: return "×2"
        case .triplets: return "×3"
        case .sixteenths: return "×4"
        case .quintuplets: return "×5"
        case .sextuplets: return "×6"
        case .septuplets: return "×7"
        case .swing: return "Swing"
        case .tripletSkip: return "Shuffle"
        case .offBeat: return "Off-beat"
        default: return "×\(s.steps)"
        }
    }

    private func practiceSubtitle(_ s: MetronomeSettings) -> String {
        var parts: [String] = []
        if s.trainer.enabled { parts.append("trainer") }
        if s.gap.enabled { parts.append("gap") }
        if s.countInBars > 0 { parts.append("count-in") }
        return parts.isEmpty ? "trainer · gap" : parts.joined(separator: " · ")
    }
}

// MARK: - Transport

struct TransportBar: View {
    @Environment(Metronome.self) private var m
    var compact = false

    var body: some View {
        let theme = m.prefs.theme
        if compact {
            playButton(theme)
        } else {
            HStack {
                volume(theme).frame(width: 120)
                Spacer()
                playButton(theme)
                Spacer()
                status(theme).frame(width: 120, alignment: .trailing)
            }
        }
    }

    private func playButton(_ theme: Theme) -> some View {
        Button { m.toggle() } label: {
            ZStack {
                Circle().fill(m.isPlaying ? theme.surfaceStrong : theme.strongColor)
                Circle().stroke(theme.strongColor, lineWidth: m.isPlaying ? 3 : 0)
                Image(systemName: m.isPlaying ? "stop.fill" : "play.fill")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(m.isPlaying ? theme.strongColor : (theme.isDark ? Color.black.opacity(0.85) : .white))
                    .offset(x: m.isPlaying ? 0 : 2)
            }
            .frame(width: 84, height: 84)
            .shadow(color: theme.strongColor.opacity(m.isPlaying ? 0 : 0.35), radius: 16, y: 6)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .medium), trigger: m.isPlaying)
        .accessibilityLabel(m.isPlaying ? "Stop metronome" : "Start metronome")
    }

    private func volume(_ theme: Theme) -> some View {
        @Bindable var m = m
        return HStack(spacing: 6) {
            Image(systemName: m.settings.volume < 0.01 ? "speaker.slash.fill" : "speaker.wave.1.fill")
                .font(.system(size: 13)).foregroundStyle(theme.secondaryInk)
            Slider(value: Binding(get: { m.settings.volume }, set: { v in m.commit { $0.volume = v } }), in: 0...1)
                .accessibilityLabel("Volume")
        }
    }

    private func status(_ theme: Theme) -> some View {
        let phase = m.phase
        return VStack(alignment: .trailing, spacing: 2) {
            if m.isPlaying && phase.pulseIndex >= 0 {
                Text(phase.countIn ? "Count-in" : "Bar \(phase.bar + 1)")
                    .font(.system(size: 15, weight: .bold, design: .rounded)).monospacedDigit()
                if phase.muted {
                    Text("silent bar").font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(theme.strongColor)
                } else if m.settings.trainer.enabled {
                    Text("→ \(Int(m.settings.trainer.targetBPM))").font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(theme.secondaryInk)
                }
            } else {
                Text(m.settings.summary)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.secondaryInk)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(3)
            }
        }
    }
}
