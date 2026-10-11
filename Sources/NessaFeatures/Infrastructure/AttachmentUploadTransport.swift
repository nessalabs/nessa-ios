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
