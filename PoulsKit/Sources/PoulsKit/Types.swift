import Foundation

// MARK: - Accent

/// How loud one pulse of the bar is. Tapping a pulse in the beat grid cycles through these.
public enum AccentLevel: Int, Codable, CaseIterable, Sendable, Comparable {
    case off = 0, soft, medium, strong

    public static func < (a: AccentLevel, b: AccentLevel) -> Bool { a.rawValue < b.rawValue }

    /// Linear gain applied to the click.
    public var gain: Double {
        switch self {
        case .off: return 0
        case .soft: return 0.42
        case .medium: return 0.72
        case .strong: return 1.0
        }
    }

    /// off → soft → medium → strong → off
    public var next: AccentLevel {
        switch self {
        case .off: return .soft
        case .soft: return .medium
        case .medium: return .strong
        case .strong: return .off
        }
    }

    public var label: String {
        switch self {
        case .off: return "Silent"
        case .soft: return "Soft"
        case .medium: return "Normal"
        case .strong: return "Accent"
        }
    }
}

// MARK: - Beat unit

/// The note value that the BPM number counts.
public enum BeatUnit: String, Codable, CaseIterable, Identifiable, Sendable {
    case whole, dottedHalf, half, dottedQuarter, quarter, dottedEighth, eighth, dottedSixteenth, sixteenth, thirtySecond

    public var id: String { rawValue }

    /// Length in quarter notes.
    public var quarters: Double {
        switch self {
        case .whole: return 4
        case .dottedHalf: return 3
        case .half: return 2
        case .dottedQuarter: return 1.5
        case .quarter: return 1
        case .dottedEighth: return 0.75
        case .eighth: return 0.5
        case .dottedSixteenth: return 0.375
        case .sixteenth: return 0.25
        case .thirtySecond: return 0.125
        }
    }

    public var name: String {
        switch self {
        case .whole: return "Whole note"
        case .dottedHalf: return "Dotted half"
        case .half: return "Half note"
        case .dottedQuarter: return "Dotted quarter"
        case .quarter: return "Quarter note"
        case .dottedEighth: return "Dotted eighth"
        case .eighth: return "Eighth note"
        case .dottedSixteenth: return "Dotted sixteenth"
        case .sixteenth: return "Sixteenth note"
        case .thirtySecond: return "Thirty-second"
        }
    }

    /// Compact text used where a notation glyph would not render reliably.
    public var shortName: String {
        switch self {
        case .whole: return "1/1"
        case .dottedHalf: return "1/2."
        case .half: return "1/2"
        case .dottedQuarter: return "1/4."
        case .quarter: return "1/4"
        case .dottedEighth: return "1/8."
        case .eighth: return "1/8"
        case .dottedSixteenth: return "1/16."
        case .sixteenth: return "1/16"
        case .thirtySecond: return "1/32"
        }
    }

    /// Unit matching a plain denominator (4 → quarter, 8 → eighth …).
    public static func matching(denominator: Int) -> BeatUnit {
        switch denominator {
        case 1: return .whole
        case 2: return .half
        case 4: return .quarter
        case 8: return .eighth
        case 16: return .sixteenth
        default: return .thirtySecond
        }
    }
}

// MARK: - Meter

/// One bar's worth of structure: how many pulses, what note value a pulse is, how the
/// pulses are grouped (3+2+2 …) and how strongly each one is accented.
public struct Meter: Codable, Hashable, Sendable {
    public static let validDenominators = [1, 2, 4, 8, 16, 32]
    public static let maxNumerator = 32

    public private(set) var numerator: Int
    public private(set) var denominator: Int
    public private(set) var grouping: [Int]
    public var accents: [AccentLevel]

