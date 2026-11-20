import Foundation

// MARK: - Sound identifiers

/// Every click voice the synthesizer can make. All are generated in code: no sample files.
public enum SoundID: String, Codable, CaseIterable, Identifiable, Sendable {
    case clickHigh, clickMid, clickLow, tick
    case woodHigh, woodMid, woodLow
    case beepHigh, beepMid, beepLow
    case cowbellHigh, cowbell, cowbellLow
    case kick, snare, hatClosed, hatOpen, rim, clap, shaker
    case clave, sticks
    case marimbaHigh, marimba, marimbaLow
    case chimeHigh, chime, triangle
    case tockHigh, tockLow

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .clickHigh: return "Click · high"
        case .clickMid: return "Click · mid"
        case .clickLow: return "Click · low"
        case .tick: return "Tick"
        case .woodHigh: return "Wood block · high"
        case .woodMid: return "Wood block · mid"
        case .woodLow: return "Wood block · low"
        case .beepHigh: return "Beep · high"
        case .beepMid: return "Beep · mid"
        case .beepLow: return "Beep · low"
        case .cowbellHigh: return "Cowbell · high"
        case .cowbell: return "Cowbell"
        case .cowbellLow: return "Cowbell · low"
        case .kick: return "Kick"
        case .snare: return "Snare"
        case .hatClosed: return "Hi-hat · closed"
        case .hatOpen: return "Hi-hat · open"
        case .rim: return "Rim shot"
        case .clap: return "Hand clap"
        case .shaker: return "Shaker"
        case .clave: return "Clave"
        case .sticks: return "Sticks"
        case .marimbaHigh: return "Marimba · high"
        case .marimba: return "Marimba"
        case .marimbaLow: return "Marimba · low"
        case .chimeHigh: return "Chime · high"
        case .chime: return "Chime"
        case .triangle: return "Triangle"
        case .tockHigh: return "Mechanical · tick"
        case .tockLow: return "Mechanical · tock"
        }
    }
}

/// A named set of four sounds: accent, normal, soft and subdivision.
public enum SoundKit: String, Codable, CaseIterable, Identifiable, Sendable {
    case classic, wood, digital, cowbell, drums, marimba, clave, chime, mechanical, studio

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .classic: return "Classic click"
        case .wood: return "Wood block"
        case .digital: return "Digital beep"
        case .cowbell: return "Cowbell"
        case .drums: return "Drum kit"
        case .marimba: return "Marimba"
        case .clave: return "Clave & sticks"
        case .chime: return "Chimes"
        case .mechanical: return "Mechanical"
        case .studio: return "Studio rim"
        }
    }

    public var symbol: String {
        switch self {
        case .classic: return "metronome"
        case .wood: return "square.stack.3d.down.right"
        case .digital: return "waveform"
        case .cowbell: return "bell"
        case .drums: return "circle.circle"
        case .marimba: return "pianokeys"
        case .clave: return "line.diagonal"
        case .chime: return "sparkles"
        case .mechanical: return "gearshape"
        case .studio: return "dot.radiowaves.left.and.right"
        }
    }

    public var selection: SoundSelection {
        switch self {
        case .classic: return SoundSelection(strong: .clickHigh, medium: .clickMid, soft: .clickLow, sub: .tick)
        case .wood: return SoundSelection(strong: .woodHigh, medium: .woodMid, soft: .woodLow, sub: .tick)
        case .digital: return SoundSelection(strong: .beepHigh, medium: .beepMid, soft: .beepLow, sub: .tick)
        case .cowbell: return SoundSelection(strong: .cowbellHigh, medium: .cowbell, soft: .cowbellLow, sub: .tick)
        case .drums: return SoundSelection(strong: .kick, medium: .snare, soft: .hatClosed, sub: .hatClosed)
        case .marimba: return SoundSelection(strong: .marimbaHigh, medium: .marimba, soft: .marimbaLow, sub: .marimbaLow)
        case .clave: return SoundSelection(strong: .clave, medium: .rim, soft: .sticks, sub: .tick)
        case .chime: return SoundSelection(strong: .chimeHigh, medium: .chime, soft: .chime, sub: .tick)
        case .mechanical: return SoundSelection(strong: .tockHigh, medium: .tockLow, soft: .tockLow, sub: .tick)
        case .studio: return SoundSelection(strong: .rim, medium: .sticks, soft: .sticks, sub: .tick)
        }
    }
}

