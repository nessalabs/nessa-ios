import Foundation

/// Non-secret handshake evidence; the gateway still authorizes every command.
public struct GatewaySessionSnapshot: Codable, Equatable, Sendable {
  public struct Identity: Codable, Equatable, Sendable {
    public let gatewayID: String
    public let principalID: String
    public let organizationID: String
    public let membershipID: String
    public let credentialID: String
    public let audienceID: String
    public init(
      gatewayID: String, principalID: String, organizationID: String, membershipID: String,
      credentialID: String, audienceID: String
    ) {
      self.gatewayID = gatewayID
      self.principalID = principalID
      self.organizationID = organizationID
      self.membershipID = membershipID
      self.credentialID = credentialID
      self.audienceID = audienceID
    }
  }
  public struct Resource: Codable, Equatable, Sendable {
    public let organizationID: String
    public let id: String
    public init(organizationID: String, id: String) {
      self.organizationID = organizationID
      self.id = id
    }
  }
  public struct Grant: Codable, Equatable, Sendable {
    public let action: String
    public let resource: Resource
    public init(action: String, resource: Resource) {
      self.action = action
      self.resource = resource
    }
  }
  public let identity: Identity
  public let expiresAt: UInt64?
  public let grants: [Grant]
  public let methods: [String]
  public init(identity: Identity, expiresAt: UInt64?, grants: [Grant], methods: [String]) {
    self.identity = identity
    self.expiresAt = expiresAt
    self.grants = grants
    self.methods = methods
  }
}

public struct AuthenticatedGatewaySession: Equatable, Sendable {
  public let connection: GatewayConnectionLease
  public let snapshot: GatewaySessionSnapshot
  public init(connection: GatewayConnectionLease, snapshot: GatewaySessionSnapshot) {
    self.connection = connection
    self.snapshot = snapshot
  }
}

/// A publication belongs to the exact current authenticated socket lease.
public protocol AuthenticatedGatewaySessionProviding: Sendable {
  func authenticatedSession(for lease: GatewayConnectionLease) async throws
    -> AuthenticatedGatewaySession
}