    public init(numerator: Int, denominator: Int, grouping: [Int]? = nil, accents: [AccentLevel]? = nil) {
        let n = min(max(numerator, 1), Meter.maxNumerator)
        let d = Meter.validDenominators.contains(denominator) ? denominator : 4
        var g = grouping ?? []
        if g.isEmpty || g.contains(where: { $0 < 1 }) || g.reduce(0, +) != n {
            g = Meter.defaultGrouping(numerator: n, denominator: d)
        }
        var a = accents ?? []
        if a.count != n { a = Meter.defaultAccents(grouping: g) }
        self.numerator = n
        self.denominator = d
        self.grouping = g
        self.accents = a
    }

    private enum CodingKeys: String, CodingKey { case numerator, denominator, grouping, accents }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            numerator: try c.decodeIfPresent(Int.self, forKey: .numerator) ?? 4,
            denominator: try c.decodeIfPresent(Int.self, forKey: .denominator) ?? 4,
            grouping: try c.decodeIfPresent([Int].self, forKey: .grouping),
            accents: try c.decodeIfPresent([AccentLevel].self, forKey: .accents))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(numerator, forKey: .numerator)
        try c.encode(denominator, forKey: .denominator)
        try c.encode(grouping, forKey: .grouping)
        try c.encode(accents, forKey: .accents)
    }

    // MARK: Defaults

    /// The conventional way to feel a meter: compound meters in threes, odd meters in 2s and 3s.
    public static func defaultGrouping(numerator n: Int, denominator d: Int) -> [Int] {
        if d >= 8 {
            switch n {
            case 1: return [1]
            case 2: return [2]
            case 3: return [3]
            case 4: return [2, 2]
            case 5: return [3, 2]
            default:
                let k = n / 3, r = n % 3
                switch r {
                case 0: return Array(repeating: 3, count: k)
                case 1: return [2, 2] + Array(repeating: 3, count: k - 1)
                default: return Array(repeating: 3, count: k) + [2]
                }
            }
        }
        switch n {
        case 5: return [3, 2]
        case 7: return [4, 3]
        default: return Array(repeating: 1, count: n)
        }
    }

    /// First pulse of the bar strong, other group starts normal, the rest soft.
    public static func defaultAccents(grouping: [Int]) -> [AccentLevel] {
        var out: [AccentLevel] = []
        for (gi, size) in grouping.enumerated() {
            for i in 0..<size {
                if i == 0 { out.append(gi == 0 ? .strong : .medium) } else { out.append(.soft) }
            }
        }
        return out
    }

    // MARK: Derived

    /// 6/8, 9/8, 12/8 … felt in beats of three.
    public var isCompound: Bool {
        denominator >= 8 && numerator >= 6 && numerator % 3 == 0 && grouping.allSatisfy { $0 == 3 }
    }

    /// 5/8, 7/8, 11/8 … : groups of unequal size.
    public var isAsymmetric: Bool { Set(grouping).count > 1 }

    /// The beat unit a musician would naturally count this meter in.
    public var suggestedBeatUnit: BeatUnit {
        if isCompound {
            switch denominator {
            case 8: return .dottedQuarter
            case 16: return .dottedEighth
            default: return .dottedSixteenth
            }
        }
        return BeatUnit.matching(denominator: denominator)
    }

    public var name: String { "\(numerator)/\(denominator)" }

    public var groupingString: String { grouping.map(String.init).joined(separator: "+") }

    /// "7/8 · 2+2+3" when the grouping carries information, "4/4" otherwise.
    public var longName: String {
        grouping.count > 1 && grouping.contains(where: { $0 > 1 }) ? "\(name) · \(groupingString)" : name
    }

    /// Index of the group a pulse belongs to, and whether it starts that group.
    public func groupInfo(forPulse p: Int) -> (group: Int, isStart: Bool) {
        var start = 0
        for (gi, size) in grouping.enumerated() {
            if p < start + size { return (gi, p == start) }
            start += size
        }
        return (max(grouping.count - 1, 0), false)
    }

    /// The number to show or say for a pulse. Meters felt in groups count inside each group
    /// ("1 2 | 1 2 | 1 2 3"); plain meters count straight through.
    public func countNumber(forPulse p: Int) -> Int {
        guard grouping.contains(where: { $0 > 1 }) else { return p + 1 }
        var start = 0
        for size in grouping {
            if p < start + size { return p - start + 1 }
            start += size
        }
        return p + 1
    }

    // MARK: Mutation

    public mutating func setAccent(_ pulse: Int, _ level: AccentLevel) {
        guard accents.indices.contains(pulse) else { return }
        accents[pulse] = level
    }

    public mutating func resetAccents() { accents = Meter.defaultAccents(grouping: grouping) }

    /// Changes the grouping if it is valid for this numerator and resets the accents to match.
    @discardableResult
    public mutating func setGrouping(_ g: [Int]) -> Bool {
        guard !g.isEmpty, !g.contains(where: { $0 < 1 }), g.reduce(0, +) == numerator else { return false }
        grouping = g
        resetAccents()
        return true
    }

    // MARK: Parsing

    /// "3+3+2", "3 3 2", "3,3,2" → [3,3,2]; nil unless the parts add up to `numerator`.
    public static func parseGrouping(_ text: String, numerator: Int) -> [Int]? {
        let parts = text.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard !parts.isEmpty, !parts.contains(where: { $0 < 1 }), parts.reduce(0, +) == numerator else { return nil }
        return parts
    }

    /// "7/8", "7/8 2+2+3", "5/4 (3+2)" → a meter.
    public static func parse(_ text: String) -> Meter? {
        let digits = text.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard digits.count >= 2, digits[0] >= 1, digits[0] <= maxNumerator, validDenominators.contains(digits[1]) else { return nil }
        let n = digits[0], d = digits[1]
        if digits.count > 2, let g = parseGrouping(digits.dropFirst(2).map(String.init).joined(separator: "+"), numerator: n) {
            return Meter(numerator: n, denominator: d, grouping: g)
        }
        return Meter(numerator: n, denominator: d)
    }

    /// Time signatures offered as one-tap choices.
    public static let commonSignatures: [(Int, Int)] = [
        (2, 4), (3, 4), (4, 4), (5, 4), (6, 4), (7, 4),
        (2, 2), (3, 8), (5, 8), (6, 8), (7, 8), (9, 8),
        (10, 8), (11, 8), (12, 8), (13, 8), (15, 16),
    ]
}

