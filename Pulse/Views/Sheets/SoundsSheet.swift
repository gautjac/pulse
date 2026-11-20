import SwiftUI
import PulseKit

struct SoundsSheet: View {
    @Environment(Metronome.self) private var m

    var body: some View {
        let theme = m.prefs.theme
        let s = m.settings
        SheetScaffold(title: "Sound") {
            List {
                Section("Sound kit") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        ForEach(SoundKit.allCases) { kit in
                            let selected = s.sounds.matchingKit == kit
                            Button {
                                m.applyKit(kit)
                                m.previewSound(kit.selection.strong)
                            } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: kit.symbol).font(.system(size: 20, weight: .semibold))
                                    Text(kit.name).font(.system(size: 12, weight: .bold, design: .rounded)).multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.8)
                                }
                                .frame(maxWidth: .infinity, minHeight: 74)
                                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(selected ? theme.strongColor.opacity(0.25) : theme.surface))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(selected ? theme.strongColor : .clear, lineWidth: 1.5))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }

                Section {
                    roleRow("Accent", \.strong)
                    roleRow("Normal", \.medium)
                    roleRow("Soft", \.soft)
                    roleRow("Subdivision", \.sub)
                } header: {
                    Text("Sound for each level")
                } footer: {
                    Text("Mix and match: any sound can play at any level. Tap the speaker to hear it.")
                }

                Section("Tone & level") {
                    VStack(alignment: .leading) {
                        HStack { Text("Pitch"); Spacer(); Text(pitchText(s.pitchSemitones)).foregroundStyle(.secondary).monospacedDigit() }
                        Slider(value: Binding(get: { s.pitchSemitones }, set: { v in m.commit { $0.pitchSemitones = v.rounded() } }), in: -12...12, step: 1)
                    }
                    VStack(alignment: .leading) {
                        HStack { Text("Volume"); Spacer(); Text("\(Int(s.volume * 100))%").foregroundStyle(.secondary).monospacedDigit() }
                        Slider(value: Binding(get: { s.volume }, set: { v in m.commit { $0.volume = v } }), in: 0...1)
                    }
                }

                polySection(theme)
            }
        }
    }

    private func roleRow(_ title: String, _ key: WritableKeyPath<SoundSelection, SoundID>) -> some View {
        HStack {
            Picker(title, selection: Binding(
                get: { m.settings.sounds[keyPath: key] },
                set: { id in
                    m.commit { $0.sounds[keyPath: key] = id }
                    m.previewSound(id)
                })) {
                ForEach(SoundID.allCases) { Text($0.name).tag($0) }
            }
            Button { m.previewSound(m.settings.sounds[keyPath: key]) } label: {
                Image(systemName: "speaker.wave.2.circle.fill").font(.system(size: 26))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Play \(title) sound")
        }
    }

    private func polySection(_ theme: Theme) -> some View {
        let poly = m.settings.poly
        let n = m.settings.firstMeter.numerator
        return Section {
            Toggle("Polyrhythm layer", isOn: Binding(get: { poly.enabled }, set: { v in m.commit { $0.poly.enabled = v } }))
            if poly.enabled {
                Stepper(value: Binding(get: { poly.clicks }, set: { v in m.commit { $0.poly = PolyLayer(enabled: true, clicks: v, sound: $0.poly.sound, volume: $0.poly.volume) } }), in: 2...16) {
                    HStack { Text("Clicks per bar"); Spacer(); Text("\(poly.clicks) against \(n)").foregroundStyle(.secondary) }
                }
                HStack {
                    Picker("Sound", selection: Binding(get: { poly.sound }, set: { id in m.commit { $0.poly.sound = id }; m.previewSound(id) })) {
                        ForEach(SoundID.allCases) { Text($0.name).tag($0) }
                    }
                    Button { m.previewSound(poly.sound) } label: { Image(systemName: "speaker.wave.2.circle.fill").font(.system(size: 26)) }
                        .buttonStyle(.plain)
                }
                VStack(alignment: .leading) {
                    HStack { Text("Layer volume"); Spacer(); Text("\(Int(poly.volume * 100))%").foregroundStyle(.secondary).monospacedDigit() }
                    Slider(value: Binding(get: { poly.volume }, set: { v in m.commit { $0.poly.volume = v } }), in: 0...1)
                }
            }
        } header: {
            Text("Polyrhythm")
        } footer: {
            Text(poly.enabled
                 ? "\(poly.clicks) evenly spaced clicks across every bar, against the bar's own \(n) beats."
                 : "Adds a second voice that divides each bar differently: 3 against 4, 5 against 4, 7 against 8…")
        }
    }

    private func pitchText(_ v: Double) -> String {
        v == 0 ? "Normal" : (v > 0 ? "+\(Int(v)) semitones" : "\(Int(v)) semitones")
    }
}
