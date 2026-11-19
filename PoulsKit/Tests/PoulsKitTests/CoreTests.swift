import XCTest
@testable import PoulsKit

final class CoreTests: XCTestCase {
    let sr = 48_000.0

    /// Runs the core offline and collects every slot it fires.
    func run(_ s: MetronomeSettings, seconds: Double, sampleRate: Double = 48_000,
             setup: ((MetronomeCore) -> Void)? = nil) -> (records: [TriggerRecord], audio: [Float], core: MetronomeCore) {
        let core = MetronomeCore(sampleRate: sampleRate, settings: s)
        var records: [TriggerRecord] = []
        core.observer = { records.append($0) }
        setup?(core)
        core.start()
        let audio = core.renderOffline(seconds: seconds)
        return (records, audio, core)
    }

    var lead: Double { MetronomeCore.startLead * sr }

    func pulses(_ r: [TriggerRecord]) -> [TriggerRecord] { r.filter { $0.kind == .pulse } }

    // MARK: Timing

    func testFourFourAt120IsExactlyHalfSecondApart() {
        let r = run(.make(bpm: 120, numerator: 4, denominator: 4), seconds: 4.1).records
        let p = pulses(r)
        XCTAssertEqual(p.count, 9)
        for (i, e) in p.enumerated() {
            XCTAssertEqual(e.sample, lead + Double(i) * 24_000, accuracy: 1e-6)
            XCTAssertEqual(e.pulse, i % 4)
        }
        XCTAssertEqual(p[0].sound, .clickHigh)
        XCTAssertEqual(p[1].sound, .clickMid)
        XCTAssertEqual(p[4].sound, .clickHigh)
    }

    func testNoDriftOverTenMinutes() {
        // 137.3 BPM does not divide the sample rate evenly; fractional timing must not accumulate error.
        let bpm = 137.3
        let r = run(.make(bpm: bpm, numerator: 4, denominator: 4), seconds: 600, blockSize512: true).records
        let p = pulses(r)
        let expectedCount = Int((600 - MetronomeCore.startLead) * bpm / 60) + 1
        XCTAssertEqual(p.count, expectedCount, accuracy: 1)
        let last = p.last!
        let expected = lead + Double(p.count - 1) * 60.0 * sr / bpm
        XCTAssertEqual(last.sample, expected, accuracy: 1e-3, "no accumulated drift")
    }

    func testRenderedClickLandsOnTheExactSample() {
        let (records, audio, _) = run(.make(bpm: 120, numerator: 4, denominator: 4), seconds: 1.2)
        let p = pulses(records)
        for e in p {
            let idx = Int(e.sample.rounded(.up))
            guard idx < audio.count else { continue }
            let before = abs(audio[idx - 1])
            let at = abs(audio[idx])
            XCTAssertLessThan(before, 1e-4, "silence just before the click at \(idx)")
            XCTAssertGreaterThanOrEqual(at, 0)   // attack ramp starts at zero
            let window = audio[idx..<min(idx + 200, audio.count)].map { abs($0) }.max()!
            XCTAssertGreaterThan(window, 0.05, "click is audible at \(idx)")
        }
    }

    func testBufferSizeDoesNotChangeTiming() {
        let s = MetronomeSettings.make(bpm: 173, numerator: 7, denominator: 8, grouping: [2, 2, 3], subdivision: .triplets)
        var reference: [Double] = []
        for block in [64, 256, 512, 1024, 4096, 333] {
            let core = MetronomeCore(sampleRate: sr, settings: s)
            var times: [Double] = []
            core.observer = { times.append($0.sample) }
            core.start()
            _ = core.renderOffline(seconds: 5, blockSize: block)
            if reference.isEmpty { reference = times } else { XCTAssertEqual(times, reference, "block \(block)") }
        }
        XCTAssertGreaterThan(reference.count, 40)
    }