// MARK: - Bar

/// A bar of a given meter, optionally repeated. A sequence of these makes a mixed-meter pattern.
public struct BarSpec: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var meter: Meter
    public var repeats: Int

    public init(meter: Meter, repeats: Int = 1, id: UUID = UUID()) {
        self.id = id
        self.meter = meter
        self.repeats = min(max(repeats, 1), 64)
    }

    private enum CodingKeys: String, CodingKey { case id, meter, repeats }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            meter: try c.decodeIfPresent(Meter.self, forKey: .meter) ?? Meter(numerator: 4, denominator: 4),
            repeats: try c.decodeIfPresent(Int.self, forKey: .repeats) ?? 1,
            id: try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID())
    }

    /// A copy with a fresh identity (for "duplicate bar").
    public func duplicated() -> BarSpec { BarSpec(meter: meter, repeats: repeats) }

    /// Same pulse structure (accents and identity ignored). Changing the shape restarts the bar;
    /// changing accents does not.
    public func sameShape(as other: BarSpec) -> Bool {
        meter.numerator == other.meter.numerator
            && meter.denominator == other.meter.denominator
            && repeats == other.repeats
    }
}

// MARK: - Subdivision

/// How each pulse is cut up. `steps` evenly spaced slots per pulse; `mask` says which sub-slots sound.
public struct Subdivision: Codable, Hashable, Sendable {
    public static let maxSteps = 12

    public private(set) var steps: Int
    /// One entry per step; entry 0 is the pulse itself and is always true.
    public var mask: [Bool]
    /// Position of the second eighth when `steps == 2` (0.5 straight, 0.667 triplet swing).
    public var swing: Double
    /// False for "off-beats only": the pulse stays silent and only the sub-slots sound.
    public var playsPulse: Bool

