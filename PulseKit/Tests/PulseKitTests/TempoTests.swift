import XCTest
@testable import PulseKit

final class TempoTests: XCTestCase {
    func testTempoMarkings() {
        XCTAssertEqual(TempoMarking.name(forBPM: 50), "Largo")
        XCTAssertEqual(TempoMarking.name(forBPM: 72), "Adagio")
        XCTAssertEqual(TempoMarking.name(forBPM: 100), "Andante")
        XCTAssertEqual(TempoMarking.name(forBPM: 120), "Allegro")
        XCTAssertEqual(TempoMarking.name(forBPM: 140), "Allegro")
        XCTAssertEqual(TempoMarking.name(forBPM: 168), "Vivace")
        XCTAssertEqual(TempoMarking.name(forBPM: 190), "Presto")
        XCTAssertEqual(TempoMarking.name(forBPM: 300), "Prestissimo")
        XCTAssertEqual(TempoMarking.name(forBPM: 20), "Larghissimo")
        // dotted quarter at 60 is 90 quarter-notes per minute
        XCTAssertEqual(TempoMarking.name(forBPM: 60, unit: .dottedQuarter), "Andante")
        // eighth at 120 is 60 quarters per minute
        XCTAssertEqual(TempoMarking.name(forBPM: 120, unit: .eighth), "Larghetto")
    }

    func testTapTempoSteady() {
        var t = TapTempo()
        XCTAssertNil(t.tap(at: 10.0))
        XCTAssertEqual(t.tap(at: 10.5)!, 120, accuracy: 0.001)
        XCTAssertEqual(t.tap(at: 11.0)!, 120, accuracy: 0.001)
        XCTAssertEqual(t.tap(at: 11.5)!, 120, accuracy: 0.001)
    }

    func testTapTempoAveragesJitter() {
        var t = TapTempo()
        var last: Double?
        for (i, jitter) in [0.0, 0.02, -0.015, 0.01, -0.02, 0.0].enumerated() {
            last = t.tap(at: Double(i) * 0.6 + jitter)
        }
        XCTAssertEqual(last!, 100, accuracy: 3)
    }

    func testTapTempoResetsAfterPause() {
        var t = TapTempo()
        t.tap(at: 0); t.tap(at: 0.5)
        XCTAssertNil(t.tap(at: 10.0), "a long pause starts a new measurement")
        XCTAssertEqual(t.tap(at: 10.75)!, 80, accuracy: 0.01)
    }

    func testTapTempoClamps() {
        var t = TapTempo()
        t.tap(at: 0)
        XCTAssertEqual(t.tap(at: 0.01)!, 400)
        t.reset()
        t.tap(at: 0)
        XCTAssertEqual(t.tap(at: 1.9)!, 31.6, accuracy: 0.1)
    }

    func testTapTempoWindow() {
        var t = TapTempo()
        t.window = 4
        for i in 0..<10 { t.tap(at: Double(i) * 0.5) }
        XCTAssertEqual(t.taps.count, 4)
    }
}
