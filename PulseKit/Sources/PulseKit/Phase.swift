import Foundation

/// Where playback is right now, as heard: derived from the engine's published pulses and the clock.
/// The visual layer samples this every frame.
public struct PlaybackPhase: Equatable, Sendable {
    public var isPlaying: Bool
    /// Running pulse counter (−1 before the first click).
    public var pulseIndex: Int
    /// Pulse within the bar.
    public var pulse: Int
    public var numerator: Int
    /// Which bar spec of the sequence is sounding.
    public var barSeq: Int
    /// Bars completed since the count-in.
    public var bar: Int
    /// 0..<1 progress through the current pulse.
    public var progress: Double
    public var accent: AccentLevel
    public var countIn: Bool
    public var muted: Bool
    public var bpm: Double
    /// Seconds in the current pulse.
    public var pulseSeconds: Double

    public static let idle = PlaybackPhase(
        isPlaying: false, pulseIndex: -1, pulse: 0, numerator: 4, barSeq: 0, bar: 0, progress: 0,
        accent: .off, countIn: false, muted: false, bpm: 0, pulseSeconds: 0.5)

    /// Position within the bar, 0..<1.
    public var barProgress: Double {
        guard numerator > 0 else { return 0 }
        return (Double(pulse) + progress) / Double(numerator)
    }

    /// Seconds since the current pulse began.
    public var secondsIntoPulse: Double { progress * pulseSeconds }

    /// Progress through the current pulse mapped to a subdivision slot.
    public func subIndex(for subdivision: Subdivision) -> Int {
        var idx = 0
        for k in 0..<subdivision.steps where progress >= subdivision.offset(ofStep: k) { idx = k }
        return idx
    }

    /// Works out the phase heard at `hostSecondsNow` (+ `latency`, to push the visuals later for slow outputs).
    public static func compute(from snap: CoreSnapshot, hostSecondsNow: Double, latency: Double = 0) -> PlaybackPhase {
        guard snap.playing else { return .idle }
        let audible = Double(snap.clockAtBufferStart)
            + (hostSecondsNow - latency - snap.hostSecondsAtBufferStart) * snap.sampleRate
        var found: PulseEvent?
        for e in snap.events where e.sample <= audible { found = e }
        guard let e = found else {
            var p = PlaybackPhase.idle
            p.isPlaying = true
            p.bpm = snap.liveBPM
            return p
        }
        let progress = min(max((audible - e.sample) / max(e.length, 1), 0), 0.9999)
        return PlaybackPhase(
            isPlaying: true, pulseIndex: e.index, pulse: e.pulse, numerator: e.numerator, barSeq: e.barSeq,
            bar: e.bar, progress: progress, accent: e.accent, countIn: e.countIn, muted: e.muted,
            bpm: e.bpm, pulseSeconds: e.length / snap.sampleRate)
    }
}
