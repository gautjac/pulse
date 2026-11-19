import SwiftUI
import PoulsKit

struct SubdivisionSheet: View {
    @Environment(Metronome.self) private var m

    var body: some View {
        let theme = m.prefs.theme
        let sub = m.settings.subdivision
        SheetScaffold(title: "Subdivision") {
            List {
                Section("Patterns") {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        ForEach(Subdivision.catalog) { entry in
                            let selected = sub == entry.value
                            Button { m.setSubdivision(entry.value) } label: {
                                VStack(spacing: 3) {
                                    Text(entry.name).font(.system(size: 15, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.7)
                                    Text(entry.counting).font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(.secondary).lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, minHeight: 54)
                                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(selected ? theme.strongColor.opacity(0.25) : theme.surface))
                                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(selected ? theme.strongColor : .clear, lineWidth: 1.5))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }

                Section {
                    Stepper(value: Binding(get: { sub.steps }, set: { v in var s = m.settings.subdivision; s.setSteps(v); m.setSubdivision(s) }), in: 1...9) {
                        HStack { Text("Clicks per beat"); Spacer(); Text("\(sub.steps)").monospacedDigit().foregroundStyle(.secondary) }
                    }
                    if sub.steps > 1 {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Tap a slot to mute or unmute it").font(.footnote).foregroundStyle(.secondary)
                            HStack(spacing: 8) {
                                ForEach(0..<sub.steps, id: \.self) { k in
                                    Button {
                                        guard k > 0 else { return }
                                        var s = m.settings.subdivision
                                        s.mask[k].toggle()
                                        m.setSubdivision(s)
                                    } label: {
                                        Circle()
                                            .fill(sub.mask[k] ? (k == 0 ? theme.strongColor : theme.mediumColor) : theme.surface)
                                            .overlay(Circle().stroke(theme.inkColor.opacity(0.3), lineWidth: 1))
                                            .overlay(Text(k == 0 ? "1" : "\(k + 1)").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(sub.mask[k] ? Color.black.opacity(0.75) : theme.secondaryInk))
                                            .frame(maxWidth: 40).aspectRatio(1, contentMode: .fit)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Slot \(k + 1)")
                                    .accessibilityValue(sub.mask[k] ? "on" : "muted")
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        Toggle("Sound the beat itself", isOn: Binding(get: { sub.playsPulse }, set: { v in var s = m.settings.subdivision; s = Subdivision(steps: s.steps, mask: s.mask, swing: s.swing, playsPulse: v); m.setSubdivision(s) }))
                    }
                    if sub.steps == 2 {
                        VStack(alignment: .leading) {
                            HStack { Text("Swing"); Spacer(); Text(swingText(sub.swing)).foregroundStyle(.secondary) }
                            Slider(value: Binding(get: { sub.swing }, set: { v in var s = m.settings.subdivision; s = Subdivision(steps: 2, mask: s.mask, swing: v, playsPulse: s.playsPulse); m.setSubdivision(s) }), in: 0.5...0.75)
                        }
                    }
                } header: {
                    Text("Custom")
                }

                Section("Balance") {
                    VStack(alignment: .leading) {
                        HStack { Text("Subdivision volume"); Spacer(); Text("\(Int(m.settings.subdivisionVolume * 100))%").foregroundStyle(.secondary).monospacedDigit() }
                        Slider(value: Binding(get: { m.settings.subdivisionVolume }, set: { v in m.commit { $0.subdivisionVolume = v } }), in: 0...1)
                    }
                }
            }
        }
    }

    private func swingText(_ v: Double) -> String {
        switch v {
        case ..<0.52: return "Straight"
        case 0.64..<0.70: return "Triplet swing"
        case 0.73...: return "Dotted"
        default: return "\(Int((v * 100).rounded()))%"
        }
    }
}
