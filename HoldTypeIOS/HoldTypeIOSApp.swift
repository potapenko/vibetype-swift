//
//  HoldTypeIOSApp.swift
//  HoldType-iOS
//
//  Created by Codex on 6/21/26.
//

import SwiftUI

@main
struct HoldTypeIOSApp: App {
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
