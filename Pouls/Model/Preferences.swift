import SwiftUI
import PoulsKit

enum VisualMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case pendulum, pulse, orbit, bounce
    var id: String { rawValue }
    var name: String {
        switch self {
        case .pendulum: return "Pendulum"
        case .pulse: return "Pulse"
        case .orbit: return "Orbit"
        case .bounce: return "Bounce"
        }
    }
    var symbol: String {
        switch self {
        case .pendulum: return "metronome"
        case .pulse: return "sun.max.fill"
        case .orbit: return "circle.dotted.circle"
        case .bounce: return "basketball.fill"
        }
    }
}

struct Preferences: Codable, Equatable {
    var visualMode: VisualMode = .pendulum
    var themeID: String = Theme.ember.id
    var haptics = true
    var keepAwake = true
    var mixWithOthers = true
    /// Shifts the visuals later (+) or earlier (−) to line up with what you hear.
    var visualOffsetMs: Double = 0
    var showCounts = true
    var flashIntensity: Double = 1.0

    var theme: Theme { Theme.all.first { $0.id == themeID } ?? .ember }

    init() {}

    private enum CodingKeys: String, CodingKey {
        case visualMode, themeID, haptics, keepAwake, mixWithOthers, visualOffsetMs, showCounts, flashIntensity
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        visualMode = try c.decodeIfPresent(VisualMode.self, forKey: .visualMode) ?? .pendulum
        themeID = try c.decodeIfPresent(String.self, forKey: .themeID) ?? Theme.ember.id
        haptics = try c.decodeIfPresent(Bool.self, forKey: .haptics) ?? true
        keepAwake = try c.decodeIfPresent(Bool.self, forKey: .keepAwake) ?? true
        mixWithOthers = try c.decodeIfPresent(Bool.self, forKey: .mixWithOthers) ?? true
        visualOffsetMs = try c.decodeIfPresent(Double.self, forKey: .visualOffsetMs) ?? 0
        showCounts = try c.decodeIfPresent(Bool.self, forKey: .showCounts) ?? true
        flashIntensity = try c.decodeIfPresent(Double.self, forKey: .flashIntensity) ?? 1.0
    }
}

// MARK: - Theme

struct Theme: Identifiable, Equatable {
    let id: String
    let name: String
    let isDark: Bool
    let top: UInt32
    let bottom: UInt32
    let strong: UInt32
    let medium: UInt32
    let soft: UInt32
    let ink: UInt32

    var background: LinearGradient {
        LinearGradient(colors: [Color(hex: top), Color(hex: bottom)], startPoint: .top, endPoint: .bottom)
    }
    var strongColor: Color { Color(hex: strong) }
    var mediumColor: Color { Color(hex: medium) }
    var softColor: Color { Color(hex: soft) }
    var inkColor: Color { Color(hex: ink) }
    var secondaryInk: Color { Color(hex: ink).opacity(0.62) }
    var surface: Color { Color(hex: ink).opacity(isDark ? 0.07 : 0.06) }
    var surfaceStrong: Color { Color(hex: ink).opacity(isDark ? 0.13 : 0.11) }

    func color(for level: AccentLevel) -> Color {
        switch level {
        case .off: return softColor.opacity(0.35)
        case .soft: return softColor
        case .medium: return mediumColor
        case .strong: return strongColor
        }
    }

    static let ember = Theme(id: "ember", name: "Ember", isDark: true, top: 0x14100D, bottom: 0x2A1710, strong: 0xFF6B3D, medium: 0xFFB347, soft: 0x8A6A55, ink: 0xFFF3E8)
    static let ocean = Theme(id: "ocean", name: "Ocean", isDark: true, top: 0x08121F, bottom: 0x0E2A44, strong: 0x4CC9F0, medium: 0x4895EF, soft: 0x4A6D90, ink: 0xE8F6FF)
    static let neon = Theme(id: "neon", name: "Neon", isDark: true, top: 0x0B0614, bottom: 0x1A0B2E, strong: 0xFF2E93, medium: 0xB14EFF, soft: 0x6E4A9C, ink: 0xF6E9FF)
    static let forest = Theme(id: "forest", name: "Forest", isDark: true, top: 0x0A1410, bottom: 0x12261C, strong: 0x7CFFB2, medium: 0x3DDC97, soft: 0x4C7C68, ink: 0xE8FFF3)
    static let mono = Theme(id: "mono", name: "Mono", isDark: true, top: 0x0A0A0A, bottom: 0x1A1A1A, strong: 0xFFFFFF, medium: 0xC8C8C8, soft: 0x707070, ink: 0xF2F2F2)
    static let paper = Theme(id: "paper", name: "Paper", isDark: false, top: 0xF6F1E7, bottom: 0xE9E0CF, strong: 0xD9381E, medium: 0xE08A1E, soft: 0xA89C84, ink: 0x1E1A14)

    static let all: [Theme] = [.ember, .ocean, .neon, .forest, .mono, .paper]
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}
