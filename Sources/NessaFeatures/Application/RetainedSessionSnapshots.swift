import Foundation

/// Passive evidence from the native owner, not command or account authority.
public enum RetainedAttemptFailure: String, Equatable, Sendable {
  case invalidProof
  case connectionClosed
  case handshakeDeadline
  case verifierUnavailable
}

public enum RetainedAttemptState: String, Equatable, Sendable {
  case pending
  case failed
  case claimed
  case superseded
}

public enum RetainedConsentClass: String, Equatable, Sendable {
  case deviceRead
  case peerRead
  case peerEnvironment
}

public enum RetainedCryptoFailure: String, Equatable, Sendable {
  case invalidCode
  case invalidContext
  case invalidProof
  case unavailable
  case pendingStorage
}

public enum RetainedEnrollmentFailureKind: String, Equatable, Sendable {
  case busy
  case pendingExists
  case enrolled
  case originalNotRetryable
  case noPending
  case storage
  case crypto
  case handshake
  case wire
  case phase
  case otherEnrollee
  case refused
  case io
  case entropy
  case workerFault
}

public enum RetainedEnrollmentPhase: String, Equatable, Sendable {
  case pending
  case unclaimed
  case claimed
  case approved
  case staging
  case active
  case terminal
}

public enum RetainedKeyPublication: String, Equatable, Sendable {
  case notPublished
  case published
}

public enum RetainedPairingFailure: String, Equatable, Sendable {
  case invalid
  case expired
  case attemptsExhausted
  case capacity
  case availableSlotOccupied
  case conflict
  case ineligible
  case wrongActor
  case staleGeneration
}

public enum RetainedPrivateStateKind: String, Equatable, Sendable {
  case auditUnavailable
  case publication
  case auditPublication
  case corrupt
  case conflict
  case locked
  case unavailable
  case uncertain
}

public enum RetainedPublicationEffect: String, Equatable, Sendable {
  case notPublished
  case published
}

public enum RetainedPublicationStep: String, Equatable, Sendable {
  case validateDestination
  case verifyOriginBinding
  case validateReservation
  case flushBeforeRename
  case rename
  case flushAfterRename
  case validatePublishedDestination
  case verifyPublishedBinding
  case syncDirectory
}

public enum RetainedReadFailure: String, Equatable, Sendable {
  case refused
  case unreachable
  case resetRequired
  case `protocol`
  case cache
  case cacheDamaged
  case quota
  case stopped
}

public enum RetainedSessionFailureKind: String, Equatable, Sendable {
  case busy
  case closed
  case damaged
  case runtime
  case privateState
  case cache
  case enrollment
  case noCredential
  case stopped
}

public enum RetainedStorageFailure: String, Equatable, Sendable {
  case unsafeStorage
  case unavailable
}

public enum RetainedTerminalCause: String, Equatable, Sendable {
  case credentialRevoked
  case denied
  case cancelled
  case expired
  case restarted
}

public enum RetainedTranscriptState: String, Equatable, Sendable {
  case notLoaded
  case deleted
  case retained
}

public enum RetainedWireFailureKind: String, Equatable, Sendable {
  case tooLarge
  case invalid
  case correlation
}

public enum RetainedWorkerFault: String, Equatable, Sendable {
  case panic
  case cancelled
}

public struct RetainedCatalogueEntry: Equatable, Sendable {
  public let agent: String?
  public let archived: Bool?
  public let createdAtMs: UInt64?
  public let deleted: Bool
  public let key: RetainedEntryKey
  public let model: String?
  public let preview: String?
  public let revision: UInt64
  public let title: String?
  public let updatedAtMs: UInt64?
  public init(
    agent: String?, archived: Bool?, createdAtMs: UInt64?, deleted: Bool, key: RetainedEntryKey,
    model: String?, preview: String?, revision: UInt64, title: String?, updatedAtMs: UInt64?
  ) {
    self.agent = agent
    self.archived = archived
    self.createdAtMs = createdAtMs
    self.deleted = deleted
    self.key = key
    self.model = model
    self.preview = preview
    self.revision = revision
    self.title = title
    self.updatedAtMs = updatedAtMs
  }
}

public struct RetainedCataloguePage: Equatable, Sendable {
  public let activeBoundary: UInt64?
  public let activeCursor: RetainedEntryKey?
  public let completed: UInt64
  public let entries: [RetainedCatalogueEntry]
  public let generation: UInt64
  public let next: RetainedEntryKey?
  public let scope: RetainedScope
  public init(
    activeBoundary: UInt64?, activeCursor: RetainedEntryKey?, completed: UInt64,
    entries: [RetainedCatalogueEntry], generation: UInt64, next: RetainedEntryKey?,
    scope: RetainedScope
  ) {
    self.activeBoundary = activeBoundary
    self.activeCursor = activeCursor
    self.completed = completed
    self.entries = entries
    self.generation = generation
    self.next = next
    self.scope = scope
  }
}

