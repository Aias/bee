@testable import Bee
import Foundation

// MARK: - Test Factories

/// Creates a Bee instance for testing with sensible defaults.
func makeBee(
    id: String,
    schedule: String = "*/5 * * * *",
    overlap: String = "skip",
    enabled: Bool = true,
    displayName: String? = nil,
    description: String = ""
) -> Bee {
    Bee(
        id: id,
        displayName: displayName ?? id,
        icon: "ant",
        description: description,
        path: URL(fileURLWithPath: "/tmp/bee-tests/\(id)"),
        allowedTools: [],
        config: BeeConfig(
            enabled: enabled,
            schedule: schedule,
            cli: nil,
            model: nil,
            overlap: overlap,
            timeout: nil
        )
    )
}

/// Creates a Date for testing with sensible defaults (Jan 2, 2026).
func makeDate(
    year: Int = 2026,
    month: Int = 1,
    day: Int = 2,
    hour: Int,
    minute: Int,
    second: Int = 0
) -> Date {
    let calendar = Calendar.current
    guard let date = calendar.date(from: DateComponents(
        year: year,
        month: month,
        day: day,
        hour: hour,
        minute: minute,
        second: second
    )) else {
        fatalError("Failed to create date from components")
    }
    return date
}
