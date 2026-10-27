import Foundation
import Testing

@testable import NessaFeatures

@Test func artifactsPreserveDuplicateOccurrencesAndTurnIdentity() {
  let image = NessaStoredAttachment(digest: "same", mimeType: "image/png", size: 1)
  var turn = NessaTurn(
    executionId: "first", userText: "", status: "completed", error: nil, parts: [])
  turn.attachments = [image, image]
  turn.files = [NessaFileAttachment(name: "notes.txt", mimeType: "text/plain", data: nil)]
  let artifacts = ConversationArtifact.collect(from: [turn])
  #expect(artifacts.count == 3)
  #expect(Set(artifacts.map(\.id)).count == 3)
  #expect(artifacts.allSatisfy { $0.turnID == "first" })
}

@Test func liveTurnsWithoutOptionalFilesRemainDecodable() throws {
  let turn = try JSONDecoder().decode(
    NessaTurn.self,
    from: Data(
      #"{"executionId":"live","userText":"Hi","status":"completed","parts":[]}"#.utf8))
  #expect(turn.files == nil)
  #expect(ConversationArtifact.collect(from: [turn]).isEmpty)
  let profile = AgentProfile(id: "other", displayName: "Other agent")
  #expect(profile.prompt == nil)
  #expect(profile.grantedAccess == nil)
}

@Test func mockDetailsAreScopedAndFilesSurviveTurnCompletion() async throws {
  let repository = MockRepository(agents: [AgentProfile(id: "helper", displayName: "Helper")])
  await repository.connect(address: "mock://details", credential: "", instance: "test")
  #expect(try await repository.agents().first?.prompt == nil)
  let id = try await repository.create(agent: "helper")
  let bytes = Data("Hello from a file".utf8)
  try await repository.send(
    "",
    attachments: [
      DraftAttachment(name: "Hello.txt", mimeType: "text/plain", data: bytes)
    ], conversationID: id)
  #expect(try await repository.read(id).runtime?.agent == "helper")
  #expect(try await repository.read(id).messages.first?.files?.first?.data == bytes)
  try await Task.sleep(for: .seconds(1.5))
  #expect(try await repository.read(id).messages.first?.status == "completed")
  #expect(try await repository.read(id).messages.first?.files?.first?.data == bytes)
}
