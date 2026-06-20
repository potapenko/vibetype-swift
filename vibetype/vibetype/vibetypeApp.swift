//
//  vibetypeApp.swift
//  vibetype
//
//  Created by Eugene Potapenko on 6/20/26.
//

import SwiftUI

@main
struct VibeTypeApp: App {
    var body: some Scene {
        MenuBarExtra("VibeType", systemImage: "mic.fill") {
            MenuBarView()
        }
        .menuBarExtraStyle(.menu)
    }
}
