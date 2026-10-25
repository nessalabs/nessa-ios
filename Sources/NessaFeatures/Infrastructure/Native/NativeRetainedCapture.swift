import Foundation
import NessaNative

/// Converts immutable foreign results while successful worker admission is held.
enum NativeRetainedCapture {
  static func capture(_ value: NativeAttemptFailure) -> RetainedAttemptFailure {
    switch value {
    case .invalidProof: return .invalidProof
    case .connectionClosed: return .connectionClosed
    case .handshakeDeadline: return .handshakeDeadline
    case .verifierUnavailable: return .verifierUnavailable
    }
  }

  static func capture(_ value: NativeAttemptState) -> RetainedAttemptState {
    switch value {
    case .pending: return .pending
    case .failed: return .failed
    case .claimed: return .claimed
    case .superseded: return .superseded
    }
  }

  static func capture(_ value: NativeConsentClass) -> RetainedConsentClass {
    switch value {
    case .deviceRead: return .deviceRead
    case .peerRead: return .peerRead
    case .peerEnvironment: return .peerEnvironment
    case .ownerPhoneReadWrite: return .ownerPhoneReadWrite
    }
  }

  static func capture(_ value: NativeCryptoFailure) -> RetainedCryptoFailure {
    switch value {
    case .invalidCode: return .invalidCode
    case .invalidContext: return .invalidContext
    case .invalidProof: return .invalidProof
    case .unavailable: return .unavailable
    case .pendingStorage: return .pendingStorage
    }
  }

  static func capture(_ value: NativeEnrollmentFailureKind) -> RetainedEnrollmentFailureKind {
    switch value {
    case .busy: return .busy
    case .pendingExists: return .pendingExists
    case .enrolled: return .enrolled
    case .originalNotRetryable: return .originalNotRetryable
    case .noPending: return .noPending
    case .storage: return .storage
    case .crypto: return .crypto
    case .handshake: return .handshake
    case .wire: return .wire
    case .phase: return .phase
    case .otherEnrollee: return .otherEnrollee
    case .refused: return .refused
    case .io: return .io
    case .entropy: return .entropy
    case .workerFault: return .workerFault
    }
  }

  static func capture(_ value: NativeEnrollmentPhase) -> RetainedEnrollmentPhase {
    switch value {
    case .pending: return .pending
    case .unclaimed: return .unclaimed
    case .claimed: return .claimed
    case .approved: return .approved
    case .staging: return .staging
    case .active: return .active
    case .terminal: return .terminal
    }
  }

  static func capture(_ value: NativeKeyPublication) -> RetainedKeyPublication {
    switch value {
    case .notPublished: return .notPublished
    case .published: return .published
    }
  }

  static func capture(_ value: NativePairingFailure) -> RetainedPairingFailure {
    switch value {
    case .invalid: return .invalid
    case .expired: return .expired
    case .attemptsExhausted: return .attemptsExhausted
    case .capacity: return .capacity
    case .availableSlotOccupied: return .availableSlotOccupied
    case .conflict: return .conflict
    case .ineligible: return .ineligible
    case .wrongActor: return .wrongActor
    case .staleGeneration: return .staleGeneration
    }
  }

  static func capture(_ value: NativePrivateStateKind) -> RetainedPrivateStateKind {
    switch value {
    case .auditUnavailable: return .auditUnavailable
    case .publication: return .publication
    case .auditPublication: return .auditPublication
    case .corrupt: return .corrupt
    case .conflict: return .conflict
    case .locked: return .locked
    case .unavailable: return .unavailable
    case .uncertain: return .uncertain
    }
  }

  static func capture(_ value: NativePublicationEffect) -> RetainedPublicationEffect {
    switch value {
    case .notPublished: return .notPublished
    case .published: return .published
    }
  }

  static func capture(_ value: NativePublicationStep) -> RetainedPublicationStep {
    switch value {
    case .validateDestination: return .validateDestination
    case .verifyOriginBinding: return .verifyOriginBinding
    case .validateReservation: return .validateReservation
    case .flushBeforeRename: return .flushBeforeRename
    case .rename: return .rename
    case .flushAfterRename: return .flushAfterRename
    case .validatePublishedDestination: return .validatePublishedDestination
    case .verifyPublishedBinding: return .verifyPublishedBinding
    case .syncDirectory: return .syncDirectory
    }
  }

