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
                                    copyToClipboard(row.portText)
                                },
                                copyBindAction: {
                                    copyToClipboard(row.bindSummary)
                                },
                                copyFamilyAction: {
                                    copyToClipboard(row.familySummary)
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
    let copyBindAction: () -> Void
    let copyFamilyAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Button(action: copyPortAction) {
                    Text(row.portText)
                        .font(.headline.monospacedDigit().weight(.bold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.accentColor.gradient)
                        )
                }
                .buttonStyle(.plain)
                .help("Copy port \(row.portText)")

                Text(row.processName)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)

                Spacer(minLength: 8)

                if row.requiresAdminToKill {
                    Text("requires admin")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .foregroundStyle(Color(red: 0.73, green: 0.33, blue: 0.33))
                        .background(Color(red: 0.73, green: 0.33, blue: 0.33).opacity(0.14))
                        .clipShape(Capsule())
                }
            }
            .lineLimit(1)
            .truncationMode(.tail)

            HStack(spacing: 6) {
                copyPill("PID \(row.pid)", monospacedDigits: true, action: copyPIDAction)
                copyPill("bind \(row.bindSummary)", tone: row.bindTone, action: copyBindAction)
                copyPill(row.familySummary, action: copyFamilyAction)
                Spacer(minLength: 0)
            }
            .lineLimit(1)
            .truncationMode(.tail)

            tickerRow

            if let statsText = row.statsText {
                Text(statsText)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                Button("Sink") {
                    sinkAction(false)
                }
                .buttonStyle(.bordered)
                .tint(Color(red: 0.8, green: 0.5, blue: 0.1, opacity: 0.95))
                .disabled(row.requiresAdminToKill || isSinking)

                Button("Force Sink") {
                    sinkAction(true)
                }
                .buttonStyle(.bordered)
                .tint(Color(red: 1, green: 0.09, blue: 0.25, opacity: 0.75))
                .disabled(row.requiresAdminToKill || isSinking)

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

    private func copyPill(
        _ text: String,
        monospacedDigits: Bool = false,
        tone: ListenerRow.BindTone = .neutral,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            metadataChip(text, monospacedDigits: monospacedDigits, tone: tone)
        }
        .buttonStyle(.plain)
        .help("Copy \(text)")
    }

    @ViewBuilder
    private var tickerRow: some View {
        if let command = row.tickerCommandText, let cwd = row.tickerCwdText {
            HStack(spacing: 4) {
                Text(command)
                    .foregroundStyle(.primary)
                    .layoutPriority(2)
                Text("•")
                    .foregroundStyle(.tertiary)
                Text(cwd)
                    .foregroundStyle(.secondary)
                    .layoutPriority(1)
            }
            .font(.caption2.monospaced())
            .lineLimit(1)
            .truncationMode(.tail)
        } else if let command = row.tickerCommandText {
            Text(command)
                .font(.caption2.monospaced())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
        } else if let cwd = row.tickerCwdText {
            Text(cwd)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        } else {
            Text("No command line or cwd metadata")
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    @ViewBuilder
    private func metadataChip(
        _ text: String,
        monospacedDigits: Bool = false,
        tone: ListenerRow.BindTone = .neutral
    ) -> some View {
        let (foreground, background) = chipColors(for: tone)
        let base = Text(text)
            .foregroundStyle(foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(background)
            )

        if monospacedDigits {
            base.font(.caption2.monospacedDigit())
        } else {
            base.font(.caption2)
        }
    }

    private func chipColors(for tone: ListenerRow.BindTone) -> (Color, Color) {
        switch tone {
        case .neutral:
            return (.secondary, Color.secondary.opacity(0.13))
        case .localhost:
            return (
                Color(red: 0.21, green: 0.52, blue: 0.74),
                Color(red: 0.21, green: 0.52, blue: 0.74).opacity(0.16)
            )
        case .wildcard:
            return (
                Color(red: 0.73, green: 0.45, blue: 0.12),
                Color(red: 0.73, green: 0.45, blue: 0.12).opacity(0.17)
            )
        case .protected:
            return (
                Color(red: 0.70, green: 0.34, blue: 0.34),
                Color(red: 0.70, green: 0.34, blue: 0.34).opacity(0.16)
            )
        }
    }
}

private struct PendingSinkAction: Identifiable {
    let id = UUID()
    let row: ListenerRow
    let force: Bool

    var title: String {
        force ? "Force Sink \(row.portText)?" : "Sink \(row.portText)?"
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
