import Foundation
import Testing

@testable import NessaFeatures

@Test @MainActor func connectingReadsTheChannelsAndEachChatsChannel() async throws {
  let model = MessagesViewModel(
    service: MessagingService(repository: MockRepository()), credentials: InMemoryCredentialStore(),
    preferences: InMemoryChatPreferences())
  await model.connect(address: "mock://one", credential: "", instance: "phone")
  #expect(model.channels.map(\.channelId) == MockRepository.fixtureChannels.map(\.channelId))
  #expect(model.channels.first?.isDefault == true)
  #expect(model.conversations.contains { $0.channelId == "ch_aaaaaaaaaa" })
}

@Test @MainActor func aChatWithNoChannelIsInTheDefaultOne() async throws {
  let model = MessagesViewModel(
    service: MessagingService(repository: MockRepository()), credentials: InMemoryCredentialStore(),
    preferences: InMemoryChatPreferences())
  await model.connect(address: "mock://one", credential: "", instance: "phone")
  let byChannel = model.channels.map { model.conversations(inChannel: $0.id).count }
  #expect(byChannel.reduce(0, +) == model.visibleConversations.count)
  #expect(model.conversations(inChannel: NessaChannel.defaultID).allSatisfy { $0.channelId == nil })
  #expect(model.conversations(inChannel: "ch_aaaaaaaaaa").allSatisfy { $0.channelId == "ch_aaaaaaaaaa" })
}

@Test @MainActor func aChatStartedInAChannelIsListedThere() async throws {
  let model = MessagesViewModel(
    service: MessagingService(repository: MockRepository()), credentials: InMemoryCredentialStore(),
    preferences: InMemoryChatPreferences())
  await model.connect(address: "mock://one", credential: "", instance: "phone")
  let id = try #require(await model.create(channel: "ch_bbbbbbbbbb"))
  #expect(model.conversations(inChannel: "ch_bbbbbbbbbb").contains { $0.id == id })
  try await model.refreshList()
  #expect(model.conversations(inChannel: "ch_bbbbbbbbbb").contains { $0.id == id })
  #expect(!model.conversations(inChannel: NessaChannel.defaultID).contains { $0.id == id })
}

@Test func aJournaledCreationFromBeforeChannelsStillReads() throws {
  let saved = Data(
    #"{"requestID":"r","conversationID":"c","agent":null,"model":null}"#.utf8)
  let creation = try JSONDecoder().decode(PreparedConversationCommand.Creation.self, from: saved)
  #expect(creation.channelID == nil)
}