    public init(steps: Int = 1, mask: [Bool]? = nil, swing: Double = 0.5, playsPulse: Bool = true) {
        let s = min(max(steps, 1), Subdivision.maxSteps)
        var m = mask ?? []
        if m.count != s { m = Array(repeating: true, count: s) }
        m[0] = true
        self.steps = s
        self.mask = m
        self.swing = min(max(swing, 0.5), 0.8)
        self.playsPulse = playsPulse
    }

    private enum CodingKeys: String, CodingKey { case steps, mask, swing, playsPulse }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            steps: try c.decodeIfPresent(Int.self, forKey: .steps) ?? 1,
            mask: try c.decodeIfPresent([Bool].self, forKey: .mask),
            swing: try c.decodeIfPresent(Double.self, forKey: .swing) ?? 0.5,
            playsPulse: try c.decodeIfPresent(Bool.self, forKey: .playsPulse) ?? true)
    }

    public var isNone: Bool { steps == 1 && playsPulse }

    /// Position of a step inside its pulse, 0..<1.
    public func offset(ofStep k: Int) -> Double {
        if steps == 2 && k == 1 { return swing }
        return Double(k) / Double(steps)
    }

    /// Changes the number of steps, keeping the mask where it still fits.
    public mutating func setSteps(_ n: Int) {
        let s = min(max(n, 1), Subdivision.maxSteps)
        var m = Array(repeating: true, count: s)
        for i in 0..<min(s, mask.count) { m[i] = mask[i] }
        m[0] = true
        steps = s
        mask = m
    }

    // MARK: Catalogue

    public struct Entry: Identifiable, Sendable {
        public var id: String { name }
        public let name: String
        public let counting: String
        public let value: Subdivision
    }

    public static let none = Subdivision(steps: 1)
    public static let eighths = Subdivision(steps: 2)
    public static let triplets = Subdivision(steps: 3)
    public static let sixteenths = Subdivision(steps: 4)
    public static let quintuplets = Subdivision(steps: 5)
    public static let sextuplets = Subdivision(steps: 6)
    public static let septuplets = Subdivision(steps: 7)
    public static let swing = Subdivision(steps: 2, swing: 2.0 / 3.0)
    public static let offBeat = Subdivision(steps: 2, playsPulse: false)
    public static let gallop = Subdivision(steps: 4, mask: [true, false, true, true])
    public static let syncopated = Subdivision(steps: 4, mask: [true, false, false, true])
    public static let tripletSkip = Subdivision(steps: 3, mask: [true, false, true])

    public static let catalog: [Entry] = [
        Entry(name: "None", counting: "1  2  3  4", value: .none),
        Entry(name: "Eighths", counting: "1 &", value: .eighths),
        Entry(name: "Triplets", counting: "1 trip-let", value: .triplets),
        Entry(name: "Sixteenths", counting: "1 e & a", value: .sixteenths),
        Entry(name: "Quintuplets", counting: "1 2 3 4 5", value: .quintuplets),
        Entry(name: "Sextuplets", counting: "1 2 3 4 5 6", value: .sextuplets),
        Entry(name: "Septuplets", counting: "1 2 3 4 5 6 7", value: .septuplets),
        Entry(name: "Swing eighths", counting: "1 – let", value: .swing),
        Entry(name: "Shuffle (triplet skip)", counting: "1 – let", value: .tripletSkip),
        Entry(name: "Off-beats only", counting: "· &", value: .offBeat),
        Entry(name: "Gallop", counting: "1 · & a", value: .gallop),
        Entry(name: "Syncopated", counting: "1 · · a", value: .syncopated),
    ]

    /// Catalogue name, or "Custom ×n" when the pattern is not a stock one.
    public var name: String {
        Subdivision.catalog.first(where: { $0.value == self })?.name ?? "Custom ×\(steps)"
    }
}