    func testWorksAtOtherSampleRates() {
        for rate in [44_100.0, 48_000, 96_000] {
            let p = pulses(run(.make(bpm: 90, numerator: 3, denominator: 4), seconds: 3, sampleRate: rate).records)
            let spacing = p[1].sample - p[0].sample
            XCTAssertEqual(spacing, rate * 60 / 90, accuracy: 1e-6)
        }
    }

    // MARK: Meters

    func testSevenEightGroupsAndAccents() {
        var s = MetronomeSettings.make(bpm: 240, numerator: 7, denominator: 8, grouping: [2, 2, 3])
        s.sounds = SoundKit.classic.selection
        let p = pulses(run(s, seconds: 2).records)
        // 240 eighths per minute = 0.25 s per pulse
        XCTAssertEqual(p[1].sample - p[0].sample, 12_000, accuracy: 1e-6)
        let expected: [SoundID] = [.clickHigh, .clickLow, .clickMid, .clickLow, .clickMid, .clickLow, .clickLow]
        XCTAssertEqual(p.prefix(7).compactMap(\.sound), expected)
        XCTAssertEqual(p[7].pulse, 0, "bar wraps after seven pulses")
        XCTAssertEqual(p[7].sound, .clickHigh)
        XCTAssertEqual(p[7].sample - p[0].sample, 7 * 12_000, accuracy: 1e-6)
    }

    func testCompoundSixEightUsesDottedQuarterBeat() {
        // dotted quarter = 60 → 2 s per bar of six
        let p = pulses(run(.make(bpm: 60, numerator: 6, denominator: 8), seconds: 4.5).records)
        XCTAssertEqual(p[6].sample - p[0].sample, 2 * sr, accuracy: 1e-6)
        XCTAssertEqual(p[1].sample - p[0].sample, sr / 3, accuracy: 1e-6)
    }

    func testSilentAccentMakesNoSound() {
        var s = MetronomeSettings.make(bpm: 120, numerator: 4, denominator: 4)
        s.bars[0].meter.setAccent(2, .off)
        let (rec, audio, _) = run(s, seconds: 2.1)
        let p = pulses(rec)
        XCTAssertNil(p[2].sound)
        XCTAssertNotNil(p[3].sound)
        let at = Int(p[2].sample)
        XCTAssertLessThan(audio[at..<(at + 2000)].map { abs($0) }.max()!, 0.02, "silent slot stays silent (ring-out of the previous click aside)")
    }

    func testMixedMeterSequenceAdvancesThroughBars() {
        var s = MetronomeSettings.make(bpm: 120, numerator: 3, denominator: 4)
        s.bars = [
            BarSpec(meter: Meter(numerator: 3, denominator: 4), repeats: 2),
            BarSpec(meter: Meter(numerator: 5, denominator: 4)),
        ]
        let p = pulses(run(s, seconds: 12).records)
        let counts = p.prefix(11 + 11).map { "\($0.pulse)" }.joined(separator: ",")
        XCTAssertTrue(counts.hasPrefix("0,1,2,0,1,2,0,1,2,3,4,0,1,2,0,1,2,0,1,2,3,4"), counts)
        XCTAssertEqual(p[6].numerator, 5)
    }

    func testMixedDenominatorsKeepEighthNoteConstant() {
        // 7/8 then 4/4 with the beat unit fixed to eighths: each eighth should last the same.
        var s = MetronomeSettings.make(bpm: 240, numerator: 7, denominator: 8, grouping: [2, 2, 3], unit: .eighth)
        s.bars.append(BarSpec(meter: Meter(numerator: 4, denominator: 4)))
        let p = pulses(run(s, seconds: 4).records)
        let seven = p[1].sample - p[0].sample          // an eighth
        let quarter = p[8].sample - p[7].sample        // a quarter, in the 4/4 bar
        XCTAssertEqual(seven, 12_000, accuracy: 1e-6)
        XCTAssertEqual(quarter, 24_000, accuracy: 1e-6)
    }

