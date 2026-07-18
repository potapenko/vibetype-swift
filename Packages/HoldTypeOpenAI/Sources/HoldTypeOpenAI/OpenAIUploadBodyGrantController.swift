import Foundation

nonisolated final class OpenAIUploadBodyGrantController: @unchecked Sendable {
    private enum GrantKind {
        case initial
        case approvedReplay
    }

    private struct Grant {
        let taskIdentifier: Int
        let kind: GrantKind
    }

    private let lock = NSLock()
    private var grant: Grant?
    private var didInstallInitialGrant = false
    private var didApproveReplay = false

    func installInitialGrant(forTaskIdentifier taskIdentifier: Int) -> Bool {
        lock.withLock {
            guard !didInstallInitialGrant, grant == nil else { return false }
            didInstallInitialGrant = true
            grant = Grant(taskIdentifier: taskIdentifier, kind: .initial)
            return true
        }
    }

    func consumeFullBodyGrant(forTaskIdentifier taskIdentifier: Int) -> Bool {
        lock.withLock {
            guard grant?.taskIdentifier == taskIdentifier else { return false }
            grant = nil
            return true
        }
    }

    func approveReplay(forTaskIdentifier taskIdentifier: Int) -> Bool {
        lock.withLock {
            guard grant == nil, !didApproveReplay else { return false }
            didApproveReplay = true
            grant = Grant(
                taskIdentifier: taskIdentifier,
                kind: .approvedReplay
            )
            return true
        }
    }

    func consumeOffsetReplayGrant(
        forTaskIdentifier taskIdentifier: Int,
        offset: Int64,
        byteCount: Int64
    ) -> Bool {
        lock.withLock {
            guard grant?.taskIdentifier == taskIdentifier,
                  grant?.kind == .approvedReplay else {
                return false
            }
            grant = nil
            return offset == 0 && byteCount > 0
        }
    }
}
