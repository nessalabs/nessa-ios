import Foundation

/// Joins published facts only; Auth and the retained owner still decide validity.
enum PhonePairingCorrelation {
  static func validate(_ owner: GatewayPairingStatus, profile: PhoneProfile) throws {
    guard equal(owner.grant.resource.organizationID, profile.identity.organizationID),
      equal(owner.grant.resource.id, profile.identity.gatewayID)
    else { throw PhoneProfileCoordinationRefusal.correlationChanged }
  }
  static func validate(
    _ owner: GatewayPairingStatus, local: RetainedLocalEnrollment, profile: PhoneProfile
  ) throws {
    try validate(owner, profile: profile)
    let intent = local.publicIntent
    guard owner.invitationID == intent.invitation, owner.consentID == intent.consent,
      owner.generation == intent.generation, equal(owner.consentClass, intent.consentClassName),
      owner.expiresAtMs == intent.expiryMs,
      owner.claimedDeviceKey == nil || owner.claimedDeviceKey == local.deviceKey
    else { throw PhoneProfileCoordinationRefusal.correlationChanged }
    if let issued = local.issued {
      if let credential = owner.credentialID {
        guard equal(credential, issued.credential) else {
          throw PhoneProfileCoordinationRefusal.correlationChanged
        }
      }
      if let receiver = owner.receiver?.id {
        guard equal(receiver, issued.receiver) else {
          throw PhoneProfileCoordinationRefusal.correlationChanged
        }
      }
    }
  }
  static func validate(_ receipt: RetainedEnrollmentReceipt, profile: PhoneProfile) throws {
    if let audience = receipt.audience {
      guard equal(audience, profile.identity.gatewayID),
        equal(audience, profile.identity.audienceID)
      else { throw PhoneProfileCoordinationRefusal.correlationChanged }
    }
    if let organization = receipt.organization {
      guard equal(organization, profile.identity.organizationID) else {
        throw PhoneProfileCoordinationRefusal.correlationChanged
      }
    }
    if let resource = receipt.resource {
      guard equal(resource, profile.identity.gatewayID) else {
        throw PhoneProfileCoordinationRefusal.correlationChanged
      }
    }
    if let owner = profile.pairingStatus {
      let intent = receipt.publicIntent
      guard owner.invitationID == intent.invitation, owner.consentID == intent.consent,
        owner.generation == intent.generation, equal(owner.consentClass, intent.consentClassName),
        owner.expiresAtMs == intent.expiryMs
      else { throw PhoneProfileCoordinationRefusal.correlationChanged }
      if let credential = owner.credentialID, let observed = receipt.credential {
        guard equal(credential, observed) else {
          throw PhoneProfileCoordinationRefusal.correlationChanged
        }
      }
      if let receiver = owner.receiver?.id, let observed = receipt.receiver {
        guard equal(receiver, observed) else {
          throw PhoneProfileCoordinationRefusal.correlationChanged
        }
      }
    }
  }
  static func equal(_ a: String, _ b: String) -> Bool { a.utf8.elementsEqual(b.utf8) }
}
