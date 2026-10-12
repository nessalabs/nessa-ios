/// Provider-independent identity. IDs are opaque; they are not model or vendor names.
public struct AgentProfile: Identifiable, Sendable, Equatable {
  public let id: String
  public let displayName: String
  public let description: String?
  public let prompt: String?
  public let grantedAccess: [String]?
  public let defaultModel: String?
  public let models: [AgentModel]
  /// Prefer the gateway default when it supports photos; otherwise use an offered vision model.
  public var phoneModel: String? {
    models.first { $0.id == defaultModel && $0.supportsImages }?.id
      ?? models.first { $0.supportsImages }?.id ?? defaultModel
  }
  public init(
    id: String, displayName: String, description: String? = nil,
    prompt: String? = nil, grantedAccess: [String]? = nil,
    defaultModel: String? = nil, models: [AgentModel] = []
  ) {
    self.id = id
    self.displayName = displayName
    self.description = description
    self.prompt = prompt
    self.grantedAccess = grantedAccess
    self.defaultModel = defaultModel
    self.models = models
  }
}

public struct AgentModel: Identifiable, Sendable, Equatable {
  public let id: String
  public let displayName: String
  public let supportsImages: Bool
  public init(id: String, displayName: String, supportsImages: Bool) {
    self.id = id
    self.displayName = displayName
    self.supportsImages = supportsImages
  }
}
