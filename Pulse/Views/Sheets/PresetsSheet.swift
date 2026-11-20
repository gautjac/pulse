import SwiftUI
import PulseKit

struct PresetsSheet: View {
    @Environment(Metronome.self) private var m
    @Environment(\.dismiss) private var dismiss
    @State private var showSave = false
    @State private var newName = ""

    var body: some View {
        SheetScaffold(title: "Presets") {
            List {
                if !m.userPresets.isEmpty {
                    Section("My presets") {
                        ForEach(m.userPresets) { row($0) }
                            .onDelete { offsets in
                                let ids = offsets.map { m.userPresets[$0].id }
                                ids.forEach(m.deletePreset)
                            }
                    }
                }
                ForEach(PresetLibrary.sections) { section in
                    Section(section.title) { ForEach(section.presets) { row($0) } }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { newName = ""; showSave = true } label: { Label("Save current", systemImage: "plus") }
                }
            }
            .alert("Save preset", isPresented: $showSave) {
                TextField("Name", text: $newName)
                Button("Save") { m.saveCurrentAsPreset(named: newName) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(m.settings.summary)
            }
        }
    }

    private func row(_ p: Preset) -> some View {
        let theme = m.prefs.theme
        return Button {
            m.load(p)
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.name).font(.body.weight(.semibold))
                    Text(p.subtitle.isEmpty ? p.settings.summary : "\(p.subtitle) · \(Int(p.settings.bpm)) BPM")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if m.activePresetID == p.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.strongColor) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