  static func capture(_ value: NativeReadFailure) -> RetainedReadFailure {
    switch value {
    case .refused: return .refused
    case .unreachable: return .unreachable
    case .away: return .away
    case .resetRequired: return .resetRequired
    case .`protocol`: return .`protocol`
    case .cache: return .cache
    case .cacheDamaged: return .cacheDamaged
    case .cacheUncertain: return .cacheUncertain
    case .quota: return .quota
    case .stopped: return .stopped
    case .cursorAhead: return .cursorAhead
    case .subscriptionCapacity: return .subscriptionCapacity
    }
  }

  static func capture(_ value: NativeSessionFailureKind) -> RetainedSessionFailureKind {
    switch value {
    case .busy: return .busy
    case .closed: return .closed
    case .damaged: return .damaged
    case .runtime: return .runtime
    case .privateState: return .privateState
    case .cache: return .cache
    case .enrollment: return .enrollment
    case .noCredential: return .noCredential
    case .stopped: return .stopped
    case .product: return .product
    case .owner: return .owner
    }
  }

  static func capture(_ value: NativeStorageFailure) -> RetainedStorageFailure {
    switch value {
    case .unsafeStorage: return .unsafeStorage
    case .unavailable: return .unavailable
    }
  }

  static func capture(_ value: NativeTerminalCause) -> RetainedTerminalCause {
    switch value {
    case .credentialRevoked: return .credentialRevoked
    case .denied: return .denied
    case .cancelled: return .cancelled
    case .expired: return .expired
    case .restarted: return .restarted
    }
  }

  static func capture(_ value: NativeTranscriptState) -> RetainedTranscriptState {
    switch value {
    case .notLoaded: return .notLoaded
    case .deleted: return .deleted
    case .retained: return .retained
    }
  }

  static func capture(_ value: NativeWireFailureKind) -> RetainedWireFailureKind {
    switch value {
    case .tooLarge: return .tooLarge
    case .invalid: return .invalid
    case .correlation: return .correlation
    }
  }

  static func capture(_ value: NativeWorkerFault) -> RetainedWorkerFault {
    switch value {
    case .panic: return .panic
    case .cancelled: return .cancelled
    }
  }

  static func capture(_ value: any NativeCatalogueEntryProtocol) -> RetainedCatalogueEntry {
    RetainedCatalogueEntry(
      agent: value.agent(),
      archived: value.archived(),
      createdAtMs: value.createdAtMs(),
      deleted: value.deleted(),
      key: capture(value.key()),
      model: value.model(),
      preview: value.preview(),
      revision: value.revision(),
      title: value.title(),
      updatedAtMs: value.updatedAtMs()
    )
  }

  static func capture(_ value: any NativeCataloguePageProtocol) -> RetainedCataloguePage {
    RetainedCataloguePage(
      activeBoundary: value.activeBoundary(),
      activeCursor: value.activeCursor().map { capture($0) },
      completed: value.completed(),
      entries: value.entries().map { capture($0) },
      generation: value.generation(),
      next: value.next().map { capture($0) },
      scope: capture(value.scope())
    )
  }

  static func capture(_ value: any NativeEnrollmentFailureProtocol) -> RetainedEnrollmentFailure {
    RetainedEnrollmentFailure(
      crypto: value.crypto().map { capture($0) },
      ioDiagnostic: value.ioDiagnostic(),
      kind: capture(value.kind()),
      storage: value.storage().map { capture($0) },
      wire: value.wire().map { capture($0) },
      worker: value.worker().map { capture($0) }
    )
  }

  static func capture(_ value: any NativeEnrollmentReceiptProtocol) -> RetainedEnrollmentReceipt {
    RetainedEnrollmentReceipt(
      accessEpoch: value.accessEpoch(),
      attemptFailure: value.attemptFailure().map { capture($0) },
      attemptState: value.attemptState().map { capture($0) },
      audience: value.audience(),
      credential: value.credential(),
      organization: value.organization(),
      phase: capture(value.phase()),
      publicIntent: capture(value.publicIntent()),
      receiver: value.receiver(),
      resource: value.resource(),
      terminalCause: value.terminalCause().map { capture($0) }
    )
  }

  static func capture(_ value: any NativeEntryKeyProtocol) -> RetainedEntryKey {
    RetainedEntryKey(
      creation: value.creation(),
      id: value.id()
    )
  }

