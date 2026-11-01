import Foundation

/// Identifiers and context come from the host application's authenticated session.
/// Do not construct the current user / conversation identity from user-entered text.
public struct TerminalActionContext: Sendable, Equatable {
    public let conversationID: String?
    public let accountID: String?

    public init(conversationID: String? = nil, accountID: String? = nil) {
        self.conversationID = conversationID
        self.accountID = accountID
    }
}

public struct TerminalActionRequest: Sendable, Equatable {
    public let commandID: String
    public let parameters: [String: String]
    public let risk: TerminalRisk
    public let context: TerminalActionContext

    public init(match: TerminalMatch, context: TerminalActionContext) {
        commandID = match.commandID
        parameters = match.parameters
        risk = match.risk
        self.context = context
    }
}

/// Human-readable, host-verified review details, not values manufactured by a language model.
public struct TerminalActionPreview: Sendable, Equatable {
    public let title: String
    public let details: [String]
    public init(title: String, details: [String]) {
        self.title = title
        self.details = details
    }
}

public struct TerminalActionResult: Sendable, Equatable {
    public let message: String
    public init(message: String) { self.message = message }
}

/// The host connects its existing, permission-checked services to TerminalKit.
/// In execute(_:), check the authenticated account, conversation ownership, wallet
/// policy, anti-spam limits and (when applicable) cryptographic authorization again.
@MainActor
public protocol TerminalActionHost: AnyObject {
    func preview(_ request: TerminalActionRequest) async throws -> TerminalActionPreview
    func execute(_ request: TerminalActionRequest) async throws -> TerminalActionResult
}

public struct TerminalApproval: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let preview: TerminalActionPreview
    public let commandID: String
    public let expiresAt: Date
}

public enum TerminalDispatchOutcome: Sendable, Equatable {
    case completed(TerminalActionResult)
    case needsInput([String])
    case confirmationRequired(TerminalApproval)
    case rejected(String)
}

/// Explicit confirmation is mandatory for sensitive catalog actions.
/// Previewing never invokes the host's execute method. Approval is single use
/// and only valid for the exact prepared action for a short interval.
@MainActor
public final class TerminalExecutionGate {
    private struct Pending {
        let approval: TerminalApproval
        let request: TerminalActionRequest
    }

    private let host: any TerminalActionHost
    private var pending: Pending?
    private var generation = UUID()
    private var busy = false
    private let approvalLifetime: TimeInterval

    public init(host: any TerminalActionHost, approvalLifetime: TimeInterval = 90) {
        self.host = host
        self.approvalLifetime = max(5, min(approvalLifetime, 300))
    }

    public func submit(_ match: TerminalMatch, context: TerminalActionContext) async -> TerminalDispatchOutcome {
        guard !busy else { return .rejected("Command is already running") }
        pending = nil // Never reuse previous authorization on a new command.
        generation = UUID()
        let submissionGeneration = generation
        guard !match.needsInput else { return .needsInput(match.missingParameters) }
        let request = TerminalActionRequest(match: match, context: context)
        busy = true
        defer { busy = false }
        if match.risk == .sensitive {
            do {
                let preview = try await host.preview(request)
                guard generation == submissionGeneration, !Task.isCancelled else {
                    return .rejected("Action was cancelled")
                }
                // No approval without explicit, populated review data supplied by the host.
                guard !preview.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      !preview.details.isEmpty,
                      preview.details.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
                else { return .rejected("Action review is unavailable") }
                let approval = TerminalApproval(id: UUID(), preview: preview,
                    commandID: match.commandID, expiresAt: Date().addingTimeInterval(approvalLifetime))
                pending = Pending(approval: approval, request: request)
                return .confirmationRequired(approval)
            } catch { return .rejected(error.localizedDescription) }
        }
        do { return .completed(try await host.execute(request)) }
        catch { return .rejected(error.localizedDescription) }
    }

    public func approve(_ approvalID: UUID) async -> TerminalDispatchOutcome {
        guard !busy else { return .rejected("Command is already running") }
        guard let attempt = pending, attempt.approval.id == approvalID else {
            return .rejected("No matching approval")
        }
        pending = nil  // Consume before awaiting to prevent replay / double-send.
        guard attempt.approval.expiresAt > Date() else {
            return .rejected("Approval expired. Enter the command again.")
        }
        busy = true
        defer { busy = false }
        do { return .completed(try await host.execute(attempt.request)) }
        catch { return .rejected(error.localizedDescription) }
    }

    public func cancelApproval() {
        generation = UUID() // Invalidate an outstanding async preview too.
        pending = nil
    }
}
