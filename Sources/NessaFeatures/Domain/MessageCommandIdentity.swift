import Foundation

/// Allocated by the application/composer before uploads or socket work begins.
public struct MessageCommandIdentity: Sendable, Equatable {
  public let requestID: String
  public let executionID: String
  public init(
    requestID: String = UUID().uuidString.lowercased(),
    executionID: String = UUID().uuidString.lowercased()
  ) {
    self.requestID = requestID
    self.executionID = executionID
  }
}
