import Foundation

/// Italian tempo names.
public enum TempoMarking {
    private static let table: [(upTo: Double, name: String)] = [
        (24, "Larghissimo"), (40, "Grave"), (60, "Largo"), (66, "Larghetto"), (76, "Adagio"),
        (108, "Andante"), (120, "Moderato"), (156, "Allegro"), (176, "Vivace"), (200, "Presto"),
        (.infinity, "Prestissimo"),
    ]

    /// Name for a tempo, judged on quarter notes per minute (so ♩. = 60 reads as 90).
    public static func name(forBPM bpm: Double, unit: BeatUnit = .quarter) -> String {
        let quarterBPM = bpm * unit.quarters
        return table.first(where: { quarterBPM < $0.upTo })?.name ?? "Prestissimo"
    }

    /// Common landmark tempos, handy for quick-pick chips.
    public static let landmarks: [(name: String, bpm: Double)] = [
        ("Largo", 50), ("Adagio", 70), ("Andante", 92), ("Moderato", 114),
        ("Allegro", 138), ("Vivace", 168), ("Presto", 188),
    ]
}

/// Averages recent taps into a tempo.
public struct TapTempo: Sendable {
    public private(set) var taps: [TimeInterval] = []
    public var resetAfter: TimeInterval = 2.0
    public var window = 8

    public init() {}

    /// Registers a tap at time `t` (seconds, any monotonic clock). Returns the tempo once two taps are in.
    @discardableResult
    public mutating func tap(at t: TimeInterval) -> Double? {
        if let last = taps.last, t - last > resetAfter { taps.removeAll() }
        taps.append(t)
        if taps.count > window { taps.removeFirst(taps.count - window) }
        guard taps.count >= 2 else { return nil }
        let span = taps[taps.count - 1] - taps[0]
        guard span > 0 else { return nil }
        let bpm = 60.0 / (span / Double(taps.count - 1))
        return MetronomeSettings.clamp(bpm)
    }

    public mutating func reset() { taps.removeAll() }
}
