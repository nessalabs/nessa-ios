import Foundation
import Testing

@testable import NessaFeatures

@Test func phoneModelRetainsVisionDefaultAndFallsBackOnlyToOfferedModels() {
  let text = AgentModel(id: "text", displayName: "Text", supportsImages: false)
  let vision = AgentModel(id: "vision", displayName: "Vision", supportsImages: true)
  let other = AgentModel(id: "other", displayName: "Other", supportsImages: true)
  #expect(
    AgentProfile(
      id: "a", displayName: "A", defaultModel: "vision",
      models: [other, vision]
    ).phoneModel == "vision")
  #expect(
    AgentProfile(
      id: "a", displayName: "A", defaultModel: "text",
      models: [text, vision]
    ).phoneModel == "vision")
  #expect(
    AgentProfile(
      id: "a", displayName: "A", defaultModel: "text",
      models: [text]
    ).phoneModel == "text")
  #expect(AgentProfile(id: "a", displayName: "A").phoneModel == nil)
}
@Test @MainActor func newPhoneConversationPinsTheAdvertisedVisionModel() async throws {
  let profile = AgentProfile(
    id: "a", displayName: "A", defaultModel: "text",
    models: [
      .init(id: "text", displayName: "Text", supportsImages: false),
      .init(id: "vision", displayName: "Vision", supportsImages: true),
    ])
  let repository = MockRepository(agents: [profile])
  let store = NessaDependencies.development(repository: repository).makeMessagesViewModel()
  await store.connect(address: "mock://phone", credential: "", instance: "test")
  let id = try #require(await store.create(agent: "a"))
  #expect(try await repository.read(id).runtime?.model == "vision")
  let defaultID = try #require(await store.create())
  #expect(try await repository.read(defaultID).runtime?.model == "vision")
}
@Test func gatewayDirectoryMapsPublishedImageCapability() throws {
  let bytes = Data(
    """
    {"agents":[{"agent":"codex","defaultModel":"vision","models":[
      {"modelId":"vision","displayName":"Vision","imageInput":true},
      {"modelId":"text","displayName":"Text","imageInput":false}]}]}
    """.utf8)
  let result = try JSONDecoder().decode(GatewayAgentListDTO.self, from: bytes)
  #expect(result.agents[0].profile.phoneModel == "vision")
  #expect(result.agents[0].profile.models[1].supportsImages == false)
}

@Test func photoRefusalUsesWireCodeAndDoesNotParseDiagnosticText() {
  if case .imageInputUnsupported = GatewayFailureDTO.failure(
    code: "image_input_unsupported", message: "anything")
  {
  } else {
    Issue.record("Photo refusal must have an actionable typed error")
  }
  if case .rejected = GatewayFailureDTO.failure(code: "other", message: "image_input_unsupported") {
  } else {
    Issue.record("Diagnostic text must not determine the refusal type")
  }
}
