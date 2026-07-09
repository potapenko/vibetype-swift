//
//  OpenAIUsageStoreTests.swift
//  HoldTypeTests
//
//  Created by Codex on 6/22/26.
//

import Foundation
import HoldTypeDomain
import Testing
@testable import HoldType

@MainActor
struct OpenAIUsageStoreTests {

    @Test func appendPersistsNewestFirstUsageEvents() throws {
        let persistence = FakeOpenAIUsagePersistence()
        let now = makeDate(year: 2026, month: 6, day: 22, hour: 12)
        let store = OpenAIUsageStore(
            persistence: persistence,
            calendar: makeCalendar(),
            now: { now }
        )
        let olderEvent = OpenAIUsagePricing.current.makeEvent(
            timestamp: makeDate(year: 2026, month: 6, day: 21, hour: 10),
            model: "gpt-4o-transcribe",
            durationSeconds: 60
        )
        let newerEvent = OpenAIUsagePricing.current.makeEvent(
            timestamp: makeDate(year: 2026, month: 6, day: 22, hour: 10),
            model: "gpt-4o-mini-transcribe",
            durationSeconds: 120
        )

        try store.append(olderEvent)
        try store.append(newerEvent)

        #expect(store.entries.map(\.id) == [newerEvent.id, olderEvent.id])
        #expect(try store.load().map(\.id) == [newerEvent.id, olderEvent.id])
        #expect(persistence.savedData != nil)
    }

    @Test func appendPrunesEventsOutsideRetentionWindow() throws {
        let persistence = FakeOpenAIUsagePersistence()
        let now = makeDate(year: 2026, month: 6, day: 22, hour: 12)
        let store = OpenAIUsageStore(
            persistence: persistence,
            retentionDays: 2,
            calendar: makeCalendar(),
            now: { now }
        )
        let retainedEvent = OpenAIUsagePricing.current.makeEvent(
            timestamp: makeDate(year: 2026, month: 6, day: 21, hour: 10),
            model: "gpt-4o-transcribe",
            durationSeconds: 60
        )
        let prunedEvent = OpenAIUsagePricing.current.makeEvent(
            timestamp: makeDate(year: 2026, month: 6, day: 19, hour: 10),
            model: "gpt-4o-transcribe",
            durationSeconds: 60
        )

        try store.append(retainedEvent)
        try store.append(prunedEvent)

        #expect(store.entries.map(\.id) == [retainedEvent.id])
    }

    @Test func recordSuccessfulTranscriptionUsageUsesCurrentPricingAndClock() throws {
        let persistence = FakeOpenAIUsagePersistence()
        let now = makeDate(year: 2026, month: 6, day: 22, hour: 12)
        let store = OpenAIUsageStore(
            persistence: persistence,
            calendar: makeCalendar(),
            now: { now }
        )
        let transcriptionID = try #require(
            UUID(uuidString: "D92652ED-9594-4534-8AA7-F80AEEA89663")
        )
        let usage = try SuccessfulTranscriptionUsage(
            transcriptionID: transcriptionID,
            model: "gpt-4o-mini-transcribe",
            audioDuration: 180
        )

        store.recordSuccessfulTranscriptionUsage(usage)

