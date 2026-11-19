import XCTest
@testable import PoulsKit

final class PhaseTests: XCTestCase {
    func snapshot(bpm: Double = 120, seconds: Double = 3.3, numerator: Int = 4) -> CoreSnapshot {
        let core = MetronomeCore(sampleRate: 48_000, settings: .make(bpm: bpm, numerator: numerator, denominator: 4))
        core.start()
        _ = core.renderOffline(seconds: seconds, blockSize: 512)
        return core.snapshot()
    }

    func testIdleWhenStopped() {
        let core = MetronomeCore(sampleRate: 48_000, settings: MetronomeSettings())
        XCTAssertEqual(PlaybackPhase.compute(from: core.snapshot(), hostSecondsNow: 0), .idle)
    }

    func testPhaseAtKnownTimes() {
        let snap = snapshot()
        // renderOffline reports host seconds = frames/sr, so "now" is a time on that axis.
        let lead = MetronomeCore.startLead
        // 0.25 s into the second pulse (pulse index 1 starts at lead + 0.5)
        let p = PlaybackPhase.compute(from: snap, hostSecondsNow: lead + 0.5 + 0.25)
        XCTAssertEqual(p.pulseIndex, 1)
        XCTAssertEqual(p.pulse, 1)
        XCTAssertEqual(p.progress, 0.5, accuracy: 0.01)
        XCTAssertEqual(p.bpm, 120)
        XCTAssertEqual(p.pulseSeconds, 0.5, accuracy: 1e-9)
        XCTAssertEqual(p.barProgress, (1 + 0.5) / 4, accuracy: 0.01)
        XCTAssertEqual(p.accent, .medium)
    }

    func testDownbeatIsStrong() {
        let snap = snapshot()
        let p = PlaybackPhase.compute(from: snap, hostSecondsNow: MetronomeCore.startLead + 2.0 + 0.01)
        XCTAssertEqual(p.pulse, 0)
        XCTAssertEqual(p.accent, .strong)
        XCTAssertEqual(p.pulseIndex, 4)
    }

    func testBeforeFirstClickIsPrerollNotIdle() {
        let snap = snapshot()
        let p = PlaybackPhase.compute(from: snap, hostSecondsNow: 0.01)
        XCTAssertTrue(p.isPlaying)
        XCTAssertEqual(p.pulseIndex, -1)
    }

    func testLatencyShiftsVisualsLater() {
        let snap = snapshot()
        let now = MetronomeCore.startLead + 0.5 + 0.1
        let a = PlaybackPhase.compute(from: snap, hostSecondsNow: now)
        let b = PlaybackPhase.compute(from: snap, hostSecondsNow: now, latency: 0.2)
        XCTAssertEqual(a.pulseIndex, 1)
        XCTAssertEqual(b.pulseIndex, 0)
    }

    func testSubIndexMapping() {
        var p = PlaybackPhase.idle
        p.progress = 0.0; XCTAssertEqual(p.subIndex(for: .sixteenths), 0)
        p.progress = 0.3; XCTAssertEqual(p.subIndex(for: .sixteenths), 1)
        p.progress = 0.99; XCTAssertEqual(p.subIndex(for: .sixteenths), 3)
        p.progress = 0.6; XCTAssertEqual(p.subIndex(for: .triplets), 1)
        p.progress = 0.55; XCTAssertEqual(p.subIndex(for: .swing), 0, "swing's second eighth is late")
        p.progress = 0.7; XCTAssertEqual(p.subIndex(for: .swing), 1)
    }

    func testClampsWhenAudioRunsAheadOfEvents() {
        let snap = snapshot(seconds: 1.0)
        let p = PlaybackPhase.compute(from: snap, hostSecondsNow: 50)
        XCTAssertLessThan(p.progress, 1)
        XCTAssertGreaterThanOrEqual(p.progress, 0)
    }
}
