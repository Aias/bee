import SwiftUI

struct PreferencesView: View {
    @AppStorage("defaultCLI") private var defaultCLI = "claude"
    @AppStorage("defaultOverlap") private var defaultOverlap = "skip"
    @AppStorage("hivePath") private var hivePath = "~/.bee"

    var body: some View {
        Form {
            Section {
                Picker("Default CLI", selection: $defaultCLI) {
                    Text("Claude").tag("claude")
                    Text("Codex").tag("codex")
                    Text("Cursor").tag("cursor")
                }
                .pickerStyle(.menu)

                Picker("Overlap Behavior", selection: $defaultOverlap) {
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
                    TextField("Hive Path", text: $hivePath)
                        .textFieldStyle(.roundedBorder)

                    Button("Reveal") {
                        let expanded = NSString(string: hivePath).expandingTildeInPath
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: expanded)
                    }
                }
            } header: {
                Text("Storage")
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 200)
        .navigationTitle("Bee Preferences")
    }
}
