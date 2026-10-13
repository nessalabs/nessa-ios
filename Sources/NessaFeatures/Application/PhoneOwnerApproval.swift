import Foundation

/// Original nonsecret discovery and bootstrap facts. This record grants no authority.
public struct PhoneOwnerApprovalContext: Codable, Sendable, Equatable {
  public let bootstrap: GatewaySessionSnapshot.Identity
  public let productAddress: String
  public let instance: String
  public let nativeAddress: String
  public let gatewayPin: Data
  public let consentClass: String
  public let grants: [GatewaySessionSnapshot.Grant]
  public init(
    bootstrap: GatewaySessionSnapshot.Identity, productAddress: String, instance: String,
    nativeAddress: String, gatewayPin: Data, consentClass: String,
    grants: [GatewaySessionSnapshot.Grant]
  ) {
    self.bootstrap = bootstrap
    self.productAddress = productAddress
    self.instance = instance
    self.nativeAddress = nativeAddress
    self.gatewayPin = gatewayPin
    self.consentClass = consentClass
    self.grants = grants
  }
  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.bootstrap == rhs.bootstrap && lhs.gatewayPin == rhs.gatewayPin && lhs.grants == rhs.grants
      && equal(lhs.productAddress, rhs.productAddress) && equal(lhs.instance, rhs.instance)
      && equal(lhs.nativeAddress, rhs.nativeAddress) && equal(lhs.consentClass, rhs.consentClass)
  }
  public func validate() throws {
    let fields = [
      bootstrap.gatewayID, bootstrap.principalID, bootstrap.organizationID,
      bootstrap.membershipID, bootstrap.credentialID, bootstrap.audienceID,
      productAddress, instance, nativeAddress,
    ]
    guard fields.allSatisfy({ !$0.isEmpty && $0.utf8.prefix(8193).count <= 8192 }),
      gatewayPin.count == 44,
      Self.equal(consentClass, "gateway-owner-conversation-read-write"), grants.count == 3
    else { throw PhoneOwnerApprovalRefusal.invalid }
    let resource = GatewaySessionSnapshot.Resource(
      organizationID: bootstrap.organizationID, id: bootstrap.gatewayID)
    let expected = Set(
      ["conversation.read", "conversation.write", "server.read"].map { Data($0.utf8) })
    guard grants.allSatisfy({ $0.resource == resource }),
      Set(grants.map { Data($0.action.utf8) }) == expected
    else { throw PhoneOwnerApprovalRefusal.invalid }
  }
  private static func equal(_ lhs: String, _ rhs: String) -> Bool {
    lhs.utf8.elementsEqual(rhs.utf8)
  }
}

/// A new, unselected native scope and original request, reserved before key preparation.
public struct PhoneOwnerApprovalReservation: Codable, Sendable, Equatable {
  public let profileID: UUID
  public let requestID: UUID
  public let context: PhoneOwnerApprovalContext
  public init(profileID: UUID, requestID: UUID, context: PhoneOwnerApprovalContext) {
    self.profileID = profileID
    self.requestID = requestID
    self.context = context
  }
}

/// Public native-owned proof bytes. Swift does not construct or sign their transcript.
public struct PhoneOwnerApprovalPreparation: Codable, Sendable, Equatable {
  public let reservation: PhoneOwnerApprovalReservation
  public let deviceKey: Data
  public let signature: Data
  public let digest: Data
  public init(
    reservation: PhoneOwnerApprovalReservation, deviceKey: Data, signature: Data, digest: Data
  ) {
    self.reservation = reservation
    self.deviceKey = deviceKey
    self.signature = signature
    self.digest = digest
  }
  public func validate() throws {
    try reservation.context.validate()
    guard deviceKey.count == 32, signature.count == 64, digest.count == 32 else {
      throw PhoneOwnerApprovalRefusal.invalid
    }
  }
}

/// Prepared history is neither remote approval nor proof of current private-key possession.
public struct PhoneOwnerApprovalRecord: Codable, Sendable, Equatable {
  public let schema: Int
  public let reservation: PhoneOwnerApprovalReservation
  public let preparation: PhoneOwnerApprovalPreparation?
  public init(
    reservation: PhoneOwnerApprovalReservation, preparation: PhoneOwnerApprovalPreparation? = nil,
    schema: Int = 1
  ) {
    self.schema = schema
    self.reservation = reservation
    self.preparation = preparation
  }
  public func validate() throws {
    guard schema == 1 else { throw PhoneOwnerApprovalRefusal.invalid }
    try reservation.context.validate()
    if let preparation {
      try preparation.validate()
      guard preparation.reservation == reservation else { throw PhoneOwnerApprovalRefusal.changed }
    }
  }
}

public protocol PhoneOwnerApprovalStoring: Sendable {
  func load() async throws -> [PhoneOwnerApprovalRecord]
  /// Success means durable publication. Equal records must also be durably republished.
  /// Compare-and-swap is atomic; readback after a write failure never means success.
  func publish(
    _ records: [PhoneOwnerApprovalRecord], replacing expected: [PhoneOwnerApprovalRecord])
    async throws
}

public protocol PhoneOwnerApprovalPreparing: Sendable {
  /// Nonnetwork: restore/validate the original private scope and durably prepare its exact proof.
  /// Missing or uncertain history cannot generate a replacement key/request. No selected profile changes.
  func prepare(_ reservation: PhoneOwnerApprovalReservation) async throws
    -> PhoneOwnerApprovalPreparation
  /// Wake and join actual work; successful return means physical release. Repeated closes join.
  func close() async throws
}

public enum PhoneOwnerApprovalRefusal: Error, Equatable, Sendable {
  case invalid, changed, unresolved, noOriginal, capacity, busy, closed
}

public struct PhoneOwnerApprovalFailure: Error, Sendable {
  public let source: AuthenticatedGatewaySession?
  public let reservation: PhoneOwnerApprovalReservation?
  public let preparation: PhoneOwnerApprovalPreparation?
  public let underlying: any Error
  public init(
    source: AuthenticatedGatewaySession?, reservation: PhoneOwnerApprovalReservation?,
    preparation: PhoneOwnerApprovalPreparation?, underlying: any Error
  ) {
    self.source = source
    self.reservation = reservation
    self.preparation = preparation
    self.underlying = underlying
  }
}
