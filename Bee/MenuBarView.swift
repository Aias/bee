import SwiftUI

struct MenuBarView: View {
    var hive: HiveManager
    var scheduler: Scheduler
    @Binding var isPaused: Bool
    @State private var selectedBeeId: String?

    private var selectedBee: Bee? {
        guard let id = selectedBeeId else { return nil }
        return hive.bees.first { $0.id == id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let bee = selectedBee {
                BeeDetailView(
                    bee: bee,
                    hive: hive,
                    scheduler: scheduler,
                    isPaused: isPaused,
                    onBack: { selectedBeeId = nil }
                )
            } else {
                beeListView
            }
        }
        .frame(width: 280)
    }

    private var beeListView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "ant")
                Text("Bee")
                    .font(.headline)
                Spacer()
                Button {
                    hive.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Refresh bee list")
            }
            .padding()
            .background(.bar)

            Divider()

            // Bee list
            if hive.bees.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No bees discovered")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                    Text("Add bee folders to ~/.bee/")
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(hive.bees) { bee in
                    BeeRow(
                        bee: bee,
                        isPaused: isPaused,
                        isRunning: scheduler.runningBees.contains(bee.id)
                    )
                    .onTapGesture {
                        selectedBeeId = bee.id
                    }
                    .contextMenu {
                        beeContextMenu(bee: bee)
                    }
                }
            }

            Divider()

            // Footer actions
            footerActions
        }
    }

    @ViewBuilder
    private func beeContextMenu(bee: Bee) -> some View {
        Button("Run Now") {
            scheduler.triggerManually(bee)
        }
        .disabled(scheduler.runningBees.contains(bee.id))

        Button(bee.config.enabled ? "Disable" : "Enable") {
            hive.updateBeeConfig(bee.id) { config in
                config.enabled.toggle()
            }
        }

        Divider()

        Button("Open Logs Folder") {
            openLogsFolder(bee: bee)
        }

        Button("Open Skill Folder") {
            NSWorkspace.shared.open(bee.path)
        }
    }

    private func openLogsFolder(bee: Bee) {
        let logsPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".bee/logs")
            .appendingPathComponent(bee.id)
        NSWorkspace.shared.open(logsPath)
    }

    private var footerActions: some View {
        VStack(spacing: 0) {
            Button {
                isPaused.toggle()
            } label: {
                Label(
                    isPaused ? "Resume All" : "Pause All",
                    systemImage: isPaused ? "play.fill" : "pause.fill"
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            Button {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Preferences...", systemImage: "gear")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit Bee", systemImage: "xmark.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .keyboardShortcut("q", modifiers: .command)
        }
    }
}

// MARK: - Bee Detail View

struct BeeDetailView: View {
    let bee: Bee
    var hive: HiveManager
    var scheduler: Scheduler
    let isPaused: Bool
    let onBack: () -> Void

    @State private var recentRuns: [BeeRunLog] = []

    private var isRunning: Bool {
        scheduler.runningBees.contains(bee.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with back button
            HStack {
                Button {
                    onBack()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)

                Text(bee.displayName)
                    .font(.headline)
                Spacer()

                Circle()
                    .fill(isRunning ? Color.orange : (bee.config.enabled ? Color.green : Color.secondary))
                    .frame(width: 8, height: 8)
            }
            .padding()
            .background(.bar)

            Divider()

            // Status info
            VStack(alignment: .leading, spacing: 4) {
                if !bee.description.isEmpty {
                    Text(bee.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Schedule:")
                        .foregroundStyle(.secondary)
                    Text(bee.config.enabled ? CronParser.toEnglish(bee.config.schedule) : "Disabled")
                }
                .font(.caption)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // Actions
            VStack(spacing: 0) {
                Button {
                    scheduler.triggerManually(bee)
                } label: {
                    Label("Run Now", systemImage: "play.fill")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
                .padding(.vertical, 6)
                .disabled(isRunning)

                Button {
                    hive.updateBeeConfig(bee.id) { config in
                        config.enabled.toggle()
                    }
                } label: {
                    Label(
                        bee.config.enabled ? "Disable" : "Enable",
                        systemImage: bee.config.enabled ? "pause.circle" : "play.circle"
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
                .padding(.vertical, 6)

                Divider()

                Button {
                    let logsPath = FileManager.default.homeDirectoryForCurrentUser
                        .appendingPathComponent(".bee/logs")
                        .appendingPathComponent(bee.id)
                    NSWorkspace.shared.open(logsPath)
                } label: {
                    Label("Open Logs Folder", systemImage: "folder")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
                .padding(.vertical, 6)

                Button {
                    NSWorkspace.shared.open(bee.path)
                } label: {
                    Label("Open Skill Folder", systemImage: "doc.text")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
                .padding(.vertical, 6)
            }

            Divider()

            // Recent runs
            VStack(alignment: .leading, spacing: 4) {
                Text("Recent Runs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.top, 8)

                if recentRuns.isEmpty {
                    Text("No runs yet")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                } else {
                    ForEach(recentRuns.prefix(5)) { run in
                        HStack {
                            Circle()
                                .fill(run.success ? Color.green : Color.red)
                                .frame(width: 6, height: 6)
                            Text(run.timestamp)
                                .font(.caption)
                            Spacer()
                            Text(run.durationText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 2)
                    }
                    .padding(.bottom, 4)
                }
            }
        }
        .onAppear {
            recentRuns = loadRecentRuns()
        }
    }

    private func loadRecentRuns() -> [BeeRunLog] {
        let logsPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".bee/logs")
            .appendingPathComponent(bee.id)

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: logsPath,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return files
            .filter { $0.pathExtension == "log" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .prefix(5)
            .compactMap { parseLogFile($0) }
    }

    private func parseLogFile(_ url: URL) -> BeeRunLog? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }

        // Parse timestamp from filename (2026-01-02T15:02:48.log)
        let filename = url.deletingPathExtension().lastPathComponent
        let timestamp = formatTimestamp(filename)

        // Parse duration from content
        var duration: TimeInterval = 0
        var success = true

        for line in content.components(separatedBy: .newlines) {
            if line.hasPrefix("# Duration:") {
                let value = line.replacingOccurrences(of: "# Duration:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "s", with: "")
                duration = Double(value) ?? 0
            }
            if line.contains("## Errors") {
                // Check if there's actual error content after this
                if let errorSection = content.components(separatedBy: "## Errors").last,
                   !errorSection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    success = false
                }
            }
        }

        return BeeRunLog(
            id: url.lastPathComponent,
            timestamp: timestamp,
            duration: duration,
            success: success
        )
    }

    private func formatTimestamp(_ isoString: String) -> String {
        // Convert 2026-01-02T15:02:48 to "Today 3:02 PM" or "Jan 2, 3:02 PM"
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate, .withColonSeparatorInTime]

        guard let date = formatter.date(from: isoString) else {
            return isoString
        }

        let calendar = Calendar.current
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "h:mm a"

        if calendar.isDateInToday(date) {
            return "Today \(timeFormatter.string(from: date))"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday \(timeFormatter.string(from: date))"
        } else {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MMM d"
            return "\(dateFormatter.string(from: date)), \(timeFormatter.string(from: date))"
        }
    }
}

struct BeeRunLog: Identifiable {
    let id: String
    let timestamp: String
    let duration: TimeInterval
    let success: Bool

    var durationText: String {
        if duration < 60 {
            return String(format: "%.1fs", duration)
        } else {
            let minutes = Int(duration / 60)
            let seconds = Int(duration.truncatingRemainder(dividingBy: 60))
            return "\(minutes)m \(seconds)s"
        }
    }
}

// MARK: - Bee Row

struct BeeRow: View {
    let bee: Bee
    let isPaused: Bool
    let isRunning: Bool

    private var isActive: Bool {
        bee.config.enabled && !isPaused
    }

    private var statusText: String {
        if isRunning {
            return "Running..."
        }
        if !bee.config.enabled {
            return "Disabled"
        }
        return CronParser.toEnglish(bee.config.schedule)
    }

    var body: some View {
        HStack {
            Group {
                if isRunning {
                    ProgressView()
                        .scaleEffect(0.5)
                } else {
                    Image(systemName: bee.icon)
                        .foregroundStyle(isActive ? .primary : .secondary)
                }
            }
            .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(bee.displayName)
                    .font(.subheadline)
                if !bee.description.isEmpty {
                    Text(bee.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(statusText)
                    .font(.caption2)
                    .foregroundStyle(isRunning ? .primary : .tertiary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}
