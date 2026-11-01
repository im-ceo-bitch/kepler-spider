import Foundation

public enum TerminalHostError: LocalizedError, Sendable {
    case actionUnavailable(String)
    case reviewUnavailable(String)
    case unauthorized
    case invalidParameter(String)

    public var errorDescription: String? {
        switch self {
        case .actionUnavailable(let id): return "Action not connected: \(id)"
        case .reviewUnavailable(let id): return "Review not connected: \(id)"
        case .unauthorized: return "Access denied"
        case .invalidParameter(let key): return "Invalid parameter: \(key)"
        }
    }
}

/// Registers existing application services without coupling TerminalKit to app internals.
/// Unregistered actions fail closed; the registry does not simulate successful actions.
@MainActor
public final class TerminalActionRegistryHost: TerminalActionHost {
    public typealias Action = @MainActor (TerminalActionRequest) async throws -> TerminalActionResult
    public typealias Review = @MainActor (TerminalActionRequest) async throws -> TerminalActionPreview

    private let knownIDs: Set<String>
    private var actions: [String: Action] = [:]
    private var reviews: [String: Review] = [:]

    /// Actions actually connected to this host, never merely listed in a dictionary.
    public var availableCommandIDs: Set<String> { Set(actions.keys) }

    public init() throws {
        knownIDs = Set(try TerminalEngine().catalog(language: .en).map(\.id))
    }

    /// Register an existing service callback. Sensitive actions MUST also register
    /// a review callback supplying verified details from the host backend.
    public func register(_ commandID: String, execute: @escaping Action,
                         review: Review? = nil) throws {
        guard knownIDs.contains(commandID) else {
            throw TerminalHostError.actionUnavailable(commandID)
        }
        actions[commandID] = execute
        if let review { reviews[commandID] = review }
    }

    public func preview(_ request: TerminalActionRequest) async throws -> TerminalActionPreview {
        guard let review = reviews[request.commandID], actions[request.commandID] != nil else {
            throw TerminalHostError.reviewUnavailable(request.commandID)
        }
        return try await review(request)
    }

    public func execute(_ request: TerminalActionRequest) async throws -> TerminalActionResult {
        guard let action = actions[request.commandID] else {
            throw TerminalHostError.actionUnavailable(request.commandID)
        }
        // Authentication and authorization remain mandatory in each registered service.
        return try await action(request)
    }
}