public struct RetainedEnrollmentFailure: Equatable, Sendable {
  public let crypto: RetainedCryptoFailure?
  public let ioDiagnostic: String?
  public let kind: RetainedEnrollmentFailureKind
  public let storage: RetainedPrivateStateFailure?
  public let wire: RetainedWireFailure?
  public let worker: RetainedWorkerFault?
  public init(
    crypto: RetainedCryptoFailure?, ioDiagnostic: String?, kind: RetainedEnrollmentFailureKind,
    storage: RetainedPrivateStateFailure?, wire: RetainedWireFailure?, worker: RetainedWorkerFault?
  ) {
    self.crypto = crypto
    self.ioDiagnostic = ioDiagnostic
    self.kind = kind
    self.storage = storage
    self.wire = wire
    self.worker = worker
  }
}

public struct RetainedEnrollmentReceipt: Equatable, Sendable {
  public let accessEpoch: UInt64?
  public let attemptFailure: RetainedAttemptFailure?
  public let attemptState: RetainedAttemptState?
  public let audience: String?
  public let credential: String?
  public let organization: String?
  public let phase: RetainedEnrollmentPhase
  public let publicIntent: RetainedPublicIntent
  public let receiver: String?
  public let resource: String?
  public let terminalCause: RetainedTerminalCause?
  public init(
    accessEpoch: UInt64?, attemptFailure: RetainedAttemptFailure?,
    attemptState: RetainedAttemptState?, audience: String?, credential: String?,
    organization: String?, phase: RetainedEnrollmentPhase, publicIntent: RetainedPublicIntent,
    receiver: String?, resource: String?, terminalCause: RetainedTerminalCause?
  ) {
    self.accessEpoch = accessEpoch
    self.attemptFailure = attemptFailure
    self.attemptState = attemptState
    self.audience = audience
    self.credential = credential
    self.organization = organization
    self.phase = phase
    self.publicIntent = publicIntent
    self.receiver = receiver
    self.resource = resource
    self.terminalCause = terminalCause
  }
  /// Matches the full native public intent, including the exact retry attempt.
  public func sameIntent(as other: Self) -> Bool { publicIntent == other.publicIntent }
}

public struct RetainedEntryKey: Equatable, Sendable {
  public let creation: UInt64
  public let id: String
  public init(creation: UInt64, id: String) {
    self.creation = creation
    self.id = id
  }
}

public struct RetainedPrivateStateFailure: Equatable, Sendable {
  public let keyPublication: RetainedKeyPublication?
  public let kind: RetainedPrivateStateKind
  public let publication: RetainedPublicationFailure?
  public init(
    keyPublication: RetainedKeyPublication?, kind: RetainedPrivateStateKind,
    publication: RetainedPublicationFailure?
  ) {
    self.keyPublication = keyPublication
    self.kind = kind
    self.publication = publication
  }
}

public struct RetainedPublicIntent: Equatable, Sendable {
  public let attempt: Data
  public let consent: Data
  public let consentClass: RetainedConsentClass
  public let expiryMs: UInt64
  public let generation: UInt64
  public let invitation: Data
  public init(
    attempt: Data, consent: Data, consentClass: RetainedConsentClass, expiryMs: UInt64,
    generation: UInt64, invitation: Data
  ) {
    self.attempt = attempt
    self.consent = consent
    self.consentClass = consentClass
    self.expiryMs = expiryMs
    self.generation = generation
    self.invitation = invitation
  }
}

/// Public facts from the existing private enrollment record. Not current read authority.
public struct RetainedLocalEnrollment: Equatable, Sendable {
  public let publicIntent: RetainedPublicIntent
  public let deviceKey: Data
  public let gatewayPin: Data
  public let issued: RetainedLocalIssuedEnrollment?
  public init(
    publicIntent: RetainedPublicIntent, deviceKey: Data, gatewayPin: Data,
    issued: RetainedLocalIssuedEnrollment?
  ) {
    self.publicIntent = publicIntent
    self.deviceKey = deviceKey
    self.gatewayPin = gatewayPin
    self.issued = issued
  }
}

public struct RetainedLocalIssuedEnrollment: Equatable, Sendable {
  public let credential: String
  public let receiver: String
  public init(credential: String, receiver: String) {
    self.credential = credential
    self.receiver = receiver
  }
  public static func == (lhs: Self, rhs: Self) -> Bool {
    RetainedTextEquality.equal(lhs.credential, rhs.credential)
      && RetainedTextEquality.equal(lhs.receiver, rhs.receiver)
  }
}