        #expect(store.entries.count == 1)
        #expect(store.entries.first?.id == transcriptionID)
        #expect(store.entries.first?.timestamp == now)
        #expect(store.entries.first?.model == "gpt-4o-mini-transcribe")
        #expect(store.entries.first?.durationSeconds == 180)
        #expect(isClose(store.entries.first?.estimatedCostUSD, 0.009))
    }

    @Test func repeatedTranscriptionIDKeepsTheFirstFrozenEvent() throws {
        let persistence = FakeOpenAIUsagePersistence()
        var now = makeDate(year: 2026, month: 6, day: 22, hour: 10)
        let store = OpenAIUsageStore(persistence: persistence, now: { now })
        let transcriptionID = try #require(
            UUID(uuidString: "C5133E89-5F95-485D-B7D9-6A20D93AE98A")
        )
        let firstUsage = try SuccessfulTranscriptionUsage(
            transcriptionID: transcriptionID,
            model: "gpt-4o-transcribe",
            audioDuration: 30
        )
        let conflictingReplay = try SuccessfulTranscriptionUsage(
            transcriptionID: transcriptionID,
            model: "gpt-4o-mini-transcribe",
            audioDuration: 90
        )

        store.recordSuccessfulTranscriptionUsage(firstUsage)
        now = makeDate(year: 2026, month: 6, day: 23, hour: 10)
        store.recordSuccessfulTranscriptionUsage(conflictingReplay)

        #expect(store.entries.map(\.id) == [transcriptionID])
        #expect(store.entries.first?.timestamp == makeDate(year: 2026, month: 6, day: 22, hour: 10))
        #expect(store.entries.first?.model == "gpt-4o-transcribe")
        #expect(store.entries.first?.durationSeconds == 30)
        #expect(store.entries.first?.priceUSDPerMinute == 0.006)
        #expect(persistence.saveCount == 1)
    }

    @Test func failedSaveRemainsVisibleWhenAnOlderIDIsReplayed() throws {
        let persistence = FakeOpenAIUsagePersistence()
        let store = OpenAIUsageStore(persistence: persistence)
        let firstUsage = try SuccessfulTranscriptionUsage(
            transcriptionID: try #require(UUID(uuidString: "511BB044-397E-49E4-B87A-0C7368C9AD34")),
            model: "gpt-4o-transcribe",
            audioDuration: 30
        )
        let failedUsage = try SuccessfulTranscriptionUsage(
            transcriptionID: try #require(UUID(uuidString: "DD5208C1-1B74-4A23-9681-3BBF41D4D72B")),
            model: "gpt-4o-mini-transcribe",
            audioDuration: 60
        )

        store.recordSuccessfulTranscriptionUsage(firstUsage)
        persistence.saveError = OpenAIUsagePersistenceTestError.saveFailed
        store.recordSuccessfulTranscriptionUsage(failedUsage)
        let failedMessage = store.storageErrorMessage
        persistence.saveError = nil

        store.recordSuccessfulTranscriptionUsage(firstUsage)

        #expect(store.entries.map(\.id) == [firstUsage.transcriptionID])
        #expect(failedMessage == "OpenAI usage estimate could not be saved.")
        #expect(store.storageErrorMessage == failedMessage)
        #expect(persistence.saveCount == 2)
    }

    @Test func clearRemovesUsageEstimateOnlyFromLocalStore() throws {
        let persistence = FakeOpenAIUsagePersistence()
        let now = makeDate(year: 2026, month: 6, day: 22, hour: 12)
        let store = OpenAIUsageStore(
            persistence: persistence,
            calendar: makeCalendar(),
            now: { now }
        )
        let event = OpenAIUsagePricing.current.makeEvent(
            timestamp: now,
            model: "gpt-4o-transcribe",
            durationSeconds: 60
        )
        try store.append(event)

        try store.clear()

        #expect(store.entries.isEmpty)
        #expect(persistence.removedKeys == [OpenAIUsageStore.defaultStorageKey])
    }

    private func makeCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int) -> Date {
        var components = DateComponents()
        components.calendar = makeCalendar()
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return components.date!
    }

    private func isClose(_ value: Double?, _ expected: Double, tolerance: Double = 0.000_001) -> Bool {
        guard let value else {
            return false
        }

        return abs(value - expected) <= tolerance
    }
}

private final class FakeOpenAIUsagePersistence: OpenAIUsagePersistence {
    var savedData: Data?
    var removedKeys: [String] = []
    var saveCount = 0
    var saveError: (any Error)?

    func loadData(forKey key: String) throws -> Data? {
        savedData
    }

    func saveData(_ data: Data, forKey key: String) throws {
        saveCount += 1
        if let saveError {
            throw saveError
        }
        savedData = data
    }

    func removeData(forKey key: String) throws {
        removedKeys.append(key)
        savedData = nil
    }
}

private enum OpenAIUsagePersistenceTestError: Error {
    case saveFailed
}