/// Which sound plays at each level, plus the polyrhythm layer's own sound.
public struct SoundSelection: Codable, Hashable, Sendable {
    public var strong: SoundID
    public var medium: SoundID
    public var soft: SoundID
    public var sub: SoundID

    public init(strong: SoundID, medium: SoundID, soft: SoundID, sub: SoundID) {
        self.strong = strong; self.medium = medium; self.soft = soft; self.sub = sub
    }

    public func sound(for level: AccentLevel) -> SoundID? {
        switch level {
        case .off: return nil
        case .soft: return soft
        case .medium: return medium
        case .strong: return strong
        }
    }

    /// The kit this selection exactly matches, if any.
    public var matchingKit: SoundKit? { SoundKit.allCases.first { $0.selection == self } }
}

// MARK: - Synthesis recipes

/// Additive "modal" recipe: a handful of decaying sine partials, a filtered noise burst,
/// an optional pitch drop and soft clipping. Cheap enough to run a dozen at once.
struct SoundRecipe: Sendable {
    var count = 0
    var ratios = SIMD8<Double>(repeating: 1)
    var gains = SIMD8<Double>(repeating: 0)
    /// Time for each partial to fall by 60 dB.
    var decays = SIMD8<Double>(repeating: 0.05)
    var freq = 1000.0
    var attack = 0.0006
    var noiseGain = 0.0
    var noiseDecay = 0.01
    var hpA = 0.3          // one-pole high-pass coefficient (bigger = higher cutoff)
    var lpA = 0.8          // one-pole low-pass coefficient (bigger = brighter)
    var bursts = 1
    var burstGap = 0.0
    var pitchDrop = 0.0    // start frequency is freq * (1 + pitchDrop)
    var pitchTime = 0.03
    var drive = 0.0
    var loudness = 1.0     // relative loudness before peak normalisation
    var level = 1.0        // set by SoundBank: normalises the peak

    struct Noise { var gain: Double; var t60: Double; var hp: Double = 0.3; var lp: Double = 0.8; var attack: Double? = nil }

    static func make(freq: Double, partials: [(Double, Double, Double)], noise: Noise? = nil,
                     attack: Double = 0.0006, pitchDrop: Double = 0, pitchTime: Double = 0.03,
                     drive: Double = 0, bursts: Int = 1, burstGap: Double = 0, loudness: Double = 1) -> SoundRecipe {
        var r = SoundRecipe()
        r.freq = freq
        r.count = min(partials.count, 8)
        for (i, p) in partials.prefix(8).enumerated() {
            r.ratios[i] = p.0; r.gains[i] = p.1; r.decays[i] = p.2
        }
        if let n = noise {
            r.noiseGain = n.gain; r.noiseDecay = n.t60; r.hpA = n.hp; r.lpA = n.lp
        }
        r.attack = attack
        r.pitchDrop = pitchDrop; r.pitchTime = pitchTime
        r.drive = drive; r.bursts = bursts; r.burstGap = burstGap
        r.loudness = loudness
        return r
    }
}