public struct RetainedPublicationFailure: Equatable, Sendable {
  public let cleanup: RetainedStorageFailure?
  public let effect: RetainedPublicationEffect
  public let primary: RetainedStorageFailure
  public let reconciliation: RetainedStorageFailure?
  public let step: RetainedPublicationStep
  public init(
    cleanup: RetainedStorageFailure?, effect: RetainedPublicationEffect,
    primary: RetainedStorageFailure, reconciliation: RetainedStorageFailure?,
    step: RetainedPublicationStep
  ) {
    self.cleanup = cleanup
    self.effect = effect
    self.primary = primary
    self.reconciliation = reconciliation
    self.step = step
  }
}

public struct RetainedPurge: Equatable, Sendable {
  public let catalogueEntries: UInt64
  public let observedAtMs: UInt64
  public let receiver: String
  public let records: UInt64
  public let transcripts: UInt64
  public init(
    catalogueEntries: UInt64, observedAtMs: UInt64, receiver: String, records: UInt64,
    transcripts: UInt64
  ) {
    self.catalogueEntries = catalogueEntries
    self.observedAtMs = observedAtMs
    self.receiver = receiver
    self.records = records
    self.transcripts = transcripts
  }
}

public struct RetainedRead: Equatable, Sendable {
  public let complete: Bool?
  public let conversations: UInt64?
  public let failure: RetainedReadFailure?
  public let moved: Bool?
  public let withdrawn: [String]
  public init(
    complete: Bool?, conversations: UInt64?, failure: RetainedReadFailure?, moved: Bool?,
    withdrawn: [String]
  ) {
    self.complete = complete
    self.conversations = conversations
    self.failure = failure
    self.moved = moved
    self.withdrawn = withdrawn
  }
}

public struct RetainedRefresh: Equatable, Sendable {
  public let initial: RetainedStatus
  public let read: RetainedRead?
  public let recheck: RetainedStatus?
  public let selectionFailure: RetainedEnrollmentFailure?
  public init(
    initial: RetainedStatus, read: RetainedRead?, recheck: RetainedStatus?,
    selectionFailure: RetainedEnrollmentFailure?
  ) {
    self.initial = initial
    self.read = read
    self.recheck = recheck
    self.selectionFailure = selectionFailure
  }
}

public struct RetainedRetry: Equatable, Sendable {
  public let original: RetainedEnrollmentReceipt
  public let retried: RetainedEnrollmentReceipt
  public init(original: RetainedEnrollmentReceipt, retried: RetainedEnrollmentReceipt) {
    self.original = original
    self.retried = retried
  }
}

public struct RetainedScope: Equatable, Sendable {
  public let accessEpoch: String
  public let incarnation: String
  public let origin: String
  public let receiver: String
  public let schema: String
  public let stream: String
  public init(
    accessEpoch: String, incarnation: String, origin: String, receiver: String, schema: String,
    stream: String
  ) {
    self.accessEpoch = accessEpoch
    self.incarnation = incarnation
    self.origin = origin
    self.receiver = receiver
    self.schema = schema
    self.stream = stream
  }
}

public struct RetainedSessionFailure: Equatable, Sendable {
  public let cache: RetainedReadFailure?
  public let enrollment: RetainedEnrollmentFailure?
  public let kind: RetainedSessionFailureKind
  public let privateState: RetainedPrivateStateFailure?
  public let runtimeDiagnostic: String?
  public init(
    cache: RetainedReadFailure?, enrollment: RetainedEnrollmentFailure?,
    kind: RetainedSessionFailureKind, privateState: RetainedPrivateStateFailure?,
    runtimeDiagnostic: String?
  ) {
    self.cache = cache
    self.enrollment = enrollment
    self.kind = kind
    self.privateState = privateState
    self.runtimeDiagnostic = runtimeDiagnostic
  }
}

public struct RetainedStatus: Equatable, Sendable {
  public let completionCaptured: Bool
  public let failure: RetainedEnrollmentFailure?
  public let purge: RetainedPurge?
  public let purgeAttempted: Bool
  public let purgeFailure: RetainedReadFailure?
  public let receipt: RetainedEnrollmentReceipt?
  public init(
    completionCaptured: Bool, failure: RetainedEnrollmentFailure?, purge: RetainedPurge?,
    purgeAttempted: Bool, purgeFailure: RetainedReadFailure?, receipt: RetainedEnrollmentReceipt?
  ) {
    self.completionCaptured = completionCaptured
    self.failure = failure
    self.purge = purge
    self.purgeAttempted = purgeAttempted
    self.purgeFailure = purgeFailure
    self.receipt = receipt
  }
}

