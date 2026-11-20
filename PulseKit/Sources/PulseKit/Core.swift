import Foundation
import os

// MARK: - Published types

/// One pulse as scheduled by the engine. The UI replays these against the clock to animate.
public struct PulseEvent: Sendable, Equatable {
    /// Start of the pulse, in samples since the core was created.
    public var sample: Double = 0
    /// Length of the pulse in samples.
    public var length: Double = 1
    /// Running pulse counter since playback started (count-in included).
    public var index: Int = -1
    /// Index into `settings.bars` of the bar this pulse belongs to.
    public var barSeq: Int = 0
    /// Pulse position inside its bar.
    public var pulse: Int = 0
    public var numerator: Int = 4
    /// Bars completed since the count-in ended.
    public var bar: Int = 0
    public var accent: AccentLevel = .medium
    public var countIn = false
    /// True while a gap-click bar is silent.
    public var muted = false
    public var bpm: Double = 100

    public init() {}
}

/// What the audio thread did, for tests and diagnostics.
public struct TriggerRecord: Sendable {
    public enum Kind: Sendable { case pulse, sub, poly }
    public var kind: Kind
    public var sample: Double
    public var pulse: Int
    public var sub: Int
    /// nil when the slot was silent (muted bar, off accent).
    public var sound: SoundID?
    public var gain: Double
    public var bar: Int
    public var countIn: Bool
    public var muted: Bool
    public var bpm: Double
    public var numerator: Int = 0
}

/// A consistent copy of the engine's public state.
public struct CoreSnapshot: Sendable {
    public var playing = false
    public var sampleRate = 48_000.0
    /// Sample count at the first frame of the most recent buffer.
    public var clockAtBufferStart: Int64 = 0
    /// Wall-clock (host) seconds at which that first frame is rendered.
    public var hostSecondsAtBufferStart = 0.0
    public var liveBPM = 100.0
    /// Most recent pulses, oldest first.
    public var events: [PulseEvent] = []

    public init() {}
}

// MARK: - Compiled settings

/// Settings plus everything derived from them that the audio thread would otherwise have to compute.
final class CompiledSettings {
    let s: MetronomeSettings
    let unitQuarters: Double
    let pitchRatio: Double
    let strong: SoundRecipe
    let medium: SoundRecipe
    let soft: SoundRecipe
    let sub: SoundRecipe
    let poly: SoundRecipe

    init(_ s: MetronomeSettings) {
        self.s = s
        self.unitQuarters = s.effectiveBeatUnit.quarters
        self.pitchRatio = exp2(s.pitchSemitones / 12)
        self.strong = SoundBank.recipe(for: s.sounds.strong)
        self.medium = SoundBank.recipe(for: s.sounds.medium)
        self.soft = SoundBank.recipe(for: s.sounds.soft)
        self.sub = SoundBank.recipe(for: s.sounds.sub)
        self.poly = SoundBank.recipe(for: s.poly.sound)
    }
}

// MARK: - Core

/// Sample-accurate metronome engine.
///
/// `render` is meant to be called from an audio render callback: it never allocates or blocks.
/// Control calls (`apply`, `start`, `stop`, `preview`) come from one other thread (the main thread).
public final class MetronomeCore: @unchecked Sendable {
    public let sampleRate: Double

    /// Called on the audio thread for every slot. Tests only; leave nil in the app.
    public var observer: ((TriggerRecord) -> Void)?

    // Control channel (main thread → audio thread).
    private let controlLock: UnsafeMutablePointer<os_unfair_lock>
    private var pendingCfg: CompiledSettings?
    private var pendingStart = false
    private var pendingStop = false
    private let previewBuffer: UnsafeMutablePointer<Int32>
    private var previewGains: UnsafeMutablePointer<Double>
    private var previewCount = 0
    /// Keeps recent configs alive so the audio thread never drops the last reference.
    private var retained: [CompiledSettings] = []

