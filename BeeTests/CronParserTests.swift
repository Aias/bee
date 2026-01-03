@testable import Bee
import XCTest

// MARK: - CronParserTests

final class CronParserTests: XCTestCase {
    // MARK: - matches() tests

    func testMatchesEveryFiveMinutes() {
        let date = makeDate(hour: 10, minute: 15)
        XCTAssertTrue(CronParser.matches("*/5 * * * *", date: date))
        XCTAssertFalse(CronParser.matches("*/7 * * * *", date: date))
    }

    func testMatchesWildcard() {
        let date = makeDate(hour: 14, minute: 37)
        XCTAssertTrue(CronParser.matches("* * * * *", date: date))
    }

    func testMatchesExactMinute() {
        let date = makeDate(hour: 10, minute: 30)
        XCTAssertTrue(CronParser.matches("30 * * * *", date: date))
        XCTAssertFalse(CronParser.matches("31 * * * *", date: date))
    }

    func testMatchesExactHourAndMinute() {
        let date = makeDate(hour: 9, minute: 0)
        XCTAssertTrue(CronParser.matches("0 9 * * *", date: date))
        XCTAssertFalse(CronParser.matches("0 10 * * *", date: date))
    }

    func testMatchesRange() {
        // 9 AM is within 9-17 (business hours)
        let morning = makeDate(hour: 9, minute: 0)
        XCTAssertTrue(CronParser.matches("0 9-17 * * *", date: morning))

        // 8 AM is outside 9-17
        let early = makeDate(hour: 8, minute: 0)
        XCTAssertFalse(CronParser.matches("0 9-17 * * *", date: early))

        // 17 (5 PM) is within range (inclusive)
        let evening = makeDate(hour: 17, minute: 0)
        XCTAssertTrue(CronParser.matches("0 9-17 * * *", date: evening))
    }

    func testMatchesList() {
        let date = makeDate(hour: 10, minute: 15)
        XCTAssertTrue(CronParser.matches("0,15,30,45 * * * *", date: date))
        XCTAssertFalse(CronParser.matches("0,10,20,30 * * * *", date: date))
    }

    func testMatchesDayOfWeek() {
        // Jan 2, 2026 is a Friday (weekday 5, but Swift Calendar uses 1=Sun, so Friday=6)
        // CronParser subtracts 1, so Friday = 5
        let friday = makeDate(year: 2026, month: 1, day: 2, hour: 9, minute: 0)
        XCTAssertTrue(CronParser.matches("0 9 * * 5", date: friday))
        XCTAssertFalse(CronParser.matches("0 9 * * 1", date: friday)) // Monday
    }

    func testMatchesInvalidCronReturnsFalse() {
        let date = makeDate(hour: 10, minute: 0)
        XCTAssertFalse(CronParser.matches("* * * *", date: date)) // Only 4 parts
        XCTAssertFalse(CronParser.matches("", date: date))
    }

    // MARK: - nextRun() tests

    func testNextRunReturnsMatchingDate() {
        let start = makeDate(hour: 10, minute: 12)

        guard let next = CronParser.nextRun("*/10 * * * *", after: start) else {
            return XCTFail("Expected next run time")
        }

        XCTAssertTrue(next > start)
        XCTAssertTrue(CronParser.matches("*/10 * * * *", date: next))
    }

    func testNextRunReturnsNilForInvalidCron() {
        let start = makeDate(hour: 10, minute: 0)
        XCTAssertNil(CronParser.nextRun("invalid", after: start))
    }

    // MARK: - toEnglish() tests

    func testToEnglishEveryMinute() {
        XCTAssertEqual(CronParser.toEnglish("*/1 * * * *"), "Every minute")
    }

    func testToEnglishEveryNMinutes() {
        XCTAssertEqual(CronParser.toEnglish("*/5 * * * *"), "Every 5 minutes")
        XCTAssertEqual(CronParser.toEnglish("*/15 * * * *"), "Every 15 minutes")
    }

    func testToEnglishEveryHour() {
        XCTAssertEqual(CronParser.toEnglish("0 * * * *"), "Every hour")
    }

    func testToEnglishEveryHourAtMinute() {
        XCTAssertEqual(CronParser.toEnglish("30 * * * *"), "Every hour at :30")
    }

    func testToEnglishDailyAtTime() {
        XCTAssertEqual(CronParser.toEnglish("0 9 * * *"), "Daily at 9:00 AM")
        XCTAssertEqual(CronParser.toEnglish("30 14 * * *"), "Daily at 2:30 PM")
    }

    func testToEnglishWeekdays() {
        XCTAssertEqual(CronParser.toEnglish("0 9 * * 1-5"), "Weekdays at 9:00 AM")
    }

    func testToEnglishWeekends() {
        XCTAssertEqual(CronParser.toEnglish("0 10 * * 0,6"), "Weekends at 10:00 AM")
    }

    func testToEnglishEveryNHours() {
        XCTAssertEqual(CronParser.toEnglish("0 */2 * * *"), "Every 2 hours")
        XCTAssertEqual(CronParser.toEnglish("0 */1 * * *"), "Every hour")
    }

    func testToEnglishUnrecognizedReturnsCron() {
        // Complex patterns that don't match any template
        let complex = "15 9 1 * *" // 9:15 AM on the 1st of every month
        XCTAssertEqual(CronParser.toEnglish(complex), complex)
    }
}
