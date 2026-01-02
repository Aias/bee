import Foundation

/// Handles the Confirm tool flow using file-based IPC
/// When a bee calls the Confirm tool, we:
/// 1. Write request to a temp file
/// 2. Show notification (via NotificationManager)
/// 3. Wait for user response
/// 4. Return result to the bee process
enum ConfirmServer {

    struct ConfirmRequest: Codable {
        let id: String
        let beeId: String
        let beeName: String
        let message: String
        let timestamp: Date
    }

    struct ConfirmResponse: Codable {
        let id: String
        let confirmed: Bool
        let timestamp: Date
    }

    private static var pendingRequests: [String: (
        request: ConfirmRequest,
        continuation: CheckedContinuation<Bool, Never>,
        timeoutWork: DispatchWorkItem
    )] = [:]
    private static let queue = DispatchQueue(label: "com.bee.confirm-server")

    /// Request confirmation from the user
    /// Returns true if confirmed, false if rejected/timeout
    static func requestConfirmation(
        beeId: String,
        beeName: String,
        message: String,
        timeout: TimeInterval = 300
    ) async -> Bool {
        let requestId = UUID().uuidString

        let request = ConfirmRequest(
            id: requestId,
            beeId: beeId,
            beeName: beeName,
            message: message,
            timestamp: Date()
        )

        // Show notification with actions
        return await withCheckedContinuation { continuation in
            // Create cancellable timeout work item
            let timeoutWork = DispatchWorkItem {
                Self.handleResponse(requestId: requestId, confirmed: false, reason: "timeout")
            }

            queue.sync {
                pendingRequests[requestId] = (request, continuation, timeoutWork)
            }

            // Show actionable notification
            NotificationManager.showConfirmation(
                id: requestId,
                beeId: beeId,
                beeName: beeName,
                message: message
            )

            // Schedule timeout (can be cancelled if user responds first)
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: timeoutWork)
        }
    }

    /// Handle user response from notification
    static func handleResponse(requestId: String, confirmed: Bool, reason: String? = nil) {
        queue.sync {
            guard let pending = pendingRequests.removeValue(forKey: requestId) else {
                return
            }

            // Cancel the timeout if it hasn't fired yet
            pending.timeoutWork.cancel()

            if let reason {
                print("🐝 Confirm \(pending.request.beeName): \(reason)")
            }

            pending.continuation.resume(returning: confirmed)
        }
    }

    /// Get all pending confirmation requests
    static func getPendingRequests() -> [ConfirmRequest] {
        queue.sync {
            pendingRequests.values.map(\.request)
        }
    }

    /// Check if there are any pending confirmations
    static var hasPendingConfirmations: Bool {
        queue.sync {
            !pendingRequests.isEmpty
        }
    }
}
