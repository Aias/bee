import Foundation
import SwiftUI

struct Bee: Identifiable {
    let id: String  // folder name (matches SKILL.md name field per spec)
    let displayName: String  // from metadata.display-name, falls back to id
    let icon: String  // SF Symbol name from metadata.icon, falls back to "ant"
    let description: String
    let path: URL
    let allowedTools: [String]
    var config: BeeConfig

    var skillPath: URL { path.appendingPathComponent("SKILL.md") }
    var scriptsPath: URL { path.appendingPathComponent("scripts") }
}

struct BeeConfig: Equatable {
    var enabled: Bool = true
    var schedule: String = "*/5 * * * *"  // Default: every 5 minutes
    var cli: String?  // nil = use global default
    var overlap: String?  // nil = use global default
}

struct HiveConfig {
    var version: Int = 1
    var defaultCLI: String = "claude"
    var defaultOverlap: String = "skip"
    var bees: [String: BeeConfig] = [:]
}

@Observable
final class HiveManager {
    private(set) var bees: [Bee] = []
    private(set) var config: HiveConfig = HiveConfig()
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

    private func syncConfigWithBees() {
        var needsSave = false
        for bee in bees {
            if config.bees[bee.id] == nil {
                config.bees[bee.id] = BeeConfig()
                needsSave = true
            }
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
                    break  // End of frontmatter
                } else {
                    inFrontmatter = true
                    continue
                }
            }
            if inFrontmatter {
                frontmatterLines.append(line)
            }
        }

        // Parse with support for one level of nesting (e.g., metadata.display-name)
        var currentParent: String?
        for line in frontmatterLines {
            let indent = line.prefix(while: { $0 == " " }).count
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            let parts = trimmed.split(separator: ":", maxSplits: 1)
            guard parts.count >= 1 else { continue }

            let key = String(parts[0]).trimmingCharacters(in: .whitespaces)

            if indent == 0 {
                if parts.count == 2 {
                    let value = String(parts[1]).trimmingCharacters(in: .whitespaces)
                    result[key] = value
                    currentParent = nil
                } else {
                    // Parent key with no value (e.g., "metadata:")
                    currentParent = key
                }
            } else if indent == 2, let parent = currentParent {
                // Nested key
                if parts.count == 2 {
                    let value = String(parts[1]).trimmingCharacters(in: .whitespaces)
                    result["\(parent).\(key)"] = value
                }
            }
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

            if indent == 0 {
                if trimmed.hasPrefix("version:") {
                    config.version = Int(parseValue(trimmed)) ?? 1
                } else if trimmed == "defaults:" {
                    inBees = false
                } else if trimmed == "bees:" {
                    inBees = true
                }
                currentBeeId = nil
            } else if indent == 2 {
                if inBees && trimmed.hasSuffix(":") {
                    currentBeeId = String(trimmed.dropLast())
                    config.bees[currentBeeId!] = BeeConfig()
                } else if !inBees {
                    if trimmed.hasPrefix("cli:") {
                        config.defaultCLI = parseValue(trimmed)
                    } else if trimmed.hasPrefix("overlap:") {
                        config.defaultOverlap = parseValue(trimmed)
                    }
                }
            } else if indent == 4, let beeId = currentBeeId {
                var beeConfig = config.bees[beeId] ?? BeeConfig()
                if trimmed.hasPrefix("enabled:") {
                    beeConfig.enabled = parseValue(trimmed) == "true"
                } else if trimmed.hasPrefix("schedule:") {
                    beeConfig.schedule = parseValue(trimmed).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                } else if trimmed.hasPrefix("cli:") {
                    beeConfig.cli = parseValue(trimmed)
                } else if trimmed.hasPrefix("overlap:") {
                    beeConfig.overlap = parseValue(trimmed)
                }
                config.bees[beeId] = beeConfig
            }
        }

        return config
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
            if let overlap = beeConfig.overlap {
                lines.append("    overlap: \(overlap)")
            }
        }

        return lines.joined(separator: "\n") + "\n"
    }
}
