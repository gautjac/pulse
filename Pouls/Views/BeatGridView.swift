import SwiftUI
import PoulsKit

/// One tappable column per pulse of the bar. Height = loudness; tap to change it.
struct BeatGridView: View {
    @Environment(Metronome.self) private var m

    var body: some View {
        let theme = m.prefs.theme
        let barIndex = m.visibleBarIndex
        let spec = m.settings.bars[barIndex]
        let meter = spec.meter
        let phase = m.phase
        let live = m.isPlaying && phase.pulseIndex >= 0 && phase.barSeq == barIndex

        VStack(spacing: 8) {
            if m.settings.bars.count > 1 { barPager(theme, playing: m.isPlaying ? phase.barSeq : nil) }
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(meter.grouping.enumerated()), id: \.offset) { gi, size in
                    let start = meter.grouping.prefix(gi).reduce(0, +)
                    ForEach(0..<size, id: \.self) { i in
                        let pulse = start + i
                        PulseCell(
                            level: meter.accents[pulse],
                            isCurrent: live && phase.pulse == pulse,
                            progress: phase.progress,
                            label: label(meter, pulse),
                            muted: live && phase.muted,
                            theme: theme)
                        .onTapGesture {
                            Haptics.selection.selectionChanged()
                            m.cycleAccent(bar: barIndex, pulse: pulse)
                        }
                        .contextMenu {
                            ForEach(AccentLevel.allCases.reversed(), id: \.self) { level in
                                Button(level.label) { m.setAccent(bar: barIndex, pulse: pulse, level: level) }
                            }
                        }
                        .accessibilityElement()
                        .accessibilityLabel("Beat \(meter.countNumber(forPulse: pulse)), group \(meter.groupInfo(forPulse: pulse).group + 1)")
                        .accessibilityValue(meter.accents[pulse].label)
                        .accessibilityHint("Double tap to change the accent")
                        .accessibilityAddTraits(.isButton)
                    }
                    if gi < meter.grouping.count - 1 { Color.clear.frame(width: meter.numerator > 16 ? 3 : 9, height: 1) }
                }
            }
            .frame(height: 84)
        }
    }

    private func label(_ meter: Meter, _ pulse: Int) -> String? {
        if meter.numerator > 20 { return meter.groupInfo(forPulse: pulse).isStart ? "\(meter.countNumber(forPulse: pulse))" : nil }
        return "\(meter.countNumber(forPulse: pulse))"
    }

    private func barPager(_ theme: Theme, playing: Int?) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(m.settings.bars.enumerated()), id: \.element.id) { i, bar in
                    let selected = i == m.visibleBarIndex
                    Button { m.editBar = i } label: {
                        HStack(spacing: 5) {
                            if playing == i { Circle().fill(theme.strongColor).frame(width: 6, height: 6) }
                            Text(bar.meter.name + (bar.repeats > 1 ? " ×\(bar.repeats)" : ""))
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                        }
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(selected ? theme.strongColor.opacity(0.25) : theme.surface))
                        .overlay(Capsule().stroke(selected ? theme.strongColor.opacity(0.7) : .clear, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct PulseCell: View {
    let level: AccentLevel
    let isCurrent: Bool
    let progress: Double
    let label: String?
    let muted: Bool
    let theme: Theme

    private var fraction: CGFloat {
        switch level {
        case .off: return 0.1
        case .soft: return 0.36
        case .medium: return 0.66
        case .strong: return 1
        }
    }

    var body: some View {
        let flash = isCurrent ? exp(-progress * 4) : 0
        VStack(spacing: 4) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(theme.surface)
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(theme.color(for: level))
                    .frame(height: 62 * fraction)
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(flash * 0.55)))
            }
            .frame(height: 62)
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(theme.inkColor.opacity(isCurrent ? 0.9 : 0), lineWidth: 2))
            .scaleEffect(1 + flash * 0.07, anchor: .bottom)
            .opacity(muted ? 0.4 : 1)
            Text(label ?? " ")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(isCurrent ? theme.inkColor : theme.secondaryInk)
                .lineLimit(1).minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}
