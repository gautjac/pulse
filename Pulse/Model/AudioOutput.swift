import AVFoundation
import PulseKit

/// What the model needs from an audio back end. The real one plays through AVAudioEngine; tests use a stub.
@MainActor
protocol ClickOutput: AnyObject {
    var mixWithOthers: Bool { get set }
    /// Seconds between a sample being rendered and being heard.
    var outputLatency: Double { get }
    var onInterruption: (() -> Void)? { get set }
    func start(_ settings: MetronomeSettings) throws
    func stop()
    func apply(_ settings: MetronomeSettings)
    func preview(_ sound: SoundID, settings: MetronomeSettings)
    func snapshot() -> CoreSnapshot?
}

/// Plays the engine through AVAudioEngine with a source node that calls straight into `MetronomeCore.render`.
@MainActor
final class AudioOutput: ClickOutput {
    var mixWithOthers = true
    var onInterruption: (() -> Void)?

    private var engine = AVAudioEngine()
    private var source: AVAudioSourceNode?
    private(set) var core: MetronomeCore?
    private var latest = MetronomeSettings()
    private var playing = false
    private var idleWork: DispatchWorkItem?
    private var observers: [NSObjectProtocol] = []

    init() {
        let nc = NotificationCenter.default
        #if os(iOS)
        observers.append(nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
            MainActor.assumeIsolated { self?.onInterruption?() }
        })
        observers.append(nc.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable else { return }
            MainActor.assumeIsolated { self?.onInterruption?() }   // headphones pulled: stop, like any player
        })
        #endif
        observers.append(nc.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuildAfterConfigurationChange() }
        })
    }

    var outputLatency: Double {
        #if os(iOS)
        AVAudioSession.sharedInstance().outputLatency
        #else
        // The device's own latency plus the engine's buffering, as CoreAudio reports it.
        engine.outputNode.presentationLatency
        #endif
    }

    // MARK: ClickOutput

    func start(_ settings: MetronomeSettings) throws {
        latest = settings
        idleWork?.cancel()
        try prepare()
        core?.apply(settings)
        core?.start()
        playing = true
    }

    func stop() {
        playing = false
        core?.stop()
        scheduleIdleShutdown()
    }

    func apply(_ settings: MetronomeSettings) {
        latest = settings
        core?.apply(settings)
    }

    func preview(_ sound: SoundID, settings: MetronomeSettings) {
        latest = settings
        idleWork?.cancel()
        do {
            try prepare()
            core?.apply(settings)
            core?.preview(sound)
            if !playing { scheduleIdleShutdown(after: 2.0) }
        } catch {
            NSLog("Pulse: preview failed: \(error)")
        }
    }

    func snapshot() -> CoreSnapshot? { core?.snapshot() }

    // MARK: Engine

    private func prepare() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: mixWithOthers ? [.mixWithOthers] : [])
        try? session.setPreferredIOBufferDuration(0.005)
        try session.setActive(true)
        let rate = session.sampleRate > 0 ? session.sampleRate : 48_000
        #else
        // macOS has no audio session: the output device's own rate is the engine's rate.
        let deviceRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let rate = deviceRate > 0 ? deviceRate : 48_000
        #endif
        if core == nil || core?.sampleRate != rate { buildGraph(sampleRate: rate) }
        if !engine.isRunning {
            engine.prepare()
            try engine.start()
        }
    }

    private func buildGraph(sampleRate: Double) {
        engine.stop()
        if let source { engine.detach(source) }
        engine = AVAudioEngine()
        let core = MetronomeCore(sampleRate: sampleRate, settings: latest)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let node = AVAudioSourceNode(format: format) { _, timeStamp, frameCount, bufferList -> OSStatus in
            let abl = UnsafeMutableAudioBufferListPointer(bufferList)
            guard abl.count >= 1, let left = abl[0].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            let right: UnsafeMutablePointer<Float>? = abl.count > 1 ? abl[1].mData?.assumingMemoryBound(to: Float.self) : nil
            let host = AVAudioTime.seconds(forHostTime: timeStamp.pointee.mHostTime)
            core.render(frames: Int(frameCount), left: left, right: right, hostSeconds: host)
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        source = node
        self.core = core
    }

    /// A route change (Bluetooth connects, sample rate switches) stops the engine; bring it back.
    private func rebuildAfterConfigurationChange() {
        guard core != nil else { return }
        let wasPlaying = playing
        core = nil
        do {
            try prepare()
            core?.apply(latest)
            if wasPlaying { core?.start() }
        } catch {
            NSLog("Pulse: could not restart audio: \(error)")
            if wasPlaying { onInterruption?() }
        }
    }

    private func scheduleIdleShutdown(after delay: TimeInterval = 1.5) {
        idleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.playing else { return }
            self.engine.pause()
            #if os(iOS)
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            #endif
        }
        idleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Wall-clock now on the same axis as the render callback's host time.
    static func nowHostSeconds() -> Double {
        AVAudioTime.seconds(forHostTime: mach_absolute_time())
    }
}

/// Silent stand-in used by tests and previews.
@MainActor
final class NullOutput: ClickOutput {
    var mixWithOthers = true
    var outputLatency = 0.0
    var onInterruption: (() -> Void)?
    private(set) var started: [MetronomeSettings] = []
    private(set) var applied: [MetronomeSettings] = []
    private(set) var previews: [SoundID] = []
    private(set) var stopCount = 0
    var failOnStart = false

    func start(_ settings: MetronomeSettings) throws {
        if failOnStart { throw NSError(domain: "NullOutput", code: 1) }
        started.append(settings)
    }
    func stop() { stopCount += 1 }
    func apply(_ settings: MetronomeSettings) { applied.append(settings) }
    func preview(_ sound: SoundID, settings: MetronomeSettings) { previews.append(sound) }
    func snapshot() -> CoreSnapshot? { nil }
}
