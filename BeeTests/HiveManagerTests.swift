@testable import Bee
import XCTest

final class HiveManagerTests: XCTestCase {
    // swiftlint:disable:next implicitly_unwrapped_optional
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("bee-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
    }

    // MARK: - Path injection tests

    func testUsesInjectedHivePath() {
        let hive = HiveManager(hivePath: tempDir)
        XCTAssertEqual(hive.hivePath, tempDir)
    }

    func testCreatesHiveDirectoryIfMissing() {
        let newPath = tempDir.appendingPathComponent("new-hive")
        _ = HiveManager(hivePath: newPath)

        XCTAssertTrue(FileManager.default.fileExists(atPath: newPath.path))
    }

    // MARK: - Config persistence tests

    func testConfigSaveAndLoad() throws {
        // Create hive, modify config, and verify it persists
        let hive1 = HiveManager(hivePath: tempDir)

        // Modify global config
        hive1.updateGlobalConfig { config in
            config.defaultCLI = "custom-cli"
            config.defaultModel = "opus"
            config.defaultOverlap = "queue"
        }

        // Create new HiveManager pointing to same path - should load saved config
        let hive2 = HiveManager(hivePath: tempDir)

        XCTAssertEqual(hive2.config.defaultCLI, "custom-cli")
        XCTAssertEqual(hive2.config.defaultModel, "opus")
        XCTAssertEqual(hive2.config.defaultOverlap, "queue")
    }

    func testBeeConfigPersistence() throws {
        // Create a bee directory with SKILL.md
        let beeDir = tempDir.appendingPathComponent("test-bee")
        try FileManager.default.createDirectory(at: beeDir, withIntermediateDirectories: true)
        try "---\ndescription: Test bee\n---\n# Test".write(
            to: beeDir.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        // Create hive and update bee config
        let hive1 = HiveManager(hivePath: tempDir)
        XCTAssertEqual(hive1.bees.count, 1)

        hive1.updateBeeConfig("test-bee") { config in
            config.enabled = false
            config.schedule = "0 9 * * *"
            config.model = "haiku"
        }

        // Create new HiveManager - should load bee config
        let hive2 = HiveManager(hivePath: tempDir)
        let beeConfig = hive2.config.bees["test-bee"]

        XCTAssertNotNil(beeConfig)
        XCTAssertEqual(beeConfig?.enabled, false)
        XCTAssertEqual(beeConfig?.schedule, "0 9 * * *")
        XCTAssertEqual(beeConfig?.model, "haiku")
    }

    // MARK: - Bee discovery tests

    func testDiscoversBeeWithSkillMd() throws {
        // Create bee directory with SKILL.md
        let beeDir = tempDir.appendingPathComponent("my-bee")
        try FileManager.default.createDirectory(at: beeDir, withIntermediateDirectories: true)
        try "---\ndescription: My test bee\n---\n# My Bee".write(
            to: beeDir.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        let hive = HiveManager(hivePath: tempDir)

        XCTAssertEqual(hive.bees.count, 1)
        XCTAssertEqual(hive.bees.first?.id, "my-bee")
        XCTAssertEqual(hive.bees.first?.description, "My test bee")
    }

    func testIgnoresDirectoryWithoutSkillMd() throws {
        // Create directory without SKILL.md
        let otherDir = tempDir.appendingPathComponent("not-a-bee")
        try FileManager.default.createDirectory(at: otherDir, withIntermediateDirectories: true)
        try "Just a text file".write(
            to: otherDir.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )

        let hive = HiveManager(hivePath: tempDir)

        XCTAssertEqual(hive.bees.count, 0)
    }

    func testParsesDisplayNameFromFrontmatter() throws {
        let beeDir = tempDir.appendingPathComponent("journal-bee")
        try FileManager.default.createDirectory(at: beeDir, withIntermediateDirectories: true)
        try """
        ---
        description: Captures daily thoughts
        metadata:
          display-name: Daily Journal
          icon: book
        ---
        # Journal Bee
        """.write(
            to: beeDir.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        let hive = HiveManager(hivePath: tempDir)

        XCTAssertEqual(hive.bees.first?.displayName, "Daily Journal")
        XCTAssertEqual(hive.bees.first?.icon, "book")
    }

    func testFallsBackToFolderNameForDisplayName() throws {
        let beeDir = tempDir.appendingPathComponent("simple-bee")
        try FileManager.default.createDirectory(at: beeDir, withIntermediateDirectories: true)
        try "---\ndescription: Simple\n---\n# Simple".write(
            to: beeDir.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        let hive = HiveManager(hivePath: tempDir)

        XCTAssertEqual(hive.bees.first?.displayName, "simple-bee")
        XCTAssertEqual(hive.bees.first?.icon, "ant") // Default icon
    }

    // MARK: - Refresh tests

    func testRefreshDetectsNewBees() throws {
        let hive = HiveManager(hivePath: tempDir)
        XCTAssertEqual(hive.bees.count, 0)

        // Add a bee after initialization
        let beeDir = tempDir.appendingPathComponent("new-bee")
        try FileManager.default.createDirectory(at: beeDir, withIntermediateDirectories: true)
        try "---\ndescription: New\n---\n# New".write(
            to: beeDir.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        hive.refresh()

        XCTAssertEqual(hive.bees.count, 1)
        XCTAssertEqual(hive.bees.first?.id, "new-bee")
    }

    // MARK: - Preview factory tests

    func testPreviewFactoryCreatesManagerWithMockBees() {
        let hive = HiveManager.preview()

        XCTAssertEqual(hive.bees.count, 3)
        XCTAssertTrue(hive.bees.contains { $0.id == "journal-bee" })
        XCTAssertTrue(hive.bees.contains { $0.id == "test-bee" })
        XCTAssertTrue(hive.bees.contains { $0.id == "backup-bee" })
    }

    func testPreviewFactoryWithCustomBees() {
        let customBees = [makeBee(id: "custom", displayName: "Custom Bee")]
        let hive = HiveManager.preview(bees: customBees)

        XCTAssertEqual(hive.bees.count, 1)
        XCTAssertEqual(hive.bees.first?.id, "custom")
    }

    func testPreviewBeesHaveValidData() {
        let bees = Bee.previewBees

        for bee in bees {
            XCTAssertFalse(bee.id.isEmpty)
            XCTAssertFalse(bee.displayName.isEmpty)
            XCTAssertFalse(bee.icon.isEmpty)
            XCTAssertFalse(bee.config.schedule.isEmpty)
        }
    }
}
