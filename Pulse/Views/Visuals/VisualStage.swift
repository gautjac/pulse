import SwiftUI
import PulseKit

/// Hosts whichever visual is selected, with a mode picker and a full-screen toggle.
struct VisualStage: View {
    @Environment(Metronome.self) private var m
    @Binding var stage: Bool

    var body: some View {
        let theme = m.prefs.theme
        ZStack {
            RoundedRectangle(cornerRadius: 30, style: .continuous).fill(theme.surface)
            Group {
                switch m.prefs.visualMode {
                case .pendulum: PendulumView()
                case .pulse: PulseView()
                case .orbit: OrbitView()
                case .bounce: BounceView()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .accessibilityHidden(true)
        }
        .overlay(alignment: .topTrailing) {
            Button { stage.toggle() } label: {
                Image(systemName: stage ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(theme.surface))
            }
            .buttonStyle(.plain)
            .padding(10)
            .accessibilityLabel(stage ? "Show controls" : "Full screen visual")
        }
        .overlay(alignment: .bottom) { modePicker(theme).padding(.bottom, 10) }
        .overlay(alignment: .topLeading) {
            if m.isPlaying, m.phase.countIn {
                Text("COUNT-IN")
                    .font(.system(size: 12, weight: .heavy, design: .rounded)).tracking(2)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(theme.strongColor.opacity(0.25)))
                    .padding(14)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .onTapGesture(count: 2) { stage.toggle() }
    }

    private func modePicker(_ theme: Theme) -> some View {
        HStack(spacing: 4) {
            ForEach(VisualMode.allCases) { mode in
                Button { m.prefs.visualMode = mode } label: {
                    Image(systemName: mode.symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 38, height: 32)
                        .background(Capsule().fill(m.prefs.visualMode == mode ? theme.strongColor.opacity(0.3) : .clear))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode.name)
                .accessibilityAddTraits(m.prefs.visualMode == mode ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Capsule().fill(theme.surface))
    }
}

/// How strongly an accent level lights the screen.
func flashStrength(_ level: AccentLevel) -> Double {
    switch level {
    case .strong: return 1.0
    case .medium: return 0.65
    case .soft: return 0.35
    case .off: return 0.0
    }
}

// MARK: - Pendulum

struct PendulumView: View {
    @Environment(Metronome.self) private var m

    var body: some View {
        let theme = m.prefs.theme
        let phase = m.phase
        let bpm = m.displayBPM
        let running = phase.isPlaying && phase.pulseIndex >= 0
        let t = running ? Double(phase.pulseIndex) + phase.progress : 0
        let angle = running ? cos(.pi * t) * 0.40 : 0
        let flash = running && !phase.muted ? exp(-phase.progress * 5) * flashStrength(phase.accent) * m.prefs.flashIntensity : 0
        let accentColor = theme.color(for: running ? phase.accent : .strong)

        Canvas { ctx, size in
            let w = size.width, h = size.height
            let bodyH = min(h * 0.80, w * 1.35)
            let baseW = min(w * 0.60, bodyH * 0.62)
            let topW = baseW * 0.30
            let cx = w / 2
            let baseY = h * 0.5 + bodyH / 2
            let topY = baseY - bodyH

            var body = Path()
            body.move(to: CGPoint(x: cx - baseW / 2, y: baseY))
            body.addLine(to: CGPoint(x: cx + baseW / 2, y: baseY))
            body.addLine(to: CGPoint(x: cx + topW / 2, y: topY))
            body.addLine(to: CGPoint(x: cx - topW / 2, y: topY))
            body.closeSubpath()
            ctx.fill(body, with: .color(theme.inkColor.opacity(0.07)))
            ctx.stroke(body, with: .color(theme.inkColor.opacity(0.28)), style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))

            // tempo scale on the front
            let pivot = CGPoint(x: cx, y: baseY - bodyH * 0.09)
            let rodLen = bodyH * 0.88
            for i in 0..<9 {
                let f = CGFloat(i) / 8
                let y = pivot.y - rodLen * (0.18 + 0.72 * f)
                var tick = Path()
                tick.move(to: CGPoint(x: cx - 14 + (1 - f) * -4, y: y))
                tick.addLine(to: CGPoint(x: cx - 6, y: y))
                ctx.stroke(tick, with: .color(theme.inkColor.opacity(0.18)), lineWidth: 1.5)
            }

            let dir = CGPoint(x: sin(angle), y: -cos(angle))
            let tip = CGPoint(x: pivot.x + dir.x * rodLen, y: pivot.y + dir.y * rodLen)
            var rod = Path()
            rod.move(to: pivot)
            rod.addLine(to: tip)
            ctx.stroke(rod, with: .color(theme.inkColor.opacity(0.85)), style: StrokeStyle(lineWidth: 5, lineCap: .round))

            // The weight rides higher for slower tempos.
            let bpmFrac = min(max((bpm - 30) / 230, 0), 1)
            let wf = 0.88 - 0.66 * bpmFrac
            let wp = CGPoint(x: pivot.x + dir.x * rodLen * wf, y: pivot.y + dir.y * rodLen * wf)
            var weightCtx = ctx
            weightCtx.translateBy(x: wp.x, y: wp.y)
            weightCtx.rotate(by: .radians(angle))
            let ww = baseW * 0.30, wh = baseW * 0.17
            let weight = Path(roundedRect: CGRect(x: -ww / 2, y: -wh / 2, width: ww, height: wh), cornerRadius: 6)
            weightCtx.fill(weight, with: .color(accentColor))
            weightCtx.stroke(weight, with: .color(theme.inkColor.opacity(0.4)), lineWidth: 1.5)

            // glow at the tip on the beat
            if flash > 0.01 {
                let r = 10 + flash * 22
                ctx.fill(Path(ellipseIn: CGRect(x: tip.x - r, y: tip.y - r, width: r * 2, height: r * 2)), with: .color(accentColor.opacity(flash * 0.55)))
            }
            ctx.fill(Path(ellipseIn: CGRect(x: tip.x - 6, y: tip.y - 6, width: 12, height: 12)), with: .color(theme.inkColor.opacity(0.9)))

            // pivot cap and the lamp at the top of the case
            ctx.fill(Path(ellipseIn: CGRect(x: pivot.x - 9, y: pivot.y - 9, width: 18, height: 18)), with: .color(theme.inkColor))
            let lampR: CGFloat = 8 + flash * 3
            ctx.fill(Path(ellipseIn: CGRect(x: cx - lampR, y: topY + 22 - lampR, width: lampR * 2, height: lampR * 2)),
                     with: .color(flash > 0.05 ? accentColor : theme.softColor.opacity(0.6)))
        }
        .padding(.bottom, 44)
    }
}

// MARK: - Pulse

struct PulseView: View {
    @Environment(Metronome.self) private var m
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let theme = m.prefs.theme
        let phase = m.phase
        let running = phase.isPlaying && phase.pulseIndex >= 0
        let strength = flashStrength(phase.accent) * m.prefs.flashIntensity * (reduceMotion ? 0.4 : 1)
        let flash = running && !phase.muted ? exp(-phase.progress * 7) * strength : 0
        let meter = m.settings.bars[min(phase.barSeq, m.settings.bars.count - 1)].meter
        let color = theme.color(for: running ? phase.accent : .strong)

        ZStack {
            Rectangle().fill(color).opacity(flash)
            VStack(spacing: 4) {
                if m.prefs.showCounts {
                    Text(running ? "\(meter.countNumber(forPulse: min(phase.pulse, meter.numerator - 1)))" : "–")
                        .font(.system(size: 190, weight: .heavy, design: .rounded))
                        .minimumScaleFactor(0.3)
                        .lineLimit(1)
                        .foregroundStyle(flash > 0.5 ? (theme.isDark ? Color.black.opacity(0.85) : .white) : theme.inkColor)
                        .contentTransition(.identity)
                }
                if running, meter.grouping.count > 1, meter.grouping.contains(where: { $0 > 1 }) {
                    HStack(spacing: 8) {
                        ForEach(0..<meter.grouping.count, id: \.self) { g in
                            Capsule()
                                .fill(g == meter.groupInfo(forPulse: phase.pulse).group ? theme.inkColor : theme.inkColor.opacity(0.25))
                                .frame(width: CGFloat(meter.grouping[g]) * 10, height: 6)
                        }
                    }
                }
            }
            .padding(.bottom, 64)
        }
    }
}

// MARK: - Orbit

struct OrbitView: View {
    @Environment(Metronome.self) private var m

    var body: some View {
        let theme = m.prefs.theme
        let phase = m.phase
        let running = phase.isPlaying && phase.pulseIndex >= 0
        let bar = m.settings.bars[min(running ? phase.barSeq : m.visibleBarIndex, m.settings.bars.count - 1)]
        let meter = bar.meter
        let sub = m.settings.subdivision
        let n = meter.numerator
        let progress = running ? phase.barProgress : 0
        let flash = running && !phase.muted ? exp(-phase.progress * 6) * flashStrength(phase.accent) * m.prefs.flashIntensity : 0

        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2 - 12)
            let r = min(size.width, size.height - 70) * 0.40
            func point(_ f: Double, _ rad: CGFloat) -> CGPoint {
                let a = -Double.pi / 2 + 2 * Double.pi * f
                return CGPoint(x: c.x + rad * CGFloat(cos(a)), y: c.y + rad * CGFloat(sin(a)))
            }
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                       with: .color(theme.inkColor.opacity(0.14)), lineWidth: 2)

            // swept arc
            if running {
                var arc = Path()
                arc.addArc(center: c, radius: r, startAngle: .radians(-Double.pi / 2), endAngle: .radians(-Double.pi / 2 + 2 * Double.pi * progress), clockwise: false)
                ctx.stroke(arc, with: .color(theme.strongColor.opacity(0.35)), style: StrokeStyle(lineWidth: 8, lineCap: .round))
            }

            // group separators
            var start = 0
            for g in meter.grouping {
                let a = point((Double(start)) / Double(n) - 0.5 / Double(n), r - 14)
                let b = point((Double(start)) / Double(n) - 0.5 / Double(n), r + 14)
                var sep = Path(); sep.move(to: a); sep.addLine(to: b)
                if meter.grouping.count > 1 { ctx.stroke(sep, with: .color(theme.inkColor.opacity(0.18)), lineWidth: 1.5) }
                start += g
            }

            // subdivision ticks
            if sub.steps > 1 {
                for i in 0..<n {
                    for k in 1..<sub.steps where sub.mask[k] {
                        let f = (Double(i) + sub.offset(ofStep: k)) / Double(n)
                        let p = point(f, r)
                        ctx.fill(Path(ellipseIn: CGRect(x: p.x - 2.5, y: p.y - 2.5, width: 5, height: 5)), with: .color(theme.inkColor.opacity(0.4)))
                    }
                }
            }

            // pulses
            for i in 0..<n {
                let level = meter.accents[i]
                let p = point(Double(i) / Double(n), r)
                var dot: CGFloat
                switch level { case .strong: dot = 15; case .medium: dot = 11; case .soft: dot = 8; case .off: dot = 4.5 }
                let current = running && phase.pulse == i
                if current { dot += CGFloat(flash) * 10 }
                if current && flash > 0.02 {
                    let g = dot + 16 * CGFloat(flash)
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - g, y: p.y - g, width: g * 2, height: g * 2)), with: .color(theme.color(for: level).opacity(0.35 * flash)))
                }
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - dot, y: p.y - dot, width: dot * 2, height: dot * 2)), with: .color(theme.color(for: level)))
            }

            // hand
            if running {
                let tip = point(progress, r)
                var hand = Path(); hand.move(to: c); hand.addLine(to: point(progress, r - 22))
                ctx.stroke(hand, with: .color(theme.inkColor.opacity(0.8)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                ctx.fill(Path(ellipseIn: CGRect(x: tip.x - 5, y: tip.y - 5, width: 10, height: 10)), with: .color(theme.inkColor))
            }
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - 7, y: c.y - 7, width: 14, height: 14)), with: .color(theme.inkColor))
        }
        .overlay {
            if m.prefs.showCounts, running {
                Text("\(meter.countNumber(forPulse: min(phase.pulse, n - 1)))")
                    .font(.system(size: 64, weight: .heavy, design: .rounded))
                    .foregroundStyle(theme.inkColor.opacity(0.14))
                    .offset(y: -12)
            }
        }
        .padding(.bottom, 20)
    }
}

