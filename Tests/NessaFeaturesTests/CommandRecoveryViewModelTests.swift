import Foundation
import Testing

@testable import NessaFeatures

private func recoveryCommand(create: Bool = false) -> PreparedConversationCommand {
  let request = "00000000-0000-4000-8000-000000000021"
  let conversation = "00000000-0000-4000-8000-000000000022"
  if create {
    return .create(.init(requestID: request, conversationID: conversation, agent: nil, model: nil))
  }
  return .submit(
    .init(
      requestID: request, conversationID: conversation,
      executionID: "00000000-0000-4000-8000-000000000023", text: "> Parent\n\nReply",
      replyTo: "parent"))
}

/// Deliberately returns late successful results after reconnect, exercising presentation fencing.
private actor RecoveryRepository: MessagingRepository, CommandRecoveryProviding {
  private var credential = ""
  private var values: [String: [PreparedConversationCommand]] = [:]
  var pendingFailure = false
  var pendingCalls = 0
  var recoveryCalls = 0
  var sendCalls = 0
  private var holdPending = false
  private var pendingGate: CheckedContinuation<Void, Never>?
  private var gates: [Int: CheckedContinuation<Void, Never>] = [:]
  var wrongPayload = false
  var knownAcceptanceFailure = false
  func seed(_ command: PreparedConversationCommand, credential: String) {
    values[credential] = [command]
  }
  func failPending(_ value: Bool) { pendingFailure = value }
  func holdPendingLoad() { holdPending = true }
  func releasePending() {
    pendingGate?.resume()
    pendingGate = nil
  }
  func releaseRecovery(_ index: Int) { gates.removeValue(forKey: index)?.resume() }
  func returnWrongPayload() { wrongPayload = true }
  func failKnownAcceptance() { knownAcceptanceFailure = true }
  func connect(address: String, credential: String, instance: String) {
    self.credential = credential
  }
  func disconnect() {}
  func list() -> NessaConversationList { .init(conversations: [], complete: true) }
  func read(_ id: String) -> NessaConversationView {
    .init(
      conversationId: id, messages: [], permissions: [], truncated: false,
      interactionViewError: nil, runtime: nil)
  }
  func create(agent: String?, model: String?) -> String { UUID().uuidString.lowercased() }
  func create(_ intent: PreparedConversationCommand.Creation) -> String { intent.conversationID }
  func send(_ text: String, attachments: [DraftAttachment], conversationID: String) -> String {
    UUID().uuidString.lowercased()
  }
  func send(
    _ text: String, attachments: [DraftAttachment], conversationID: String,
    identity: MessageCommandIdentity, replyTo: String?
  ) throws -> String {
    sendCalls += 1
    if knownAcceptanceFailure {
      let command = PreparedConversationCommand.submit(
        .init(
          requestID: identity.requestID,
          conversationID: conversationID, executionID: identity.executionID, text: text,
          replyTo: replyTo))
      values[credential, default: []].append(command)
      throw CommandDeliveryFailure(
        command: command, acknowledgment: .submitted(identity.executionID),
        underlying: PhoneCommandStoreError.unavailable)
    }
    return identity.executionID
  }
  func answer(_ permission: NessaPermission, option: NessaPermission.Option, conversationID: String)
  {}
  func delete(_ conversationID: String) {}
  func pendingCommands() async throws -> [PreparedConversationCommand] {
    let original = credential
    pendingCalls += 1
    if holdPending {
      holdPending = false
      await withCheckedContinuation { pendingGate = $0 }
    }
    if pendingFailure { throw PhoneCommandStoreError.corrupt }
    return values[original] ?? []
  }
  func checkCommand(_ requestID: String) async throws -> ResolvedConversationCommand? {
    try await recovery(requestID)
  }
  func retryCommand(_ requestID: String) async throws -> ResolvedConversationCommand {
    try await recovery(requestID)
  }
  private func recovery(_ requestID: String) async throws -> ResolvedConversationCommand {
    let original = credential
    let command = try #require(values[original]?.first(where: { $0.requestID == requestID }))
    recoveryCalls += 1
    let index = recoveryCalls
    await withCheckedContinuation { gates[index] = $0 }
    var result = command
    if wrongPayload, case .submit(let value) = command {
      result = .submit(
        .init(
          requestID: value.requestID, conversationID: value.conversationID,
          executionID: value.executionID, text: "Substituted payload"))
    } else {
      values[original]?.removeAll { $0.requestID == requestID }
    }
    let acknowledgment: ConversationCommandAcknowledgment
    switch result {
    case .create(let value): acknowledgment = .created(value.conversationID)
    case .submit(let value): acknowledgment = .submitted(value.executionID)
    }
    return .init(command: result, acknowledgment: acknowledgment)
  }
}

@MainActor private func recoveryModel(_ repository: RecoveryRepository) -> MessagesViewModel {
  MessagesViewModel(
    service: MessagingService(repository: repository),
    credentials: InMemoryCredentialStore(), preferences: InMemoryChatPreferences())
}
private func recoveryEntered(_ condition: @Sendable () async -> Bool) async throws {
  let deadline = ContinuousClock.now + .seconds(2)
  while ContinuousClock.now < deadline {
    if await condition() { return }
    try await Task.sleep(for: .milliseconds(1))
  }
  #expect(await condition())
}

