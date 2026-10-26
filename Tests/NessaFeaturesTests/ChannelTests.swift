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
