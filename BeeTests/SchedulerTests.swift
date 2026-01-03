@testable import Bee
import XCTest

// MARK: - SchedulerTests

final class SchedulerTests: XCTestCase {
    // MARK: - evaluate() tests

    func testEvaluateAddsRunningBeeOnMatch() {
        let scheduler = Scheduler()
        let bee = makeBee(id: "alpha", schedule: "*/5 * * * *", overlap: "skip")
        let now = makeDate(hour: 10, minute: 10) // Divisible by 5

        scheduler.evaluate(bees: [bee], isPaused: { false }, now: now)

        XCTAssertEqual(scheduler.runningBees, ["alpha"])
    }

    func testEvaluateDoesNotTriggerOnNonMatch() {
        let scheduler = Scheduler()
        let bee = makeBee(id: "alpha", schedule: "*/5 * * * *", overlap: "skip")
        let now = makeDate(hour: 10, minute: 13) // Not divisible by 5

        scheduler.evaluate(bees: [bee], isPaused: { false }, now: now)

        XCTAssertTrue(scheduler.runningBees.isEmpty)
    }

    func testEvaluateSkipsDisabledBees() {
        let scheduler = Scheduler()
        let bee = makeBee(id: "alpha", schedule: "*/5 * * * *", overlap: "skip", enabled: false)
        let now = makeDate(hour: 10, minute: 10)

        scheduler.evaluate(bees: [bee], isPaused: { false }, now: now)

        XCTAssertTrue(scheduler.runningBees.isEmpty)
    }

    func testEvaluateSkipsWhenPaused() {
        let scheduler = Scheduler()
        let bee = makeBee(id: "alpha", schedule: "*/5 * * * *", overlap: "skip")
        let now = makeDate(hour: 10, minute: 10)

        scheduler.evaluate(bees: [bee], isPaused: { true }, now: now)

        XCTAssertTrue(scheduler.runningBees.isEmpty)
    }

    func testEvaluateTriggersMultipleBees() {
        let scheduler = Scheduler()
        let bee1 = makeBee(id: "alpha", schedule: "*/5 * * * *", overlap: "skip")
        let bee2 = makeBee(id: "beta", schedule: "*/5 * * * *", overlap: "skip")
        let now = makeDate(hour: 10, minute: 10)

        scheduler.evaluate(bees: [bee1, bee2], isPaused: { false }, now: now)

        XCTAssertEqual(scheduler.runningBees.sorted(), ["alpha", "beta"])
    }

    // MARK: - Overlap behavior tests

    func testQueueOverlapAddsQueuedBee() {
        let scheduler = Scheduler()
        let bee = makeBee(id: "alpha", schedule: "*/5 * * * *", overlap: "queue")
        let now = makeDate(hour: 10, minute: 10)

        scheduler.evaluate(bees: [bee], isPaused: { false }, now: now)
        scheduler.evaluate(bees: [bee], isPaused: { false }, now: now)

        XCTAssertEqual(scheduler.runningBees, ["alpha"])
        XCTAssertEqual(scheduler.queuedBees, ["alpha"])
    }

    func testSkipOverlapDoesNotQueue() {
        let scheduler = Scheduler()
        let bee = makeBee(id: "alpha", schedule: "*/5 * * * *", overlap: "skip")
        let now = makeDate(hour: 10, minute: 10)

        scheduler.evaluate(bees: [bee], isPaused: { false }, now: now)
        scheduler.evaluate(bees: [bee], isPaused: { false }, now: now)

        XCTAssertEqual(scheduler.runningBees, ["alpha"])
        XCTAssertTrue(scheduler.queuedBees.isEmpty)
    }

    func testQueueOnlyAddsOnce() {
        let scheduler = Scheduler()
        let bee = makeBee(id: "alpha", schedule: "*/5 * * * *", overlap: "queue")
        let now = makeDate(hour: 10, minute: 10)

        scheduler.evaluate(bees: [bee], isPaused: { false }, now: now)
        scheduler.evaluate(bees: [bee], isPaused: { false }, now: now)
        scheduler.evaluate(bees: [bee], isPaused: { false }, now: now)

        XCTAssertEqual(scheduler.queuedBees.count, 1)
    }

    // MARK: - markComplete() tests

    func testMarkCompleteClearsRunningBee() {
        let scheduler = Scheduler()
        let bee = makeBee(id: "alpha", schedule: "*/5 * * * *", overlap: "skip")
        let now = makeDate(hour: 10, minute: 10)

        scheduler.evaluate(bees: [bee], isPaused: { false }, now: now)
        XCTAssertTrue(scheduler.runningBees.contains("alpha"))

        scheduler.markComplete("alpha")
        XCTAssertFalse(scheduler.runningBees.contains("alpha"))
    }

    func testMarkCompleteRemovesFromQueue() {
        let scheduler = Scheduler()
        let bee = makeBee(id: "alpha", schedule: "*/5 * * * *", overlap: "queue")
        let now = makeDate(hour: 10, minute: 10)

        // Trigger twice to add to queue
        scheduler.evaluate(bees: [bee], isPaused: { false }, now: now)
        scheduler.evaluate(bees: [bee], isPaused: { false }, now: now)
        XCTAssertEqual(scheduler.queuedBees, ["alpha"])

        // Complete first run - should dequeue and re-trigger
        scheduler.markComplete("alpha")

        // Note: re-trigger adds back to running, removes from queue
        // But since hive is nil in test, trigger callback won't fire
        // So it just removes from queue
        XCTAssertTrue(scheduler.queuedBees.isEmpty)
    }

    func testMarkCompleteNonexistentBeeIsNoOp() {
        let scheduler = Scheduler()

        // Should not crash
        scheduler.markComplete("nonexistent")

        XCTAssertTrue(scheduler.runningBees.isEmpty)
        XCTAssertTrue(scheduler.queuedBees.isEmpty)
    }

    // MARK: - Preview factory tests

    func testPreviewFactoryCreatesEmptyScheduler() {
        let scheduler = Scheduler.preview()

        XCTAssertTrue(scheduler.runningBees.isEmpty)
        XCTAssertTrue(scheduler.queuedBees.isEmpty)
    }

    func testPreviewFactoryWithRunningBees() {
        let scheduler = Scheduler.preview(running: ["alpha", "beta"])

        XCTAssertEqual(scheduler.runningBees, ["alpha", "beta"])
        XCTAssertTrue(scheduler.queuedBees.isEmpty)
    }
}
