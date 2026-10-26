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
    // A conversation's grants can take several pages; every page of one read
    // names the same revision, and a moved revision is a changed list.
    var shares: [PhoneConversationShare] = []
    var cursor: SharingCursor?
    var first: (AuthenticatedGatewaySession, UInt64)?
    repeat {
      let (source, page): (AuthenticatedGatewaySession, SharingGrantsDTO) = try await pairing(
        "conversation.shares",
        params: SharingConversation(conversationId: id, pageSize: SharingConversation.page, cursor: cursor),
        schema: "ConversationSharesParams", on: lease)
      if let first, first.1 != page.changeRevision || first.0 != source {
        throw PhoneConversationSharingRefusal.changed
      }
      first = first ?? (source, page.changeRevision)
      shares += page.items
      cursor = page.cursor
      guard shares.count <= SharingConversation.limit else { throw NessaGatewayError.invalidFrame }
    } while cursor != nil
    return .init(source: first!.0, value: shares)
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
        requestId: intent.requestID.uuidString.lowercased(), credentialId: credential),
      schema: "ConversationShareParams", on: lease)
    return .init(source: captured, value: value.value)
  }
}
struct SharingRead: Encodable {
  let conversationId: String
  let requestId: String
  let credentialId: String
  let capabilities = ["read"]
}
private struct SharingEmpty: Encodable {}
private struct SharingConversation: Encodable {
  static let page = 8
  /// The most grants one conversation holds.
  static let limit = 64
  let conversationId: String
  let pageSize: Int
  let cursor: SharingCursor?
}
private struct SharingCursor: Codable, Equatable {
  let credentialId: String
  let grantedAtMs: UInt64
}
private struct SharingListDTO: Decodable {
  let value: NessaConversationList
  init(from decoder: Decoder) throws {
    try validateGatewayWire(decoder, named: "ConversationListResult")
    value = try NessaConversationList(from: decoder)
  }
}
private struct SharingGrantsDTO: Decodable {
  let items: [PhoneConversationShare]
  let changeRevision: UInt64
  let cursor: SharingCursor?
  private enum CodingKeys: String, CodingKey { case items, changeRevision, cursor }
  init(from decoder: Decoder) throws {
    try validateGatewayWire(decoder, named: "ConversationSharesResult")
    let values = try decoder.container(keyedBy: CodingKeys.self)
    items = try values.decode([PhoneConversationShare].self, forKey: .items)
    changeRevision = try values.decode(UInt64.self, forKey: .changeRevision)
    cursor = try values.decodeIfPresent(SharingCursor.self, forKey: .cursor)
  }
}
private struct SharingMutationDTO: Decodable {
  let value: PhoneConversationShareAcknowledgment
  init(from decoder: Decoder) throws {
    try validateGatewayWire(decoder, named: "ConversationMutationResult")
    value = try PhoneConversationShareAcknowledgment(from: decoder)
  }
}
