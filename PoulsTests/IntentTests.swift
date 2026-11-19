import XCTest
import AppIntents
import PoulsKit
@testable import Pouls

/// Intents act on `Metronome.shared`, so these tests drive the real singleton and restore it afterwards.
@MainActor
final class IntentTests: XCTestCase {
    private var saved: MetronomeSettings!

    override func setUp() async throws {
        saved = Metronome.shared.settings
        Metronome.shared.stop()
        Metronome.shared.commit { $0 = MetronomeSettings() }
    }

    override func tearDown() async throws {
        Metronome.shared.stop()
        Metronome.shared.commit { $0 = self.saved }
    }

    func testSetTempo() async throws {
        var i = SetTempoIntent(); i.tempo = 132
        _ = try await i.perform()
        XCTAssertEqual(Metronome.shared.settings.bpm, 132)
    }

    func testSpeedUpAndSlowDown() async throws {
        Metronome.shared.setBPM(100)
        var up = SpeedUpIntent(); up.amount = 8
        _ = try await up.perform()
        XCTAssertEqual(Metronome.shared.settings.bpm, 108)
        var down = SlowDownIntent(); down.amount = 3
        _ = try await down.perform()
        XCTAssertEqual(Metronome.shared.settings.bpm, 105)
    }

    func testChangeTempoByPercent() async throws {
        Metronome.shared.setBPM(100)
        var i = ChangeTempoIntent(); i.direction = .slower; i.amount = 10; i.unit = .percent
        _ = try await i.perform()
        XCTAssertEqual(Metronome.shared.settings.bpm, 90)
    }

    func testScaleTempo() async throws {
        Metronome.shared.setBPM(90)
        var i = ScaleTempoIntent(); i.scale = .double
        _ = try await i.perform()
        XCTAssertEqual(Metronome.shared.settings.bpm, 180)
        i.scale = .half
        _ = try await i.perform()
        XCTAssertEqual(Metronome.shared.settings.bpm, 90)
    }

    func testTimeSignatures() async throws {
        var i = SetTimeSignatureIntent(); i.signature = .sevenEight
        _ = try await i.perform()
        let m = Metronome.shared.settings.firstMeter
        XCTAssertEqual(m.numerator, 7); XCTAssertEqual(m.denominator, 8); XCTAssertEqual(m.grouping, [2, 2, 3])
        for option in [TimeSignatureOption.twoFour, .threeFour, .fourFour, .fiveFour, .sixFour, .sevenFour, .twoTwo, .threeEight, .fiveEight, .sixEight, .sevenEight, .nineEight, .tenEight, .elevenEight, .twelveEight, .thirteenEight, .fifteenSixteen] {
            var x = SetTimeSignatureIntent(); x.signature = option
            _ = try await x.perform()
            XCTAssertEqual(Metronome.shared.settings.firstMeter.numerator, option.parts.numerator)
            XCTAssertEqual(Metronome.shared.settings.firstMeter.denominator, option.parts.denominator)
        }
    }

    func testCustomTimeSignatureWithGrouping() async throws {
        var i = SetCustomTimeSignatureIntent(); i.beats = 8; i.noteValue = .eighth; i.grouping = "3+3+2"
        _ = try await i.perform()
        XCTAssertEqual(Metronome.shared.settings.firstMeter.grouping, [3, 3, 2])
        i.grouping = "5+5"   // does not add up: falls back to the usual grouping
        _ = try await i.perform()
        XCTAssertEqual(Metronome.shared.settings.firstMeter.grouping, [3, 3, 2])
    }

    func testSubdivisionSoundVolumeAndCountIn() async throws {
        var s = SetSubdivisionIntent(); s.subdivision = .triplets
        _ = try await s.perform()
        XCTAssertEqual(Metronome.shared.settings.subdivision, .triplets)
        var k = SetSoundIntent(); k.sound = .wood
        _ = try await k.perform()
        XCTAssertEqual(Metronome.shared.settings.sounds.matchingKit, .wood)
        var v = SetVolumeIntent(); v.percent = 40
        _ = try await v.perform()
        XCTAssertEqual(Metronome.shared.settings.volume, 0.4, accuracy: 1e-9)
        var c = SetCountInIntent(); c.bars = 2
        _ = try await c.perform()
        XCTAssertEqual(Metronome.shared.settings.countInBars, 2)
    }

    func testPolyrhythm() async throws {
        var p = SetPolyrhythmIntent(); p.clicks = 5; p.enabled = true
        _ = try await p.perform()
        XCTAssertTrue(Metronome.shared.settings.poly.enabled)
        XCTAssertEqual(Metronome.shared.settings.poly.clicks, 5)
        p.enabled = false
        _ = try await p.perform()
        XCTAssertFalse(Metronome.shared.settings.poly.enabled)
    }

    func testSpeedTrainerIntent() async throws {
        var t = StartSpeedTrainerIntent(); t.from = 80; t.to = 120; t.step = 5; t.everyBars = 2
        _ = try await t.perform()
        let s = Metronome.shared.settings
        XCTAssertEqual(s.bpm, 80)
        XCTAssertTrue(s.trainer.enabled)
        XCTAssertEqual(s.trainer.targetBPM, 120)
        XCTAssertEqual(s.trainer.stepBPM, 5)
        XCTAssertEqual(s.trainer.everyBars, 2)
        Metronome.shared.stop()
        _ = try await StopSpeedTrainerIntent().perform()
        XCTAssertFalse(Metronome.shared.settings.trainer.enabled)
    }

    func testPresetEntityAndIntent() async throws {
        let all = try await PresetQuery().suggestedEntities()
        XCTAssertGreaterThan(all.count, 25)
        let hits = try await PresetQuery().entities(matching: "waltz")
        XCTAssertEqual(hits.first?.id, "builtin.waltz")
        let byID = try await PresetQuery().entities(for: ["builtin.waltz", "missing"])
        XCTAssertEqual(byID.count, 1)
        var l = LoadPresetIntent(); l.preset = hits[0]
        _ = try await l.perform()
        XCTAssertEqual(Metronome.shared.settings.firstMeter.numerator, 3)
    }

    func testGetTempoReturnsValue() async throws {
        Metronome.shared.setBPM(121)
        let result = try await GetTempoIntent().perform()
        XCTAssertEqual(result.value, 121)
    }

    func testVisualModeIntent() async throws {
        var i = SetVisualModeIntent(); i.mode = .orbit
        _ = try await i.perform()
        XCTAssertEqual(Metronome.shared.prefs.visualMode, .orbit)
        Metronome.shared.prefs.visualMode = .pendulum
    }

    func testEveryOptionMapsToSomething() {
        for o in SubdivisionOption.allCases { XCTAssertGreaterThanOrEqual(o.subdivision.steps, 1) }
        for o in SoundKitOption.allCases { XCTAssertEqual(o.kit.rawValue, o.rawValue) }
        XCTAssertEqual(TempoScale.twoThirds.factor, 2.0 / 3.0, accuracy: 1e-12)
    }

    func testShortcutsProviderStaysWithinAppleLimit() {
        XCTAssertLessThanOrEqual(PoulsShortcuts.appShortcuts.count, 10)
    }
}
