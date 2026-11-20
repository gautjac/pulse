import SwiftUI
import PulseKit

struct MeterSheet: View {
    @Environment(Metronome.self) private var m
    @State private var groupingText = ""
    @State private var groupingInvalid = false
    @FocusState private var groupingFocused: Bool

    private var bar: Int { min(m.editBar, m.settings.bars.count - 1) }
    private var meter: Meter { m.settings.bars[bar].meter }

    var body: some View {
        let theme = m.prefs.theme
        SheetScaffold(title: "Meter") {
            List {
                if m.settings.isMixedMeter {
                    Section {
                        Text("Editing bar \(bar + 1) of \(m.settings.bars.count).")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                signatureSection(theme)
                customSection(theme)
                beatUnitSection
                sequenceSection(theme)
            }
            .toolbar { ToolbarItem(placement: .topBarLeading) { EditButton() } }
            .onAppear { groupingText = meter.groupingString }
            .onChange(of: meter.groupingString) { _, new in if !groupingFocused { groupingText = new } }
        }
    }

    // MARK: Sections

    private func signatureSection(_ theme: Theme) -> some View {
        Section("Time signature") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(Meter.commonSignatures, id: \.0) { n, d in
                    let selected = meter.numerator == n && meter.denominator == d
                    Button {
                        apply(Meter(numerator: n, denominator: d))
                    } label: {
                        Text("\(n)/\(d)")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(selected ? theme.strongColor.opacity(0.25) : theme.surface))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(selected ? theme.strongColor : .clear, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(n) over \(d)")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.vertical, 4)
            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
        }
    }

    private func customSection(_ theme: Theme) -> some View {
        Section {
            Stepper(value: Binding(get: { meter.numerator }, set: { apply(Meter(numerator: $0, denominator: meter.denominator)) }), in: 1...Meter.maxNumerator) {
                HStack { Text("Beats per bar"); Spacer(); Text("\(meter.numerator)").monospacedDigit().foregroundStyle(.secondary) }
            }
            Picker("Note value", selection: Binding(get: { meter.denominator }, set: { apply(Meter(numerator: meter.numerator, denominator: $0)) })) {
                ForEach(Meter.validDenominators, id: \.self) { Text("\($0)").tag($0) }
            }
            .pickerStyle(.segmented)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Grouping")
                    Spacer()
                    TextField("e.g. 3+3+2", text: $groupingText)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numbersAndPunctuation)
                        .focused($groupingFocused)
                        .submitLabel(.done)
                        .foregroundStyle(groupingInvalid ? .red : .primary)
                        .onSubmit(applyGrouping)
                        .onChange(of: groupingText) { _, _ in groupingInvalid = false }
                    Button("Auto") {
                        apply(Meter(numerator: meter.numerator, denominator: meter.denominator))
                        groupingText = meter.groupingString
                        groupingFocused = false
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                }
                GroupingPreview(meter: meter, theme: theme)
                if groupingInvalid {
                    Text("The groups must add up to \(meter.numerator).").font(.footnote).foregroundStyle(.red)
                } else {
                    Text("Accents follow the groups: the first beat of each group is stressed. Tap beats on the main screen to change any of them.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Custom")
        }
    }

    private var beatUnitSection: some View {
        Section {
            Picker("Tempo counts", selection: Binding<BeatUnit?>(get: { m.settings.beatUnitOverride }, set: { m.setBeatUnit($0) })) {
                Text("Automatic · \(m.settings.firstMeter.suggestedBeatUnit.name)").tag(BeatUnit?.none)
                ForEach(BeatUnit.allCases) { u in Text(u.name).tag(Optional(u)) }
            }
        } header: {
            Text("Beat unit")
        } footer: {
            Text("The BPM number counts this note value. 6/8 is usually felt in dotted quarters; 7/8 in eighths.")
        }
    }

    private func sequenceSection(_ theme: Theme) -> some View {
        Section {
            ForEach(Array(m.settings.bars.enumerated()), id: \.element.id) { i, spec in
                HStack {
                    Button { m.editBar = i } label: {
                        HStack(spacing: 10) {
                            Image(systemName: i == bar ? "largecircle.fill.circle" : "circle").foregroundStyle(i == bar ? theme.strongColor : .secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Bar \(i + 1) · \(spec.meter.name)").font(.body.weight(.medium))
                                Text(spec.meter.groupingString).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Stepper("Repeat", value: Binding(get: { spec.repeats }, set: { v in m.commit { $0.bars[i].repeats = v } }), in: 1...16)
                        .labelsHidden()
                    Text("×\(spec.repeats)").monospacedDigit().frame(width: 30, alignment: .trailing).foregroundStyle(.secondary)
                }
            }
            .onDelete { offsets in
                guard m.settings.bars.count > 1 else { return }
                m.commit { $0.bars.remove(atOffsets: offsets) }
            }
            .onMove { from, to in m.commit { $0.bars.move(fromOffsets: from, toOffset: to) } }
            Button {
                m.commit { s in
                    let copy = s.bars[min(bar, s.bars.count - 1)].duplicated()
                    s.bars.insert(copy, at: min(bar + 1, s.bars.count))
                }
                m.editBar = min(bar + 1, m.settings.bars.count - 1)
            } label: {
                Label("Add a bar after this one", systemImage: "plus.circle.fill")
            }
        } header: {
            Text("Bars in the pattern")
        } footer: {
            Text("Add bars to change meter as you play, such as 7/8 then 4/4. The pattern loops. Keep \"Tempo counts\" on a fixed note value so each beat stays the same speed across bars.")
        }
    }

    // MARK: Actions

    private func apply(_ new: Meter) {
        m.setMeter(new, bar: bar)
        groupingText = new.groupingString
    }

    private func applyGrouping() {
        guard let g = Meter.parseGrouping(groupingText, numerator: meter.numerator) else {
            groupingInvalid = !groupingText.isEmpty
            return
        }
        var new = meter
        new.setGrouping(g)
        m.setMeter(new, bar: bar)
        groupingText = new.groupingString
    }
}
