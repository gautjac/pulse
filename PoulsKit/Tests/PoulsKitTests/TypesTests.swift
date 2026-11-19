import XCTest
@testable import PoulsKit

final class TypesTests: XCTestCase {
    func testDefaultGroupings() {
        XCTAssertEqual(Meter.defaultGrouping(numerator: 4, denominator: 4), [1, 1, 1, 1])
        XCTAssertEqual(Meter.defaultGrouping(numerator: 6, denominator: 8), [3, 3])
        XCTAssertEqual(Meter.defaultGrouping(numerator: 12, denominator: 8), [3, 3, 3, 3])
        XCTAssertEqual(Meter.defaultGrouping(numerator: 7, denominator: 8), [2, 2, 3])
        XCTAssertEqual(Meter.defaultGrouping(numerator: 5, denominator: 8), [3, 2])
        XCTAssertEqual(Meter.defaultGrouping(numerator: 11, denominator: 8), [3, 3, 3, 2])
        XCTAssertEqual(Meter.defaultGrouping(numerator: 13, denominator: 8), [2, 2, 3, 3, 3])
        XCTAssertEqual(Meter.defaultGrouping(numerator: 10, denominator: 8), [2, 2, 3, 3])
        XCTAssertEqual(Meter.defaultGrouping(numerator: 5, denominator: 4), [3, 2])
        XCTAssertEqual(Meter.defaultGrouping(numerator: 7, denominator: 4), [4, 3])
        XCTAssertEqual(Meter.defaultGrouping(numerator: 4, denominator: 8), [2, 2])
    }

    func testEveryDefaultGroupingSumsToNumerator() {
        for d in Meter.validDenominators {
            for n in 1...Meter.maxNumerator {
                let g = Meter.defaultGrouping(numerator: n, denominator: d)
                XCTAssertEqual(g.reduce(0, +), n, "\(n)/\(d)")
                XCTAssertFalse(g.contains(where: { $0 < 1 }))
            }
        }
    }

    func testMeterNormalisesBadInput() {
        let m = Meter(numerator: 99, denominator: 7, grouping: [1, 1], accents: [.soft])
        XCTAssertEqual(m.numerator, 32)
        XCTAssertEqual(m.denominator, 4)
        XCTAssertEqual(m.grouping.reduce(0, +), 32)
        XCTAssertEqual(m.accents.count, 32)
        let z = Meter(numerator: 0, denominator: 4)
        XCTAssertEqual(z.numerator, 1)
    }

    func testDefaultAccents() {
        let m = Meter(numerator: 7, denominator: 8, grouping: [2, 2, 3])
        XCTAssertEqual(m.accents, [.strong, .soft, .medium, .soft, .medium, .soft, .soft])
        let four = Meter(numerator: 4, denominator: 4)
        XCTAssertEqual(four.accents, [.strong, .medium, .medium, .medium])
    }

    func testCompoundAndSuggestedUnit() {
        XCTAssertTrue(Meter(numerator: 6, denominator: 8).isCompound)
        XCTAssertEqual(Meter(numerator: 6, denominator: 8).suggestedBeatUnit, .dottedQuarter)
        XCTAssertEqual(Meter(numerator: 12, denominator: 8).suggestedBeatUnit, .dottedQuarter)
        XCTAssertFalse(Meter(numerator: 7, denominator: 8).isCompound)
        XCTAssertEqual(Meter(numerator: 7, denominator: 8).suggestedBeatUnit, .eighth)
        XCTAssertEqual(Meter(numerator: 4, denominator: 4).suggestedBeatUnit, .quarter)
        XCTAssertEqual(Meter(numerator: 2, denominator: 2).suggestedBeatUnit, .half)
        XCTAssertEqual(Meter(numerator: 9, denominator: 16).suggestedBeatUnit, .dottedEighth)
        XCTAssertTrue(Meter(numerator: 7, denominator: 8).isAsymmetric)
        XCTAssertFalse(Meter(numerator: 6, denominator: 8).isAsymmetric)
    }

    func testGroupingParsing() {
        XCTAssertEqual(Meter.parseGrouping("3+3+2", numerator: 8), [3, 3, 2])
        XCTAssertEqual(Meter.parseGrouping("2 2 3", numerator: 7), [2, 2, 3])
        XCTAssertEqual(Meter.parseGrouping("2,2,3", numerator: 7), [2, 2, 3])
        XCTAssertNil(Meter.parseGrouping("3+3", numerator: 8))
        XCTAssertNil(Meter.parseGrouping("", numerator: 4))
        XCTAssertNil(Meter.parseGrouping("0+4", numerator: 4))
    }

