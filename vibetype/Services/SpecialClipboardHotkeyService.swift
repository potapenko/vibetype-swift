//
//  SpecialClipboardHotkeyService.swift
//  vibetype
//
//  Created by Codex on 6/22/26.
//

import Carbon.HIToolbox
import Foundation

protocol SpecialClipboardHotkeyListening: AnyObject {
    var shortcut: GlobalHotkeyShortcut { get }
    var isListening: Bool { get }

    func start(handler: @escaping () -> Void) throws
    func stop()
}

final class CarbonSpecialClipboardHotkeyService: SpecialClipboardHotkeyListening {
    let shortcut = GlobalHotkeyShortcut.appClipboardPaste

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var handlerBox: SpecialClipboardHotkeyHandlerBox?

    var isListening: Bool {
        hotKeyRef != nil
    }

    func start(handler: @escaping () -> Void) throws {
        stop()

        let handlerBox = SpecialClipboardHotkeyHandlerBox(handler: handler)
        self.handlerBox = handlerBox

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        var newEventHandlerRef: EventHandlerRef?
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            specialClipboardHotkeyEventHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(handlerBox).toOpaque(),
            &newEventHandlerRef
        )

        guard installStatus == noErr else {
            self.handlerBox = nil
            throw SpecialClipboardHotkeyServiceError.registrationFailed(status: installStatus)
        }

        var newHotKeyRef: EventHotKeyRef?
        var hotKeyID = EventHotKeyID(
            signature: SpecialClipboardHotkeyCarbonID.signature,
            id: SpecialClipboardHotkeyCarbonID.id
        )
        let registerStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_V),
            UInt32(controlKey | cmdKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &newHotKeyRef
        )

        guard registerStatus == noErr else {
            if let newEventHandlerRef {
                RemoveEventHandler(newEventHandlerRef)
            }
            self.handlerBox = nil
            throw SpecialClipboardHotkeyServiceError.registrationFailed(status: registerStatus)
        }

        eventHandlerRef = newEventHandlerRef
        hotKeyRef = newHotKeyRef
    }

    func stop() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }

        self.hotKeyRef = nil
        self.eventHandlerRef = nil
        handlerBox = nil
    }

    deinit {
        stop()
    }
}

@MainActor
final class SpecialClipboardHotkeyCoordinator {
    private let hotkeyService: any SpecialClipboardHotkeyListening
    private let pasteService: SpecialClipboardPasteService
    private let settingsStore: AppSettingsStore
    private let transcriptClipboardStore: any TranscriptClipboardStoring

    private var settingsObserver: NSObjectProtocol?
    private var isStarted = false
    private(set) var lastStatusText: String?

    init(
        hotkeyService: any SpecialClipboardHotkeyListening = CarbonSpecialClipboardHotkeyService(),
        pasteService: SpecialClipboardPasteService = SpecialClipboardPasteService(),
        settingsStore: AppSettingsStore = AppSettingsStore(),
        transcriptClipboardStore: any TranscriptClipboardStoring = AppTranscriptClipboardStore.shared
    ) {
        self.hotkeyService = hotkeyService
        self.pasteService = pasteService
        self.settingsStore = settingsStore
        self.transcriptClipboardStore = transcriptClipboardStore
    }

    func start() {
        guard !isStarted else {
            return
        }

        isStarted = true
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .appSettingsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reloadHotkeyRegistration()
            }
        }

        reloadHotkeyRegistration()
    }

    func stop() {
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
        }

        hotkeyService.stop()
        settingsObserver = nil
        isStarted = false
    }

    private func reloadHotkeyRegistration() {
        let settings = settingsStore.load()

        guard settings.saveTranscriptsToAppClipboard else {
            hotkeyService.stop()
            Task {
                await transcriptClipboardStore.clear()
            }
            lastStatusText = "VibeType Clipboard is disabled."
            return
        }

        guard !hotkeyService.isListening else {
            return
        }

        do {
            try hotkeyService.start { [weak self] in
                Task {
                    await self?.pasteFromAppClipboard()
                }
            }
            lastStatusText = nil
        } catch {
            lastStatusText = Self.userFacingMessage(for: error)
        }
    }

    private func pasteFromAppClipboard() async {
        let result = await pasteService.pasteFromAppClipboard(settings: settingsStore.load())
        lastStatusText = result.statusText
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

enum SpecialClipboardHotkeyServiceError: Error, Equatable, LocalizedError {
    case registrationFailed(status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .registrationFailed:
            return "Could not register Control+Command+V for VibeType Clipboard."
        }
    }
}

private enum SpecialClipboardHotkeyCarbonID {
    static let signature: OSType = 0x56544350
    static let id: UInt32 = 1
}

private final class SpecialClipboardHotkeyHandlerBox {
    let handler: () -> Void

    init(handler: @escaping () -> Void) {
        self.handler = handler
    }
}

private func specialClipboardHotkeyEventHandler(
    nextHandler: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else {
        return noErr
    }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )

    guard status == noErr,
          hotKeyID.signature == SpecialClipboardHotkeyCarbonID.signature,
          hotKeyID.id == SpecialClipboardHotkeyCarbonID.id
    else {
        return noErr
    }

    let handlerBox = Unmanaged<SpecialClipboardHotkeyHandlerBox>
        .fromOpaque(userData)
        .takeUnretainedValue()
    handlerBox.handler()
    return noErr
}
