import Foundation

/// A saved metronome setup.
public struct Preset: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var subtitle: String
    public var settings: MetronomeSettings
    public var isBuiltIn: Bool

    public init(id: String = UUID().uuidString, name: String, subtitle: String = "", settings: MetronomeSettings, isBuiltIn: Bool = false) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.settings = settings
        self.isBuiltIn = isBuiltIn
    }
}

public enum PresetLibrary {
    public struct Section: Identifiable, Sendable {
        public var id: String { title }
        public let title: String
        public let presets: [Preset]
    }

    private static func p(_ id: String, _ name: String, _ sub: String, _ s: MetronomeSettings) -> Preset {
        Preset(id: "builtin.\(id)", name: name, subtitle: sub, settings: s, isBuiltIn: true)
    }

    private static func mixed(bpm: Double, unit: BeatUnit?, bars: [(Int, Int, [Int]?, Int)], kit: SoundKit = .classic) -> MetronomeSettings {
        MetronomeSettings(
            bpm: bpm, beatUnitOverride: unit,
            bars: bars.map { BarSpec(meter: Meter(numerator: $0.0, denominator: $0.1, grouping: $0.2), repeats: $0.3) },
            sounds: kit.selection)
    }

    public static let sections: [Section] = [
        Section(title: "Everyday", presets: [
            p("four-four", "4/4 · Steady", "The classic", .make(bpm: 100, numerator: 4, denominator: 4)),
            p("waltz", "Waltz", "3/4 · strong–soft–soft", .make(bpm: 96, numerator: 3, denominator: 4, kit: .wood)),
            p("march", "March", "2/4 · eighths", .make(bpm: 112, numerator: 2, denominator: 4, subdivision: .eighths, kit: .drums)),
            p("sixteenths", "Sixteenth-note groove", "4/4 · 1 e & a", .make(bpm: 84, numerator: 4, denominator: 4, subdivision: .sixteenths)),
            p("swing", "Swing", "4/4 · swung eighths", .make(bpm: 132, numerator: 4, denominator: 4, subdivision: .swing, kit: .studio)),
            p("shuffle", "Blues shuffle", "4/4 · triplet skip", MetronomeSettings(
                bpm: 66, bars: [BarSpec(meter: Meter(numerator: 4, denominator: 4))], subdivision: .tripletSkip, sounds: SoundKit.drums.selection)),
            p("compound-six", "6/8 · Jig", "Two big beats of three", .make(bpm: 108, numerator: 6, denominator: 8, kit: .marimba)),
            p("twelve-eight", "12/8 · Slow ballad", "Four beats of three", .make(bpm: 60, numerator: 12, denominator: 8, kit: .chime)),
        ]),
        Section(title: "Odd meters", presets: [
            p("five-four", "5/4 · Take Five feel", "3+2", .make(bpm: 168, numerator: 5, denominator: 4, grouping: [3, 2], kit: .wood)),
            p("seven-four", "7/4 · 4+3", "Money-style groove", .make(bpm: 120, numerator: 7, denominator: 4, grouping: [4, 3], kit: .cowbell)),
            p("five-eight", "5/8 · 3+2", "Quick limp", .make(bpm: 200, numerator: 5, denominator: 8, grouping: [3, 2])),
            p("seven-eight", "7/8 · 2+2+3", "Balkan rachenitsa", .make(bpm: 220, numerator: 7, denominator: 8, grouping: [2, 2, 3], kit: .clave)),
            p("seven-eight-b", "7/8 · 3+2+2", "Aksak variant", .make(bpm: 220, numerator: 7, denominator: 8, grouping: [3, 2, 2], kit: .clave)),
            p("nine-eight", "9/8 · 2+2+2+3", "Blue Rondo pulse", .make(bpm: 240, numerator: 9, denominator: 8, grouping: [2, 2, 2, 3], kit: .wood)),
            p("ten-eight", "10/8 · 3+3+2+2", "Bulgarian dance", .make(bpm: 230, numerator: 10, denominator: 8, grouping: [3, 3, 2, 2])),
            p("eleven-eight", "11/8 · 3+3+3+2", "Progressive", .make(bpm: 230, numerator: 11, denominator: 8, grouping: [3, 3, 3, 2], kit: .digital)),
            p("thirteen-eight", "13/8 · 3+3+3+2+2", "Odd and then some", .make(bpm: 240, numerator: 13, denominator: 8, grouping: [3, 3, 3, 2, 2])),
            p("fifteen-sixteen", "15/16 · 4+4+4+3", "Math-rock", .make(bpm: 400, numerator: 15, denominator: 16, grouping: [4, 4, 4, 3], kit: .digital)),
            p("tresillo", "8/8 · 3+3+2", "Tresillo", .make(bpm: 180, numerator: 8, denominator: 8, grouping: [3, 3, 2], kit: .clave)),
        ]),
        Section(title: "Changing meters", presets: [
            p("seven-four-mix", "7/8 then 8/8", "Alternate every bar", mixed(bpm: 200, unit: .eighth, bars: [(7, 8, [2, 2, 3], 1), (8, 8, [4, 4], 1)])),
            p("five-three", "5/4 + 3/4", "Eight beats in two bars", mixed(bpm: 150, unit: .quarter, bars: [(5, 4, [3, 2], 1), (3, 4, nil, 1)])),
            p("bar-of-seven", "Three 4/4, one 7/8", "Prog turnaround", mixed(bpm: 190, unit: .eighth, bars: [(8, 8, [4, 4], 3), (7, 8, [2, 2, 3], 1)])),
            p("six-two", "6/8 ⇄ 3/4", "Hemiola flip", mixed(bpm: 210, unit: .eighth, bars: [(6, 8, [3, 3], 2), (6, 8, [2, 2, 2], 2)])),
        ]),
        Section(title: "Polyrhythms", presets: [
            p("three-four", "3 against 4", "Hemiola", {
                var s = MetronomeSettings.make(bpm: 80, numerator: 4, denominator: 4)
                s.poly = PolyLayer(enabled: true, clicks: 3, sound: .cowbellLow, volume: 0.7); return s
            }()),
            p("two-three", "2 against 3", "The classic cross-rhythm", {
                var s = MetronomeSettings.make(bpm: 72, numerator: 3, denominator: 4, kit: .wood)
                s.poly = PolyLayer(enabled: true, clicks: 2, sound: .cowbellLow, volume: 0.7); return s
            }()),
            p("five-four-poly", "5 against 4", "Brain-twister", {
                var s = MetronomeSettings.make(bpm: 60, numerator: 4, denominator: 4, kit: .marimba)
                s.poly = PolyLayer(enabled: true, clicks: 5, sound: .woodHigh, volume: 0.6); return s
            }()),
            p("seven-eight-poly", "7 against 8", "Advanced", {
                var s = MetronomeSettings.make(bpm: 56, numerator: 8, denominator: 8, kit: .digital)
                s.poly = PolyLayer(enabled: true, clicks: 7, sound: .chime, volume: 0.55); return s
            }()),
        ]),
        Section(title: "Practice", presets: [
            p("builder", "Speed builder", "80 → 140, +4 every 4 bars", {
                var s = MetronomeSettings.make(bpm: 80, numerator: 4, denominator: 4)
                s.trainer = SpeedTrainer(enabled: true, targetBPM: 140, stepBPM: 4, everyBars: 4); return s
            }()),
            p("slow-down", "Slow-down drill", "160 → 100, −5 every 2 bars", {
                var s = MetronomeSettings.make(bpm: 160, numerator: 4, denominator: 4, subdivision: .eighths)
                s.trainer = SpeedTrainer(enabled: true, targetBPM: 100, stepBPM: 5, everyBars: 2); return s
            }()),
            p("gap", "Inner clock", "Three bars on, one bar silent", {
                var s = MetronomeSettings.make(bpm: 100, numerator: 4, denominator: 4)
                s.gap = GapClick(enabled: true, playBars: 3, muteBars: 1); return s
            }()),
            p("count-in", "Count-in · 2 bars", "Start with a lead-in", {
                var s = MetronomeSettings.make(bpm: 100, numerator: 4, denominator: 4)
                s.countInBars = 2; return s
            }()),
            p("offbeat", "Off-beat feel", "Clicks only on the &", .make(bpm: 120, numerator: 4, denominator: 4, subdivision: .offBeat, kit: .studio)),
        ]),
    ]

    public static var all: [Preset] { sections.flatMap(\.presets) }

    public static func builtIn(id: String) -> Preset? { all.first { $0.id == id } }
}
