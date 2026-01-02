import Foundation

struct BeeRunResult {
    let success: Bool
    let output: String
    let error: String?
    let duration: TimeInterval
}

enum BeeRunner {
    static func run(_ bee: Bee, cli: String, model: String?, completion: @escaping (BeeRunResult) -> Void) {
        let startTime = Date()

        Task {
            do {
                // 1. Gather context from scripts
                let context = await gatherContext(bee)

                // 2. Read SKILL.md
                let skillContent = try String(contentsOf: bee.skillPath, encoding: .utf8)

                // 3. Build CLI command
                let result = try await executeCLI(
                    cli: cli,
                    model: model,
                    skill: skillContent,
                    context: context,
                    allowedTools: bee.allowedTools,
                    workingDirectory: bee.path
                )

                let duration = Date().timeIntervalSince(startTime)

                // 4. Log output
                await logRun(bee: bee, output: result.output, error: result.error, duration: duration)

                await MainActor.run {
                    completion(BeeRunResult(
                        success: result.exitCode == 0,
                        output: result.output,
                        error: result.error,
                        duration: duration
                    ))
                }
            } catch {
                let duration = Date().timeIntervalSince(startTime)
                await MainActor.run {
                    completion(BeeRunResult(
                        success: false,
                        output: "",
                        error: error.localizedDescription,
                        duration: duration
                    ))
                }
            }
        }
    }

    private static func gatherContext(_ bee: Bee) async -> String {
        let scriptsDir = bee.scriptsPath
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: scriptsDir.path) else {
            return ""
        }

        guard let scripts = try? fileManager.contentsOfDirectory(
            at: scriptsDir,
            includingPropertiesForKeys: [.isExecutableKey],
            options: [.skipsHiddenFiles]
        ) else {
            return ""
        }

        var contextParts: [String] = []

        for script in scripts.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            // Check if executable
            guard let resourceValues = try? script.resourceValues(forKeys: [.isExecutableKey]),
                  resourceValues.isExecutable == true else {
                continue
            }

            do {
                let result = try await runProcess(script.path, arguments: [], workingDirectory: bee.path)
                if !result.output.isEmpty {
                    contextParts.append("# Context from \(script.lastPathComponent)\n\(result.output)")
                }
            } catch {
                contextParts.append("# Error running \(script.lastPathComponent): \(error.localizedDescription)")
            }
        }

        return contextParts.joined(separator: "\n\n")
    }

    private static func executeCLI(
        cli: String,
        model: String?,
        skill: String,
        context: String,
        allowedTools: [String],
        workingDirectory: URL
    ) async throws -> (output: String, error: String?, exitCode: Int32) {
        var arguments: [String] = ["--print"]

        // Add model if specified
        if let model {
            arguments.append("--model")
            arguments.append(model)
        }

        // Add allowed tools if specified
        if !allowedTools.isEmpty {
            arguments.append("--allowedTools")
            arguments.append(allowedTools.joined(separator: ","))
        }

        // Use system prompt for skill instructions
        arguments.append("--system-prompt")
        arguments.append(skill)

        // End of options marker
        arguments.append("--")

        // Build the user prompt from gathered context
        let prompt: String
        if context.isEmpty {
            prompt = "Run your scheduled task now."
        } else {
            prompt = "Run your scheduled task with this context:\n\n\(context)"
        }
        arguments.append(prompt)

        let cliPath = try await findCLI(cli)
        return try await runProcess(cliPath, arguments: arguments, workingDirectory: workingDirectory)
    }

    private static func findCLI(_ cli: String) async throws -> String {
        // Check common locations
        let searchPaths = [
            "/usr/local/bin/\(cli)",
            "/opt/homebrew/bin/\(cli)",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin/\(cli)",
            "/usr/bin/\(cli)"
        ]

        for path in searchPaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        // Try using `which`
        let result = try await runProcess("/usr/bin/which", arguments: [cli], workingDirectory: nil)
        let path = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        if !path.isEmpty && FileManager.default.fileExists(atPath: path) {
            return path
        }

        throw NSError(domain: "BeeRunner", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "CLI '\(cli)' not found"
        ])
    }

    private static func runProcess(
        _ path: String,
        arguments: [String],
        workingDirectory: URL?
    ) async throws -> (output: String, error: String?, exitCode: Int32) {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments

            if let workingDirectory {
                process.currentDirectoryURL = workingDirectory
            }

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            do {
                try process.run()
                process.waitUntilExit()

                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

                let output = String(data: outputData, encoding: .utf8) ?? ""
                let error = String(data: errorData, encoding: .utf8)

                continuation.resume(returning: (output, error, process.terminationStatus))
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private static func logRun(bee: Bee, output: String, error: String?, duration: TimeInterval) async {
        let logsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".bee/logs")
            .appendingPathComponent(bee.id)

        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        let timestamp = formatter.string(from: Date())

        let logFile = logsDir.appendingPathComponent("\(timestamp).log")

        var logContent = """
        # Bee Run: \(bee.displayName)
        # Timestamp: \(timestamp)
        # Duration: \(String(format: "%.2f", duration))s

        ## Output

        \(output)
        """

        if let error, !error.isEmpty {
            logContent += """

            ## Errors

            \(error)
            """
        }

        try? logContent.write(to: logFile, atomically: true, encoding: .utf8)
    }
}
