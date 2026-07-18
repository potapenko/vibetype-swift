/// The terminal result presented for one voice attempt.
///
/// Active work, failure details, recovery ownership, output delivery, and
/// platform presentation remain separate concerns.
public enum VoiceAttemptOutcome: Equatable, Sendable {
    case resultReady
    case recoverableFailure
    case interrupted
}