    // Publication channel (audio thread → main thread).
    private let pubLock: UnsafeMutablePointer<os_unfair_lock>
    private let ringCapacity = 32
    private let ring: UnsafeMutablePointer<PulseEvent>
    private let pubRing: UnsafeMutablePointer<PulseEvent>
    private var ringHead = 0
    private var ringCount = 0
    private var pubHead = 0
    private var pubCount = 0
    private var pubPlaying = false
    private var pubClock: Int64 = 0
    private var pubHost = 0.0
    private var pubBPM = 100.0

    // Audio-thread state.
    private var cfg: CompiledSettings
    private var playing = false
    private var clock: Int64 = 0
    private var nextEventTime = 0.0
    private var pulseStart = 0.0
    private var pulseLen = 1.0
    private var seq = 0
    private var rep = 0
    private var pulse = 0
    private var sub = 0
    private var barsPlayed = 0
    private var globalPulse = 0
    private var inCountIn = false
    private var countInLeft = 0
    private var liveBPM: Double
    private var gapMutedBar = false
    private var needsRestructure = false
    private var polyBarStart = 0.0
    private var polyBarLen = 0.0
    private var polyIndex = 0
    private var nextPolyTime = Double.infinity
    private let maxVoices = 32
    private let voices: UnsafeMutablePointer<Voice>
    private var seedCounter: UInt32 = 0x2545F491

    /// Seconds between `start()` taking effect and the first click.
    public static let startLead = 0.04

    public init(sampleRate: Double, settings: MetronomeSettings) {
        self.sampleRate = sampleRate
        _ = SoundBank.recipes   // warm up off the audio thread
        let c = CompiledSettings(settings)
        cfg = c
        retained = [c]
        liveBPM = settings.bpm
        controlLock = .allocate(capacity: 1); controlLock.initialize(to: os_unfair_lock())
        pubLock = .allocate(capacity: 1); pubLock.initialize(to: os_unfair_lock())
        previewBuffer = .allocate(capacity: 8); previewBuffer.initialize(repeating: 0, count: 8)
        previewGains = .allocate(capacity: 8); previewGains.initialize(repeating: 0, count: 8)
        ring = .allocate(capacity: ringCapacity); ring.initialize(repeating: PulseEvent(), count: ringCapacity)
        pubRing = .allocate(capacity: ringCapacity); pubRing.initialize(repeating: PulseEvent(), count: ringCapacity)
        voices = .allocate(capacity: maxVoices); voices.initialize(repeating: Voice(), count: maxVoices)
        pubBPM = settings.bpm
    }

    deinit {
        controlLock.deallocate(); pubLock.deallocate()
        previewBuffer.deallocate(); previewGains.deallocate()
        ring.deallocate(); pubRing.deallocate(); voices.deallocate()
    }

    // MARK: Control (main thread)

    /// Hands new settings to the audio thread. Takes effect at the next pulse (tempo, sound, subdivision)
    /// or restarts the bar (when the pulse structure changed).
    public func apply(_ settings: MetronomeSettings) {
        let c = CompiledSettings(settings)
        retained.append(c)
        if retained.count > 8 { retained.removeFirst(retained.count - 8) }
        os_unfair_lock_lock(controlLock)
        pendingCfg = c
        os_unfair_lock_unlock(controlLock)
    }

    /// Starts from the top of the pattern (with the count-in, if any).
    public func start() {
        os_unfair_lock_lock(controlLock)
        pendingStart = true
        pendingStop = false
        os_unfair_lock_unlock(controlLock)
    }

    public func stop() {
        os_unfair_lock_lock(controlLock)
        pendingStop = true
        pendingStart = false
        os_unfair_lock_unlock(controlLock)
    }

    /// Plays one sound right away (sound picker audition).
    public func preview(_ sound: SoundID, gain: Double = 0.9) {
        os_unfair_lock_lock(controlLock)
        if previewCount < 8 {
            previewBuffer[previewCount] = Int32(SoundBank.index(of: sound))
            previewGains[previewCount] = gain
            previewCount += 1
        }
        os_unfair_lock_unlock(controlLock)
    }