extension SoundID {
    /// Raw (un-normalised) recipe.
    var rawRecipe: SoundRecipe {
        typealias R = SoundRecipe
        switch self {
        case .clickHigh: return R.make(freq: 2600, partials: [(1, 1, 0.035)], noise: .init(gain: 0.35, t60: 0.006, hp: 0.35, lp: 0.8), loudness: 0.9)
        case .clickMid: return R.make(freq: 1900, partials: [(1, 1, 0.035)], noise: .init(gain: 0.35, t60: 0.006, hp: 0.35, lp: 0.8), loudness: 0.9)
        case .clickLow: return R.make(freq: 1300, partials: [(1, 1, 0.04)], noise: .init(gain: 0.3, t60: 0.006, hp: 0.3, lp: 0.7), loudness: 0.9)
        case .tick: return R.make(freq: 4200, partials: [(1, 1, 0.02)], noise: .init(gain: 0.3, t60: 0.004, hp: 0.4, lp: 0.9), loudness: 0.55)

        case .woodHigh: return R.make(freq: 1350, partials: [(1, 1, 0.10), (2.38, 0.5, 0.06), (4.1, 0.25, 0.03)], noise: .init(gain: 0.25, t60: 0.01, hp: 0.2, lp: 0.7), loudness: 0.95)
        case .woodMid: return R.make(freq: 980, partials: [(1, 1, 0.11), (2.38, 0.5, 0.06), (4.1, 0.25, 0.03)], noise: .init(gain: 0.25, t60: 0.01, hp: 0.2, lp: 0.7), loudness: 0.95)
        case .woodLow: return R.make(freq: 700, partials: [(1, 1, 0.12), (2.38, 0.5, 0.07), (4.1, 0.25, 0.035)], noise: .init(gain: 0.25, t60: 0.01, hp: 0.2, lp: 0.7), loudness: 0.95)

        case .beepHigh: return R.make(freq: 1760, partials: [(1, 1, 0.09)], attack: 0.002, drive: 1.5, loudness: 0.8)
        case .beepMid: return R.make(freq: 1320, partials: [(1, 1, 0.09)], attack: 0.002, drive: 1.5, loudness: 0.8)
        case .beepLow: return R.make(freq: 880, partials: [(1, 1, 0.09)], attack: 0.002, drive: 1.5, loudness: 0.8)

        case .cowbellHigh: return R.make(freq: 760, partials: [(1, 1, 0.35), (1.504, 0.85, 0.28), (2.0, 0.35, 0.15), (2.58, 0.25, 0.1)], noise: .init(gain: 0.05, t60: 0.01), drive: 2, loudness: 0.85)
        case .cowbell: return R.make(freq: 640, partials: [(1, 1, 0.35), (1.504, 0.85, 0.28), (2.0, 0.35, 0.15), (2.58, 0.25, 0.1)], noise: .init(gain: 0.05, t60: 0.01), drive: 2, loudness: 0.85)
        case .cowbellLow: return R.make(freq: 540, partials: [(1, 1, 0.35), (1.504, 0.85, 0.28), (2.0, 0.35, 0.15), (2.58, 0.25, 0.1)], noise: .init(gain: 0.05, t60: 0.01), drive: 2, loudness: 0.85)

        case .kick: return R.make(freq: 52, partials: [(1, 1, 0.28)], noise: .init(gain: 0.25, t60: 0.006, hp: 0.1, lp: 0.4), pitchDrop: 2.2, pitchTime: 0.035, drive: 1.8, loudness: 1.0)
        case .snare: return R.make(freq: 190, partials: [(1, 0.6, 0.12), (1.6, 0.3, 0.08)], noise: .init(gain: 0.9, t60: 0.16, hp: 0.12, lp: 0.85), loudness: 0.85)
        case .hatClosed: return R.make(freq: 300, partials: [(1, 0.12, 0.06), (1.48, 0.12, 0.06), (1.79, 0.12, 0.06), (2.52, 0.12, 0.06), (3.9, 0.12, 0.06), (5.1, 0.12, 0.06)], noise: .init(gain: 0.8, t60: 0.06, hp: 0.5, lp: 0.95), loudness: 0.6)
        case .hatOpen: return R.make(freq: 300, partials: [(1, 0.12, 0.35), (1.48, 0.12, 0.35), (1.79, 0.12, 0.35), (2.52, 0.12, 0.35), (3.9, 0.12, 0.35), (5.1, 0.12, 0.35)], noise: .init(gain: 0.8, t60: 0.35, hp: 0.5, lp: 0.95), loudness: 0.6)
        case .rim: return R.make(freq: 1750, partials: [(1, 0.9, 0.03), (1.7, 0.5, 0.025)], noise: .init(gain: 0.6, t60: 0.015, hp: 0.3, lp: 0.8), loudness: 0.9)
        case .clap: return R.make(freq: 1000, partials: [], noise: .init(gain: 1.0, t60: 0.14, hp: 0.2, lp: 0.8), bursts: 3, burstGap: 0.010, loudness: 0.8)
        case .shaker: return R.make(freq: 1000, partials: [], noise: .init(gain: 1.0, t60: 0.09, hp: 0.55, lp: 0.9), attack: 0.008, loudness: 0.6)

        case .clave: return R.make(freq: 2450, partials: [(1, 1, 0.09), (2.0, 0.2, 0.05)], noise: .init(gain: 0.1, t60: 0.003), attack: 0.0003, loudness: 0.9)
        case .sticks: return R.make(freq: 3100, partials: [(1, 0.5, 0.025)], noise: .init(gain: 0.9, t60: 0.02, hp: 0.4, lp: 0.9), loudness: 0.8)

        case .marimbaHigh: return R.make(freq: 880, partials: [(1, 1, 0.38), (4.0, 0.28, 0.08), (9.9, 0.1, 0.03)], loudness: 0.9)
        case .marimba: return R.make(freq: 587, partials: [(1, 1, 0.38), (4.0, 0.28, 0.08), (9.9, 0.1, 0.03)], loudness: 0.9)
        case .marimbaLow: return R.make(freq: 392, partials: [(1, 1, 0.4), (4.0, 0.28, 0.08), (9.9, 0.1, 0.03)], loudness: 0.9)

        case .chimeHigh: return R.make(freq: 1568, partials: [(1, 1, 0.9), (2.76, 0.35, 0.55), (5.4, 0.2, 0.3), (8.93, 0.1, 0.2)], attack: 0.001, loudness: 0.7)
        case .chime: return R.make(freq: 1175, partials: [(1, 1, 0.9), (2.76, 0.35, 0.55), (5.4, 0.2, 0.3), (8.93, 0.1, 0.2)], attack: 0.001, loudness: 0.7)
        case .triangle: return R.make(freq: 2900, partials: [(1, 1, 0.9), (2.76, 0.5, 0.6), (5.4, 0.3, 0.4), (8.93, 0.2, 0.25)], attack: 0.0005, loudness: 0.5)

        case .tockHigh: return R.make(freq: 1100, partials: [(1, 1, 0.05), (2.2, 0.4, 0.03)], noise: .init(gain: 0.2, t60: 0.006), loudness: 0.9)
        case .tockLow: return R.make(freq: 640, partials: [(1, 1, 0.07), (2.1, 0.35, 0.04)], noise: .init(gain: 0.2, t60: 0.006), loudness: 0.9)
        }
    }
}

/// Holds the peak-normalised recipes. The first touch renders each sound once to measure its
/// peak, so it must be warmed up off the audio thread (`MetronomeCore.init` does).
enum SoundBank {
    static let recipes: [SoundRecipe] = {
        SoundID.allCases.map { id in
            var r = id.rawRecipe
            var voice = Voice()
            voice.start(r, gain: 1, pitchRatio: 1, sampleRate: 48_000, seed: 0xC0FFEE)
            var buffer = [Float](repeating: 0, count: 24_000)
            buffer.withUnsafeMutableBufferPointer { voice.renderAdd($0.baseAddress!, frames: 24_000) }
            let peak = Double(buffer.reduce(0) { max($0, abs($1)) })
            r.level = peak > 1e-6 ? (0.9 * r.loudness) / peak : 1
            return r
        }
    }()

    static let indices: [SoundID: Int] = {
        var d: [SoundID: Int] = [:]
        for (i, id) in SoundID.allCases.enumerated() { d[id] = i }
        return d
    }()

    static func index(of id: SoundID) -> Int { indices[id] ?? 0 }
    static func recipe(for id: SoundID) -> SoundRecipe { recipes[index(of: id)] }
}
