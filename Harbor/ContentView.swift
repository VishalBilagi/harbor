//
//  ContentView.swift
//  Harbor
//
//  Created by Vishal Bilagi on 3/3/26.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Harbor")
                .font(.headline)

            Text("Port monitor scaffold")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Label("PortKit remains the shared Swift core", systemImage: "shippingbox")
                Label("The CLI will power machine-readable output", systemImage: "terminal")
                Label("The TUI will live in the Go module", systemImage: "rectangle.grid.1x2")
            }
            .font(.caption)

            Button("Refresh Placeholder") {
            }
            .buttonStyle(.borderedProminent)
            .disabled(true)
        }
        .padding()
        .frame(width: 320)
    }
}

#Preview {
    ContentView()
}