    /// Latest published state.
    public func snapshot() -> CoreSnapshot {
        var snap = CoreSnapshot()
        os_unfair_lock_lock(pubLock)
        snap.playing = pubPlaying
        snap.clockAtBufferStart = pubClock
        snap.hostSecondsAtBufferStart = pubHost
        snap.liveBPM = pubBPM
        snap.events.reserveCapacity(pubCount)
        for i in 0..<pubCount {
            snap.events.append(pubRing[(pubHead - pubCount + i + ringCapacity) % ringCapacity])
        }
        os_unfair_lock_unlock(pubLock)
        snap.sampleRate = sampleRate
        return snap
    }

    /// The settings most recently handed to `apply`.
    public var currentSettings: MetronomeSettings { retained.last?.s ?? cfg.s }

    // MARK: Render (audio thread)

    /// Fills `left` (and copies to `right`) with `frames` samples.
    /// - Parameter hostSeconds: wall-clock time at which the first frame will be heard.
    public func render(frames: Int, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>?, hostSeconds: Double) {
        adoptControl()
        left.update(repeating: 0, count: frames)
        let bufferStart = clock

        var pos = 0
        while pos < frames {
            if !playing {
                mixVoices(left + pos, frames - pos)
                pos = frames
                break
            }
            let t = min(nextEventTime, nextPolyTime)
            let evSample = Int64(t.rounded(.up))
            let rel = evSample - (clock + Int64(pos))
            if rel <= 0 {
                fire(t)
                continue
            }
            let n = Int(min(rel, Int64(frames - pos)))
            mixVoices(left + pos, n)
            pos += n
        }

        // Gentle ceiling so stacked voices never wrap into digital clipping.
        for i in 0..<frames {
            let x = left[i]
            if x > 0.95 || x < -0.95 { left[i] = Float(tanh(Double(x))) }
        }
        if let right { right.update(from: left, count: frames) }
        clock += Int64(frames)

        if os_unfair_lock_trylock(pubLock) {
            pubClock = bufferStart
            pubHost = hostSeconds
            pubPlaying = playing
            pubBPM = liveBPM
            pubRing.update(from: ring, count: ringCapacity)
            pubHead = ringHead
            pubCount = ringCount
            os_unfair_lock_unlock(pubLock)
        }
    }

    // MARK: Control adoption

