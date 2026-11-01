import XCTest
@testable import SpyderTerminalKit

@MainActor
private final class RecordingHost: TerminalActionHost {
    var previews: [TerminalActionRequest] = []
    var executions: [TerminalActionRequest] = []
    var previewValue = TerminalActionPreview(title: "Review transfer", details: ["25 SPD", "Recipient @ali"])
    var result = TerminalActionResult(message: "OK")

    func preview(_ request: TerminalActionRequest) async throws -> TerminalActionPreview {
        previews.append(request)
        return previewValue
    }
    func execute(_ request: TerminalActionRequest) async throws -> TerminalActionResult {
        executions.append(request)
        return result
    }
}

final class TerminalActionBridgeTests: XCTestCase {
    private let parser = try! TerminalEngine()

    func testReadAndWriteCommandsCallHostDirectly() async {
        let host = await RecordingHost()
        let gate = await TerminalExecutionGate(host: host)
        let match = match("sp change chat theme to Cyberpunk")
        let result = await gate.submit(match, context: .init(conversationID: "conversation-1"))
        guard case .completed(let response) = result else { return XCTFail("Expected completion") }
        XCTAssertEqual(response.message, "OK")
        let executed = await host.executions
        let previews = await host.previews
        XCTAssertEqual(executed.count, 1)
        XCTAssertTrue(previews.isEmpty)
        XCTAssertEqual(executed.first?.commandID, "chat.theme.set")
        XCTAssertEqual(executed.first?.parameters["theme"], "cyberpunk")
        XCTAssertEqual(executed.first?.context.conversationID, "conversation-1")
    }

    func testSensitiveActionNeverExecutesWithoutConfirmation() async {
        let host = await RecordingHost()
        let gate = await TerminalExecutionGate(host: host)
        let match = match("sp wallet send 25 SPD to @ali")
        let result = await gate.submit(match, context: .init(accountID: "account-1"))
        guard case .confirmationRequired(let pending) = result else {
            return XCTFail("Sensitive actions must require approval")
        }
        let before = await host.executions
        XCTAssertEqual(before.count, 0)
        let previewCount = await host.previews.count
        XCTAssertEqual(previewCount, 1)
        XCTAssertEqual(pending.preview.details.count, 2)
        let response = await gate.approve(pending.id)
        guard case .completed = response else { return XCTFail("Approval failed") }
        let executedCount = await host.executions.count
        XCTAssertEqual(executedCount, 1)
        let replay = await gate.approve(pending.id)
        guard case .rejected = replay else { return XCTFail("Approval replay must fail") }
        let replayCount = await host.executions.count
        XCTAssertEqual(replayCount, 1)
    }

    func testCancellationForbidsExecution() async {
        let host = await RecordingHost()
        let gate = await TerminalExecutionGate(host: host)
        let result = await gate.submit(match("сп отправь всем Здравствуйте!"), context: .init())
        guard case .confirmationRequired(let pending) = result else { return XCTFail("Missing approval") }
        await gate.cancelApproval()
        let rejected = await gate.approve(pending.id)
        guard case .rejected = rejected else { return XCTFail("Cancelled approval executed") }
        let executionCount = await host.executions.count
        XCTAssertEqual(executionCount, 0)
    }

    func testCannotApproveWithoutHostReviewDetails() async {
        let host = await RecordingHost()
        await MainActor.run { host.previewValue = .init(title: "", details: []) }
        let gate = await TerminalExecutionGate(host: host)
        let result = await gate.submit(match("sp wallet send 25 SPD to @ali"), context: .init())
        guard case .rejected = result else { return XCTFail("Expected rejection") }
        let executionCount = await host.executions.count
        XCTAssertEqual(executionCount, 0)
    }

    func testUnknownUnfilledIntentCannotExecute() async {
        let host = await RecordingHost()
        let gate = await TerminalExecutionGate(host: host)
        let incomplete = parser.validatedIntent(actionID: "wallet.send", parameters: ["amount": "25"])
        XCTAssertNotNil(incomplete)
        let result = await gate.submit(incomplete!, context: .init())
        guard case .needsInput(let keys) = result else { return XCTFail("Expected incomplete input") }
        XCTAssertTrue(keys.contains("recipient"))
        XCTAssertTrue(keys.contains("asset"))
        let executionCount = await host.executions.count
        XCTAssertEqual(executionCount, 0)
        let previewCount = await host.previews.count
        XCTAssertEqual(previewCount, 0)
    }

    private func match(_ command: String) -> TerminalMatch {
        switch parser.interpret(command, settings: .init(level: .standard)) {
        case .matched(let value): return value
        default: XCTFail("Unrecognized command"); fatalError("Unrecognized command")
        }
    }
}

final class TerminalRegistryTests: XCTestCase {
    func testUnregisteredCommandsFailClosed() async throws {
        let host = try await TerminalActionRegistryHost()
        let gate = await TerminalExecutionGate(host: host)
        let engine = try TerminalEngine()
        let interpreted = engine.interpret("сп измени фон", settings: .init(level: .standard))
        guard case .matched(let match) = interpreted else { return XCTFail("Missing match") }
        let outcome = await gate.submit(match, context: .init())
        guard case .rejected(let reason) = outcome else { return XCTFail("Expected fail-closed") }
        XCTAssertTrue(reason.contains("not connected"))
    }

    func testRegisteredCommandsInvokeRealBoundCallback() async throws {
        let host = try await TerminalActionRegistryHost()
        try await host.register("chat.theme.set") { req in
            guard req.parameters["theme"] == "cyberpunk" else {
                throw TerminalHostError.invalidParameter("theme")
            }
            return TerminalActionResult(message: "Theme changed")
        }
        let gate = await TerminalExecutionGate(host: host)
        let engine = try TerminalEngine()
        let interpreted = engine.interpret("sp change chat theme to cyberpunk", settings: .init(level: .standard))
        guard case .matched(let match) = interpreted else { return XCTFail("Missing match") }
        let outcome = await gate.submit(match, context: .init())
        guard case .completed(let reply) = outcome else { return XCTFail("Expected callback") }
        XCTAssertEqual(reply.message, "Theme changed")
    }
}
