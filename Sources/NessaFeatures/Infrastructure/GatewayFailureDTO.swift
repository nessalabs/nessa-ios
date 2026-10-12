/// Only wire error codes select behavior; diagnostic messages are display-only.
enum GatewayFailureDTO {
  static func failure(code: String?, message: String?) -> NessaGatewayError {
    if code == "image_input_unsupported" { return .imageInputUnsupported }
    return .rejected(message ?? "The gateway refused the request.")
  }
}