    private func adoptControl() {
        guard os_unfair_lock_trylock(controlLock) else { return }
        let newCfg = pendingCfg
        pendingCfg = nil
        let doStart = pendingStart
        let doStop = pendingStop
        pendingStart = false
        pendingStop = false
        let nPreview = previewCount
        var previews = (Int32(0), Int32(0), Int32(0), Int32(0), Int32(0), Int32(0), Int32(0), Int32(0))
        var gains = (0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
        if nPreview > 0 {
            withUnsafeMutableBytes(of: &previews) { $0.baseAddress!.copyMemory(from: previewBuffer, byteCount: 8 * MemoryLayout<Int32>.size) }
            withUnsafeMutableBytes(of: &gains) { $0.baseAddress!.copyMemory(from: previewGains, byteCount: 8 * MemoryLayout<Double>.size) }
            previewCount = 0
        }
        os_unfair_lock_unlock(controlLock)

        if doStop { playing = false }
        if let newCfg {
            let old = cfg
            cfg = newCfg
            if old.s.bpm != newCfg.s.bpm || !playing { liveBPM = newCfg.s.bpm }
            if !sameShape(old.s.bars, newCfg.s.bars) { needsRestructure = true }
        }
        if doStart { startPlayback() }
        if nPreview > 0 {
            withUnsafeBytes(of: &previews) { p in
                withUnsafeBytes(of: &gains) { g in
                    for i in 0..<nPreview {
                        let idx = Int(p.load(fromByteOffset: i * 4, as: Int32.self))
                        let gain = g.load(fromByteOffset: i * 8, as: Double.self)
                        triggerRaw(SoundBank.recipes[idx], gain: gain * cfg.s.volume)
                    }
                }
            }
        }
    }

    private func sameShape(_ a: [BarSpec], _ b: [BarSpec]) -> Bool {
        if a.count != b.count { return false }
        for i in 0..<a.count where !a[i].sameShape(as: b[i]) { return false }
        return true
    }

    private func startPlayback() {
        playing = true
        seq = 0; rep = 0; pulse = 0; sub = 0
        barsPlayed = 0
        globalPulse = 0
        liveBPM = cfg.s.bpm
        countInLeft = cfg.s.countInBars
        inCountIn = countInLeft > 0
        gapMutedBar = false
        needsRestructure = false
        pulseStart = Double(clock) + MetronomeCore.startLead * sampleRate
        pulseLen = computePulseLen()
        nextEventTime = pulseStart
        ringCount = 0
        ringHead = 0
        beginBar()
    }

    // MARK: Scheduling

    @inline(__always) private func currentMeter() -> Meter {
        let bars = cfg.s.bars
        return bars[min(seq, bars.count - 1)].meter
    }

    private func computePulseLen() -> Double {
        let m = currentMeter()
        return sampleRate * (4.0 / Double(m.denominator)) * 60.0 / (liveBPM * cfg.unitQuarters)
    }

    /// Called when `pulseStart` is the first pulse of a bar.
    private func beginBar() {
        let m = currentMeter()
        if inCountIn || !cfg.s.gap.enabled {
            gapMutedBar = false
        } else {
            let cycle = cfg.s.gap.playBars + cfg.s.gap.muteBars
            gapMutedBar = (barsPlayed % cycle) >= cfg.s.gap.playBars
        }
        if cfg.s.poly.enabled && !inCountIn {
            polyBarStart = pulseStart
            polyBarLen = pulseLen * Double(m.numerator)
            polyIndex = 0
            nextPolyTime = polyBarStart
        } else {
            nextPolyTime = .infinity
        }
    }

    private func advanceBar() {
        if inCountIn {
            countInLeft -= 1
            if countInLeft <= 0 {
                inCountIn = false
                seq = 0; rep = 0; barsPlayed = 0
            }
            pulse = 0
            return
        }
        barsPlayed += 1
        rep += 1
        if rep >= cfg.s.bars[min(seq, cfg.s.bars.count - 1)].repeats {
            rep = 0
            seq = (seq + 1) % cfg.s.bars.count
        }
        pulse = 0
        let t = cfg.s.trainer
        if t.enabled && barsPlayed % t.everyBars == 0 {
            if t.targetBPM >= cfg.s.bpm {
                liveBPM = min(liveBPM + t.stepBPM, max(t.targetBPM, cfg.s.bpm))
            } else {
                liveBPM = max(liveBPM - t.stepBPM, t.targetBPM)
            }
        }
    }

    /// Fires whatever is due at time `t` and schedules what comes next.
    private func fire(_ t: Double) {
        if nextEventTime <= t { fireStep() }
        if nextPolyTime <= t { firePoly() }
    }

    private func fireStep() {
        let when = nextEventTime
        let m = currentMeter()
        let s = cfg.s
        let muted = gapMutedBar && !inCountIn

        if sub == 0 {
            var level = pulse < m.accents.count ? m.accents[pulse] : .medium
            if inCountIn && level == .off { level = .soft }
            var ev = PulseEvent()
            ev.sample = pulseStart
            ev.length = pulseLen
            ev.index = globalPulse
            ev.barSeq = seq
            ev.pulse = pulse
            ev.numerator = m.numerator
            ev.bar = barsPlayed
            ev.accent = level
            ev.countIn = inCountIn
            ev.muted = muted
            ev.bpm = liveBPM
            ring[ringHead] = ev
            ringHead = (ringHead + 1) % ringCapacity
            if ringCount < ringCapacity { ringCount += 1 }
            globalPulse += 1

            var sound: SoundID?
            var gain = 0.0
            if level != .off && !muted && (s.subdivision.playsPulse || inCountIn) {
                gain = level.gain
                switch level {
                case .strong: triggerRaw(cfg.strong, gain: gain * s.volume); sound = s.sounds.strong
                case .medium: triggerRaw(cfg.medium, gain: gain * s.volume); sound = s.sounds.medium
                default: triggerRaw(cfg.soft, gain: gain * s.volume); sound = s.sounds.soft
                }
            }
            if let obs = observer {
                obs(TriggerRecord(kind: .pulse, sample: when, pulse: pulse, sub: 0, sound: sound, gain: gain,
                                  bar: barsPlayed, countIn: inCountIn, muted: muted, bpm: liveBPM, numerator: m.numerator))
            }
        } else if !inCountIn {
            let on = sub < s.subdivision.mask.count && s.subdivision.mask[sub] && !muted
            if on {
                triggerRaw(cfg.sub, gain: s.subdivisionVolume * s.volume)
            }
            if let obs = observer {
                obs(TriggerRecord(kind: .sub, sample: when, pulse: pulse, sub: sub, sound: on ? s.sounds.sub : nil,
                                  gain: on ? s.subdivisionVolume : 0, bar: barsPlayed, countIn: false, muted: muted, bpm: liveBPM))
            }
        }

        // Schedule the next slot.
        sub += 1
        let steps = max(1, s.subdivision.steps)
        if sub < steps && !inCountIn {
            nextEventTime = pulseStart + pulseLen * s.subdivision.offset(ofStep: sub)
            return
        }
        sub = 0
        pulseStart += pulseLen
        pulse += 1
        var newBar = false
        if needsRestructure {
            needsRestructure = false
            seq = 0; rep = 0; pulse = 0
            newBar = true
        } else if pulse >= m.numerator {
            advanceBar()
            newBar = true
        }
        pulseLen = computePulseLen()
        nextEventTime = pulseStart
        if newBar { beginBar() }
    }

    private func firePoly() {
        let s = cfg.s
        let when = nextPolyTime
        let muted = gapMutedBar
        if !muted {
            triggerRaw(cfg.poly, gain: s.poly.volume * s.volume)
        }
        if let obs = observer {
            obs(TriggerRecord(kind: .poly, sample: when, pulse: pulse, sub: polyIndex,
                              sound: muted ? nil : s.poly.sound, gain: muted ? 0 : s.poly.volume,
                              bar: barsPlayed, countIn: false, muted: muted, bpm: liveBPM))
        }
        polyIndex += 1
        if polyIndex < s.poly.clicks {
            nextPolyTime = polyBarStart + polyBarLen * Double(polyIndex) / Double(s.poly.clicks)
        } else {
            nextPolyTime = .infinity
        }
    }

    // MARK: Voices

    private func triggerRaw(_ recipe: SoundRecipe, gain: Double) {
        var slot = -1
        for i in 0..<maxVoices where !voices[i].active { slot = i; break }
        if slot < 0 {
            var quietest = Double.infinity
            for i in 0..<maxVoices {
                let e = voices[i].energy
                if e < quietest { quietest = e; slot = i }
            }
        }
        seedCounter = seedCounter &* 1_664_525 &+ 1_013_904_223
        voices[slot].start(recipe, gain: gain, pitchRatio: cfg.pitchRatio, sampleRate: sampleRate, seed: seedCounter)
    }

    private func mixVoices(_ out: UnsafeMutablePointer<Float>, _ frames: Int) {
        guard frames > 0 else { return }
        for i in 0..<maxVoices where voices[i].active {
            voices[i].renderAdd(out, frames: frames)
        }
    }
}

// MARK: - Offline rendering

public extension MetronomeCore {
    /// Renders `seconds` of audio into a mono array. For tests and tools; not real-time safe.
    func renderOffline(seconds: Double, blockSize: Int = 512) -> [Float] {
        let total = Int(seconds * sampleRate)
        var out = [Float](repeating: 0, count: total)
        var block = [Float](repeating: 0, count: blockSize)
        var produced = 0
        while produced < total {
            let n = min(blockSize, total - produced)
            block.withUnsafeMutableBufferPointer { b in
                render(frames: n, left: b.baseAddress!, right: nil, hostSeconds: Double(produced) / sampleRate)
            }
            for i in 0..<n { out[produced + i] = block[i] }
            produced += n
        }
        return out
    }
}
