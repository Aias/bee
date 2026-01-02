import Foundation

struct BeeRunResult {
    let success: Bool
    let output: String
    let error: String?
    let duration: TimeInterval
}

/// Structured output from bee execution
struct BeeOutput: Codable {
    enum Status: String, Codable {
        case needsConfirmation = "needs_confirmation"
        case completed = "completed"
        case error = "error"
    }

    let status: Status
    let confirmMessage: String?
    let result: String?
    let error: String?
}

/// Wrapper for Claude CLI JSON output format
struct CLIOutputWrapper: Codable {
    let type: String
    let result: String?
    let structuredOutput: BeeOutput?
    let isError: Bool?

    enum CodingKeys: String, CodingKey {
        case type
        case result
        case structuredOutput = "structured_output"
        case isError = "is_error"
    }
}

/// JSON schema for structured bee output
private let beeOutputSchema = """
{
  "type": "object",
  "properties": {
    "status": {
      "type": "string",
      "enum": ["needs_confirmation", "completed", "error"],
      "description": "Current status: needs_confirmation if awaiting user approval, completed if task finished, error if something went wrong"
    },
    "confirmMessage": {
      "type": "string",
      "description": "Message to show user when requesting confirmation (required when status is needs_confirmation)"
    },
    "result": {
      "type": "string",
      "description": "Summary of what was accomplished (required when status is completed)"
    },
    "error": {
      "type": "string",
      "description": "Error description (required when status is error)"
    }
  },
  "required": ["status"],
  "additionalProperties": false
}
"""

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
                await logRun(bee: bee, cli: cli, model: model, output: result.output, error: result.error, duration: duration)

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


## Output Format

Your response will be parsed as JSON. You MUST return a valid JSON object with this structure:

- If you need user confirmation before a critical action:
  {"status": "needs_confirmation", "confirmMessage": "Explain what you want to do and why"}

- If you completed the task successfully:
  {"status": "completed", "result": "Summary of what was accomplished"}

- If an error occurred:
  {"status": "error", "error": "Description of what went wrong"}

IMPORTANT: Only request confirmation for actions that modify files, send data, or have side effects.
Do not request confirmation for read-only operations.
"""

        arguments.append("--system-prompt")
        arguments.append(enhancedSkill)

        // Use structured output for reliable parsing
        arguments.append("--output-format")
        arguments.append("json")
        arguments.append("--json-schema")
        arguments.append(beeOutputSchema)

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

        // Parse CLI JSON wrapper, then extract structured_output
        guard let jsonData = result.output.data(using: .utf8),
              let cliOutput = try? JSONDecoder().decode(CLIOutputWrapper.self, from: jsonData),
              let beeOutput = cliOutput.structuredOutput else {
            // Failed to parse - return raw output as error
            return (result.output, "Failed to parse structured output", false)
        }

        switch beeOutput.status {
        case .needsConfirmation:
            let confirmMessage = beeOutput.confirmMessage ?? "Confirmation requested"
            print("🐝 \(bee.displayName) requesting confirmation: \(confirmMessage)")

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
                    model: model,
                    sessionId: sessionId,
                    skill: enhancedSkill,
                    allowedTools: allowedTools,
                    workingDirectory: workingDirectory,
                    previousOutput: confirmMessage
                )
            } else {
                return (confirmMessage, "User rejected confirmation", false)
            }

        case .completed:
            let output = beeOutput.result ?? "Task completed"
            return (output, nil, true)

        case .error:
            let errorMsg = beeOutput.error ?? "Unknown error"
            return (result.output, errorMsg, false)
        }
    }

    /// Resume an existing session after user confirmation
    private static func resumeSession(
        bee: Bee,
        cli: String,
        model: String?,
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

        // Model must be passed on resume to maintain consistency
        if let model {
            arguments.append("--model")
            arguments.append(model)
        }

        // Must include allowedTools on resume too
        if !allowedTools.isEmpty {
            arguments.append("--allowedTools")
            arguments.append(allowedTools.joined(separator: ","))
        }

        // System prompt is NOT preserved on resume - must pass it again
        arguments.append("--system-prompt")
        arguments.append(skill)

        // Use structured output for reliable parsing
        arguments.append("--output-format")
        arguments.append("json")
        arguments.append("--json-schema")
        arguments.append(beeOutputSchema)

        // Use -- to separate options from the prompt
        arguments.append("--")
        arguments.append("The user has CONFIRMED. Proceed with the action now.")

        let cliPath = try await findCLI(cli)
        let result = try await runProcess(cliPath, arguments: arguments, workingDirectory: workingDirectory)

        // Parse CLI JSON wrapper, then extract structured_output
        guard let jsonData = result.output.data(using: .utf8),
              let cliOutput = try? JSONDecoder().decode(CLIOutputWrapper.self, from: jsonData),
              let beeOutput = cliOutput.structuredOutput else {
            let combinedOutput = previousOutput + "\n\n--- After Confirmation ---\n\n" + result.output
            return (combinedOutput, "Failed to parse structured output", false)
        }

        switch beeOutput.status {
        case .completed:
            let output = beeOutput.result ?? "Task completed"
            let combinedOutput = previousOutput + "\n\n--- After Confirmation ---\n\n" + output
            return (combinedOutput, nil, true)

        case .error:
            let errorMsg = beeOutput.error ?? "Unknown error"
            let combinedOutput = previousOutput + "\n\n--- After Confirmation ---\n\n" + errorMsg
            return (combinedOutput, errorMsg, false)

        case .needsConfirmation:
            // Shouldn't happen after confirmation, but handle gracefully
            let confirmMessage = beeOutput.confirmMessage ?? "Confirmation requested"
            let errorMsg = "Unexpected confirmation request after user confirmed: \(confirmMessage)"
            let combinedOutput = previousOutput + "\n\n--- After Confirmation ---\n\n" + errorMsg
            return (combinedOutput, errorMsg, false)
        }
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

            // Read output asynchronously to avoid deadlock when output exceeds pipe buffer
            var outputData = Data()
            var errorData = Data()
            let outputLock = NSLock()
            let errorLock = NSLock()

            outputPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty {
                    outputLock.lock()
                    outputData.append(data)
                    outputLock.unlock()
                }
            }

            errorPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty {
                    errorLock.lock()
                    errorData.append(data)
                    errorLock.unlock()
                }
            }

            do {
                try process.run()
                process.waitUntilExit()

                // Clean up handlers
                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil

                // Read any remaining data
                outputLock.lock()
                outputData.append(outputPipe.fileHandleForReading.readDataToEndOfFile())
                outputLock.unlock()

                errorLock.lock()
                errorData.append(errorPipe.fileHandleForReading.readDataToEndOfFile())
                errorLock.unlock()

                let output = String(data: outputData, encoding: .utf8) ?? ""
                let error = String(data: errorData, encoding: .utf8)

                continuation.resume(returning: (output, error, process.terminationStatus))
            } catch {
                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }

    private static func logRun(bee: Bee, cli: String, model: String?, output: String, error: String?, duration: TimeInterval) async {
        let logsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".bee/logs")
            .appendingPathComponent(bee.id)

        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HHmmss"
        formatter.timeZone = TimeZone.current
        let timestamp = formatter.string(from: Date())

        let logFile = logsDir.appendingPathComponent("\(timestamp).log")

        var logContent = """
        # Bee Run: \(bee.displayName)
        # Timestamp: \(timestamp)
        # Duration: \(String(format: "%.2f", duration))s
        # CLI: \(cli)
        # Model: \(model ?? "default")

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