    func testMeterParsing() {
        XCTAssertEqual(Meter.parse("7/8")?.numerator, 7)
        XCTAssertEqual(Meter.parse("7/8 2+2+3")?.grouping, [2, 2, 3])
        XCTAssertEqual(Meter.parse("5/4 (3+2)")?.grouping, [3, 2])
        XCTAssertNil(Meter.parse("7/7"))
        XCTAssertNil(Meter.parse("hello"))
        XCTAssertEqual(Meter.parse("7/8 9")?.grouping, [2, 2, 3], "bad grouping falls back to default")
    }

    func testSetGroupingResetsAccents() {
        var m = Meter(numerator: 8, denominator: 8)
        XCTAssertTrue(m.setGrouping([3, 3, 2]))
        XCTAssertEqual(m.accents, [.strong, .soft, .soft, .medium, .soft, .soft, .medium, .soft])
        XCTAssertFalse(m.setGrouping([3, 3]))
        XCTAssertEqual(m.grouping, [3, 3, 2])
    }

    func testAccentCycle() {
        XCTAssertEqual(AccentLevel.off.next, .soft)
        XCTAssertEqual(AccentLevel.soft.next, .medium)
        XCTAssertEqual(AccentLevel.medium.next, .strong)
        XCTAssertEqual(AccentLevel.strong.next, .off)
        XCTAssertTrue(AccentLevel.strong > AccentLevel.soft)
    }

    func testGroupInfo() {
        let m = Meter(numerator: 7, denominator: 8, grouping: [2, 2, 3])
        XCTAssertEqual(m.groupInfo(forPulse: 0).group, 0)
        XCTAssertTrue(m.groupInfo(forPulse: 0).isStart)
        XCTAssertFalse(m.groupInfo(forPulse: 1).isStart)
        XCTAssertEqual(m.groupInfo(forPulse: 4).group, 2)
        XCTAssertTrue(m.groupInfo(forPulse: 4).isStart)
        XCTAssertEqual(m.groupInfo(forPulse: 6).group, 2)
    }

    func testCountNumbers() {
        let seven = Meter(numerator: 7, denominator: 8, grouping: [2, 2, 3])
        XCTAssertEqual((0..<7).map { seven.countNumber(forPulse: $0) }, [1, 2, 1, 2, 1, 2, 3])
        let four = Meter(numerator: 4, denominator: 4)
        XCTAssertEqual((0..<4).map { four.countNumber(forPulse: $0) }, [1, 2, 3, 4])
        let six = Meter(numerator: 6, denominator: 8)
        XCTAssertEqual((0..<6).map { six.countNumber(forPulse: $0) }, [1, 2, 3, 1, 2, 3])
    }

    func testSubdivisionBasics() {
        XCTAssertTrue(Subdivision.none.isNone)
        XCTAssertEqual(Subdivision.triplets.offset(ofStep: 1), 1.0 / 3.0, accuracy: 1e-12)
        XCTAssertEqual(Subdivision.swing.offset(ofStep: 1), 2.0 / 3.0, accuracy: 1e-12)
        XCTAssertEqual(Subdivision.eighths.offset(ofStep: 1), 0.5, accuracy: 1e-12)
        XCTAssertEqual(Subdivision.sixteenths.offset(ofStep: 3), 0.75, accuracy: 1e-12)
        XCTAssertEqual(Subdivision.gallop.mask, [true, false, true, true])
        XCTAssertFalse(Subdivision.offBeat.playsPulse)
        XCTAssertEqual(Subdivision.swing.name, "Swing eighths")
        XCTAssertEqual(Subdivision(steps: 5, mask: [true, true, false, true, true]).name, "Custom ×5")
    }

    func testSubdivisionClampsAndKeepsMask() {
        var s = Subdivision(steps: 99)
        XCTAssertEqual(s.steps, Subdivision.maxSteps)
        s = Subdivision(steps: 4, mask: [false, false, true, false])
        XCTAssertTrue(s.mask[0], "slot 0 is always on")
        s.setSteps(6)
        XCTAssertEqual(s.mask, [true, false, true, false, true, true])
        s.setSteps(2)
        XCTAssertEqual(s.mask, [true, false])
    }

    func testBeatUnitQuarters() {
        XCTAssertEqual(BeatUnit.dottedQuarter.quarters, 1.5)
        XCTAssertEqual(BeatUnit.eighth.quarters, 0.5)
        XCTAssertEqual(BeatUnit.matching(denominator: 8), .eighth)
        for u in BeatUnit.allCases { XCTAssertGreaterThan(u.quarters, 0) }
    }

    func testBarSpecShape() {
        let a = BarSpec(meter: Meter(numerator: 7, denominator: 8))
        var b = a.duplicated()
        XCTAssertNotEqual(a.id, b.id)
        XCTAssertTrue(a.sameShape(as: b))
        b.meter.setAccent(0, .off)
        XCTAssertTrue(a.sameShape(as: b), "accent changes keep the shape")
        b.repeats = 2
        XCTAssertFalse(a.sameShape(as: b))
    }