@Test @MainActor func pendingCommandsAreLoadedBeforePublishingReadiness() async throws {
  let repository = RecoveryRepository()
  let command = recoveryCommand()
  await repository.seed(command, credential: "old")
  await repository.holdPendingLoad()
  let model = recoveryModel(repository)
  let connecting = Task {
    await model.connect(address: "mock://phone", credential: "old", instance: "phone")
  }
  try await recoveryEntered { await repository.pendingCalls == 1 }
  #expect(!model.connected)
  await repository.releasePending()
  await connecting.value
  #expect(model.connected)
  #expect(model.pendingCommands == [command])
  #expect(!model.canSubmit(in: command.conversationID))
  #expect(await model.send("New intent", to: command.conversationID) == false)
  #expect(await repository.sendCalls == 0)
}

@Test @MainActor func failedPendingLoadKeepsReadsAvailableButBlocksCommands() async {
  let repository = RecoveryRepository()
  await repository.failPending(true)
  let model = recoveryModel(repository)
  await model.connect(address: "mock://phone", credential: "old", instance: "phone")
  #expect(model.connected)
  #expect(model.pendingLoadError != nil)
  #expect(!model.canSubmit(in: recoveryCommand().conversationID))
  #expect(await model.create() == nil)
  await repository.failPending(false)
  await model.refreshPendingCommands()
  #expect(model.pendingLoadError == nil)
  #expect(model.canSubmit(in: recoveryCommand().conversationID))
}

@Test(arguments: [false, true]) @MainActor
func oldRecoveryCannotNavigateOrConfirmAcrossAccountReplacement(retry: Bool) async throws {
  let repository = RecoveryRepository()
  let command = recoveryCommand(create: true)
  await repository.seed(command, credential: "old")
  let model = recoveryModel(repository)
  await model.connect(address: "mock://phone", credential: "old", instance: "phone")
  let originalScope = model.deliveryScopeRevision
  let old = Task { await model.recoverCommand(command.requestID, retry: retry) }
  try await recoveryEntered { await repository.recoveryCalls == 1 }
  await model.connect(address: "mock://phone", credential: "new", instance: "phone")
  await repository.releaseRecovery(1)
  #expect(await old.value == nil)
  #expect(model.deliveryScopeRevision != originalScope)
  #expect(model.acknowledgedCommands.isEmpty)
  #expect(model.pendingCommands.isEmpty)
  #expect(model.checkingCommands.isEmpty)
  #expect(model.error == nil)
}

@Test(arguments: [false, true]) @MainActor
func oldRecoveryCannotReleaseReplacementActionAndRestoresFrozenReply(retry: Bool) async throws {
  let repository = RecoveryRepository()
  let command = recoveryCommand()
  await repository.seed(command, credential: "old")
  let model = recoveryModel(repository)
  await model.connect(address: "mock://phone", credential: "old", instance: "phone")
  let old = Task { await model.recoverCommand(command.requestID, retry: retry) }
  try await recoveryEntered { await repository.recoveryCalls == 1 }
  await model.connect(address: "mock://phone", credential: "old", instance: "phone")
  let replacement = Task { await model.recoverCommand(command.requestID, retry: retry) }
  try await recoveryEntered { await repository.recoveryCalls == 2 }
  await repository.releaseRecovery(1)
  #expect(await old.value == nil)
  #expect(model.checkingCommands.contains(command.requestID))
  await repository.releaseRecovery(2)
  _ = await replacement.value
  #expect(model.checkingCommands.isEmpty)
  #expect(model.pendingCommands.isEmpty)
  #expect(model.acknowledgedCommands.contains(command.requestID))
  #expect(
    model.replies(in: command.conversationID)["00000000-0000-4000-8000-000000000023"] == "parent")
}

@Test @MainActor func substitutedRecoveredPayloadDoesNotConfirmOriginalDraft() async throws {
  let repository = RecoveryRepository()
  let command = recoveryCommand()
  await repository.seed(command, credential: "old")
  await repository.returnWrongPayload()
  let model = recoveryModel(repository)
  await model.connect(address: "mock://phone", credential: "old", instance: "phone")
  let checking = Task { await model.recoverCommand(command.requestID, retry: false) }
  try await recoveryEntered { await repository.recoveryCalls == 1 }
  await repository.releaseRecovery(1)
  _ = await checking.value
  #expect(model.acknowledgedCommands.isEmpty)
  #expect(model.pendingCommands == [command])
  #expect(model.error != nil)
}

@Test @MainActor func knownSendAcceptanceClearsOriginalButKeepsFailedResolutionPending() async {
  let repository = RecoveryRepository()
  await repository.failKnownAcceptance()
  let model = recoveryModel(repository)
  await model.connect(address: "mock://phone", credential: "old", instance: "phone")
  let draft = ComposerDraftViewModel()
  draft.text = "Reply"
  draft.reply = .init(id: "parent", author: "Agent", text: "Parent")
  let attempt = draft.begin(scope: model.deliveryScopeRevision)
  #expect(
    await model.send(
      attempt.text, reply: attempt.reply, to: recoveryCommand().conversationID,
      identity: attempt.identity))
  draft.accept(model.acknowledgedCommands, scope: model.deliveryScopeRevision)
  #expect(draft.text.isEmpty)
  #expect(model.pendingCommands.count == 1)
  #expect(model.pendingCommands.first?.requestID == attempt.identity.requestID)
  #expect(!model.canSubmit(in: recoveryCommand().conversationID))
  #expect(
    model.replies(in: recoveryCommand().conversationID)[attempt.identity.executionID] == "parent")
}
