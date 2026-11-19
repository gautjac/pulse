import SwiftUI
import PoulsKit

struct PracticeSheet: View {
    @Environment(Metronome.self) private var m

    var body: some View {
        let s = m.settings
        SheetScaffold(title: "Practice") {
            List {
                Section {
                    Picker("Count-in", selection: Binding(get: { s.countInBars }, set: { v in m.commit { $0.countInBars = v } })) {
                        Text("Off").tag(0)
                        Text("1 bar").tag(1)
                        Text("2 bars").tag(2)
                        Text("4 bars").tag(4)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Count-in")
                } footer: {
                    Text("Clicks only, one bar at a time, before the pattern starts.")
                }

                Section {
                    Toggle("Speed trainer", isOn: Binding(get: { s.trainer.enabled }, set: { v in m.commit { $0.trainer.enabled = v } }))
                    if s.trainer.enabled {
                        Stepper(value: Binding(get: { Int(s.trainer.targetBPM) }, set: { v in m.commit { $0.trainer = SpeedTrainer(enabled: true, targetBPM: Double(v), stepBPM: $0.trainer.stepBPM, everyBars: $0.trainer.everyBars) } }), in: 20...400, step: 5) {
                            HStack { Text("Target tempo"); Spacer(); Text("\(Int(s.trainer.targetBPM)) BPM").foregroundStyle(.secondary).monospacedDigit() }
                        }
                        Stepper(value: Binding(get: { Int(s.trainer.stepBPM) }, set: { v in m.commit { $0.trainer = SpeedTrainer(enabled: true, targetBPM: $0.trainer.targetBPM, stepBPM: Double(v), everyBars: $0.trainer.everyBars) } }), in: 1...50) {
                            HStack { Text("Change by"); Spacer(); Text("\(Int(s.trainer.stepBPM)) BPM").foregroundStyle(.secondary).monospacedDigit() }
                        }
                        Stepper(value: Binding(get: { s.trainer.everyBars }, set: { v in m.commit { $0.trainer = SpeedTrainer(enabled: true, targetBPM: $0.trainer.targetBPM, stepBPM: $0.trainer.stepBPM, everyBars: v) } }), in: 1...64) {
                            HStack { Text("Every"); Spacer(); Text("\(s.trainer.everyBars) bar\(s.trainer.everyBars == 1 ? "" : "s")").foregroundStyle(.secondary).monospacedDigit() }
                        }
                    }
                } header: {
                    Text("Speed trainer")
                } footer: {
                    Text(s.trainer.enabled ? trainerSummary(s) : "Starts at your tempo and nudges it toward a target, bar by bar, so you can build speed without touching the phone.")
                }

                Section {
                    Toggle("Gap click", isOn: Binding(get: { s.gap.enabled }, set: { v in m.commit { $0.gap.enabled = v } }))
                    if s.gap.enabled {
                        Stepper(value: Binding(get: { s.gap.playBars }, set: { v in m.commit { $0.gap = GapClick(enabled: true, playBars: v, muteBars: $0.gap.muteBars) } }), in: 1...32) {
                            HStack { Text("Click for"); Spacer(); Text("\(s.gap.playBars) bar\(s.gap.playBars == 1 ? "" : "s")").foregroundStyle(.secondary).monospacedDigit() }
                        }
                        Stepper(value: Binding(get: { s.gap.muteBars }, set: { v in m.commit { $0.gap = GapClick(enabled: true, playBars: $0.gap.playBars, muteBars: v) } }), in: 1...32) {
                            HStack { Text("Then silent for"); Spacer(); Text("\(s.gap.muteBars) bar\(s.gap.muteBars == 1 ? "" : "s")").foregroundStyle(.secondary).monospacedDigit() }
                        }
                    }
                } header: {
                    Text("Gap click")
                } footer: {
                    Text("Keeps time silently every so often. If you're still with the beat when it comes back, your inner clock is solid.")
                }
            }
        }
    }

    private func trainerSummary(_ s: MetronomeSettings) -> String {
        let t = s.trainer
        let dir = t.targetBPM >= s.bpm ? "up" : "down"
        return "\(Int(s.bpm)) → \(Int(t.targetBPM)) BPM, \(dir) \(Int(t.stepBPM)) every \(t.everyBars) bar\(t.everyBars == 1 ? "" : "s"). It holds at the target."
    }
}
