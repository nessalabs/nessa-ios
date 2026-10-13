import Foundation

extension NessaGatewayClient: GatewayConversationSharingProviding {
  public func ownerConversationChoices(on lease: GatewayConnectionLease) async throws
    -> PhoneConversationShareReceipt<NessaConversationList>
  {
    let (source, value): (AuthenticatedGatewaySession, SharingListDTO) = try await pairing(
      "conversation.list", params: SharingEmpty(), schema: "ConversationListParams", on: lease)
    return .init(source: source, value: value.value)
  }
  public func conversationShares(_ id: String, on lease: GatewayConnectionLease) async throws
    -> PhoneConversationShareReceipt<[PhoneConversationShare]>
  {
    let (source, value): (AuthenticatedGatewaySession, SharingGrantsDTO) = try await pairing(
      "conversation.shares", params: SharingConversation(conversationId: id),
      schema: "ConversationSharesParams", on: lease)
    return .init(source: source, value: value.items)
  }
  public func setConversationRead(
    _ intent: PhoneConversationShareIntent, on lease: GatewayConnectionLease
  )
    async throws -> PhoneConversationShareReceipt<PhoneConversationShareAcknowledgment>
  {
    let source = try authenticatedSession(for: lease)
    guard source.snapshot.identity == intent.owner, let credential = intent.device.credentialID
    else { throw PhoneConversationSharingRefusal.changed }
    let (captured, value): (AuthenticatedGatewaySession, SharingMutationDTO) = try await pairing(
      "conversation.share",
      params: SharingRead(
        conversationId: intent.conversationID,
        requestId: intent.requestID.uuidString.lowercased(), credentialId: credential, role: "read"),
      schema: "ConversationShareParams", on: lease)
    return .init(source: captured, value: value.value)
  }
}
struct SharingRead: Encodable {
  let conversationId: String
  let requestId: String
  let credentialId: String
  let role: String
}
private struct SharingEmpty: Encodable {}
private struct SharingConversation: Encodable { let conversationId: String }
private struct SharingListDTO: Decodable {
  let value: NessaConversationList
  init(from decoder: Decoder) throws {
    try validateGatewayWire(decoder, named: "ConversationListResult")
    value = try NessaConversationList(from: decoder)
  }
}
private struct SharingGrantsDTO: Decodable {
  let items: [PhoneConversationShare]
  private enum CodingKeys: String, CodingKey { case items }
  init(from decoder: Decoder) throws {
    try validateGatewayWire(decoder, named: "ConversationSharesResult")
    items = try decoder.container(keyedBy: CodingKeys.self).decode(
      [PhoneConversationShare].self, forKey: .items)
  }
}
private struct SharingMutationDTO: Decodable {
  let value: PhoneConversationShareAcknowledgment
  init(from decoder: Decoder) throws {
    try validateGatewayWire(decoder, named: "ConversationMutationResult")
    value = try PhoneConversationShareAcknowledgment(from: decoder)
  }
}
