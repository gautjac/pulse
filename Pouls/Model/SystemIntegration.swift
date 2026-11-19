import Foundation
import MediaPlayer
import PoulsKit

/// Lock-screen / headphone / Control Center transport: play, pause and the Now Playing card.
@MainActor
final class SystemIntegration {
    private weak var metronome: Metronome?
    private var tokens: [(MPRemoteCommand, Any)] = []

    init(metronome: Metronome) {
        self.metronome = metronome
        let center = MPRemoteCommandCenter.shared()
        func add(_ command: MPRemoteCommand, _ handler: @escaping @MainActor (Metronome) -> Void) {
            let token = command.addTarget { [weak metronome] _ in
                guard let metronome else { return .commandFailed }
                MainActor.assumeIsolated { handler(metronome) }
                return .success
            }
            tokens.append((command, token))
        }
        add(center.playCommand) { $0.start() }
        add(center.pauseCommand) { $0.stop() }
        add(center.stopCommand) { $0.stop() }
        add(center.togglePlayPauseCommand) { $0.toggle() }
        add(center.nextTrackCommand) { $0.nudge(5) }
        add(center.previousTrackCommand) { $0.nudge(-5) }
        center.nextTrackCommand.isEnabled = true
        center.previousTrackCommand.isEnabled = true
    }

    func refresh() {
        guard let m = metronome else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: "\(Int(m.displayBPM.rounded())) BPM",
            MPMediaItemPropertyArtist: m.settings.bars.count > 1
                ? m.settings.bars.map { $0.meter.name }.joined(separator: " → ")
                : m.settings.firstMeter.longName,
            MPMediaItemPropertyAlbumTitle: "Pouls",
            MPNowPlayingInfoPropertyPlaybackRate: m.isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyIsLiveStream: true,
        ]
        if let name = m.activePreset?.name { info[MPMediaItemPropertyAlbumTitle] = name }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = m.isPlaying ? .playing : .paused
    }
}
