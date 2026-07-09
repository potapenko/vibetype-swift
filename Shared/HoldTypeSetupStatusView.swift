//
//  HoldTypeSetupStatusView.swift
//  HoldType
//
//  Created by Codex on 6/21/26.
//

import SwiftUI

enum HoldTypeSetupSurface {
    case iOSContainingApp

    var eyebrow: String {
        "iOS keyboard feasibility"
    }

    var title: String {
        "HoldType"
    }

    var summary: String {
        "A contained first step toward a native-feeling HoldType voice keyboard."
    }

    var primaryStatusTitle: String {
        "Phase 0 extension is embedded"
    }

    var primaryStatusDetail: String {
        "This build validates keyboard loading, shared state, and safe text insertion."
    }

    var statusItems: [HoldTypeSetupStatusItem] {
        [
            HoldTypeSetupStatusItem(
                symbolName: "keyboard",
                title: "Insertion probe",
                detail: "The extension can type a normal character and insert an accepted sample."
            ),
            HoldTypeSetupStatusItem(
                symbolName: "folder.badge.gearshape",
                title: "Private shared bridge",
                detail: "Only a short, expiring transcript record crosses the App Group boundary."
            ),
            HoldTypeSetupStatusItem(
                symbolName: "mic.slash.fill",
                title: "Voice path is still gated",
                detail: "Microphone, background session, network, and OpenAI remain outside this spike."
            ),
        ]
    }
}

struct HoldTypeSetupStatusItem: Identifiable {
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

struct HoldTypeSetupStatusView: View {
    let surface: HoldTypeSetupSurface
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
                        HoldTypeSetupStatusRow(item: item)
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

private struct HoldTypeSetupStatusRow: View {
    let item: HoldTypeSetupStatusItem

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
        HoldTypeSetupStatusView(surface: .iOSContainingApp)
            .padding(24)
    }
}