    // MARK: Subdivisions

    func testEighthsLandHalfwayBetweenPulses() {
        let s = MetronomeSettings.make(bpm: 120, numerator: 4, denominator: 4, subdivision: .eighths)
        let r = run(s, seconds: 2.2).records
        let subs = r.filter { $0.kind == .sub }
        XCTAssertEqual(subs.count, 4)
        XCTAssertEqual(subs[0].sample, lead + 12_000, accuracy: 1e-6)
        XCTAssertEqual(subs[0].sound, .tick)
        XCTAssertEqual(subs[0].sub, 1)
    }

    func testTripletsAndSixteenthsSpacing() {
        for (sub, n) in [(Subdivision.triplets, 3), (.sixteenths, 4), (.quintuplets, 5), (.septuplets, 7)] {
            let s = MetronomeSettings.make(bpm: 60, numerator: 2, denominator: 4, subdivision: sub)
            let r = run(s, seconds: 2.05).records
            let slots = r.prefix(n * 2)
            for (i, e) in slots.enumerated() {
                XCTAssertEqual(e.sample, lead + Double(i) * sr / Double(n), accuracy: 1e-6, "\(n) per pulse, slot \(i)")
            }
        }
    }

    func testSwingPlacesSecondEighthLate() {
        let s = MetronomeSettings.make(bpm: 60, numerator: 4, denominator: 4, subdivision: .swing)
        let subs = run(s, seconds: 3).records.filter { $0.kind == .sub }
        XCTAssertEqual(subs[0].sample, lead + sr * 2.0 / 3.0, accuracy: 1e-6)
    }

    func testOffBeatOnlyMutesThePulse() {
        let s = MetronomeSettings.make(bpm: 120, numerator: 4, denominator: 4, subdivision: .offBeat)
        let r = run(s, seconds: 2.2).records
        XCTAssertTrue(pulses(r).allSatisfy { $0.sound == nil })
        XCTAssertTrue(r.filter { $0.kind == .sub }.allSatisfy { $0.sound == .tick })
    }

    func testMaskedSubdivisionSkipsSlots() {
        let s = MetronomeSettings.make(bpm: 60, numerator: 1, denominator: 4, subdivision: .gallop)
        let r = run(s, seconds: 1.05).records
        // gallop = [on, off, on, on]
        XCTAssertEqual(r.prefix(4).map { $0.sound != nil }, [true, false, true, true])
    }

    // MARK: Count-in, gap click, trainer, polyrhythm

    func testCountInPlaysBeforeTheBars() {
        var s = MetronomeSettings.make(bpm: 120, numerator: 4, denominator: 4, subdivision: .eighths)
        s.countInBars = 2
        let r = run(s, seconds: 7).records
        let p = pulses(r)
        XCTAssertTrue(p.prefix(8).allSatisfy { $0.countIn })
        XCTAssertFalse(p[8].countIn)
        XCTAssertEqual(p[8].pulse, 0)
        XCTAssertEqual(p[8].bar, 0)
        XCTAssertEqual(r.prefix(8).filter { $0.kind == .sub }.count, 0, "no subdivisions during the count-in")
        XCTAssertEqual(p[9].bar, 0)
        XCTAssertEqual(p[12].bar, 1)
    }

    func testGapClickSilencesTheRightBars() {
        var s = MetronomeSettings.make(bpm: 240, numerator: 2, denominator: 4)
        s.gap = GapClick(enabled: true, playBars: 2, muteBars: 1)
        let p = pulses(run(s, seconds: 6).records)
        // 2 pulses per bar: bars 0,1 audible, bar 2 silent, 3,4 audible, 5 silent
        let pattern = p.prefix(12).map { $0.sound == nil ? "·" : "x" }.joined()
        XCTAssertEqual(pattern, "xxxx··xxxx··")
        XCTAssertTrue(p[4].muted)
    }

