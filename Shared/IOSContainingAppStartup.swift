import HoldTypeOpenAI

@MainActor
struct IOSContainingAppStartup {
    init(
        scheduleProviderStartupMaintenance: @MainActor () -> Void = {
            OpenAIProviderStartupMaintenance.schedule()
        }
    ) {
        scheduleProviderStartupMaintenance()
    }
}
