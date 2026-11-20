import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// Everything that differs between iOS/iPadOS and macOS lives here, so the rest of the app stays platform-neutral.

/// Haptics. iPhone gets the Taptic Engine; the Mac gives trackpad feedback for UI gestures only (a beat has no hand to feel it).
@MainActor
enum Haptics {
    enum Weight { case light, medium, strong }

    #if os(iOS)
    private static let selectionGen = UISelectionFeedbackGenerator()
    private static let impacts = [
        UIImpactFeedbackGenerator(style: .light), UIImpactFeedbackGenerator(style: .medium), UIImpactFeedbackGenerator(style: .rigid),
    ]
    static func selection() { selectionGen.selectionChanged() }
    static func prepareSelection() { selectionGen.prepare() }
    static func impact(_ weight: Weight, intensity: CGFloat = 1) {
        switch weight {
        case .light: impacts[0].impactOccurred(intensity: intensity)
        case .medium: impacts[1].impactOccurred(intensity: intensity)
        case .strong: impacts[2].impactOccurred(intensity: intensity)
        }
    }
    static let hasTapticEngine = true
    #else
    static func selection() { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default) }
    static func prepareSelection() {}
    static func impact(_ weight: Weight, intensity: CGFloat = 1) {}
    static let hasTapticEngine = false
    #endif
}

/// Keeps the screen on (iOS) or the app out of App Nap and the display awake (macOS) while the metronome runs.
@MainActor
final class StayAwake {
    #if os(macOS)
    private var activity: NSObjectProtocol?
    #endif

    func update(playing: Bool, keepDisplayOn: Bool) {
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = playing && keepDisplayOn
        #else
        if let activity { ProcessInfo.processInfo.endActivity(activity); self.activity = nil }
        if playing {
            // `.userInitiated` stops App Nap throttling the display link while a window is hidden behind another.
            var options: ProcessInfo.ActivityOptions = [.userInitiated]
            if keepDisplayOn { options.insert(.idleDisplaySleepDisabled) }
            activity = ProcessInfo.processInfo.beginActivity(options: options, reason: "Pulse is keeping time")
        }
        #endif
    }
}

/// Calls `tick` once per screen refresh.
@MainActor
final class DisplayLinkDriver: NSObject {
    private var link: CADisplayLink?
    private let tick: () -> Void

    init(tick: @escaping () -> Void) {
        self.tick = tick
        super.init()
        #if os(iOS)
        let l = CADisplayLink(target: self, selector: #selector(fire))
        #else
        // macOS 14+: display links come from the screen the window is on.
        let screen = NSApp?.keyWindow?.screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let l = screen?.displayLink(target: self, selector: #selector(fire)) else { return }
        #endif
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        l.add(to: .main, forMode: .common)
        link = l
    }

    @objc private func fire() { tick() }

    func invalidate() {
        link?.invalidate()
        link = nil
    }
}

// MARK: - SwiftUI shims

extension View {
    /// Number pad on iPhone; nothing on the Mac, where there is a hardware keyboard.
    @ViewBuilder func numberPadKeyboard() -> some View {
        #if os(iOS)
        self.keyboardType(.numberPad)
        #else
        self
        #endif
    }

    /// Digits plus `+` and punctuation, for groupings like `3+3+2`.
    @ViewBuilder func groupingKeyboard() -> some View {
        #if os(iOS)
        self.keyboardType(.numbersAndPunctuation)
        #else
        self
        #endif
    }

    @ViewBuilder func inlineNavigationTitle() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    /// Sheet sizing: detents on iOS; a comfortable fixed panel on the Mac.
    @ViewBuilder func sheetSizing(large: Bool) -> some View {
        #if os(iOS)
        self.presentationDetents(large ? [.large] : [.medium, .large]).presentationDragIndicator(.visible)
        #else
        self.frame(minWidth: 480, idealWidth: 520, minHeight: 520, idealHeight: large ? 700 : 600)
        #endif
    }
}

extension ToolbarItemPlacement {
    /// Leading edge of a sheet's toolbar on every platform.
    static var leadingBar: ToolbarItemPlacement {
        #if os(iOS)
        .topBarLeading
        #else
        .cancellationAction
        #endif
    }
}
