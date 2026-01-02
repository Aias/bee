import SwiftUI

struct MenuBarView: View {
    var hive: HiveManager
    var scheduler: Scheduler
    @Binding var isPaused: Bool

    var body: some View {
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
                    .contextMenu {
                        Button("Run Now") {
                            scheduler.triggerManually(bee)
                        }
                        .disabled(scheduler.runningBees.contains(bee.id) || !bee.config.enabled)

                        Button(bee.config.enabled ? "Disable" : "Enable") {
                            hive.updateBeeConfig(bee.id) { config in
                                config.enabled.toggle()
                            }
                        }

                        Divider()

                        Button("Open Logs Folder") {
                            let logsPath = FileManager.default.homeDirectoryForCurrentUser
                                .appendingPathComponent(".bee/logs")
                                .appendingPathComponent(bee.id)
                            NSWorkspace.shared.open(logsPath)
                        }

                        Button("Open Skill Folder") {
                            NSWorkspace.shared.open(bee.path)
                        }
                    }
                }
            }

            Divider()

            // Footer actions
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

                SettingsLink {
                    Label("Preferences...", systemImage: "gear")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
                .padding(.vertical, 8)

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
        .frame(width: 280)
    }
}

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
                    Image(systemName: "ant")
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
            Circle()
                .fill(isRunning ? Color.orange : (isActive ? Color.green : Color.secondary))
                .frame(width: 8, height: 8)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}