    func testSpeedTrainerRampsAndStopsAtTarget() {
        var s = MetronomeSettings.make(bpm: 100, numerator: 2, denominator: 4)
        s.trainer = SpeedTrainer(enabled: true, targetBPM: 112, stepBPM: 4, everyBars: 2)
        let p = pulses(run(s, seconds: 25).records)
        let tempos = p.map { $0.bpm }
        XCTAssertEqual(tempos[0], 100)
        XCTAssertEqual(tempos[3], 100)
        XCTAssertEqual(tempos[4], 104)  // after 2 bars (4 pulses)
        XCTAssertEqual(tempos[8], 108)
        XCTAssertEqual(tempos[12], 112)
        XCTAssertEqual(tempos.last!, 112, "holds at target")
        XCTAssertEqual(tempos.max()!, 112)
        // pulse spacing follows the ramp exactly
        XCTAssertEqual(p[5].sample - p[4].sample, sr * 60 / 104, accuracy: 1e-6)
    }

    func testSpeedTrainerCanSlowDown() {
        var s = MetronomeSettings.make(bpm: 120, numerator: 2, denominator: 4)
        s.trainer = SpeedTrainer(enabled: true, targetBPM: 100, stepBPM: 10, everyBars: 1)
        let tempos = pulses(run(s, seconds: 12).records).map(\.bpm)
        XCTAssertEqual(Array(tempos.prefix(6)), [120, 120, 110, 110, 100, 100])
        XCTAssertEqual(tempos.last!, 100)
    }

    func testPolyrhythmThreeAgainstFour() {
        var s = MetronomeSettings.make(bpm: 120, numerator: 4, denominator: 4)
        s.poly = PolyLayer(enabled: true, clicks: 3, sound: .cowbellLow)
        let r = run(s, seconds: 4.1).records
        let poly = r.filter { $0.kind == .poly }
        XCTAssertGreaterThanOrEqual(poly.count, 6)
        let bar = 4 * 24_000.0
        XCTAssertEqual(poly[0].sample, lead, accuracy: 1e-6)
        XCTAssertEqual(poly[1].sample, lead + bar / 3, accuracy: 1e-6)
        XCTAssertEqual(poly[2].sample, lead + 2 * bar / 3, accuracy: 1e-6)
        XCTAssertEqual(poly[3].sample, lead + bar, accuracy: 1e-6)
        XCTAssertTrue(poly.allSatisfy { $0.sound == .cowbellLow })
    }

    // MARK: Live changes

    func testTempoChangeAppliesAtNextPulse() {
        let s = MetronomeSettings.make(bpm: 120, numerator: 4, denominator: 4)
        let core = MetronomeCore(sampleRate: sr, settings: s)
        var times: [Double] = []
        core.observer = { if $0.kind == .pulse { times.append($0.sample) } }
        core.start()
        _ = core.renderOffline(seconds: 1.2)
        var fast = s
        fast.setBPM(240)
        core.apply(fast)
        _ = core.renderOffline(seconds: 2)
        let gaps = zip(times.dropFirst(), times).map { $0 - $1 }
        XCTAssertEqual(gaps.first!, 24_000, accuracy: 1e-6)
        XCTAssertEqual(gaps.last!, 12_000, accuracy: 1e-6)
        // phase is continuous: the beat after the change starts when the previous one ends
        for (i, g) in gaps.enumerated() { XCTAssertTrue(g == 24_000 || g == 12_000, "gap \(i) = \(g)") }
    }

    func testAccentEditDoesNotRestartTheBar() {
        var s = MetronomeSettings.make(bpm: 240, numerator: 4, denominator: 4)
        let core = MetronomeCore(sampleRate: sr, settings: s)
        var pulseNumbers: [Int] = []
        core.observer = { if $0.kind == .pulse { pulseNumbers.append($0.pulse) } }
        core.start()
        _ = core.renderOffline(seconds: 0.6)
        s.bars[0].meter.setAccent(3, .strong)
        core.apply(s)
        _ = core.renderOffline(seconds: 1.5)
        for (i, n) in pulseNumbers.enumerated() { XCTAssertEqual(n, i % 4) }
    }

