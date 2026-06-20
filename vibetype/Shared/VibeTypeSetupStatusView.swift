//
//  VibeTypeSetupStatusView.swift
//  vibetype
//
//  Created by Codex on 6/21/26.
//

import SwiftUI

enum VibeTypeSetupSurface {
    case macOSSettings
    case iOSContainingApp

    var eyebrow: String {
        switch self {
        case .macOSSettings:
            return "macOS menu bar app"
        case .iOSContainingApp:
            return "iOS simulator companion"
        }
    }

    var title: String {
        "VibeType"
    }

    var summary: String {
        switch self {
        case .macOSSettings:
            return "Native dictation controls are being built for the menu bar app."
        case .iOSContainingApp:
            return "A shared SwiftUI surface for testing setup and status screens on iOS."
        }
    }

    var primaryStatusTitle: String {
        switch self {
        case .macOSSettings:
            return "Settings shell is available"
        case .iOSContainingApp:
            return "Containing app target is available"
        }
    }

    var primaryStatusDetail: String {
        switch self {
        case .macOSSettings:
            return "Recording, transcription, and paste controls will land behind native services."
        case .iOSContainingApp:
            return "Keyboard setup, recording, transcription, and text insertion stay disabled for now."
        }
    }

    var statusItems: [VibeTypeSetupStatusItem] {
        switch self {
        case .macOSSettings:
            return [
                VibeTypeSetupStatusItem(
                    symbolName: "menubar.rectangle",
                    title: "Menu bar first",
                    detail: "The production surface remains the macOS menu bar utility."
                ),
                VibeTypeSetupStatusItem(
                    symbolName: "lock.shield",
                    title: "Local privacy boundary",
                    detail: "Secrets, permissions, and paste handoff stay in macOS-specific services."
                ),
                VibeTypeSetupStatusItem(
                    symbolName: "iphone",
                    title: "Shared screen path",
                    detail: "Reusable SwiftUI can be exercised on iOS without moving platform logic."
                ),
            ]
        case .iOSContainingApp:
            return [
                VibeTypeSetupStatusItem(
                    symbolName: "rectangle.connected.to.line.below",
                    title: "Shared SwiftUI",
                    detail: "This screen is compiled from the same source as the macOS setup header."
                ),
                VibeTypeSetupStatusItem(
                    symbolName: "keyboard",
                    title: "No keyboard extension",
                    detail: "The target does not add Open Access, shared containers, or input extension code."
                ),
                VibeTypeSetupStatusItem(
                    symbolName: "network",
                    title: "No provider calls",
                    detail: "The simulator surface makes no microphone, network, or transcription request."
                ),
            ]
        }
    }
}

struct VibeTypeSetupStatusItem: Identifiable {
    let id: String
    let symbolName: String
    let title: String
    let detail: String

    init(symbolName: String, title: String, detail: String) {
        self.id = title
        self.symbolName = symbolName
        self.title = title
        self.detail = detail
    }
}

struct VibeTypeSetupStatusView: View {
    let surface: VibeTypeSetupSurface
    var showsDetailSections = true

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            primaryStatus

            if showsDetailSections {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Current Scope")
                        .font(.headline)

                    ForEach(surface.statusItems) { item in
                        VibeTypeSetupStatusRow(item: item)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.accentColor.opacity(0.16))
                    .frame(width: 58, height: 58)

                Image(systemName: "mic.fill")
                    .font(.system(size: 27, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(surface.eyebrow)
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)

                Text(surface.title)
                    .font(.title.weight(.semibold))

                Text(surface.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var primaryStatus: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.green)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(surface.primaryStatusTitle)
                    .font(.headline)

                Text(surface.primaryStatusDetail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct VibeTypeSetupStatusRow: View {
    let item: VibeTypeSetupStatusItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.symbolName)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))

                Text(item.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview("iOS companion") {
    ScrollView {
        VibeTypeSetupStatusView(surface: .iOSContainingApp)
            .padding(24)
    }
}

#Preview("macOS settings") {
    VibeTypeSetupStatusView(surface: .macOSSettings, showsDetailSections: false)
        .padding(24)
        .frame(width: 460)
}
