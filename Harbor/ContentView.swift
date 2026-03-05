//
//  ContentView.swift
//  Harbor
//
//  Created by Vishal Bilagi on 3/3/26.
//

import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: HarborMenuModel
    @Binding var refreshIntervalSeconds: Double

    @State private var query = ""
    @State private var pendingSinkAction: PendingSinkAction?

    private var visibleRows: [ListenerRow] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return model.rows
        }

        let needle = trimmed.lowercased()
        return model.rows.filter { $0.matches(query: needle) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if let sinkMessage = model.sinkMessage, !sinkMessage.isEmpty {
                Text(sinkMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            if let errorMessage = model.errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            rowsContent

            footer
        }
        .padding(12)
        .frame(width: 680, height: 520)
        .onAppear {
            model.refresh(for: .menuOpen)
        }
        .task(id: Int(refreshIntervalSeconds)) {
            await model.runFallbackTimer(every: Int(refreshIntervalSeconds))
        }
        .confirmationDialog(
            pendingSinkAction?.title ?? "Confirm Sink",
            isPresented: Binding(
                get: { pendingSinkAction != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingSinkAction = nil
                    }
                }
            ),
            titleVisibility: .visible,
            presenting: pendingSinkAction
        ) { action in
            Button(action.confirmationLabel, role: .destructive) {
                model.sink(pid: action.row.pid, force: action.force)
                pendingSinkAction = nil
            }
            Button("Cancel", role: .cancel) {
                pendingSinkAction = nil
            }
        } message: { action in
            Text(action.message)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            TextField("Filter by port, process, PID, command, or cwd", text: $query)
                .textFieldStyle(.roundedBorder)

            Button {
                model.refresh(for: .manualAction)
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(model.isRefreshing)

            SettingsLink {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)

            if model.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private var rowsContent: some View {
        Group {
            if visibleRows.isEmpty {
                ContentUnavailableView(
                    model.rows.isEmpty ? "No Listening Ports" : "No Matches",
                    systemImage: model.rows.isEmpty ? "bolt.slash.fill" : "line.3.horizontal.decrease.circle",
                    description: Text(
                        model.rows.isEmpty
                        ? "Open the menu again or refresh to read the latest local listeners."
                        : "Try a broader filter."
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(visibleRows) { row in
                            ListenerRowView(
                                row: row,
                                isSinking: model.isSinking(pid: row.pid),
                                sinkAction: { force in
                                    pendingSinkAction = PendingSinkAction(row: row, force: force)
                                },
                                copyPIDAction: {
                                    copyToClipboard(String(row.pid))
                                },
                                copyPortAction: {
                                    copyToClipboard(String(row.port))
                                }
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Text(model.statusSummary)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
    }

    private func copyToClipboard(_ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }
}

private struct ListenerRowView: View {
    let row: ListenerRow
    let isSinking: Bool
    let sinkAction: (_ force: Bool) -> Void
    let copyPIDAction: () -> Void
    let copyPortAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(":\(row.port)")
                    .font(.headline.monospacedDigit())

                Text(row.processName)
                    .font(.headline)
                    .lineLimit(1)

                Text("PID \(row.pid)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)

                Text("bind \(row.bindSummary)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(row.familySummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                if row.requiresAdminToKill {
                    Text("requires admin")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .foregroundStyle(.orange)
                        .background(Color.orange.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            .lineLimit(1)
            .truncationMode(.tail)

            Text(row.tickerText)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            if let statsText = row.statsText {
                Text(statsText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                Button("Sink") {
                    sinkAction(false)
                }
                .buttonStyle(.bordered)
                .disabled(row.requiresAdminToKill || isSinking)

                Button("Force Sink") {
                    sinkAction(true)
                }
                .buttonStyle(.bordered)
                .disabled(row.requiresAdminToKill || isSinking)

                Button("Copy PID", action: copyPIDAction)
                    .buttonStyle(.borderless)

                Button("Copy Port", action: copyPortAction)
                    .buttonStyle(.borderless)

                Spacer(minLength: 0)

                if isSinking {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .font(.caption)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }
}

private struct PendingSinkAction: Identifiable {
    let id = UUID()
    let row: ListenerRow
    let force: Bool

    var title: String {
        force ? "Force Sink :\(row.port)?" : "Sink :\(row.port)?"
    }

    var confirmationLabel: String {
        force ? "Force Sink" : "Sink"
    }

    var message: String {
        force
        ? "This sends SIGKILL to PID \(row.pid) (\(row.processName))."
        : "This sends SIGTERM to PID \(row.pid) (\(row.processName))."
    }
}

#Preview {
    ContentView(
        model: HarborMenuModel(),
        refreshIntervalSeconds: .constant(AppSettings.defaultRefreshIntervalSeconds)
    )
}
