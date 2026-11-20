import SwiftUI
import UIKit
import PulseKit

/// Shared haptic generators so rapid interaction does not allocate.
@MainActor
enum Haptics {
    static let selection = UISelectionFeedbackGenerator()
    static let light = UIImpactFeedbackGenerator(style: .light)
}

struct Chip: View {
    let title: String
    var subtitle: String?
    let symbol: String
    var active = false
    let theme: Theme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 17, weight: .semibold))
                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(subtitle ?? " ")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.secondaryInk)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(active ? theme.strongColor.opacity(0.22) : theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(active ? theme.strongColor.opacity(0.7) : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.inkColor)
    }
}

struct SheetScaffold<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
        }
    }
}

/// A round button that repeats while held, speeding up.
struct RepeatButton: View {
    let symbol: String
    let label: String
    let theme: Theme
    let action: () -> Void
    @State private var task: Task<Void, Never>?
    @State private var pressed = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 22, weight: .bold))
            .foregroundStyle(theme.inkColor)
            .frame(width: 58, height: 58)
            .background(Circle().fill(theme.surfaceStrong))
            .scaleEffect(pressed ? 0.9 : 1)
            .animation(.spring(duration: 0.18), value: pressed)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in begin() }
                    .onEnded { _ in end() }
            )
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
    }

    private func begin() {
        guard task == nil else { return }
        pressed = true
        action()
        task = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(380))
            var delay = 110
            while !Task.isCancelled {
                action()
                try? await Task.sleep(for: .milliseconds(delay))
                delay = max(32, delay - 6)
            }
        }
    }

    private func end() {
        task?.cancel()
        task = nil
        pressed = false
    }
}

/// "2+2+3" drawn as grouped dots.
struct GroupingPreview: View {
    let meter: Meter
    let theme: Theme

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(meter.grouping.enumerated()), id: \.offset) { _, size in
                HStack(spacing: 3) {
                    ForEach(0..<size, id: \.self) { i in
                        Circle().fill(i == 0 ? theme.strongColor : theme.softColor).frame(width: i == 0 ? 10 : 7, height: i == 0 ? 10 : 7)
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(Capsule().fill(theme.surface))
            }
        }
    }
}
