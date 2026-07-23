import Foundation
import Testing

struct KeyboardFixBridgeMetadataTests {
    @Test func metadataContainsOnlyBoundedPromptFreeProjection() throws {
        let fixture = try KeyboardFixBridgeTestFixture()
        defer { fixture.remove() }
        let snapshot = try makeKeyboardFixMetadataSnapshot(customCount: 6)

        try fixture.store.publishMetadata(snapshot)

        #expect(try fixture.store.loadMetadata() == snapshot)
        #expect(snapshot.enabledActions.count == 5)
        #expect(snapshot.action(identifier: "user.action.3")?.isEnabled == false)
        let data = try Data(
            contentsOf: fixture.url(
                for: KeyboardFixBridgeConfiguration.metadataFilename
            )
        )
        let object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let actions = try #require(object["actions"] as? [[String: Any]])
        #expect(Set(object.keys) == [
            "schemaVersion",
            "revision",
            "publishedAt",
            "actions",
        ])
        #expect(actions.allSatisfy {
            Set($0.keys) == [
                "identifier",
                "kind",
                "title",
                "icon",
                "order",
                "isEnabled",
            ]
        })
        let encoded = String(decoding: data, as: UTF8.self)
        for forbidden in ["prompt", "apiKey", "credential", "model"] {
            #expect(encoded.contains(forbidden) == false)
        }
        #expect(data.count <= KeyboardFixBridgeConfiguration.maximumMetadataBytes)
    }

    @Test func actionMembersUseExactCharacterAndByteLimits() {
        let eightyEmoji = String(repeating: "👨‍👩‍👧‍👦", count: 80)
        #expect(
            KeyboardFixMetadataAction(
                identifier: String(repeating: "a", count: 128),
                kind: .customPrompt,
                title: eightyEmoji,
                icon: .custom,
                order: 2,
                isEnabled: true
            ) != nil
        )
        #expect(
            KeyboardFixMetadataAction(
                identifier: String(repeating: "a", count: 129),
                kind: .customPrompt,
                title: "Title",
                icon: .custom,
                order: 2,
                isEnabled: true
            ) == nil
        )
        #expect(
            KeyboardFixMetadataAction(
                identifier: "user.too-long-title",
                kind: .customPrompt,
                title: eightyEmoji + "x",
                icon: .custom,
                order: 2,
                isEnabled: true
            ) == nil
        )
        #expect(
            KeyboardFixMetadataAction(
                identifier: " ",
                kind: .customPrompt,
                title: "Title",
                icon: .custom,
                order: 2,
                isEnabled: true
            ) == nil
        )
    }

    @Test func snapshotPinsBuiltInsUniqueIdentityAndContiguousOrder() throws {
        let valid = try makeKeyboardFixMetadataActions(customCount: 2)
        let reversed = [valid[1], valid[0]] + valid.dropFirst(2)
        let duplicate = valid + [valid[2]]
        let wrongOrder = try valid.enumerated().map { index, action in
            guard let copy = KeyboardFixMetadataAction(
                identifier: action.identifier,
                kind: action.kind,
                title: action.title,
                icon: action.icon,
                order: index == 2 ? 9 : action.order,
                isEnabled: action.isEnabled
            ) else {
                throw KeyboardFixBridgeTestSupportError.invalidFixture
            }
            return copy
        }

        #expect(
            KeyboardFixMetadataSnapshot(
                revision: 1,
                publishedAt: Date(),
                actions: valid
            ) != nil
        )
        #expect(
            KeyboardFixMetadataSnapshot(
                revision: 1,
                publishedAt: Date(),
                actions: Array(reversed)
            ) == nil
        )
        #expect(
            KeyboardFixMetadataSnapshot(
                revision: 1,
                publishedAt: Date(),
                actions: duplicate
            ) == nil
        )
        #expect(
            KeyboardFixMetadataSnapshot(
                revision: 1,
                publishedAt: Date(),
                actions: wrongOrder
            ) == nil
        )
    }

    @Test func metadataSupportsAtMostOneHundredActions() throws {
        let accepted = try makeKeyboardFixMetadataActions(customCount: 98)
        #expect(accepted.count == 100)
        #expect(
            KeyboardFixMetadataSnapshot(
                revision: 1,
                publishedAt: Date(),
                actions: accepted
            ) != nil
        )

        #expect(throws: KeyboardFixBridgeTestSupportError.invalidFixture) {
            try makeKeyboardFixMetadataActions(customCount: 99)
        }
    }

    @Test func revisionsIncreaseAndRuntimeReflectionHasNoPromptSurface() throws {
        let fixture = try KeyboardFixBridgeTestFixture()
        defer { fixture.remove() }
        let first = try makeKeyboardFixMetadataSnapshot(revision: 1)
        let second = try makeKeyboardFixMetadataSnapshot(revision: 2)
        try fixture.store.publishMetadata(first)

        #expect(try fixture.store.nextMetadataRevision() == 2)
        #expect(
            throws: KeyboardFixBridgeStoreError.nonIncreasingMetadataRevision(
                current: 1,
                proposed: 1
            )
        ) {
            try fixture.store.publishMetadata(first)
        }
        try fixture.store.publishMetadata(second)
        #expect(try fixture.store.loadMetadata() == second)
        #expect(String(reflecting: second).contains("prompt") == false)
    }
}
