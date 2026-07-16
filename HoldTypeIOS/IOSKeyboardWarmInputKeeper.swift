import AVFAudio
import Foundation

/// Keeps one real input render pipeline alive for the bounded keyboard
/// dictation session. Individual dictations continue to own their existing
/// descriptor-bound recorders; this owner only prevents iOS from tearing down
/// the background input capability between those recorders.
@MainActor
final class IOSKeyboardWarmInputKeeper {
    private enum KeeperError: Error {
        case inputUnavailable
    }

    private var engine: AVAudioEngine?

    var isRunning: Bool { engine?.isRunning == true }

    func startIfNeeded() throws {
        if isRunning { return }
        stop()

        let candidate = AVAudioEngine()
        let input = candidate.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate.isFinite,
              format.sampleRate > 0,
              format.channelCount > 0 else {
            throw KeeperError.inputUnavailable
        }

        input.installTap(
            onBus: 0,
            bufferSize: 1_024,
            format: format
        ) { _, _ in
            // The active descriptor-bound recorder owns persisted audio. This
            // tap intentionally retains no speech buffers between attempts.
        }
        candidate.prepare()
        do {
            try candidate.start()
            engine = candidate
        } catch {
            input.removeTap(onBus: 0)
            candidate.stop()
            throw error
        }
    }

    func stop() {
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        engine.reset()
        self.engine = nil
    }
}