  static func capture(_ value: any NativePrivateStateFailureProtocol) -> RetainedPrivateStateFailure
  {
    RetainedPrivateStateFailure(
      keyPublication: value.keyPublication().map { capture($0) },
      kind: capture(value.kind()),
      publication: value.publication().map { capture($0) }
    )
  }

  static func capture(_ value: any NativePublicIntentProtocol) -> RetainedPublicIntent {
    RetainedPublicIntent(
      attempt: value.attempt(),
      consent: value.consent(),
      consentClass: capture(value.consentClass()),
      consentClassName: value.consentClassName(),
      expiryMs: value.expiryMs(),
      generation: value.generation(),
      invitation: value.invitation()
    )
  }

  static func capture(_ value: any NativeLocalEnrollmentProtocol) -> RetainedLocalEnrollment {
    RetainedLocalEnrollment(
      publicIntent: capture(value.publicIntent()), deviceKey: value.deviceKey(),
      gatewayPin: value.gatewayPin(), issued: value.issued().map { capture($0) })
  }

  static func capture(_ value: any NativeLocalIssuedEnrollmentProtocol)
    -> RetainedLocalIssuedEnrollment
  {
    RetainedLocalIssuedEnrollment(credential: value.credential(), receiver: value.receiver())
  }

  static func capture(_ value: any NativePublicationFailureProtocol) -> RetainedPublicationFailure {
    RetainedPublicationFailure(
      cleanup: value.cleanup().map { capture($0) },
      effect: capture(value.effect()),
      primary: capture(value.primary()),
      reconciliation: value.reconciliation().map { capture($0) },
      step: capture(value.step())
    )
  }

  static func capture(_ value: any NativePurgeProtocol) -> RetainedPurge {
    RetainedPurge(
      catalogueEntries: value.catalogueEntries(),
      observedAtMs: value.observedAtMs(),
      receiver: value.receiver(),
      records: value.records(),
      transcripts: value.transcripts()
    )
  }

  static func capture(_ value: any NativeReadProtocol) -> RetainedRead {
    RetainedRead(
      complete: value.complete(),
      conversations: value.conversations(),
      failure: value.failure().map { capture($0) },
      moved: value.moved(),
      withdrawn: value.withdrawn()
    )
  }

  static func capture(_ value: any NativeRefreshProtocol) -> RetainedRefresh {
    RetainedRefresh(
      initial: capture(value.initial()),
      read: value.read().map { capture($0) },
      recheck: value.recheck().map { capture($0) },
      selectionFailure: value.selectionFailure().map { capture($0) }
    )
  }

  static func capture(_ value: any NativeRetryProtocol) -> RetainedRetry {
    RetainedRetry(
      original: capture(value.original()),
      retried: capture(value.retried())
    )
  }

  static func capture(_ value: any NativeScopeProtocol) -> RetainedScope {
    RetainedScope(
      accessEpoch: value.accessEpoch(),
      incarnation: value.incarnation(),
      origin: value.origin(),
      receiver: value.receiver(),
      schema: value.schema(),
      stream: value.stream()
    )
  }

  static func capture(_ value: any NativeSessionFailureProtocol) -> RetainedSessionFailure {
    RetainedSessionFailure(
      cache: value.cache().map { capture($0) },
      enrollment: value.enrollment().map { capture($0) },
      kind: capture(value.kind()),
      privateState: value.privateState().map { capture($0) },
      runtimeDiagnostic: value.runtimeDiagnostic(),
      ownerStatus: value.ownerStatus().map { capture($0) },
      ownerSelection: value.ownerSelection().map { capture($0) },
      product: value.product().map { capture($0) }
    )
  }

  static func capture(_ value: any NativeStatusProtocol) -> RetainedStatus {
    RetainedStatus(
      completionCaptured: value.completionCaptured(),
      failure: value.failure().map { capture($0) },
      purge: value.purge().map { capture($0) },
      purgeAttempted: value.purgeAttempted(),
      purgeFailure: value.purgeFailure().map { capture($0) },
      receipt: value.receipt().map { capture($0) },
      owner: value.owner().map { capture($0) }
    )
  }

  static func capture(_ value: any NativeWireFailureProtocol) -> RetainedWireFailure {
    RetainedWireFailure(
      correlation: value.correlation().map { capture($0) },
      kind: capture(value.kind())
    )
  }

}
