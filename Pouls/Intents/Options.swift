import AppIntents
import PoulsKit

// MARK: - Enums exposed to Siri and Shortcuts

enum TimeSignatureOption: String, AppEnum {
    case twoFour, threeFour, fourFour, fiveFour, sixFour, sevenFour, twoTwo
    case threeEight, fiveEight, sixEight, sevenEight, nineEight, tenEight, elevenEight, twelveEight, thirteenEight, fifteenSixteen

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Time Signature"
    static let caseDisplayRepresentations: [TimeSignatureOption: DisplayRepresentation] = [
        .twoFour: "2/4", .threeFour: "3/4", .fourFour: "4/4", .fiveFour: "5/4", .sixFour: "6/4", .sevenFour: "7/4",
        .twoTwo: "2/2 (cut time)", .threeEight: "3/8", .fiveEight: "5/8", .sixEight: "6/8", .sevenEight: "7/8",
        .nineEight: "9/8", .tenEight: "10/8", .elevenEight: "11/8", .twelveEight: "12/8", .thirteenEight: "13/8",
        .fifteenSixteen: "15/16",
    ]

    var parts: (numerator: Int, denominator: Int) {
        switch self {
        case .twoFour: return (2, 4)
        case .threeFour: return (3, 4)
        case .fourFour: return (4, 4)
        case .fiveFour: return (5, 4)
        case .sixFour: return (6, 4)
        case .sevenFour: return (7, 4)
        case .twoTwo: return (2, 2)
        case .threeEight: return (3, 8)
        case .fiveEight: return (5, 8)
        case .sixEight: return (6, 8)
        case .sevenEight: return (7, 8)
        case .nineEight: return (9, 8)
        case .tenEight: return (10, 8)
        case .elevenEight: return (11, 8)
        case .twelveEight: return (12, 8)
        case .thirteenEight: return (13, 8)
        case .fifteenSixteen: return (15, 16)
        }
    }
}

enum NoteValueOption: Int, AppEnum {
    case half = 2, quarter = 4, eighth = 8, sixteenth = 16

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Note Value"
    static let caseDisplayRepresentations: [NoteValueOption: DisplayRepresentation] = [
        .half: "Half note", .quarter: "Quarter note", .eighth: "Eighth note", .sixteenth: "Sixteenth note",
    ]
}

enum SubdivisionOption: String, AppEnum {
    case none, eighths, triplets, sixteenths, quintuplets, sextuplets, septuplets, swing, shuffle, offBeats, gallop

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Subdivision"
    static let caseDisplayRepresentations: [SubdivisionOption: DisplayRepresentation] = [
        .none: "None", .eighths: "Eighth notes", .triplets: "Triplets", .sixteenths: "Sixteenth notes",
        .quintuplets: "Quintuplets", .sextuplets: "Sextuplets", .septuplets: "Septuplets",
        .swing: "Swing", .shuffle: "Shuffle", .offBeats: "Off-beats", .gallop: "Gallop",
    ]

    var subdivision: Subdivision {
        switch self {
        case .none: return .none
        case .eighths: return .eighths
        case .triplets: return .triplets
        case .sixteenths: return .sixteenths
        case .quintuplets: return .quintuplets
        case .sextuplets: return .sextuplets
        case .septuplets: return .septuplets
        case .swing: return .swing
        case .shuffle: return .tripletSkip
        case .offBeats: return .offBeat
        case .gallop: return .gallop
        }
    }
}

enum SoundKitOption: String, AppEnum {
    case classic, wood, digital, cowbell, drums, marimba, clave, chime, mechanical, studio

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Sound"
    static let caseDisplayRepresentations: [SoundKitOption: DisplayRepresentation] = [
        .classic: "Classic click", .wood: "Wood block", .digital: "Digital beep", .cowbell: "Cowbell",
        .drums: "Drum kit", .marimba: "Marimba", .clave: "Clave", .chime: "Chimes",
        .mechanical: "Mechanical", .studio: "Studio rim",
    ]

    var kit: SoundKit { SoundKit(rawValue: rawValue) ?? .classic }
}

enum TempoDirection: String, AppEnum {
    case faster, slower

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Direction"
    static let caseDisplayRepresentations: [TempoDirection: DisplayRepresentation] = [
        .faster: "Faster", .slower: "Slower",
    ]
}

enum TempoUnit: String, AppEnum {
    case bpm, percent

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Unit"
    static let caseDisplayRepresentations: [TempoUnit: DisplayRepresentation] = [
        .bpm: "BPM", .percent: "Percent",
    ]
}

enum TempoScale: String, AppEnum {
    case double, half, twoThirds, threeHalves

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Tempo Change"
    static let caseDisplayRepresentations: [TempoScale: DisplayRepresentation] = [
        .double: "Double time", .half: "Half time", .twoThirds: "Two thirds", .threeHalves: "One and a half times",
    ]

    var factor: Double {
        switch self {
        case .double: return 2
        case .half: return 0.5
        case .twoThirds: return 2.0 / 3.0
        case .threeHalves: return 1.5
        }
    }
}

extension VisualMode: AppEnum {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Visual Mode"
    static let caseDisplayRepresentations: [VisualMode: DisplayRepresentation] = [
        .pendulum: "Pendulum", .pulse: "Pulse", .orbit: "Orbit", .bounce: "Bounce",
    ]
}

// MARK: - Preset entity

struct PresetEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Preset"
    static let defaultQuery = PresetQuery()

    var id: String
    var name: String
    var subtitle: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(subtitle)")
    }

    init(_ preset: Preset) {
        id = preset.id
        name = preset.name
        subtitle = preset.subtitle
    }
}

struct PresetQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [PresetEntity] {
        let all = PresetStorage.allPresets()
        return identifiers.compactMap { id in all.first { $0.id == id }.map(PresetEntity.init) }
    }

    func entities(matching string: String) async throws -> [PresetEntity] {
        let q = string.lowercased()
        return PresetStorage.allPresets()
            .filter { $0.name.lowercased().contains(q) || $0.subtitle.lowercased().contains(q) }
            .map(PresetEntity.init)
    }

    func suggestedEntities() async throws -> [PresetEntity] {
        PresetStorage.allPresets().map(PresetEntity.init)
    }
}

/// Reads presets straight from disk so intents can resolve them before the model exists.
enum PresetStorage {
    static func allPresets(defaults: UserDefaults = .standard) -> [Preset] {
        var user: [Preset] = []
        if let data = defaults.data(forKey: Metronome.presetsKey),
           let decoded = try? JSONDecoder().decode([Preset].self, from: data) {
            user = decoded
        }
        return user + PresetLibrary.all
    }
}
