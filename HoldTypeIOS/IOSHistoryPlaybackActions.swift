import Foundation
import HoldTypeDomain
import HoldTypePersistence

enum IOSHistoryPlaybackAttempt: Equatable {
    case played
    case unavailable
    case failed
}

/// Small containing-app boundary between the text-only History screen and the
/// independent accepted-recording cache.
@MainActor
struct IOSHistoryPlaybackActions {
    private let resolvePlayableResultIDs: ([UUID]) async -> Set<UUID>
    private let playRecording: (UUID) async -> IOSHistoryPlaybackAttempt
    private let stopPlayback: () async -> Void
    private let reconcileCache: (RecordingCachePolicy) async -> Bool

    init(
        cache: IOSAcceptedAudioCache,
        loadPolicy: @escaping @Sendable () async -> RecordingCachePolicy,
        player: IOSHistoryAudioPlaybackOwner
    ) {
        resolvePlayableResultIDs = { resultIDs in
            guard (await loadPolicy()).normalized.keepsRecordings else {
                return []
            }

            var playable = Set<UUID>()
            playable.reserveCapacity(resultIDs.count)
            for resultID in resultIDs {
                if await cache.cachedAudioFileURLIfAvailable(
                    resultID: resultID
                ) != nil {
                    playable.insert(resultID)
                }
            }
            return playable
        }
        playRecording = { resultID in
            guard (await loadPolicy()).normalized.keepsRecordings,
                  let fileURL = await cache
                    .cachedAudioFileURLIfAvailable(resultID: resultID) else {
                return .unavailable
            }
            return player.playCachedAudio(at: fileURL)
                ? .played
                : .failed
        }
        stopPlayback = {
            _ = await player.stopAndDeactivate()
        }
        reconcileCache = { policy in
            if !policy.normalized.keepsRecordings {
                _ = await player.stopAndDeactivate()
            }
            do {
                try await cache.reconcile(policy: policy)
                return true
            } catch {
                return false
            }
        }
    }

    init(
        resolvePlayableResultIDs: @escaping ([UUID]) async -> Set<UUID>,
        playRecording: @escaping (UUID) async
            -> IOSHistoryPlaybackAttempt,
        stopPlayback: @escaping () async -> Void = {},
        reconcileCache: @escaping (RecordingCachePolicy) async -> Bool = {
            _ in true
        }
    ) {
        self.resolvePlayableResultIDs = resolvePlayableResultIDs
        self.playRecording = playRecording
        self.stopPlayback = stopPlayback
        self.reconcileCache = reconcileCache
    }

    func playableResultIDs(_ resultIDs: [UUID]) async -> Set<UUID> {
        await resolvePlayableResultIDs(resultIDs)
    }

    func play(resultID: UUID) async -> IOSHistoryPlaybackAttempt {
        await playRecording(resultID)
    }

    func stop() async {
        await stopPlayback()
    }

    func reconcile(policy: RecordingCachePolicy) async -> Bool {
        await reconcileCache(policy.normalized)
    }
}
