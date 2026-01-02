import Foundation

struct BeeRunResult {
    let success: Bool
    let output: String
    let error: String?
    let duration: TimeInterval
}

/// Marker the bee outputs when it wants confirmation
/// Format: <!-- BEE:CONFIRM -->message here
private let confirmMarker = "<!-- BEE:CONFIRM -->"

enum BeeRunner {
    static func run(_ bee: Bee, cli: String, model: String?, completion: @escaping (BeeRunResult) -> Void) {
        let startTime = Date()
        let sessionId = UUID().uuidString

        Task {
            do {
                // 1. Gather context from scripts
                let context = await gatherContext(bee)

                // 2. Read SKILL.md
                let skillContent = try String(contentsOf: bee.skillPath, encoding: .utf8)

                // 3. Build and run CLI with session
                let result = try await executeCLIWithSession(
                    bee: bee,
                    cli: cli,
                    model: model,
                    skill: skillContent,
                    context: context,
                    allowedTools: bee.allowedTools,
                    workingDirectory: bee.path,
                    sessionId: sessionId
                )

                let duration = Date().timeIntervalSince(startTime)

                // 4. Log output
                await logRun(bee: bee, output: result.output, error: result.error, duration: duration)

                await MainActor.run {
                    completion(BeeRunResult(
                        success: result.success,
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

    /// Execute CLI with session-based approach for confirmation flow
    private static func executeCLIWithSession(
        bee: Bee,
        cli: String,
        model: String?,
        skill: String,
        context: String,
        allowedTools: [String],
        workingDirectory: URL,
        sessionId: String
    ) async throws -> (output: String, error: String?, success: Bool) {
        // Build initial arguments (--session-id must come before -p)
        var arguments: [String] = ["--session-id", sessionId, "-p"]

        if let model {
            arguments.append("--model")
            arguments.append(model)
        }

        // Specify allowed tools
        if !allowedTools.isEmpty {
            arguments.append("--allowedTools")
            arguments.append(allowedTools.joined(separator: ","))
        }

        // Add confirmation protocol to skill
        let enhancedSkill = skill + """


## Confirmation Protocol

If you need user confirmation before completing a critical action, output exactly:
<!-- BEE:CONFIRM -->Your message explaining what you want to do

Then STOP and wait. Do not proceed with the action until confirmed.
The user will see a notification with your message and can Confirm or Reject.
If confirmed, you will receive a follow-up message to proceed.
"""

        arguments.append("--system-prompt")
        arguments.append(enhancedSkill)
        arguments.append("--")

        // Build the user prompt
        let prompt: String
        if context.isEmpty {
            prompt = "Run your scheduled task now."
        } else {
            prompt = "Run your scheduled task with this context:\n\n\(context)"
        }
        arguments.append(prompt)

        let cliPath = try await findCLI(cli)
        let result = try await runProcess(cliPath, arguments: arguments, workingDirectory: workingDirectory)

        // Check if output contains confirmation request
        if let confirmRange = result.output.range(of: confirmMarker) {
            let message = String(result.output[confirmRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            let confirmMessage = message.components(separatedBy: "\n").first ?? message

            print("🐝 \(bee.displayName) requesting confirmation: \(confirmMessage)")

            // Request confirmation from user
            let confirmed = await ConfirmServer.requestConfirmation(
                beeId: bee.id,
                beeName: bee.displayName,
                message: confirmMessage,
                timeout: Double(bee.config.timeout ?? 300)
            )

            if confirmed {
                print("🐝 \(bee.displayName) confirmed, resuming session...")
                return try await resumeSession(
                    bee: bee,
                    cli: cli,
                    sessionId: sessionId,
                    skill: enhancedSkill,
                    allowedTools: allowedTools,
                    workingDirectory: workingDirectory,
                    previousOutput: result.output
                )
            } else {
                return (result.output, "User rejected confirmation", false)
            }
        }

        return (result.output, result.error, result.exitCode == 0)
    }

    /// Resume an existing session after user confirmation
    private static func resumeSession(
        bee: Bee,
        cli: String,
        sessionId: String,
        skill: String,
        allowedTools: [String],
        workingDirectory: URL,
        previousOutput: String
    ) async throws -> (output: String, error: String?, success: Bool) {
        // Resume the session with confirmation message
        var arguments: [String] = [
            "-r", sessionId,
            "-p"
        ]

        // Must include allowedTools on resume too
        if !allowedTools.isEmpty {
            arguments.append("--allowedTools")
            arguments.append(allowedTools.joined(separator: ","))
        }

        // System prompt is NOT preserved on resume - must pass it again
        arguments.append("--system-prompt")
        arguments.append(skill)

        // Use -- to separate options from the prompt
        arguments.append("--")
        arguments.append("The user has CONFIRMED. Proceed with the action now.")

        let cliPath = try await findCLI(cli)
        let result = try await runProcess(cliPath, arguments: arguments, workingDirectory: workingDirectory)

        // Combine outputs for logging
        let combinedOutput = previousOutput + "\n\n--- After Confirmation ---\n\n" + result.output

        return (combinedOutput, result.error, result.exitCode == 0)
    }

    private static func findCLI(_ cli: String) async throws -> String {
        // Prefer ~/.local/bin first (user-installed, typically newer)
        let searchPaths = [
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin/\(cli)",
            "/usr/local/bin/\(cli)",
            "/opt/homebrew/bin/\(cli)",
            "/usr/bin/\(cli)"
        ]

        for path in searchPaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

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
