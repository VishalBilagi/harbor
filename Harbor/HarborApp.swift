//
//  HarborApp.swift
//  Harbor
//
//  Created by Vishal Bilagi on 3/3/26.
//

import SwiftUI

@main
struct HarborApp: App {
    var body: some Scene {
        MenuBarExtra("Harbor", systemImage: "ferry") {
            ContentView()
        }
        Settings {
            VStack(alignment: .leading, spacing: 8) {
                Text("Harbor")
                    .font(.headline)
                Text("Menubar settings and refresh controls will be added in HAR-7.")
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(width: 320)
        }
    }
}
