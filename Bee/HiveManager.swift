import Foundation
import SwiftUI

// MARK: - Bee

struct Bee: Identifiable {
    let id: String // folder name (matches SKILL.md name field per spec)
    let displayName: String // from metadata.display-name, falls back to id
    let icon: String // SF Symbol name from metadata.icon, falls back to "ant"
    let description: String
    let path: URL
    let allowedTools: [String]
    var config: BeeConfig

    var skillPath: URL { path.appendingPathComponent("SKILL.md") }
    var scriptsPath: URL { path.appendingPathComponent("scripts") }
}

// MARK: - BeeConfig

struct BeeConfig: Equatable {
    var enabled: Bool = true
    var schedule: String = "*/5 * * * *" // Default: every 5 minutes
    var cli: String? // nil = use global default
    var model: String? // nil = use global default (e.g., "sonnet", "haiku", "opus")
    var overlap: String? // nil = use global default
    var timeout: Int? // Confirmation timeout in seconds, nil = use default (300)
}

// MARK: - HiveConfig

struct HiveConfig {
    var version: Int = 1
    var defaultCLI: String = "claude"
    var defaultModel: String? // nil = CLI default (e.g., "sonnet", "haiku", "opus")
    var defaultOverlap: String = "skip"
    var bees: [String: BeeConfig] = [:]
}

// MARK: - HiveManager

@Observable
final class HiveManager {
    private(set) var bees: [Bee] = []
    private(set) var config: HiveConfig = .init()
    private(set) var lastError: String?

