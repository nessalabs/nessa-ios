import Foundation

public enum NessaGatewayError: LocalizedError {
  case invalidAddress, invalidFrame, incompatibleProtocol, disconnected, timeout
  case imageInputUnsupported
  case rejected(String)
  public var errorDescription: String? {
    switch self {
    case .invalidAddress:
      "Enter a wss:// gateway address ending in /session (ws:// is allowed only for numeric localhost)."
    case .invalidFrame: "The gateway returned an invalid response."
    case .incompatibleProtocol: "This gateway does not support product protocol v1."
    case .disconnected: "The gateway connection closed. Reconnect before sending."
    case .timeout:
      "The gateway did not reply in time. A sent command may still have been accepted; refresh before trying again."
    case .imageInputUnsupported:
      "This chat’s model cannot receive photos. Start a new chat with an image-capable model."
    case .rejected(let message): message
    }
  }
}
