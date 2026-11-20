import SwiftUI
import PulseKit

struct TempoPanel: View {
    @Environment(Metronome.self) private var m
    let onEdit: () -> Void

    var body: some View {
        let theme = m.prefs.theme
        let bpm = m.displayBPM
        let unit = m.settings.effectiveBeatUnit
        VStack(spacing: 8) {
            HStack {
                RepeatButton(symbol: "minus", label: "Slower", theme: theme) { m.nudge(-1) }
                Spacer()
                VStack(spacing: 2) {
                    Button(action: onEdit) {
                        Text(bpmText(bpm))
                            .font(.system(size: 78, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .minimumScaleFactor(0.6)
                            .contentTransition(.numericText(value: bpm))
                            .animation(.snappy(duration: 0.2), value: Int(bpm.rounded()))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Tempo \(Int(bpm.rounded())) beats per minute. Double tap to type a tempo.")
                    HStack(spacing: 6) {
                        unitMenu(theme, unit: unit)
                        Text("·").foregroundStyle(theme.secondaryInk)
                        Text(TempoMarking.name(forBPM: bpm, unit: unit))
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(theme.secondaryInk)
                    }
                }
                Spacer()
                RepeatButton(symbol: "plus", label: "Faster", theme: theme) { m.nudge(1) }
            }
            TempoRuler(bpm: m.settings.bpm, theme: theme, haptics: m.prefs.haptics) { m.setBPM($0) }
                .frame(height: 46)
                .accessibilityElement()
                .accessibilityLabel("Tempo ruler")
                .accessibilityValue("\(Int(m.settings.bpm.rounded())) BPM")
                .accessibilityAdjustableAction { dir in m.nudge(dir == .increment ? 1 : -1) }
            HStack(spacing: 10) {
                pill("½×", theme) { m.scaleBPM(by: 0.5) }.frame(width: 64)
                tapButton(theme)
                pill("2×", theme) { m.scaleBPM(by: 2) }.frame(width: 64)
            }
        }
    }

    private func bpmText(_ v: Double) -> String {
        let r = v.rounded()
        return abs(v - r) < 0.05 ? "\(Int(r))" : String(format: "%.1f", v)
    }

    private func unitMenu(_ theme: Theme, unit: BeatUnit) -> some View {
        Menu {
            Button {
                m.setBeatUnit(nil)
            } label: {
                Label("Automatic (\(m.settings.firstMeter.suggestedBeatUnit.name))", systemImage: m.settings.beatUnitOverride == nil ? "checkmark" : "wand.and.stars")
            }
            Divider()
            ForEach(BeatUnit.allCases) { u in
                Button {
                    m.setBeatUnit(u)
                } label: {
                    Label(u.name, systemImage: m.settings.beatUnitOverride == u ? "checkmark" : "music.note")
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text("BPM")
                Text("per \(unit.shortName)").foregroundStyle(theme.secondaryInk)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(theme.secondaryInk)
            }
            .font(.system(size: 15, weight: .semibold, design: .rounded))
        }
        .accessibilityLabel("Beat unit, \(unit.name)")
    }

    private func pill(_ title: String, _ theme: Theme, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(Capsule().fill(theme.surface))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title == "2×" ? "Double tempo" : "Halve tempo")
    }

    private func tapButton(_ theme: Theme) -> some View {
        Button { m.tapTempo() } label: {
            HStack(spacing: 8) {
                Image(systemName: "hand.tap.fill")
                Text("TAP TEMPO").tracking(1.5)
            }
            .font(.system(size: 15, weight: .heavy, design: .rounded))
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(Capsule().fill(theme.strongColor.opacity(0.2)))
            .overlay(Capsule().stroke(theme.strongColor.opacity(0.6), lineWidth: 1.5))
            .scaleEffect(m.tapCount % 2 == 0 ? 1 : 0.97)
            .animation(.spring(duration: 0.15), value: m.tapCount)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Tap tempo")
    }
}

/// A tape of tick marks you drag sideways; every whole BPM clicks under your thumb.
struct TempoRuler: View {
    let bpm: Double
    let theme: Theme
    let haptics: Bool
    let onChange: (Double) -> Void

    @State private var dragStart: Double?
    @State private var shown: Double?
    @State private var lastWhole = 0
    private let points: CGFloat = 7

    var body: some View {
        let value = shown ?? bpm
        Canvas { ctx, size in
            let mid = size.width / 2
            let span = Int(size.width / points / 2) + 3
            let center = Int(value.rounded())
            for v in (center - span)...(center + span) where v >= 20 && v <= 400 {
                let x = mid + (CGFloat(v) - CGFloat(value)) * points
                let major = v % 10 == 0
                let half = v % 5 == 0
                let h: CGFloat = major ? 24 : (half ? 17 : 11)
                var p = Path()
                p.move(to: CGPoint(x: x, y: size.height - h))
                p.addLine(to: CGPoint(x: x, y: size.height))
                ctx.stroke(p, with: .color(theme.inkColor.opacity(major ? 0.75 : 0.32)), style: StrokeStyle(lineWidth: major ? 2 : 1.3, lineCap: .round))
                if major {
                    ctx.draw(Text("\(v)").font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundStyle(theme.secondaryInk),
                             at: CGPoint(x: x, y: size.height - h - 8))
                }
            }
        }
        .mask(LinearGradient(stops: [
            .init(color: .clear, location: 0), .init(color: .black, location: 0.2),
            .init(color: .black, location: 0.8), .init(color: .clear, location: 1),
        ], startPoint: .leading, endPoint: .trailing))
        .overlay(alignment: .bottom) {
            Capsule().fill(theme.strongColor).frame(width: 3.5, height: 32).shadow(color: theme.strongColor.opacity(0.6), radius: 4)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { g in
                    if dragStart == nil { dragStart = bpm; lastWhole = Int(bpm.rounded()); Haptics.prepareSelection() }
                    let raw = (dragStart ?? bpm) - Double(g.translation.width / points)
                    let clamped = min(max(raw, 20), 400)
                    shown = clamped
                    let whole = Int(clamped.rounded())
                    if whole != lastWhole {
                        lastWhole = whole
                        onChange(Double(whole))
                        if haptics { Haptics.selection() }
                    }
                }
                .onEnded { _ in dragStart = nil; shown = nil }
        )
    }
}