    func testMeterChangeRestartsBarAfterTheScheduledPulse() {
        var s = MetronomeSettings.make(bpm: 240, numerator: 5, denominator: 4)
        let core = MetronomeCore(sampleRate: sr, settings: s)
        var numbers: [Int] = []
        core.observer = { if $0.kind == .pulse { numbers.append($0.pulse) } }
        core.start()
        _ = core.renderOffline(seconds: 0.8)          // pulses 0 1 2 3 have fired; 4 is already scheduled
        XCTAssertEqual(numbers, [0, 1, 2, 3])
        s.setTimeSignature(numerator: 3, denominator: 4)
        core.apply(s)
        _ = core.renderOffline(seconds: 2.0)
        XCTAssertEqual(Array(numbers.prefix(10)), [0, 1, 2, 3, 4, 0, 1, 2, 0, 1], "restarts on the downbeat of the new meter")
    }

    func testShrinkingNumeratorMidBarNeverCrashes() {
        var s = MetronomeSettings.make(bpm: 400, numerator: 16, denominator: 8, subdivision: .sixteenths)
        let core = MetronomeCore(sampleRate: sr, settings: s)
        core.start()
        for n in [16, 3, 12, 2, 32, 1, 7] {
            _ = core.renderOffline(seconds: 0.13)
            s.setTimeSignature(numerator: n, denominator: 8)
            core.apply(s)
        }
        _ = core.renderOffline(seconds: 1)
    }

    func testStopSilencesAndRestartResets() {
        let s = MetronomeSettings.make(bpm: 120, numerator: 4, denominator: 4)
        let core = MetronomeCore(sampleRate: sr, settings: s)
        var rec: [TriggerRecord] = []
        core.observer = { rec.append($0) }
        core.start()
        _ = core.renderOffline(seconds: 1.3)
        core.stop()
        let n = rec.count
        _ = core.renderOffline(seconds: 2)
        XCTAssertEqual(rec.count, n, "nothing fires while stopped")
        XCTAssertFalse(core.snapshot().playing)
        core.start()
        _ = core.renderOffline(seconds: 0.5)
        XCTAssertEqual(rec.last?.pulse, 0, "restart begins on the downbeat")
        XCTAssertTrue(core.snapshot().playing)
    }

    func testPreviewMakesSoundWithoutPlaying() {
        let core = MetronomeCore(sampleRate: sr, settings: MetronomeSettings())
        core.preview(.woodHigh)
        let audio = core.renderOffline(seconds: 0.3)
        XCTAssertGreaterThan(audio.map { abs($0) }.max()!, 0.1)
        XCTAssertFalse(core.snapshot().playing)
    }

    // MARK: Output sanity

    func testOutputStaysFiniteAndBoundedUnderStress() {
        var s = MetronomeSettings.make(bpm: 400, numerator: 13, denominator: 16, subdivision: Subdivision(steps: 9))
        s.poly = PolyLayer(enabled: true, clicks: 11, sound: .kick, volume: 1)
        s.sounds = SoundSelection(strong: .kick, medium: .snare, soft: .hatOpen, sub: .cowbellHigh)
        s.volume = 1
        let audio = run(s, seconds: 20).audio
        XCTAssertTrue(audio.allSatisfy { $0.isFinite })
        XCTAssertLessThanOrEqual(audio.map { abs($0) }.max()!, 1.0)
        XCTAssertGreaterThan(audio.map { abs($0) }.max()!, 0.3)
    }

    func testSilentBeforeStartAndAfterTails() {
        let core = MetronomeCore(sampleRate: sr, settings: MetronomeSettings())
        let audio = core.renderOffline(seconds: 0.5)
        XCTAssertEqual(audio.map { abs($0) }.max()!, 0)
    }

