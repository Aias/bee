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

            if cronMatches(bee.config.schedule, date: now) {
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

    // MARK: - Cron Matching

    private func cronMatches(_ cron: String, date: Date) -> Bool {
        let parts = cron.split(separator: " ").map(String.init)
        guard parts.count == 5 else { return false }

        let calendar = Calendar.current
        let minute = calendar.component(.minute, from: date)
        let hour = calendar.component(.hour, from: date)
        let dayOfMonth = calendar.component(.day, from: date)
        let month = calendar.component(.month, from: date)
        let dayOfWeek = calendar.component(.weekday, from: date) - 1  // 0 = Sunday

        return fieldMatches(parts[0], value: minute, max: 59) &&
               fieldMatches(parts[1], value: hour, max: 23) &&
               fieldMatches(parts[2], value: dayOfMonth, max: 31) &&
               fieldMatches(parts[3], value: month, max: 12) &&
               fieldMatches(parts[4], value: dayOfWeek, max: 6)
    }

    private func fieldMatches(_ field: String, value: Int, max: Int) -> Bool {
        // Wildcard
        if field == "*" { return true }

        // Step values (*/n)
        if field.hasPrefix("*/") {
            guard let step = Int(field.dropFirst(2)), step > 0 else { return false }
            return value % step == 0
        }

        // Range (n-m)
        if field.contains("-") && !field.contains(",") {
            let rangeParts = field.split(separator: "-").compactMap { Int($0) }
            if rangeParts.count == 2 {
                return value >= rangeParts[0] && value <= rangeParts[1]
            }
        }

        // List (n,m,o)
        if field.contains(",") {
            let values = field.split(separator: ",").compactMap { Int($0) }
            return values.contains(value)
        }

        // Exact value
        if let exact = Int(field) {
            return value == exact
        }

        return false
    }
}
