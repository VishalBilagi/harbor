import SwiftUI

struct HarborSettingsView: View {
    @Binding var refreshIntervalSeconds: Double

    var body: some View {
        Form {
            Section("Refresh") {
                HStack {
                    Text("Fallback refresh interval")
                    Spacer()
                    Text("\(Int(refreshIntervalSeconds)) sec")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Slider(
                    value: $refreshIntervalSeconds,
                    in: AppSettings.minRefreshIntervalSeconds...AppSettings.maxRefreshIntervalSeconds,
                    step: 1
                )

                Text("Harbor refreshes on menu open, explicit refresh, and sink completion. This value controls fallback refresh while the menu is open.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Future Options") {
                Text("Additional menubar options will be added here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: 420)
    }
}

#Preview {
    HarborSettingsView(
        refreshIntervalSeconds: .constant(AppSettings.defaultRefreshIntervalSeconds)
    )
}
