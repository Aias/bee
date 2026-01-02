import SwiftUI

// MARK: - AppState

@Observable
final class AppState {
    let hive = HiveManager()
    let scheduler = Scheduler()
    var isPaused = false

    init() {
        NotificationManager.shared.setup()

        scheduler.start(hive: hive, isPaused: { [weak self] in self?.isPaused ?? true }) { [weak self] bee in
            guard let self else { return }
            let cli = bee.config.cli ?? hive.config.defaultCLI
            let model = bee.config.model ?? hive.config.defaultModel

            print("🐝 Triggered: \(bee.displayName) (using \(cli)\(model.map { ", model: \($0)" } ?? ""))")

            BeeRunner.run(bee, cli: cli, model: model) { result in
                if result.success {
                    print("✅ \(bee.displayName) completed in \(String(format: "%.1f", result.duration))s")
                } else {
                    print("❌ \(bee.displayName) failed: \(result.error ?? "unknown error")")
                    NotificationManager.showError(bee: bee, error: result.error ?? "Unknown error")
                }
                self.scheduler.markComplete(bee.id)
            }
        }
    }
}

// MARK: - BeeApp

@main
struct BeeApp: App {
    @State private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(hive: state.hive, scheduler: state.scheduler, isPaused: $state.isPaused)
        } label: {
            Label("Bee", systemImage: state.isPaused ? "pause.circle" : "ant.fill")
        }
        .menuBarExtraStyle(.window)

        Settings {
            PreferencesView(hive: state.hive)
        }
    }
}
