import Foundation

private final class NoUploadRedirects: NSObject, URLSessionTaskDelegate {
  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) {
    completionHandler(nil)
  }
}

enum AttachmentUploadTransport {
  static func put(_ attachment: DraftAttachment, ticket: String, url: URL) async throws
    -> NessaImageAttachment
  {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpCookieStorage = nil
    configuration.urlCredentialStorage = nil
    configuration.urlCache = nil
    configuration.timeoutIntervalForRequest = 30
    let session = URLSession(
      configuration: configuration, delegate: NoUploadRedirects(), delegateQueue: nil)
    defer { session.invalidateAndCancel() }
    var request = URLRequest(url: url)
    request.httpMethod = "PUT"
    request.setValue(ticket, forHTTPHeaderField: "x-nessa-upload-ticket")
    request.setValue(attachment.mimeType, forHTTPHeaderField: "Content-Type")
    let (data, response) = try await session.upload(for: request, from: attachment.data)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
      data.count <= 4096
    else {
      throw NessaGatewayError.rejected("The attachment upload failed. Your draft has been kept.")
    }
    return try JSONDecoder().decode(NessaImageAttachment.self, from: data)
  }
}

/// Uploads over the session, for a connection with no upload address.
enum AttachmentPieces {
  /// The gateway's `attachment.write` piece size: base64 of it fits one frame.
  static let maxBytes = 32 * 1024

  /// A refused piece in plain words. Every refusal ends the upload, so the
  /// draft stays and sending again begins a new one.
  static func failure(_ rejection: GatewayProductRejection) -> any Error {
    switch rejection.code {
    case "unknown_method":
      NessaGatewayError.rejected(
        "Update Nessa on your Mac to send photos from your phone. Your draft has been kept.")
    case "upload_ticket_invalid", "upload_failed":
      NessaGatewayError.rejected("The photo didn’t finish sending. Your draft has been kept.")
    case "unsupported_image":
      NessaGatewayError.rejected("Your Mac couldn’t read this photo. Try another one.")
    case "image_too_large":
      NessaGatewayError.rejected("This photo is too large to send. Try a smaller one.")
    case "image_input_unsupported": NessaGatewayError.imageInputUnsupported
    default: rejection
    }
  }
}
