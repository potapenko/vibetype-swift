//
//  HoldTypeIOSApp.swift
//  HoldType-iOS
//
//  Created by Codex on 6/21/26.
//

import HoldTypeOpenAI
import SwiftUI

@main
struct HoldTypeIOSApp: App {
    init() {
        self.init {
            OpenAIProviderStartupMaintenance.schedule()
        }
    }

    init(scheduleProviderStartupMaintenance: @MainActor () -> Void) {
        _ = IOSContainingAppStartup(
            scheduleProviderStartupMaintenance: scheduleProviderStartupMaintenance
        )
    }

    var body: some Scene {
        WindowGroup {
            HoldTypeIOSRootView()
        }
    }
}

private struct HoldTypeIOSRootView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    HoldTypeSetupStatusView(surface: .iOSContainingApp)
                    KeyboardBridgeProbeView()
                }
                .padding(24)
            }
            .navigationTitle("HoldType")
            .background(Color(.systemGroupedBackground))
        }
    }
}

#Preview {
    HoldTypeIOSRootView()
}
