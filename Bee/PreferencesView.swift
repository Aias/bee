import SwiftUI

// MARK: - PreferencesView

struct PreferencesView: View {
    var hive: HiveManager

    var body: some View {
        Form {
            Section {
                Picker("Default CLI", selection: Binding(
                    get: { hive.config.defaultCLI },
                    set: { newValue in hive.updateGlobalConfig { $0.defaultCLI = newValue } }
                )) {
                    Text("Claude").tag("claude")
                    Text("Codex").tag("codex")
                    Text("Cursor").tag("cursor")
                }
                .pickerStyle(.menu)

                Picker("Default Model", selection: Binding(
                    get: { hive.config.defaultModel ?? "" },
                    set: { newValue in hive.updateGlobalConfig { $0.defaultModel = newValue.isEmpty ? nil : newValue } }
                )) {
                    Text("CLI Default").tag("")
                    Text("Opus").tag("opus")
                    Text("Sonnet").tag("sonnet")
                    Text("Haiku").tag("haiku")
                }
                .pickerStyle(.menu)

                Picker("Overlap Behavior", selection: Binding(
                    get: { hive.config.defaultOverlap },
                    set: { newValue in hive.updateGlobalConfig { $0.defaultOverlap = newValue } }
                )) {
                    Text("Skip").tag("skip")
                    Text("Queue").tag("queue")
                    Text("Parallel").tag("parallel")
                }
                .pickerStyle(.menu)
            } header: {
                Text("Defaults")
            }

            Section {
                HStack {
                    Text(hive.hivePath.path)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("Reveal") {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: hive.hivePath.path)
                    }
                }
            } header: {
                Text("Storage")
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 300)
        .navigationTitle("Bee Preferences")
    }
}

// MARK: - Previews

#if DEBUG
    #Preview("Preferences") {
        PreferencesView(hive: .preview())
    }
#endif
