import Foundation

@Observable
final class Scheduler {
    private(set) var runningBees: Set<String> = []
    private(set) var queuedBees: [String] = []

    private var timer: Timer?
    private var hive: HiveManager?
    private var isPaused: Bool = false
    private var onTrigger: ((Bee) -> Void)?

    func start(hive: HiveManager, isPaused: @escaping () -> Bool, onTrigger: @escaping (Bee) -> Void) {
        self.hive = hive
        self.onTrigger = onTrigger

        // Check every minute at the top of the minute
        let now = Date()
        let calendar = Calendar.current
        let seconds = calendar.component(.second, from: now)
        let delayToNextMinute = Double(60 - seconds)

        // Initial delay to sync to minute boundary
        DispatchQueue.main.asyncAfter(deadline: .now() + delayToNextMinute) { [weak self] in
            self?.tick(isPaused: isPaused)
            self?.timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
                self?.tick(isPaused: isPaused)
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func triggerManually(_ bee: Bee) {
        handleTrigger(bee)
    }

    func markComplete(_ beeId: String) {
        runningBees.remove(beeId)

        // Check queue for this bee
        if let queueIndex = queuedBees.firstIndex(of: beeId) {
            queuedBees.remove(at: queueIndex)
            // Find and trigger the queued bee
            if let hive, let bee = hive.bees.first(where: { $0.id == beeId }) {
                handleTrigger(bee)
            }
        }
    }

    private func tick(isPaused: @escaping () -> Bool) {
        guard !isPaused(), let hive else { return }

        let now = Date()

        for bee in hive.bees {
            guard bee.config.enabled else { continue }

            if CronParser.matches(bee.config.schedule, date: now) {
                handleTrigger(bee)
            }
        }
    }

    private func handleTrigger(_ bee: Bee) {
        let overlap = bee.config.overlap ?? hive?.config.defaultOverlap ?? "skip"

        if runningBees.contains(bee.id) {
            switch overlap {
            case "queue":
                if !queuedBees.contains(bee.id) {
                    queuedBees.append(bee.id)
                }
            case "parallel":
                // Allow parallel execution
                onTrigger?(bee)
            default:  // "skip"
                return
            }
        } else {
            runningBees.insert(bee.id)
            onTrigger?(bee)
        }
    }

}
