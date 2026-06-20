//
//  VibeTypeIOSApp.swift
//  vibetype-iOS
//
//  Created by Codex on 6/21/26.
//

import SwiftUI

@main
struct VibeTypeIOSApp: App {
    var body: some Scene {
        WindowGroup {
            VibeTypeIOSRootView()
        }
    }
}

private struct VibeTypeIOSRootView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VibeTypeSetupStatusView(surface: .iOSContainingApp)
                    .padding(24)
            }
            .navigationTitle("VibeType")
            .background(Color(.systemGroupedBackground))
        }
    }
}

#Preview {
    VibeTypeIOSRootView()
}
