import AVFoundation
import Foundation

/// Owns the one local History player for the containing-app process.
/// Voice uses the same owner as its playback-to-recording handoff boundary.
@MainActor
final class IOSHistoryAudioPlaybackOwner: NSObject,
    IOSForegroundVoiceHistoryPlaybackArbitrating {
    private var player: AVAudioPlayer?

    @discardableResult
    func playCachedAudio(at fileURL: URL) -> Bool {
        stopPlayback()

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)

            let player = try AVAudioPlayer(contentsOf: fileURL)
            guard player.prepareToPlay(), player.play() else {
                try? session.setActive(
                    false,
                    options: .notifyOthersOnDeactivation
                )
                return false
            }
            self.player = player
            return true
        } catch {
            try? AVAudioSession.sharedInstance().setActive(
                false,
                options: .notifyOthersOnDeactivation
            )
            return false
        }
    }

    func stopAndDeactivate() async -> Bool {
        stopPlayback()
        do {
            try AVAudioSession.sharedInstance().setActive(
                false,
                options: .notifyOthersOnDeactivation
            )
            return true
        } catch {
            return false
        }
    }

    private func stopPlayback() {
        player?.stop()
        player = nil
    }
}
