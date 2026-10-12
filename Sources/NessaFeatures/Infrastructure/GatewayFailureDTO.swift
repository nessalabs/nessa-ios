/// Only wire error codes select behavior; diagnostic messages are display-only.
enum GatewayFailureDTO {
  static func failure(code: String?, message: String?) -> NessaGatewayError {
    if code == "conversation_not_found" { return .conversationNotFound }
    if code == "unknown_subscription" { return .unknownSubscription }
    if code == "image_input_unsupported" { return .imageInputUnsupported }
    if code == "model_unavailable" { return .modelUnavailable }
    if code == "agent_not_configured" { return .agentNotConfigured }
    return .rejected(message ?? "The gateway refused the request.")
  }
}
