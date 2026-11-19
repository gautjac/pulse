import Foundation

// MARK: - Practice features

/// Polyrhythm layer: `clicks` evenly spaced clicks across each bar, against the bar's own pulses (3 against 4 …).
public struct PolyLayer: Codable, Hashable, Sendable {
    public var enabled: Bool
    public var clicks: Int
    public var sound: SoundID
    public var volume: Double

    public init(enabled: Bool = false, clicks: Int = 3, sound: SoundID = .woodMid, volume: Double = 0.7) {
        self.enabled = enabled
        self.clicks = min(max(clicks, 2), 16)
        self.sound = sound
        self.volume = min(max(volume, 0), 1)
    }

    private enum CodingKeys: String, CodingKey { case enabled, clicks, sound, volume }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            enabled: try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false,
            clicks: try c.decodeIfPresent(Int.self, forKey: .clicks) ?? 3,
            sound: try c.decodeIfPresent(SoundID.self, forKey: .sound) ?? .woodMid,
            volume: try c.decodeIfPresent(Double.self, forKey: .volume) ?? 0.7)
    }
}

/// Raises (or lowers) the tempo by `stepBPM` every `everyBars` bars until it reaches `targetBPM`.
public struct SpeedTrainer: Codable, Hashable, Sendable {
    public var enabled: Bool
    public var targetBPM: Double
    public var stepBPM: Double
    public var everyBars: Int

    public init(enabled: Bool = false, targetBPM: Double = 140, stepBPM: Double = 4, everyBars: Int = 4) {
        self.enabled = enabled
        self.targetBPM = min(max(targetBPM, MetronomeSettings.bpmRange.lowerBound), MetronomeSettings.bpmRange.upperBound)
        self.stepBPM = min(max(stepBPM, 1), 50)
        self.everyBars = min(max(everyBars, 1), 64)
    }

    private enum CodingKeys: String, CodingKey { case enabled, targetBPM, stepBPM, everyBars }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            enabled: try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false,
            targetBPM: try c.decodeIfPresent(Double.self, forKey: .targetBPM) ?? 140,
            stepBPM: try c.decodeIfPresent(Double.self, forKey: .stepBPM) ?? 4,
            everyBars: try c.decodeIfPresent(Int.self, forKey: .everyBars) ?? 4)
    }
}

/// "Gap click": play `playBars` bars, then keep time silently for `muteBars` bars, and repeat.
public struct GapClick: Codable, Hashable, Sendable {
    public var enabled: Bool
    public var playBars: Int
    public var muteBars: Int

    public init(enabled: Bool = false, playBars: Int = 3, muteBars: Int = 1) {
        self.enabled = enabled
        self.playBars = min(max(playBars, 1), 32)
        self.muteBars = min(max(muteBars, 1), 32)
    }

    private enum CodingKeys: String, CodingKey { case enabled, playBars, muteBars }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            enabled: try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false,
            playBars: try c.decodeIfPresent(Int.self, forKey: .playBars) ?? 3,
            muteBars: try c.decodeIfPresent(Int.self, forKey: .muteBars) ?? 1)
    }
}

// MARK: - Settings

/// Everything the engine needs to know. Value type; the app edits a copy and hands it to the core.
public struct MetronomeSettings: Codable, Hashable, Sendable {
    public static let bpmRange: ClosedRange<Double> = 20...400

    public var bpm: Double
    /// What the BPM counts. `nil` means "whatever suits the first bar's meter" (♩. for 6/8, ♪ for 7/8 …).
    public var beatUnitOverride: BeatUnit?
    public var bars: [BarSpec]
    public var subdivision: Subdivision
    public var sounds: SoundSelection
    public var pitchSemitones: Double
    public var volume: Double
    public var subdivisionVolume: Double
    public var poly: PolyLayer
    public var countInBars: Int
    public var trainer: SpeedTrainer
    public var gap: GapClick

    public init(
        bpm: Double = 100,
        beatUnitOverride: BeatUnit? = nil,
        bars: [BarSpec] = [BarSpec(meter: Meter(numerator: 4, denominator: 4))],
        subdivision: Subdivision = .none,
        sounds: SoundSelection = SoundKit.classic.selection,
        pitchSemitones: Double = 0,
        volume: Double = 0.8,
        subdivisionVolume: Double = 0.55,
        poly: PolyLayer = PolyLayer(),
        countInBars: Int = 0,
        trainer: SpeedTrainer = SpeedTrainer(),
        gap: GapClick = GapClick()
    ) {
        self.bpm = MetronomeSettings.clamp(bpm)
        self.beatUnitOverride = beatUnitOverride
        self.bars = bars.isEmpty ? [BarSpec(meter: Meter(numerator: 4, denominator: 4))] : bars
        self.subdivision = subdivision
        self.sounds = sounds
        self.pitchSemitones = min(max(pitchSemitones, -12), 12)
        self.volume = min(max(volume, 0), 1)
        self.subdivisionVolume = min(max(subdivisionVolume, 0), 1)
        self.poly = poly
        self.countInBars = min(max(countInBars, 0), 4)
        self.trainer = trainer
        self.gap = gap
    }

