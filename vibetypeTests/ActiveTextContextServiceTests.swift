//
//  ActiveTextContextServiceTests.swift
//  vibetypeTests
//
//  Created by Codex on 6/22/26.
//

import Foundation
import Testing
@testable import vibetype

@MainActor
struct ActiveTextContextServiceTests {

    @Test func disabledSettingSkipsPermissionAndFocusedTextLookup() {
        let permissionClient = FakeActiveTextContextPermissionClient(isTrusted: true)
        let contextClient = FakeActiveTextContextClient(
            element: ActiveTextContextElement(text: "Existing active text")
        )
        let service = makeService(
            permissionClient: permissionClient,
            contextClient: contextClient
        )

        #expect(service.currentContext(settings: .defaults) == nil)
        #expect(permissionClient.trustChecks.isEmpty)
        #expect(contextClient.focusedTextLookupCount == 0)
    }

    @Test func missingAccessibilityTrustSkipsFocusedTextLookup() {
        var settings = AppSettings.defaults
        settings.useActiveTextContext = true
        let permissionClient = FakeActiveTextContextPermissionClient(isTrusted: false)
        let contextClient = FakeActiveTextContextClient(
            element: ActiveTextContextElement(text: "Existing active text")
        )
        let service = makeService(
            permissionClient: permissionClient,
            contextClient: contextClient
        )

        #expect(service.currentContext(settings: settings) == nil)
        #expect(permissionClient.trustChecks == [false])
        #expect(contextClient.focusedTextLookupCount == 0)
    }

    @Test func secureFocusedTextElementIsOmitted() {
        var settings = AppSettings.defaults
        settings.useActiveTextContext = true
        let service = makeService(
            contextClient: FakeActiveTextContextClient(
                element: ActiveTextContextElement(text: "secret", isSecure: true)
            )
        )

        #expect(service.currentContext(settings: settings) == nil)
    }

    @Test func selectedRangeUsesBoundedTextBeforeCursor() throws {
        var settings = AppSettings.defaults
        settings.useActiveTextContext = true
        let service = makeService(
            contextClient: FakeActiveTextContextClient(
                element: ActiveTextContextElement(
                    text: "abcdef",
                    selectedRange: NSRange(location: 4, length: 0)
                )
            ),
            maximumCharacterCount: 3
        )

        let context = try #require(service.currentContext(settings: settings))

        #expect(context.text == "bcd")
    }

    @Test func missingSelectedRangeUsesBoundedSuffixOfFocusedText() throws {
        var settings = AppSettings.defaults
        settings.useActiveTextContext = true
        let service = makeService(
            contextClient: FakeActiveTextContextClient(
                element: ActiveTextContextElement(text: "abcdef")
            ),
            maximumCharacterCount: 3
        )

        let context = try #require(service.currentContext(settings: settings))

        #expect(context.text == "def")
    }

    @Test func emptyFocusedTextIsOmitted() {
        var settings = AppSettings.defaults
        settings.useActiveTextContext = true
        let service = makeService(
            contextClient: FakeActiveTextContextClient(
                element: ActiveTextContextElement(text: "   \n")
            )
        )

        #expect(service.currentContext(settings: settings) == nil)
    }

    private func makeService(
        permissionClient: FakeActiveTextContextPermissionClient = FakeActiveTextContextPermissionClient(
            isTrusted: true
        ),
        contextClient: FakeActiveTextContextClient,
        maximumCharacterCount: Int = TranscriptionPromptContext.defaultMaximumCharacterCount
    ) -> ActiveTextContextService {
        ActiveTextContextService(
            accessibilityPermissionService: AccessibilityPermissionService(client: permissionClient),
            client: contextClient,
            maximumCharacterCount: maximumCharacterCount
        )
    }
}

private final class FakeActiveTextContextClient: ActiveTextContextClient {
    private let element: ActiveTextContextElement?
    private(set) var focusedTextLookupCount = 0

    init(element: ActiveTextContextElement?) {
        self.element = element
    }

    func focusedTextElement() -> ActiveTextContextElement? {
        focusedTextLookupCount += 1
        return element
    }
}

private final class FakeActiveTextContextPermissionClient: AccessibilityPermissionClient {
    private let isTrusted: Bool
    private(set) var trustChecks: [Bool] = []

    init(isTrusted: Bool) {
        self.isTrusted = isTrusted
    }

    func isProcessTrusted(promptIfNeeded: Bool) -> Bool {
        trustChecks.append(promptIfNeeded)
        return isTrusted
    }

    func openAccessibilitySettings() -> Bool {
        false
    }
}
