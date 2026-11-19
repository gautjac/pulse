import XCTest
import PoulsKit
@testable import Pouls

@MainActor
final class MetronomeTests: XCTestCase {
    private func makeModel(_ suite: String = UUID().uuidString) -> (Metronome, NullOutput, UserDefaults) {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let out = NullOutput()
        return (Metronome(output: out, defaults: defaults, systemIntegration: false), out, defaults)
    }

    func testTempoClampsAndNudges() {
        let (m, _, _) = makeModel()
        m.setBPM(500); XCTAssertEqual(m.settings.bpm, 400)
        m.setBPM(3); XCTAssertEqual(m.settings.bpm, 20)
        m.setBPM(100); m.nudge(5); XCTAssertEqual(m.settings.bpm, 105)
        m.nudge(-10); XCTAssertEqual(m.settings.bpm, 95)
        m.scaleBPM(by: 2); XCTAssertEqual(m.settings.bpm, 190)
        m.scaleBPM(by: 0.5); XCTAssertEqual(m.settings.bpm, 95)
    }

    func testEditsReachTheEngineAndPersist() {
        let (m, out, defaults) = makeModel()
        m.setBPM(133)
        XCTAssertEqual(out.applied.last?.bpm, 133)
        let reloaded = Metronome(output: NullOutput(), defaults: defaults, systemIntegration: false)
        XCTAssertEqual(reloaded.settings.bpm, 133)
    }

    func testNoOpEditDoesNotTouchEngine() {
        let (m, out, _) = makeModel()
        m.setBPM(100)
        XCTAssertTrue(out.applied.isEmpty)
    }

    func testStartStopAndFailure() {
        let (m, out, _) = makeModel()
        m.start()
        XCTAssertTrue(m.isPlaying)
        XCTAssertEqual(out.started.count, 1)
        m.toggle()
        XCTAssertFalse(m.isPlaying)
        XCTAssertEqual(out.stopCount, 1)
        out.failOnStart = true
        m.start()
        XCTAssertFalse(m.isPlaying)
        XCTAssertNotNil(m.lastError)
    }

    func testInterruptionStopsPlayback() {
        let (m, out, _) = makeModel()
        m.start()
        out.onInterruption?()
        XCTAssertFalse(m.isPlaying)
    }

    func testTimeSignatureAndAccentCycle() {
        let (m, _, _) = makeModel()
        m.setTimeSignature(numerator: 7, denominator: 8, grouping: [2, 2, 3])
        XCTAssertEqual(m.settings.firstMeter.grouping, [2, 2, 3])
        XCTAssertEqual(m.settings.effectiveBeatUnit, .eighth)
        let before = m.settings.firstMeter.accents[1]
        m.cycleAccent(bar: 0, pulse: 1)
        XCTAssertEqual(m.settings.firstMeter.accents[1], before.next)
        m.cycleAccent(bar: 9, pulse: 99)   // out of range is ignored
    }

    func testBeatUnitChangeKeepsAudibleTempo() {
        let (m, _, _) = makeModel()
        m.setTimeSignature(numerator: 4, denominator: 4)
        m.setBPM(120)
        let before = m.settings.pulseSeconds(for: m.settings.firstMeter)
        m.setBeatUnit(.eighth)               // counting eighths: the same speed is 240
        XCTAssertEqual(m.settings.bpm, 240)
        XCTAssertEqual(m.settings.pulseSeconds(for: m.settings.firstMeter), before, accuracy: 1e-9)
        m.setBeatUnit(nil)
        XCTAssertEqual(m.settings.bpm, 120)
    }

    func testPresetsLoadSaveDelete() {
        let (m, _, defaults) = makeModel()
        XCTAssertTrue(m.load(presetID: "builtin.seven-eight"))
        XCTAssertEqual(m.settings.firstMeter.numerator, 7)
        XCTAssertEqual(m.activePreset?.name, "7/8 · 2+2+3")
        m.setBPM(m.settings.bpm + 1)
        XCTAssertNil(m.activePresetID, "editing detaches from the preset")
        let saved = m.saveCurrentAsPreset(named: "  My groove ")
        XCTAssertEqual(saved.name, "My groove")
        XCTAssertEqual(m.userPresets.count, 1)
        let again = Metronome(output: NullOutput(), defaults: defaults, systemIntegration: false)
        XCTAssertEqual(again.userPresets.first?.name, "My groove")
        XCTAssertEqual(PresetStorage.allPresets(defaults: defaults).first?.name, "My groove")
        again.deletePreset(saved.id)
        XCTAssertTrue(again.userPresets.isEmpty)
        XCTAssertFalse(m.load(presetID: "nope"))
    }

    func testLoadingPresetKeepsVolume() {
        let (m, _, _) = makeModel()
        m.commit { $0.volume = 0.3 }
        _ = m.load(presetID: "builtin.waltz")
        XCTAssertEqual(m.settings.volume, 0.3)
    }

    func testTurningTrainerOffHoldsReachedTempo() {
        let (m, _, _) = makeModel()
        m.commit { $0.trainer = SpeedTrainer(enabled: true, targetBPM: 160, stepBPM: 5, everyBars: 1) }
        m.start()
        m.commit { $0.trainer.enabled = false }
        XCTAssertEqual(m.settings.bpm, 100)   // NullOutput never ramps, so the held tempo is the start tempo
    }

    func testPrefsPersist() {
        let (m, _, defaults) = makeModel()
        m.prefs.themeID = "ocean"
        m.prefs.visualMode = .orbit
        let again = Metronome(output: NullOutput(), defaults: defaults, systemIntegration: false)
        XCTAssertEqual(again.prefs.theme.id, "ocean")
        XCTAssertEqual(again.prefs.visualMode, .orbit)
    }

    func testBarSequenceEditing() {
        let (m, _, _) = makeModel()
        m.commit { $0.bars.append(BarSpec(meter: Meter(numerator: 7, denominator: 8))) }
        XCTAssertTrue(m.settings.isMixedMeter)
        m.editBar = 1
        m.commit { $0.bars.removeLast() }
        XCTAssertEqual(m.editBar, 0, "edit index follows the shrinking sequence")
    }

    func testTapTempoSetsTempo() {
        let (m, _, _) = makeModel()
        m.tapTempo()
        XCTAssertEqual(m.tapCount, 1)
    }

    func testResetAll() {
        let (m, _, _) = makeModel()
        _ = m.load(presetID: "builtin.seven-eight")
        m.resetAll()
        XCTAssertEqual(m.settings.bpm, 100)
        XCTAssertEqual(m.settings.firstMeter.numerator, 4)
        XCTAssertNil(m.activePresetID)
    }
}
