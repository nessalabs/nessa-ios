/// Provider-independent identity. IDs are opaque; they are not model or vendor names.
public struct AgentProfile: Identifiable, Sendable, Equatable {
  public let id: String
  public let displayName: String
  public let description: String?
  public let prompt: String?
  public let grantedAccess: [String]?
  public init(id: String, displayName: String, description: String? = nil,
    prompt: String? = nil, grantedAccess: [String]? = nil
  ) {
    self.id = id
    self.displayName = displayName
    self.description = description
    self.prompt = prompt
    self.grantedAccess = grantedAccess
  }
}
