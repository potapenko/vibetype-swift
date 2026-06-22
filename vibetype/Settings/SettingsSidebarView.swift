//
//  SettingsSidebarView.swift
//  vibetype
//
//  Created by Codex on 6/22/26.
//

import SwiftUI

struct SettingsSidebarView: View {
    @Binding var selection: SettingsNavigationItem?

    var body: some View {
        List(SettingsNavigationItem.allCases, selection: $selection) { item in
            SettingsSidebarRow(item: item)
                .tag(item)
        }
        .listStyle(.sidebar)
        .navigationTitle("Settings")
    }
}

private struct SettingsSidebarRow: View {
    let item: SettingsNavigationItem

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .lineLimit(1)

                if let detail = item.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}

#Preview {
    NavigationSplitView {
        SettingsSidebarView(selection: .constant(.general))
    } detail: {
        Text("General")
    }
}
