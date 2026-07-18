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

extension UserDefaults: OpenAIUsagePersistence {
    func loadData(forKey key: String) throws -> Data? {
        data(forKey: key)
    }

    func saveData(_ data: Data, forKey key: String) throws {
        set(data, forKey: key)
    }

    func removeData(forKey key: String) throws {
        removeObject(forKey: key)
    }
}

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
        let event: OpenAIUsageEvent
        do {
            event = try pricing.makeEvent(timestamp: now(), for: usage)
        } catch {
            storageErrorMessage = Self.userFacingMessage(
                for: OpenAIUsageStoreError.saveFailed
            )
            return
        }

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
            let wireEvents = try decoder.decode(
                [LegacyOpenAIUsageEventWire].self,
                from: data
            )
            var identifiers: Set<UUID> = []
            let events = try wireEvents.map { wireEvent in
                let event = try wireEvent.runtimeEvent()
                guard identifiers.insert(event.id).inserted else {
                    throw OpenAIUsageStoreError.unreadableUsage
                }
                return event
            }
            return retainedEntries(events)
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
            let wireEvents = entries.map(LegacyOpenAIUsageEventWire.init(event:))
            try persistence.saveData(try encoder.encode(wireEvents), forKey: storageKey)
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
                if lhs.timestamp != rhs.timestamp {
                    return lhs.timestamp > rhs.timestamp
                }
                return lhs.id.uuidString < rhs.id.uuidString
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

/// Preserves the existing macOS UserDefaults JSON shape without making the
/// portable runtime event a persistence contract.
private struct LegacyOpenAIUsageEventWire: Codable {
    let id: UUID
    let timestamp: Date
    let model: String
    let durationSeconds: TimeInterval
    let priceUSDPerMinute: Double?
    let estimatedCostUSD: Double?
    let pricingSource: String?

    init(event: OpenAIUsageEvent) {
        id = event.id
        timestamp = event.timestamp
        model = event.model
        durationSeconds = event.durationSeconds
        priceUSDPerMinute = event.priceUSDPerMinute
        estimatedCostUSD = event.estimatedCostUSD
        pricingSource = event.pricingSource
    }

    func runtimeEvent() throws -> OpenAIUsageEvent {
        let event = try OpenAIUsageEvent(
            id: id,
            timestamp: timestamp,
            model: model,
            durationSeconds: durationSeconds,
            priceUSDPerMinute: priceUSDPerMinute,
            estimatedCostUSD: estimatedCostUSD,
            pricingSource: pricingSource
        )
        guard event.model == model,
              event.pricingSource == pricingSource else {
            throw OpenAIUsageStoreError.unreadableUsage
        }
        return event
    }
}
