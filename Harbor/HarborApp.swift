//
//  HarborApp.swift
//  Harbor
//
//  Created by Vishal Bilagi on 3/3/26.
//

import SwiftUI

@main
struct HarborApp: App {
    @StateObject private var model = HarborMenuModel()
    @AppStorage(AppSettings.refreshIntervalKey)
    private var refreshIntervalSeconds = AppSettings.defaultRefreshIntervalSeconds

    var body: some Scene {
        MenuBarExtra("Harbor", systemImage: "ferry.fill") {
            ContentView(
                model: model,
                refreshIntervalSeconds: $refreshIntervalSeconds
            )
        }
        .menuBarExtraStyle(.window)

        Settings {
            HarborSettingsView(refreshIntervalSeconds: $refreshIntervalSeconds)
        }
    }
}