    func testSettingsCodableRoundTrip() throws {
        var s = MetronomeSettings.make(bpm: 133, numerator: 7, denominator: 8, grouping: [2, 2, 3], subdivision: .swing, kit: .wood)
        s.poly = PolyLayer(enabled: true, clicks: 5)
        s.trainer = SpeedTrainer(enabled: true, targetBPM: 180, stepBPM: 3, everyBars: 2)
        s.gap = GapClick(enabled: true, playBars: 2, muteBars: 1)
        s.countInBars = 2
        s.bars.append(BarSpec(meter: Meter(numerator: 4, denominator: 4), repeats: 3))
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(MetronomeSettings.self, from: data)
        XCTAssertEqual(s, back)
    }

    func testSettingsDecodeToleratesMissingAndDamagedFields() throws {
        let empty = try JSONDecoder().decode(MetronomeSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(empty.bpm, 100)
        XCTAssertEqual(empty.bars.count, 1)
        let damaged = Data(#"{"bpm": 9999, "bars":[{"meter":{"numerator":7,"denominator":8,"grouping":[1,1],"accents":[]}}], "countInBars": 99}"#.utf8)
        let s = try JSONDecoder().decode(MetronomeSettings.self, from: damaged)
        XCTAssertEqual(s.bpm, 400)
        XCTAssertEqual(s.bars[0].meter.grouping, [2, 2, 3])
        XCTAssertEqual(s.bars[0].meter.accents.count, 7)
        XCTAssertEqual(s.countInBars, 4)
    }

    func testTimingMaths() {
        let s = MetronomeSettings.make(bpm: 120, numerator: 4, denominator: 4)
        XCTAssertEqual(s.pulseSeconds(for: s.firstMeter), 0.5, accuracy: 1e-12)
        XCTAssertEqual(s.barSeconds(for: s.firstMeter), 2.0, accuracy: 1e-12)
        // 6/8 counted in dotted quarters at 60 → a bar every 2 seconds, 6 pulses of 1/3 s
        let c = MetronomeSettings.make(bpm: 60, numerator: 6, denominator: 8)
        XCTAssertEqual(c.effectiveBeatUnit, .dottedQuarter)
        XCTAssertEqual(c.pulseSeconds(for: c.firstMeter), 1.0 / 3.0, accuracy: 1e-12)
        XCTAssertEqual(c.barSeconds(for: c.firstMeter), 2.0, accuracy: 1e-12)
        // 7/8 counted in eighths at 240 → a pulse every 0.25 s
        let o = MetronomeSettings.make(bpm: 240, numerator: 7, denominator: 8)
        XCTAssertEqual(o.pulseSeconds(for: o.firstMeter), 0.25, accuracy: 1e-12)
        // override: 7/8 counted in quarters at 120 → eighth = 0.25 s
        var q = MetronomeSettings.make(bpm: 120, numerator: 7, denominator: 8)
        q.beatUnitOverride = .quarter
        XCTAssertEqual(q.pulseSeconds(for: q.firstMeter), 0.25, accuracy: 1e-12)
    }

    func testBPMClamp() {
        var s = MetronomeSettings()
        s.setBPM(5); XCTAssertEqual(s.bpm, 20)
        s.setBPM(999); XCTAssertEqual(s.bpm, 400)
        s.setBPM(.nan); XCTAssertEqual(s.bpm, 100)
        s.setBPM(.infinity); XCTAssertEqual(s.bpm, 100)
    }

    func testSummary() {
        var s = MetronomeSettings.make(bpm: 140, numerator: 7, denominator: 8, grouping: [2, 2, 3], subdivision: .triplets)
        XCTAssertEqual(s.summary, "140 BPM, 7/8 · 2+2+3, triplets")
        s.bars.append(BarSpec(meter: Meter(numerator: 4, denominator: 4)))
        XCTAssertEqual(s.summary, "140 BPM, 7/8 → 4/4, triplets")
    }

    func testKitsAreDistinctAndRecognised() {
        for kit in SoundKit.allCases { XCTAssertEqual(kit.selection.matchingKit, kit) }
        var custom = SoundKit.classic.selection
        custom.strong = .kick
        XCTAssertNil(custom.matchingKit)
    }

    func testPresetLibraryIsValid() {
        XCTAssertGreaterThan(PresetLibrary.all.count, 25)
        XCTAssertEqual(Set(PresetLibrary.all.map(\.id)).count, PresetLibrary.all.count, "ids unique")
        for p in PresetLibrary.all {
            XCTAssertTrue(p.isBuiltIn)
            for bar in p.settings.bars {
                XCTAssertEqual(bar.meter.grouping.reduce(0, +), bar.meter.numerator, p.name)
                XCTAssertEqual(bar.meter.accents.count, bar.meter.numerator, p.name)
            }
            XCTAssertTrue(MetronomeSettings.bpmRange.contains(p.settings.bpm), p.name)
        }
        XCTAssertNotNil(PresetLibrary.builtIn(id: "builtin.waltz"))
    }
}
