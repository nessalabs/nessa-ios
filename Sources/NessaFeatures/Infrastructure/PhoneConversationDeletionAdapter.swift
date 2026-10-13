import Foundation

struct DeletionParams: Encodable {
  let conversationId: String
  let requestId: String
}
private struct DeletionReadParams: Encodable { let conversationId: String }
private struct DeletionMutationDTO: Decodable {
  let value: PhoneDeletionAcknowledgment
  init(from decoder: Decoder) throws {
    try validateGatewayWire(decoder, named: "ConversationMutationResult")
    value = try PhoneDeletionAcknowledgment(from: decoder)
  }
}
extension NessaGatewayClient: GatewayConversationDeleting {
  public func deleteConversation(_ intent: PhoneDeletionIntent, on lease: GatewayConnectionLease)
    async throws -> PhoneDeletionReceipt<PhoneDeletionAcknowledgment>
  {
    let source = try authenticatedSession(for: lease)
    guard source.snapshot.identity == intent.scope.owner else { throw PhoneDeletionRefusal.changed }
    let (captured, reply): (AuthenticatedGatewaySession, DeletionMutationDTO) = try await pairing(
      "conversation.delete",
      params: DeletionParams(
        conversationId: intent.conversationID,
        requestId: intent.requestID.uuidString.lowercased()), schema: "ConversationDeleteParams",
      on: lease)
    return .init(source: captured, value: reply.value)
  }
  public func observeDeletion(_ id: String, on lease: GatewayConnectionLease) async throws
    -> PhoneDeletionReceipt<PhoneDeletionObservation>
  {
    let source = try authenticatedSession(for: lease)
    do {
      // Existing product read decoder; no native readiness or cleanup authority is inferred.
      let (captured, view): (AuthenticatedGatewaySession, NessaConversationView) =
        try await pairing(
          "conversation.read", params: DeletionReadParams(conversationId: id),
          schema: "ConversationReadParams", on: lease)
      guard view.conversationId.utf8.elementsEqual(id.utf8) else {
        throw NessaGatewayError.invalidFrame
      }
      return .init(source: captured, value: .readable)
    } catch let failure as GatewayPairingOperationFailure {
      guard failure.source == source, let refusal = failure.underlying as? GatewayPairingRejection
      else { throw failure }
      switch refusal.code {
      case "conversation_deleted": return .init(source: source, value: .deletionFence(refusal))
      case "conversation_not_found": return .init(source: source, value: .absence(refusal))
      default: throw failure
      }
    }
  }
}
