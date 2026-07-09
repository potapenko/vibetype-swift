//
//  OpenAIUsageStore.swift
//  HoldType
//
//  Created by Codex on 6/22/26.
//

import Combine
import Foundation
import HoldTypeDomain

protocol OpenAIUsagePersistence {
    func loadData(forKey key: String) throws -> Data?
    func saveData(_ data: Data, forKey key: String) throws
    func removeData(forKey key: String) throws
}

extension UserDefaults: OpenAIUsagePersistence {}

enum OpenAIUsageStoreError: Error, Equatable, LocalizedError {
    case loadFailed
    case unreadableUsage
    case saveFailed
    case clearFailed

    var errorDescription: String? {
        switch self {
        case .loadFailed:
            return "OpenAI usage estimate could not be loaded."
        case .unreadableUsage:
            return "Saved OpenAI usage estimate could not be read."
        case .saveFailed:
            return "OpenAI usage estimate could not be saved."
        case .clearFailed:
            return "OpenAI usage estimate could not be cleared."
        }
    }
}

@MainActor
final class OpenAIUsageStore: ObservableObject, TranscriptionUsageRecording {
    static let shared = OpenAIUsageStore()
    nonisolated static let defaultStorageKey = "holdtype.openAIUsageEstimate.events"
    nonisolated static let defaultRetentionDays = 365

    @Published private(set) var entries: [OpenAIUsageEvent]
    @Published private(set) var storageErrorMessage: String?

    private let persistence: any OpenAIUsagePersistence
    private let storageKey: String
    private let retentionDays: Int
    private let pricing: OpenAIUsagePricing
    private let calendar: Calendar
    private let now: () -> Date
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    convenience init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = OpenAIUsageStore.defaultStorageKey,
        retentionDays: Int = OpenAIUsageStore.defaultRetentionDays,
        pricing: OpenAIUsagePricing = .current,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.init(
            persistence: userDefaults,
            storageKey: storageKey,
            retentionDays: retentionDays,
            pricing: pricing,
            calendar: calendar,
            now: now,
            encoder: encoder,
            decoder: decoder
        )
    }

    init(
        persistence: any OpenAIUsagePersistence,
        storageKey: String = OpenAIUsageStore.defaultStorageKey,
        retentionDays: Int = OpenAIUsageStore.defaultRetentionDays,
        pricing: OpenAIUsagePricing = .current,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.persistence = persistence
        self.storageKey = storageKey
        self.retentionDays = max(1, retentionDays)
        self.pricing = pricing
        self.calendar = calendar
        self.now = now
        self.encoder = encoder
        self.decoder = decoder
        self.entries = []
        self.storageErrorMessage = nil

        reload()
    }

    func reload() {
        do {
            entries = try load()
            storageErrorMessage = nil
        } catch {
            entries = []
            storageErrorMessage = Self.userFacingMessage(for: error)
        }
    }

    func recordSuccessfulTranscriptionUsage(_ usage: SuccessfulTranscriptionUsage) {
        let event = pricing.makeEvent(
            timestamp: now(),
            model: usage.model,
            durationSeconds: usage.audioDuration,
            id: usage.transcriptionID
        )

        do {
            _ = try append(event)
        } catch {
            storageErrorMessage = Self.userFacingMessage(for: error)
        }
    }

    func load() throws -> [OpenAIUsageEvent] {
        let data: Data?

        do {
            data = try persistence.loadData(forKey: storageKey)
        } catch {
            throw OpenAIUsageStoreError.loadFailed
        }

        guard let data else {
            return []
        }

        do {
            return retainedEntries(try decoder.decode([OpenAIUsageEvent].self, from: data))
        } catch {
            throw OpenAIUsageStoreError.unreadableUsage
        }
    }

    @discardableResult
    func append(_ event: OpenAIUsageEvent) throws -> [OpenAIUsageEvent] {
        let existingEntries = try load()
        guard !existingEntries.contains(where: { $0.id == event.id }) else {
            entries = existingEntries
            return existingEntries
        }

        let updatedEntries = retainedEntries([event] + existingEntries)
        try save(updatedEntries)
        entries = updatedEntries
        storageErrorMessage = nil
        return updatedEntries
    }

    func clear() throws {
        do {
            try persistence.removeData(forKey: storageKey)
            entries = []
            storageErrorMessage = nil
        } catch {
            throw OpenAIUsageStoreError.clearFailed
        }
    }

    func clearUsageEstimate() {
        do {
            try clear()
        } catch {
            storageErrorMessage = Self.userFacingMessage(for: error)
        }
    }

    private func save(_ entries: [OpenAIUsageEvent]) throws {
        do {
            try persistence.saveData(try encoder.encode(entries), forKey: storageKey)
        } catch {
            throw OpenAIUsageStoreError.saveFailed
        }
    }

    private func retainedEntries(_ entries: [OpenAIUsageEvent]) -> [OpenAIUsageEvent] {
        let cutoffDay = calendar.date(
            byAdding: .day,
            value: -(retentionDays - 1),
            to: calendar.startOfDay(for: now())
        ) ?? now()

        return entries
            .filter { $0.timestamp >= cutoffDay }
            .sorted { lhs, rhs in
                lhs.timestamp > rhs.timestamp
            }
    }

    private static func userFacingMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription,
           !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return description
        }

        return error.localizedDescription
    }
}
