import SwiftUI
import AppIntents
import PulseKit

struct SettingsSheet: View {
    @Environment(Metronome.self) private var m

    var body: some View {
        @Bindable var m = m
        let theme = m.prefs.theme
        SheetScaffold(title: "Settings") {
            List {
                Section("Visual") {
                    Picker("Style", selection: $m.prefs.visualMode) {
                        ForEach(VisualMode.allCases) { Label($0.name, systemImage: $0.symbol).tag($0) }
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        ForEach(Theme.all) { t in
                            Button { m.prefs.themeID = t.id } label: {
                                VStack(spacing: 6) {
                                    HStack(spacing: 0) {
                                        Rectangle().fill(t.strongColor)
                                        Rectangle().fill(t.mediumColor)
                                        Rectangle().fill(t.softColor)
                                    }
                                    .frame(height: 26)
                                    .clipShape(Capsule())
                                    Text(t.name).font(.system(size: 12, weight: .semibold, design: .rounded))
                                }
                                .padding(8)
                                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(LinearGradient(colors: [Color(hex: t.top), Color(hex: t.bottom)], startPoint: .top, endPoint: .bottom)))
                                .foregroundStyle(t.inkColor)
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(m.prefs.themeID == t.id ? theme.strongColor : .clear, lineWidth: 2.5))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(t.name) theme")
                            .accessibilityAddTraits(m.prefs.themeID == t.id ? .isSelected : [])
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                    Toggle("Show beat numbers", isOn: $m.prefs.showCounts)
                    VStack(alignment: .leading) {
                        HStack { Text("Flash intensity"); Spacer(); Text("\(Int(m.prefs.flashIntensity * 100))%").foregroundStyle(.secondary).monospacedDigit() }
                        Slider(value: $m.prefs.flashIntensity, in: 0.2...1)
                    }
                }

                Section {
                    Toggle("Haptic tick on each beat", isOn: $m.prefs.haptics)
                    Toggle("Keep screen awake while playing", isOn: $m.prefs.keepAwake)
                    Toggle("Play along with other audio", isOn: $m.prefs.mixWithOthers)
                } header: {
                    Text("Playback")
                } footer: {
                    Text("Turn off \"Play along\" if you'd rather the metronome pause music and podcasts. Pulse keeps playing with the screen locked.")
                }

                Section {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Visual sync")
                            Spacer()
                            Text(m.prefs.visualOffsetMs == 0 ? "0 ms" : String(format: "%+.0f ms", m.prefs.visualOffsetMs)).foregroundStyle(.secondary).monospacedDigit()
                        }
                        Slider(value: $m.prefs.visualOffsetMs, in: -100...300, step: 5)
                        if m.prefs.visualOffsetMs != 0 {
                            Button("Reset to 0") { m.prefs.visualOffsetMs = 0 }.font(.footnote)
                        }
                    }
                } header: {
                    Text("Latency")
                } footer: {
                    Text("If the flash seems to come before or after the click (common with Bluetooth speakers), nudge this until they line up. The sound itself is never delayed.")
                }

                Section {
                    ShortcutsLink()
                    ForEach(Self.examples, id: \.self) { phrase in
                        Label(phrase, systemImage: "mic.fill").font(.callout)
                    }
                } header: {
                    Text("Siri & Shortcuts")
                } footer: {
                    Text("Every control is also an action in the Shortcuts app, so you can put tempo changes on the Action Button, a Lock Screen control or a custom automation.")
                }

                Section {
                    Button("Reset metronome to defaults", role: .destructive) { m.resetAll() }
                } footer: {
                    Text("Pulse 1.0 · your presets are kept.")
                }
            }
        }
    }

    private static let examples = [
        "“Hey Siri, speed up Pulse”",
        "“Slow down Pulse”",
        "“Set Pulse to seven eight”",
        "“Subdivide Pulse into triplets”",
        "“Change the sound in Pulse to wood block”",
        "“Start Waltz in Pulse”",
    ]
}
