import SwiftUI
import UIKit
import PulseKit

/// The app's single source of truth: current settings, transport, presets and preferences.
/// Views read it, App Intents call it, and it drives the audio back end.
@MainActor
@Observable
final class Metronome {
    static let shared = Metronome()

    // MARK: State

    private(set) var settings: MetronomeSettings
    private(set) var isPlaying = false
    /// The tempo actually being played (differs from `settings.bpm` while the speed trainer is ramping).
    private(set) var liveBPM: Double
    /// Where playback is right now. Updated every display frame while playing.
    private(set) var phase = PlaybackPhase.idle
    private(set) var userPresets: [Preset]
    private(set) var activePresetID: String?
    var prefs: Preferences { didSet { prefsChanged(old: oldValue) } }
    /// Which bar of a mixed-meter pattern the editor is showing while stopped.
    var editBar = 0
    var lastError: String?
    /// Increments on every tap so the tap button can pulse.
    private(set) var tapCount = 0

    // MARK: Plumbing

    @ObservationIgnored private let output: ClickOutput
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var tapper = TapTempo()
    @ObservationIgnored private var displayLink: DisplayLinkDriver?
    @ObservationIgnored private var lastHapticPulse = -1
    @ObservationIgnored private let impacts: [UIImpactFeedbackGenerator] = [
        UIImpactFeedbackGenerator(style: .light), UIImpactFeedbackGenerator(style: .medium), UIImpactFeedbackGenerator(style: .rigid),
    ]
    @ObservationIgnored private var integration: SystemIntegration?

    nonisolated static let settingsKey = "pulse.settings.v1"
    nonisolated static let prefsKey = "pulse.prefs.v1"
    nonisolated static let presetsKey = "pulse.presets.v1"
    nonisolated static let activeKey = "pulse.activePreset.v1"

    init(output: ClickOutput? = nil, defaults: UserDefaults = .standard, systemIntegration: Bool? = nil) {
        self.defaults = defaults
        let loaded = Metronome.load(MetronomeSettings.self, key: Metronome.settingsKey, from: defaults) ?? MetronomeSettings()
        settings = loaded
        liveBPM = loaded.bpm
        prefs = Metronome.load(Preferences.self, key: Metronome.prefsKey, from: defaults) ?? Preferences()
        userPresets = Metronome.load([Preset].self, key: Metronome.presetsKey, from: defaults) ?? []
        activePresetID = defaults.string(forKey: Metronome.activeKey)
        let out = output ?? AudioOutput()
        self.output = out
        out.mixWithOthers = prefs.mixWithOthers
        out.onInterruption = { [weak self] in self?.stop() }
        let wantsIntegration = systemIntegration ?? (output == nil)
        if wantsIntegration {
            integration = SystemIntegration(metronome: self)
        }
    }

    // MARK: Persistence

    private static func load<T: Decodable>(_ type: T.Type, key: String, from defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func save<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }

    private func persistSettings() { save(settings, key: Metronome.settingsKey) }

    private func prefsChanged(old: Preferences) {
        save(prefs, key: Metronome.prefsKey)
        output.mixWithOthers = prefs.mixWithOthers
        updateIdleTimer()
    }

    // MARK: Transport

    func start() {
        guard !isPlaying else { return }
        do {
            try output.start(settings)
            isPlaying = true
            liveBPM = settings.bpm
            lastHapticPulse = -1
            lastError = nil
            startDisplayLink()
            updateIdleTimer()
            integration?.refresh()
        } catch {
            lastError = "Couldn't start audio: \(error.localizedDescription)"
        }
    }

    func stop() {
        guard isPlaying else { return }
        output.stop()
        isPlaying = false
        phase = .idle
        liveBPM = settings.bpm
        stopDisplayLink()
        updateIdleTimer()
        integration?.refresh()
    }