    private enum CodingKeys: String, CodingKey {
        case bpm, beatUnitOverride, bars, subdivision, sounds, pitchSemitones, volume
        case subdivisionVolume, poly, countInBars, trainer, gap
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            bpm: try c.decodeIfPresent(Double.self, forKey: .bpm) ?? 100,
            beatUnitOverride: try c.decodeIfPresent(BeatUnit.self, forKey: .beatUnitOverride),
            bars: try c.decodeIfPresent([BarSpec].self, forKey: .bars) ?? [],
            subdivision: try c.decodeIfPresent(Subdivision.self, forKey: .subdivision) ?? .none,
            sounds: try c.decodeIfPresent(SoundSelection.self, forKey: .sounds) ?? SoundKit.classic.selection,
            pitchSemitones: try c.decodeIfPresent(Double.self, forKey: .pitchSemitones) ?? 0,
            volume: try c.decodeIfPresent(Double.self, forKey: .volume) ?? 0.8,
            subdivisionVolume: try c.decodeIfPresent(Double.self, forKey: .subdivisionVolume) ?? 0.55,
            poly: try c.decodeIfPresent(PolyLayer.self, forKey: .poly) ?? PolyLayer(),
            countInBars: try c.decodeIfPresent(Int.self, forKey: .countInBars) ?? 0,
            trainer: try c.decodeIfPresent(SpeedTrainer.self, forKey: .trainer) ?? SpeedTrainer(),
            gap: try c.decodeIfPresent(GapClick.self, forKey: .gap) ?? GapClick())
    }

    public static func clamp(_ bpm: Double) -> Double {
        guard bpm.isFinite else { return 100 }
        return min(max(bpm, bpmRange.lowerBound), bpmRange.upperBound)
    }

    // MARK: Derived

    public var firstMeter: Meter { bars[0].meter }

    public var effectiveBeatUnit: BeatUnit { beatUnitOverride ?? firstMeter.suggestedBeatUnit }

    /// Total number of bars in one trip round the sequence.
    public var sequenceBars: Int { bars.reduce(0) { $0 + $1.repeats } }

    /// True when the pattern changes meter.
    public var isMixedMeter: Bool { bars.count > 1 }

    /// Seconds in one pulse of `meter` at `bpm`.
    public func pulseSeconds(for meter: Meter, bpm: Double? = nil) -> Double {
        let b = bpm ?? self.bpm
        return (4.0 / Double(meter.denominator)) * 60.0 / (b * effectiveBeatUnit.quarters)
    }

    /// Seconds in one bar of `meter` at `bpm`.
    public func barSeconds(for meter: Meter, bpm: Double? = nil) -> Double {
        pulseSeconds(for: meter, bpm: bpm) * Double(meter.numerator)
    }

    /// Short description for Siri / Shortcuts / the lock screen.
    public var summary: String {
        let meterText = isMixedMeter ? bars.map { $0.meter.name }.joined(separator: " → ") : firstMeter.longName
        var text = "\(Int(bpm.rounded())) BPM, \(meterText)"
        if !subdivision.isNone { text += ", \(subdivision.name.lowercased())" }
        return text
    }

    // MARK: Convenience edits (pure, used by UI and intents)

    /// Replaces the pattern with a single bar of the given time signature.
    public mutating func setTimeSignature(numerator: Int, denominator: Int, grouping: [Int]? = nil) {
        bars = [BarSpec(meter: Meter(numerator: numerator, denominator: denominator, grouping: grouping))]
    }

    public mutating func setBPM(_ value: Double) { bpm = MetronomeSettings.clamp(value) }

    public mutating func applyKit(_ kit: SoundKit) { sounds = kit.selection }

    /// A canned settings value used by presets and tests.
    public static func make(
        bpm: Double, numerator: Int, denominator: Int, grouping: [Int]? = nil,
        unit: BeatUnit? = nil, subdivision: Subdivision = .none, kit: SoundKit = .classic
    ) -> MetronomeSettings {
        MetronomeSettings(
            bpm: bpm, beatUnitOverride: unit,
            bars: [BarSpec(meter: Meter(numerator: numerator, denominator: denominator, grouping: grouping))],
            subdivision: subdivision, sounds: kit.selection)
    }
}
