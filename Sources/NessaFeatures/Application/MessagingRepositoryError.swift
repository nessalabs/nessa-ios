import Foundation

public enum NessaGatewayError: LocalizedError {
  case invalidAddress, invalidFrame, incompatibleProtocol, disconnected, timeout
  case unknownSubscription
  case conversationNotFound
  case imageInputUnsupported
  case modelUnavailable, agentNotConfigured
  case rejected(String)
  case revoked(String)
  public var errorDescription: String? {
    switch self {
    case .invalidAddress:
      "Enter a wss:// gateway address ending in /session (ws:// is allowed only for numeric localhost)."
    case .invalidFrame: "The gateway returned an invalid response."
    case .incompatibleProtocol: "This gateway does not support product protocol v1."
    case .disconnected: "The gateway connection closed. Reconnect before sending."
    case .timeout:
      "The gateway did not reply in time. A sent command may still have been accepted; refresh before trying again."
    case .unknownSubscription: "Live updates already stopped."
    case .conversationNotFound: "This chat is no longer available."
    case .imageInputUnsupported:
      "This chat’s model cannot receive photos. Start a new chat with an image-capable model."
    case .modelUnavailable: "This model is no longer available. Choose another model."
    case .agentNotConfigured: "This agent is no longer available on the gateway."
    case .rejected(let message): message
    case .revoked: "This phone’s access was revoked."
    }
  }
}