    func toggle() { isPlaying ? stop() : start() }

    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = isPlaying && prefs.keepAwake
    }

    // MARK: Editing

    /// Applies an edit to the settings, persists it and pushes it to the engine.
    func commit(_ edit: (inout MetronomeSettings) -> Void) {
        var s = settings
        edit(&s)
        // Keep the tempo the trainer reached if the trainer is switched off mid-run.
        if isPlaying, settings.trainer.enabled, !s.trainer.enabled, s.bpm == settings.bpm {
            s.bpm = MetronomeSettings.clamp(liveBPM.rounded())
        }
        s = MetronomeSettings(
            bpm: s.bpm, beatUnitOverride: s.beatUnitOverride, bars: s.bars, subdivision: s.subdivision,
            sounds: s.sounds, pitchSemitones: s.pitchSemitones, volume: s.volume,
            subdivisionVolume: s.subdivisionVolume, poly: s.poly, countInBars: s.countInBars,
            trainer: s.trainer, gap: s.gap)
        guard s != settings else { return }
        settings = s
        editBar = min(editBar, s.bars.count - 1)
        if !isPlaying || !s.trainer.enabled { liveBPM = s.bpm }
        persistSettings()
        output.apply(s)
        if let id = activePresetID, allPresets.first(where: { $0.id == id })?.settings != s {
            activePresetID = nil
            defaults.removeObject(forKey: Metronome.activeKey)
        }
        integration?.refresh()
    }

    // Tempo

    func setBPM(_ value: Double) { commit { $0.setBPM(value) } }

    func nudge(_ delta: Double) { setBPM((settings.bpm + delta).rounded()) }

    /// Multiplies the tempo (used for "double" / "half" / percent changes).
    func scaleBPM(by factor: Double) { setBPM((settings.bpm * factor).rounded()) }

    func tapTempo() {
        tapCount += 1
        if prefs.haptics { impacts[1].impactOccurred() }
        if let bpm = tapper.tap(at: ProcessInfo.processInfo.systemUptime) { setBPM(bpm.rounded()) }
    }

    func setBeatUnit(_ unit: BeatUnit?) {
        // Keep the audible tempo when the unit changes.
        let old = settings.effectiveBeatUnit
        commit { s in
            s.beatUnitOverride = unit
            let new = s.effectiveBeatUnit
            if new != old { s.setBPM((s.bpm * old.quarters / new.quarters).rounded()) }
        }
    }

    // Meter

    func setTimeSignature(numerator: Int, denominator: Int, grouping: [Int]? = nil) {
        commit { $0.setTimeSignature(numerator: numerator, denominator: denominator, grouping: grouping) }
        editBar = 0
    }

    func setMeter(_ meter: Meter, bar: Int) {
        commit { s in
            guard s.bars.indices.contains(bar) else { return }
            s.bars[bar].meter = meter
        }
    }

    func cycleAccent(bar: Int, pulse: Int) {
        commit { s in
            guard s.bars.indices.contains(bar), s.bars[bar].meter.accents.indices.contains(pulse) else { return }
            s.bars[bar].meter.accents[pulse] = s.bars[bar].meter.accents[pulse].next
        }
    }

    func setAccent(bar: Int, pulse: Int, level: AccentLevel) {
        commit { $0.bars.indices.contains(bar) ? $0.bars[bar].meter.setAccent(pulse, level) : () }
    }

    // Sound

    func applyKit(_ kit: SoundKit) { commit { $0.applyKit(kit) } }

    func previewSound(_ id: SoundID) { output.preview(id, settings: settings) }

    // Subdivision

    func setSubdivision(_ sub: Subdivision) { commit { $0.subdivision = sub } }

    // MARK: Presets

    var allPresets: [Preset] { PresetLibrary.all + userPresets }

    var activePreset: Preset? { activePresetID.flatMap { id in allPresets.first { $0.id == id } } }

    func load(_ preset: Preset) {
        var s = preset.settings
        // A preset restores the sound/tempo setup but keeps the user's master volume.
        s.volume = settings.volume
        settings = s
        editBar = 0
        liveBPM = s.bpm
        activePresetID = preset.id
        defaults.set(preset.id, forKey: Metronome.activeKey)
        persistSettings()
        output.apply(s)
        integration?.refresh()
    }

    func load(presetID: String) -> Bool {
        guard let p = allPresets.first(where: { $0.id == presetID }) else { return false }
        load(p)
        return true
    }

    @discardableResult
    func saveCurrentAsPreset(named name: String) -> Preset {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let preset = Preset(name: trimmed.isEmpty ? "My preset" : trimmed, subtitle: settings.summary, settings: settings)
        userPresets.append(preset)
        activePresetID = preset.id
        defaults.set(preset.id, forKey: Metronome.activeKey)
        save(userPresets, key: Metronome.presetsKey)
        PulseShortcuts.updateAppShortcutParameters()
        return preset
    }

    func deletePreset(_ id: String) {
        userPresets.removeAll { $0.id == id }
        if activePresetID == id { activePresetID = nil; defaults.removeObject(forKey: Metronome.activeKey) }
        save(userPresets, key: Metronome.presetsKey)
        PulseShortcuts.updateAppShortcutParameters()
    }

    func resetAll() {
        commit { $0 = MetronomeSettings() }
        activePresetID = nil
        defaults.removeObject(forKey: Metronome.activeKey)
    }

    // MARK: Display link

    private func startDisplayLink() {
        guard displayLink == nil else { return }
        displayLink = DisplayLinkDriver { [weak self] in self?.frame() }
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    private func frame() {
        guard isPlaying, let snap = output.snapshot() else { return }
        let latency = output.outputLatency + prefs.visualOffsetMs / 1000
        let p = PlaybackPhase.compute(from: snap, hostSecondsNow: AudioOutput.nowHostSeconds(), latency: latency)
        phase = p
        if settings.trainer.enabled, abs(snap.liveBPM - liveBPM) > 0.01 { liveBPM = snap.liveBPM }
        if p.pulseIndex != lastHapticPulse, p.pulseIndex >= 0 {
            lastHapticPulse = p.pulseIndex
            if prefs.haptics, !p.muted {
                switch p.accent {
                case .strong: impacts[2].impactOccurred(intensity: 0.9)
                case .medium: impacts[1].impactOccurred(intensity: 0.6)
                case .soft: impacts[0].impactOccurred(intensity: 0.4)
                case .off: break
                }
            }
        }
    }

    /// The tempo to show: the live one while a ramp runs, otherwise the set one.
    var displayBPM: Double { isPlaying && settings.trainer.enabled ? liveBPM : settings.bpm }

    /// Bar shown in the editor / beat grid.
    var visibleBarIndex: Int {
        if isPlaying, phase.pulseIndex >= 0 { return min(phase.barSeq, settings.bars.count - 1) }
        return min(editBar, settings.bars.count - 1)
    }
}

// MARK: - Display link

/// Calls `tick` once per screen refresh.
@MainActor
final class DisplayLinkDriver: NSObject {
    private var link: CADisplayLink?
    private let tick: () -> Void

    init(tick: @escaping () -> Void) {
        self.tick = tick
        super.init()
        let l = CADisplayLink(target: self, selector: #selector(fire))
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