public struct RetainedWireFailure: Equatable, Sendable {
  public let correlation: RetainedPairingFailure?
  public let kind: RetainedWireFailureKind
  public init(correlation: RetainedPairingFailure?, kind: RetainedWireFailureKind) {
    self.correlation = correlation
    self.kind = kind
  }
}

public enum RetainedViewFailure: String, Equatable, Sendable {
  case busy, damagedHandle, cache, cacheDamaged, resetRequired, quota
  case invalidTarget, viewTooLarge, serialization
}

public enum RetainedSessionError: Error, Equatable, Sendable {
  case invalidArgument
  case session(RetainedSessionFailure)
  case view(RetainedViewFailure)
  case busy, closed, cancelled, bridge
}

// Opaque native identifiers preserve UTF-8; Swift String equality is canonically equivalent.
private enum RetainedTextEquality {
  static func equal(_ lhs: String, _ rhs: String) -> Bool { lhs.utf8.elementsEqual(rhs.utf8) }
  static func equal(_ lhs: String?, _ rhs: String?) -> Bool {
    switch (lhs, rhs) {
    case (.none, .none): return true
    case (.some(let lhs), .some(let rhs)): return equal(lhs, rhs)
    default: return false
    }
  }
  static func equal(_ lhs: [String], _ rhs: [String]) -> Bool {
    lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { equal($0.0, $0.1) }
  }
}

extension RetainedCatalogueEntry {
  public static func == (lhs: Self, rhs: Self) -> Bool {
    RetainedTextEquality.equal(lhs.agent, rhs.agent) && lhs.archived == rhs.archived
      && lhs.createdAtMs == rhs.createdAtMs && lhs.deleted == rhs.deleted && lhs.key == rhs.key
      && RetainedTextEquality.equal(lhs.model, rhs.model)
      && RetainedTextEquality.equal(lhs.preview, rhs.preview) && lhs.revision == rhs.revision
      && RetainedTextEquality.equal(lhs.title, rhs.title) && lhs.updatedAtMs == rhs.updatedAtMs
  }
}

extension RetainedEnrollmentFailure {
  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.crypto == rhs.crypto && RetainedTextEquality.equal(lhs.ioDiagnostic, rhs.ioDiagnostic)
      && lhs.kind == rhs.kind && lhs.storage == rhs.storage && lhs.wire == rhs.wire
      && lhs.worker == rhs.worker
  }
}

extension RetainedEnrollmentReceipt {
  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.accessEpoch == rhs.accessEpoch && lhs.attemptFailure == rhs.attemptFailure
      && lhs.attemptState == rhs.attemptState
      && RetainedTextEquality.equal(lhs.audience, rhs.audience)
      && RetainedTextEquality.equal(lhs.credential, rhs.credential)
      && RetainedTextEquality.equal(lhs.organization, rhs.organization) && lhs.phase == rhs.phase
      && lhs.publicIntent == rhs.publicIntent
      && RetainedTextEquality.equal(lhs.receiver, rhs.receiver)
      && RetainedTextEquality.equal(lhs.resource, rhs.resource)
      && lhs.terminalCause == rhs.terminalCause
  }
}

extension RetainedEntryKey {
  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.creation == rhs.creation && RetainedTextEquality.equal(lhs.id, rhs.id)
  }
}

extension RetainedPurge {
  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.catalogueEntries == rhs.catalogueEntries && lhs.observedAtMs == rhs.observedAtMs
      && RetainedTextEquality.equal(lhs.receiver, rhs.receiver) && lhs.records == rhs.records
      && lhs.transcripts == rhs.transcripts
  }
}

extension RetainedRead {
  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.complete == rhs.complete && lhs.conversations == rhs.conversations
      && lhs.failure == rhs.failure && lhs.moved == rhs.moved
      && RetainedTextEquality.equal(lhs.withdrawn, rhs.withdrawn)
  }
}

extension RetainedScope {
  public static func == (lhs: Self, rhs: Self) -> Bool {
    RetainedTextEquality.equal(lhs.accessEpoch, rhs.accessEpoch)
      && RetainedTextEquality.equal(lhs.incarnation, rhs.incarnation)
      && RetainedTextEquality.equal(lhs.origin, rhs.origin)
      && RetainedTextEquality.equal(lhs.receiver, rhs.receiver)
      && RetainedTextEquality.equal(lhs.schema, rhs.schema)
      && RetainedTextEquality.equal(lhs.stream, rhs.stream)
  }
}

extension RetainedSessionFailure {
  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.cache == rhs.cache && lhs.enrollment == rhs.enrollment && lhs.kind == rhs.kind
      && lhs.privateState == rhs.privateState
      && RetainedTextEquality.equal(lhs.runtimeDiagnostic, rhs.runtimeDiagnostic)
  }
}
