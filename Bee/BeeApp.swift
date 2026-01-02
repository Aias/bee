import SwiftUI

@Observable
final class AppState {
    let hive = HiveManager()
    let scheduler = Scheduler()
    var isPaused = false

    init() {
        scheduler.start(hive: hive, isPaused: { [weak self] in self?.isPaused ?? true }) { [weak self] bee in
            guard let self else { return }
            let cli = bee.config.cli ?? self.hive.config.defaultCLI

            print("🐝 Triggered: \(bee.displayName) (using \(cli))")

            BeeRunner.run(bee, cli: cli) { result in
                if result.success {
                    print("✅ \(bee.displayName) completed in \(String(format: "%.1f", result.duration))s")
                } else {
                    print("❌ \(bee.displayName) failed: \(result.error ?? "unknown error")")
                    // TODO: Show error notification
                }
                self.scheduler.markComplete(bee.id)
            }
        }
    }
}

@main
struct BeeApp: App {
    @State private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(hive: state.hive, scheduler: state.scheduler, isPaused: $state.isPaused)
        } label: {
            Label("Bee", systemImage: state.isPaused ? "pause.circle" : "ant")
        }
        .menuBarExtraStyle(.window)

        Settings {
            PreferencesView()
        }
    }
}
