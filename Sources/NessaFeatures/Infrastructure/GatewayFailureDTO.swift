import Foundation

/// Only wire error codes select behavior; diagnostic messages are display-only.
enum GatewayFailureDTO {
  static func failure(code: String?, message: String?) -> NessaGatewayError {
    if code == "conversation_not_found" { return .conversationNotFound }
    if code == "unknown_subscription" { return .unknownSubscription }
    if code == "image_input_unsupported" { return .imageInputUnsupported }
    if code == "model_unavailable" { return .modelUnavailable }
    if code == "agent_not_configured" { return .agentNotConfigured }
    if let code, PhoneAccess.revoked(code) { return .revoked(code) }
    return .rejected(message ?? "The gateway refused the request.")
  }
}

/// Phone send, lookup, and Stop keep the gateway's refusal code. A missing code is not a refusal.
enum PhoneSocketRefusal {
  static func error(code: String?, message: String?, details: Data?) -> any Error {
    guard let code, !code.isEmpty else { return NessaGatewayError.invalidFrame }
    return GatewayProductRejection(
      code: code, diagnostic: message ?? "", details: details,
      behavior: GatewayFailureDTO.failure(code: code, message: message))
  }
}