// MARK: - Bounce

struct BounceView: View {
    @Environment(Metronome.self) private var m

    var body: some View {
        let theme = m.prefs.theme
        let phase = m.phase
        let running = phase.isPlaying && phase.pulseIndex >= 0
        let bar = m.settings.bars[min(running ? phase.barSeq : m.visibleBarIndex, m.settings.bars.count - 1)]
        let meter = bar.meter
        let n = meter.numerator

        Canvas { ctx, size in
            let w = size.width, h = size.height
            let margin: CGFloat = 26
            let usable = w - margin * 2
            let groundY = h - 112
            let padW = min(usable / CGFloat(n) - 4, 46)
            func padX(_ i: Int) -> CGFloat { margin + usable * (CGFloat(i) + 0.5) / CGFloat(n) }

            // pads
            for i in 0..<n {
                let level = meter.accents[i]
                let current = running && phase.pulse == i
                let hit = current ? exp(-phase.progress * 7) : 0
                let pad = CGRect(x: padX(i) - padW / 2, y: groundY + CGFloat(hit) * 6, width: padW, height: 10)
                ctx.fill(Path(roundedRect: pad, cornerRadius: 5), with: .color(theme.color(for: level).opacity(level == .off ? 0.5 : 0.95)))
                if hit > 0.02 {
                    let g = pad.insetBy(dx: -8 * CGFloat(hit), dy: -8 * CGFloat(hit))
                    ctx.fill(Path(roundedRect: g, cornerRadius: 8), with: .color(theme.color(for: level).opacity(0.35 * hit)))
                }
            }

            // ball
            let from = running ? phase.pulse : 0
            let to = (from + 1) % n
            let f = running ? phase.progress : 0
            let x = padX(from) + (padX(to) - padX(from)) * CGFloat(f)
            let apex = min(h * 0.55, 190)
            let lift = running ? 4 * f * (1 - f) : 0
            let squash = running ? exp(-phase.progress * 12) * 0.35 : 0
            let radius: CGFloat = 17
            let y = groundY - radius - CGFloat(lift) * apex * (phase.accent == .strong ? 1.0 : 0.82)
            let ball = CGRect(x: x - radius * (1 + CGFloat(squash)), y: y - radius * (1 - CGFloat(squash)) + CGFloat(squash) * radius,
                              width: radius * 2 * (1 + CGFloat(squash)), height: radius * 2 * (1 - CGFloat(squash)))
            // shadow
            let sh = 1 - CGFloat(lift) * 0.6
            ctx.fill(Path(ellipseIn: CGRect(x: x - 18 * sh, y: groundY - 3, width: 36 * sh, height: 6)), with: .color(.black.opacity(0.25 * Double(sh))))
            ctx.fill(Path(ellipseIn: ball), with: .color(theme.color(for: running ? phase.accent : .strong)))
            ctx.stroke(Path(ellipseIn: ball), with: .color(theme.inkColor.opacity(0.5)), lineWidth: 2)

            // count labels
            for i in 0..<n {
                let t = Text("\(meter.countNumber(forPulse: i))")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(running && phase.pulse == i ? theme.inkColor : theme.secondaryInk)
                ctx.draw(t, at: CGPoint(x: padX(i), y: groundY + 28))
            }
        }
    }
}