    func testEverySoundIsAudibleNormalisedAndFinite() {
        for id in SoundID.allCases {
            let core = MetronomeCore(sampleRate: sr, settings: MetronomeSettings())
            core.preview(id, gain: 1)
            let audio = core.renderOffline(seconds: 1.5)
            let peak = audio.map { abs($0) }.max()!
            XCTAssertTrue(audio.allSatisfy { $0.isFinite }, id.rawValue)
            XCTAssertGreaterThan(peak, 0.15, "\(id.rawValue) too quiet: \(peak)")
            XCTAssertLessThanOrEqual(peak, 0.95, "\(id.rawValue) too loud: \(peak)")
            // decays to silence
            let tail = audio.suffix(2000).map { abs($0) }.max()!
            XCTAssertLessThan(tail, 0.01, "\(id.rawValue) rings too long")
        }
    }

    func testPitchShiftChangesFrequency() {
        func zeroCrossings(_ st: Double) -> Int {
            var s = MetronomeSettings()
            s.pitchSemitones = st
            let core = MetronomeCore(sampleRate: sr, settings: s)
            core.preview(.beepMid, gain: 1)
            let a = core.renderOffline(seconds: 0.08)
            var n = 0
            for i in 1..<a.count where (a[i - 1] < 0) != (a[i] < 0) { n += 1 }
            return n
        }
        let base = Double(zeroCrossings(0)), up = Double(zeroCrossings(12)), down = Double(zeroCrossings(-12))
        XCTAssertEqual(up / base, 2, accuracy: 0.15)
        XCTAssertEqual(down / base, 0.5, accuracy: 0.1)
    }

    func testVoiceStealingNeverOverflows() {
        // 40 near-simultaneous long sounds into 32 voices
        var s = MetronomeSettings.make(bpm: 400, numerator: 32, denominator: 32, subdivision: Subdivision(steps: 12))
        s.sounds = SoundSelection(strong: .chimeHigh, medium: .chime, soft: .triangle, sub: .hatOpen)
        let audio = run(s, seconds: 3).audio
        XCTAssertTrue(audio.allSatisfy { $0.isFinite })
    }

    // MARK: Published state

    func testSnapshotPublishesEventsAndClock() {
        let core = MetronomeCore(sampleRate: sr, settings: .make(bpm: 120, numerator: 4, denominator: 4))
        core.start()
        _ = core.renderOffline(seconds: 2.2)
        let snap = core.snapshot()
        XCTAssertTrue(snap.playing)
        XCTAssertEqual(snap.liveBPM, 120)
        XCTAssertGreaterThanOrEqual(snap.events.count, 4)
        for (a, b) in zip(snap.events, snap.events.dropFirst()) {
            XCTAssertEqual(b.index, a.index + 1)
            XCTAssertEqual(b.sample - a.sample, 24_000, accuracy: 1e-6)
        }
        XCTAssertEqual(snap.sampleRate, sr)
    }

    func testSnapshotRingKeepsOnlyRecentPulses() {
        let core = MetronomeCore(sampleRate: sr, settings: .make(bpm: 400, numerator: 4, denominator: 4))
        core.start()
        _ = core.renderOffline(seconds: 30)
        let snap = core.snapshot()
        XCTAssertEqual(snap.events.count, 32)
        XCTAssertEqual(snap.events.last!.index - snap.events.first!.index, 31)
    }
}

private extension CoreTests {
    func run(_ s: MetronomeSettings, seconds: Double, blockSize512: Bool) -> (records: [TriggerRecord], audio: [Float], core: MetronomeCore) {
        let core = MetronomeCore(sampleRate: 48_000, settings: s)
        var records: [TriggerRecord] = []
        core.observer = { if $0.kind == .pulse { records.append($0) } }
        core.start()
        let audio = core.renderOffline(seconds: seconds, blockSize: 4096)
        return (records, audio, core)
    }
}