    private let fileManager = FileManager.default
    var hivePath: URL {
        fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".bee")
    }

    private var configPath: URL {
        hivePath.appendingPathComponent("hive.yaml")
    }

    init() {
        refresh()
    }

    func refresh() {
        bees = []
        lastError = nil

        // Create ~/.bee/ if it doesn't exist
        if !fileManager.fileExists(atPath: hivePath.path) {
            do {
                try fileManager.createDirectory(at: hivePath, withIntermediateDirectories: true)
            } catch {
                lastError = "Failed to create ~/.bee/: \(error.localizedDescription)"
                return
            }
        }

        // Load hive.yaml
        config = loadConfig()

        // Scan for bee folders
        guard let contents = try? fileManager.contentsOfDirectory(
            at: hivePath,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            lastError = "Failed to read ~/.bee/"
            return
        }

        for url in contents {
            guard let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey]),
                  resourceValues.isDirectory == true else {
                continue
            }

            let skillFile = url.appendingPathComponent("SKILL.md")
            guard fileManager.fileExists(atPath: skillFile.path) else {
                continue
            }

            if let bee = parseBee(at: url) {
                bees.append(bee)
            }
        }

        bees.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

        // Sync config with discovered bees (add new ones, keep existing settings)
        syncConfigWithBees()
    }

    func updateBeeConfig(_ beeId: String, _ update: (inout BeeConfig) -> Void) {
        guard let index = bees.firstIndex(where: { $0.id == beeId }) else { return }
        update(&bees[index].config)
        config.bees[beeId] = bees[index].config
        saveConfig()
    }

    func updateGlobalConfig(_ update: (inout HiveConfig) -> Void) {
        update(&config)
        saveConfig()
    }

    private func syncConfigWithBees() {
        var needsSave = false
        for bee in bees where config.bees[bee.id] == nil {
            config.bees[bee.id] = BeeConfig()
            needsSave = true
        }
        if needsSave {
            saveConfig()
        }
    }

    private func parseBee(at url: URL) -> Bee? {
        let skillFile = url.appendingPathComponent("SKILL.md")

        guard let content = try? String(contentsOf: skillFile, encoding: .utf8) else {
            return nil
        }

        let frontmatter = parseFrontmatter(content)
        let folderName = url.lastPathComponent
        let beeConfig = config.bees[folderName] ?? BeeConfig()

        // Display name: prefer metadata.display-name, fall back to folder name
        let displayName = frontmatter["metadata.display-name"] ?? folderName
        // Icon: prefer metadata.icon, fall back to "ant"
        let icon = frontmatter["metadata.icon"] ?? "ant"

        return Bee(
            id: folderName,
            displayName: displayName,
            icon: icon,
            description: frontmatter["description"] ?? "",
            path: url,
            allowedTools: parseAllowedTools(frontmatter["allowed-tools"]),
            config: beeConfig
        )
    }

    private func parseFrontmatter(_ content: String) -> [String: String] {
        var result: [String: String] = [:]

        // Check for YAML frontmatter (starts with ---)
        guard content.hasPrefix("---") else { return result }

        let lines = content.components(separatedBy: .newlines)
        var inFrontmatter = false
        var frontmatterLines: [String] = []

        for line in lines {
            if line == "---" {
                if inFrontmatter {
                    break // End of frontmatter
                } else {
                    inFrontmatter = true
                    continue
                }
            }
            if inFrontmatter {
                frontmatterLines.append(line)
            }
        }

        // Parse with support for one level of nesting (e.g., metadata.display-name) and YAML lists
        var currentParent: String?
        var listItems: [String] = []

        for line in frontmatterLines {
            let indent = line.prefix(while: { $0 == " " }).count
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Handle YAML list items (- item)
            if indent == 2, let parent = currentParent, trimmed.hasPrefix("- ") {
                let item = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                listItems.append(item)
                continue
            }

            // Flush any accumulated list items when we leave the list
            if !listItems.isEmpty, let parent = currentParent {
                result[parent] = listItems.joined(separator: " ")
                listItems = []
            }

            let parts = trimmed.split(separator: ":", maxSplits: 1)
            guard parts.count >= 1 else { continue }

            let key = String(parts[0]).trimmingCharacters(in: .whitespaces)

            if indent == 0 {
                if parts.count == 2 {
                    let value = String(parts[1]).trimmingCharacters(in: .whitespaces)
                    result[key] = value
                    currentParent = nil
                } else {
                    // Parent key with no value (e.g., "metadata:" or "allowed-tools:")
                    currentParent = key
                }
            } else if indent == 2, let parent = currentParent {
                // Nested key-value pair
                if parts.count == 2 {
                    let value = String(parts[1]).trimmingCharacters(in: .whitespaces)
                    result["\(parent).\(key)"] = value
                }
            }
        }

        // Flush any remaining list items at end of frontmatter
        if !listItems.isEmpty, let parent = currentParent {
            result[parent] = listItems.joined(separator: " ")
        }

        return result
    }

    private func parseAllowedTools(_ value: String?) -> [String] {
        guard let value else { return [] }
        return value.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
    }

    // MARK: - Config Load/Save

    private func loadConfig() -> HiveConfig {
        guard let content = try? String(contentsOf: configPath, encoding: .utf8) else {
            return HiveConfig()
        }
        return parseHiveYaml(content)
    }

    private func saveConfig() {
        let yaml = generateHiveYaml()
        try? yaml.write(to: configPath, atomically: true, encoding: .utf8)
    }

    private func parseHiveYaml(_ content: String) -> HiveConfig {
        var config = HiveConfig()
        var currentBeeId: String?
        var inBees = false

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            let indent = line.prefix(while: { $0 == " " }).count

            switch indent {
            case 0:
                currentBeeId = nil
                parseRootLevel(trimmed, config: &config, inBees: &inBees)
            case 2:
                parseIndent2(trimmed, config: &config, inBees: inBees, currentBeeId: &currentBeeId)
            case 4:
                if let beeId = currentBeeId {
                    parseBeeConfig(trimmed, config: &config, beeId: beeId)
                }
            default:
                break
            }
        }

        return config
    }

    private func parseRootLevel(_ line: String, config: inout HiveConfig, inBees: inout Bool) {
        if line.hasPrefix("version:") {
            config.version = Int(parseValue(line)) ?? 1
        } else if line == "defaults:" {
            inBees = false
        } else if line == "bees:" {
            inBees = true
        }
    }

    private func parseIndent2(_ line: String, config: inout HiveConfig, inBees: Bool, currentBeeId: inout String?) {
        if inBees, line.hasSuffix(":") {
            let beeId = String(line.dropLast())
            currentBeeId = beeId
            config.bees[beeId] = BeeConfig()
        } else if !inBees {
            parseDefaults(line, config: &config)
        }
    }

    private func parseDefaults(_ line: String, config: inout HiveConfig) {
        if line.hasPrefix("cli:") {
            config.defaultCLI = parseValue(line)
        } else if line.hasPrefix("model:") {
            config.defaultModel = parseValue(line)
        } else if line.hasPrefix("overlap:") {
            config.defaultOverlap = parseValue(line)
        }
    }

    private func parseBeeConfig(_ line: String, config: inout HiveConfig, beeId: String) {
        var beeConfig = config.bees[beeId] ?? BeeConfig()

        if line.hasPrefix("enabled:") {
            beeConfig.enabled = parseValue(line) == "true"
        } else if line.hasPrefix("schedule:") {
            beeConfig.schedule = parseValue(line).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        } else if line.hasPrefix("cli:") {
            beeConfig.cli = parseValue(line)
        } else if line.hasPrefix("model:") {
            beeConfig.model = parseValue(line)
        } else if line.hasPrefix("overlap:") {
            beeConfig.overlap = parseValue(line)
        }

        config.bees[beeId] = beeConfig
    }

    private func parseValue(_ line: String) -> String {
        guard let colonIndex = line.firstIndex(of: ":") else { return "" }
        return String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
    }

    private func generateHiveYaml() -> String {
        var lines: [String] = []
        lines.append("version: \(config.version)")
        lines.append("")
        lines.append("defaults:")
        lines.append("  cli: \(config.defaultCLI)")
        if let model = config.defaultModel {
            lines.append("  model: \(model)")
        }
        lines.append("  overlap: \(config.defaultOverlap)")
        lines.append("")
        lines.append("bees:")

        for (beeId, beeConfig) in config.bees.sorted(by: { $0.key < $1.key }) {
            lines.append("  \(beeId):")
            lines.append("    enabled: \(beeConfig.enabled)")
            lines.append("    schedule: \"\(beeConfig.schedule)\"")
            if let cli = beeConfig.cli {
                lines.append("    cli: \(cli)")
            }
            if let model = beeConfig.model {
                lines.append("    model: \(model)")
            }
            if let overlap = beeConfig.overlap {
                lines.append("    overlap: \(overlap)")
            }
        }

        return lines.joined(separator: "\n") + "\n"
    }
}
