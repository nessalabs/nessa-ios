import Foundation

/// Serializes profile effects while the injected gateway and native owners retain their authority.
public actor PhoneProfileCoordinator: PhoneProfileCoordinating {
  private struct NativeOwner: Sendable {
    let id = UUID()
    let profileID: UUID
    let session: any RetainedSession
  }
  private let profiles: any PhoneProfileStoring
  private let credentials: any PhoneProfileCredentialStoring
  private let locations: any PhoneNativeLocationPreparing
  private let identity: any AuthenticatedGatewaySessionProviding
  private let pairing: any GatewayPairingManaging
  private let factory: any RetainedSessionFactory
  private let withdrawal: any PhoneSnapshotWithdrawing
  private let revision: @Sendable () -> UUID
  private var registry: PhoneProfiles?
  private var native: NativeOwner?
  private var admission: UUID?
  private var closing = false
  private var closeTask: Task<Void, Error>?
  private var settled: [CheckedContinuation<Void, Never>] = []
  private var needsRecovery = false
  // These capture the admitted operation's evidence, never a new account's result.
  private var source: AuthenticatedGatewaySession?
  private var accountAnchor: GatewaySessionSnapshot.Identity?
  private var observedOwner: GatewayPairingStatus?
  private var observedNative: RetainedStatus?
  private var observedRefresh: RetainedRefresh?
  private var local: RetainedLocalEnrollment?
  private var admittedLocal: RetainedLocalEnrollment?
  private var stopped: GatewayPairingActivationStop?

  public init(
    profiles: any PhoneProfileStoring, credentials: any PhoneProfileCredentialStoring,
    locations: any PhoneNativeLocationPreparing, identity: any AuthenticatedGatewaySessionProviding,
    pairing: any GatewayPairingManaging, factory: any RetainedSessionFactory,
    withdrawal: any PhoneSnapshotWithdrawing, revision: @escaping @Sendable () -> UUID = { UUID() }
  ) {
    self.profiles = profiles
    self.credentials = credentials
    self.locations = locations
    self.identity = identity
    self.pairing = pairing
    self.factory = factory
    self.withdrawal = withdrawal
    self.revision = revision
  }

  deinit {
    // A last UI owner must not perform physical drain on the UI executor.
    if let native { Task.detached { try await native.session.close() } }
  }

  public func restore() async throws -> PhoneProfileSnapshot? {
    try await perform(recovering: true) { coordinator, token in
      let saved = try await coordinator.profiles.load()
      try coordinator.checkAdmission(token)
      if let old = coordinator.registry, old != saved {
        try await coordinator.releaseNative(token)
      }
      coordinator.registry = saved
      guard let saved else { return nil }
      try saved.validate()
      // Re-publish even visible bytes: a prior writer may have failed its durability step.
      try await coordinator.publish(coordinator.selected(), token: token)
      coordinator.needsRecovery = false
      let profile = try coordinator.selected()
      _ = try await coordinator.credentials.load(reference: profile.credentialReference)
      try await coordinator.check(token)
      if profile.phase == .retired {
        try await coordinator.suppress(profile, token: token)
        return try coordinator.snapshot()
      }
      guard profile.phase == .prepared else {
        throw PhoneProfileCoordinationRefusal.knownInvitationNeedsRecovery
      }
      try await coordinator.captureNative(token)
      return try coordinator.snapshot()
    }
  }

  public func prepare(_ desired: PhoneProfile, credential: String, on lease: GatewayConnectionLease)
    async throws -> PhoneProfileSnapshot
  {
    try await perform(on: lease, preparing: desired) { coordinator, token in
      guard coordinator.source?.snapshot.identity == desired.identity else {
        throw PhoneProfileCoordinationRefusal.accountChanged
      }
      if coordinator.registry == nil {
        coordinator.registry = try await coordinator.profiles.load()
        try await coordinator.check(token)
      }
      try await coordinator.releaseNative(token)
      do {
        coordinator.registry = try await PhoneProfilePreparation(
          profiles: coordinator.profiles, credentials: coordinator.credentials,
          revision: coordinator.revision
        ).prepare(desired, credential: credential, replacing: coordinator.registry)
      } catch {
        coordinator.needsRecovery = true
        throw error
      }
      try await coordinator.check(token)
      try await coordinator.captureNative(token)
      return try coordinator.snapshot()
    }
  }

  public func startPairing(on lease: GatewayConnectionLease) async throws -> PhoneProfileSnapshot {
    try await perform(on: lease) { coordinator, token in
      try await coordinator.captureNative(token)
      let profile = try coordinator.activeProfile()
      guard profile.creationAttempt == nil, profile.pairingStatus == nil, coordinator.local == nil,
        profile.nativeReceiver == nil
      else { throw PhoneProfileCoordinationRefusal.knownInvitationNeedsRecovery }
      try await coordinator.publish(
        profile.recording(
          pairingStatus: nil, nativeReceiver: nil, nativeStatus: profile.lastNativeStatus,
          recoveredPurge: nil, retired: false, creationAttempt: token), token: token)
      let receipt = try await coordinator.pairing.createDevice(on: lease)
      coordinator.observedOwner = receipt.value.status
      try coordinator.validateSource(receipt.source)
      try await coordinator.check(token)
      try PhonePairingCorrelation.validate(receipt.value.status, profile: coordinator.selected())
      try await coordinator.saveOwner(receipt.value.status, token: token)
      let native = try await coordinator.owner(token)
      let completion = try await native.session.enroll(code: receipt.value.code)
      coordinator.observedNative = .init(
        completionCaptured: true, failure: nil, purge: nil, purgeAttempted: false,
        purgeFailure: nil, receipt: completion)
      try await coordinator.check(token)
      try await coordinator.captureNative(token)
      return try coordinator.snapshot()
    }
  }

  public func resolveInvitation(_ invitation: Data, on lease: GatewayConnectionLease) async throws
    -> PhoneProfileSnapshot
  {
    try await perform(on: lease) { coordinator, token in
      try await coordinator.captureNative(token)
      let profile = try coordinator.activeProfile()
      guard coordinator.local == nil, profile.pairingStatus == nil, profile.nativeReceiver == nil
      else {
        throw PhoneProfileCoordinationRefusal.knownInvitationNeedsRecovery
      }
      let receipt = try await coordinator.pairing.pairingStatus(invitation, on: lease)
      coordinator.observedOwner = receipt.value
      try coordinator.validateSource(receipt.source)
      try await coordinator.check(token)
      guard receipt.value.invitationID == invitation else {
        throw PhoneProfileCoordinationRefusal.correlationChanged
      }
      try PhonePairingCorrelation.validate(receipt.value, profile: profile)
      try await coordinator.saveOwner(receipt.value, token: token)
      return try coordinator.snapshot()
    }
  }

  public func observePairing(on lease: GatewayConnectionLease) async throws -> PhoneProfileSnapshot
  {
    try await perform(on: lease) { coordinator, token in
      try await coordinator.readOwner(on: lease, token: token)
      try await coordinator.captureNative(token)
      return try coordinator.snapshot()
    }
  }

  public func approve(_ confirmation: PhonePairingConfirmation, on lease: GatewayConnectionLease)
    async throws -> PhoneProfileSnapshot
  {
    try await perform(on: lease) { coordinator, token in
      try await coordinator.captureNative(token)
      try await coordinator.readOwner(on: lease, token: token)
      guard try coordinator.snapshot().confirmation == confirmation else {
        throw PhoneProfileCoordinationRefusal.confirmationChanged
      }
      let receipt = try await coordinator.pairing.approvePairing(
        confirmation.invitation, deviceKey: confirmation.deviceKey, on: lease)
      coordinator.observedOwner = receipt.value.status
      coordinator.stopped = receipt.value.activationStopped
      try coordinator.validateSource(receipt.source)
      try await coordinator.check(token)
      try await coordinator.saveOwner(receipt.value.status, token: token)
      try await coordinator.captureNative(token)
      return try coordinator.snapshot()
    }
  }

  public func cancelPairing(on lease: GatewayConnectionLease) async throws -> PhoneProfileSnapshot {
    try await perform(on: lease) { coordinator, token in
      let profile = try coordinator.activeProfile()
      guard let invitation = profile.pairingStatus?.invitationID else {
        throw PhoneProfileCoordinationRefusal.noInvitation
      }
      let receipt = try await coordinator.pairing.cancelPairing(invitation, on: lease)
      coordinator.observedOwner = receipt.value
      try coordinator.validateSource(receipt.source)
      try await coordinator.check(token)
      try await coordinator.saveOwner(receipt.value, token: token)
      try await coordinator.captureNative(token)
      return try coordinator.snapshot()
    }
  }

  public func discardUnenrolled() async throws -> PhoneProfileSnapshot {
    try await perform { coordinator, token in
      let profile = try coordinator.activeProfile()
      let owner = try await coordinator.owner(token)
      coordinator.local = try await owner.session.localEnrollment()
      try await coordinator.check(token)
      guard coordinator.local == nil, profile.nativeReceiver == nil,
        profile.lastNativeStatus?.receipt == nil, profile.recoveredPurge == nil,
        profile.pairingStatus?.claimedDeviceKey == nil,
        profile.pairingStatus?.credentialID == nil, profile.pairingStatus?.receiver == nil
      else { throw PhoneProfileCoordinationRefusal.knownInvitationNeedsRecovery }
      try await coordinator.suppress(profile, token: token)
      try await coordinator.publish(
        profile.recording(
          pairingStatus: profile.pairingStatus, nativeReceiver: nil, nativeStatus: nil,
          recoveredPurge: nil, retired: true, retirementReason: .userDiscarded), token: token)
      return try coordinator.snapshot()
    }
  }

  public func refresh(on lease: GatewayConnectionLease?) async throws -> PhoneProfileSnapshot {
    try await perform(on: lease) { coordinator, token in
      let owner = try await coordinator.captureLocal(token)
      let prior = coordinator.local
      let refresh = try await owner.session.refresh()
      coordinator.observedRefresh = refresh
      coordinator.observedNative = refresh.recheck ?? refresh.initial
      try await coordinator.check(token)
      let profile = try coordinator.selected()
      try coordinator.validateNative(refresh.initial, local: prior, profile: profile)
      if let recheck = refresh.recheck {
        try coordinator.validateNative(recheck, local: prior, profile: profile)
      }
      try await coordinator.captureNative(token, status: coordinator.observedNative)
      return try coordinator.snapshot()
    }
  }

  public func cataloguePage(after: RetainedEntryKey?, maximum: UInt32) async throws
    -> PhoneScopedRetention<RetainedCataloguePage?>
  {
    try await perform { coordinator, token in
      try await coordinator.captureNative(token)
      let profile = try coordinator.readableProfile()
      let owner = try await coordinator.owner(token)
      let value = try await owner.session.cataloguePage(after: after, maximum: maximum)
      try await coordinator.check(token)
      return .init(
        profileID: profile.id, revision: try coordinator.selectedRegistry().revision, value: value)
    }
  }

  public func transcript(conversation: String, revision: UUID) async throws
    -> PhoneScopedRetention<RetainedTranscript>
  {
    try await perform { coordinator, token in
      try await coordinator.captureNative(token)
      let profile = try coordinator.readableProfile()
      let owner = try await coordinator.owner(token)
      let value = try await owner.session.transcript(conversation: conversation, revision: revision)
      try await coordinator.check(token)
      return .init(
        profileID: profile.id, revision: try coordinator.selectedRegistry().revision, value: value)
    }
  }

  public func close() async throws {
    if let closeTask { return try await closeTask.value }
    closing = true
    let task = Task { try await self.drain() }
    closeTask = task
    try await task.value
  }

  private func drain() async throws {
    var failures: [PhoneProfileCloseFailure.Captured] = []
    let captured = native
    if let captured {
      do { try await captured.session.close() } catch {
        failures.append(.init(profileID: captured.profileID, underlying: error))
      }
    }
    if admission != nil {
      await withCheckedContinuation { settled.append($0) }
    }
    if let late = native, late.id != captured?.id {
      do { try await late.session.close() } catch {
        failures.append(.init(profileID: late.profileID, underlying: error))
      }
    }
    guard failures.isEmpty else { throw PhoneProfileCloseFailure(failures: failures) }
    native = nil
  }

  private func perform<Value: Sendable>(
    on lease: GatewayConnectionLease? = nil, recovering: Bool = false,
    preparing: PhoneProfile? = nil,
    _ operation: (isolated PhoneProfileCoordinator, UUID) async throws -> Value
  ) async throws -> Value {
    guard !closing else { throw PhoneProfileCoordinationRefusal.closed }
    guard admission == nil else { throw PhoneProfileCoordinationRefusal.busy }
    guard recovering || !needsRecovery else {
      throw PhoneProfileCoordinationRefusal.knownInvitationNeedsRecovery
    }
    let token = UUID()
    admission = token
    source = nil
    accountAnchor = preparing?.identity
    observedOwner = nil
    observedNative = nil
    observedRefresh = nil
    admittedLocal = nil
    stopped = nil
    defer {
      admission = nil
      for waiter in settled { waiter.resume() }
      settled.removeAll()
    }
    do {
      if !recovering, registry == nil {
        registry = try await profiles.load()
        try checkAdmission(token)
        try registry?.validate()
      }
      if let lease {
        source = try await identity.authenticatedSession(for: lease)
        guard source?.connection == lease else {
          throw PhoneProfileCoordinationRefusal.receiptSourceChanged
        }
        if accountAnchor == nil, registry != nil { accountAnchor = try selected().identity }
        if let accountAnchor, accountAnchor != source?.snapshot.identity {
          throw PhoneProfileCoordinationRefusal.accountChanged
        }
      }
      if recovering { try checkAdmission(token) } else { try await check(token) }
      let result = try await operation(self, token)
      try await check(token)
      return result
    } catch {
      throw PhoneProfileCoordinationFailure(
        operation: token, profileID: registry?.selected, source: source,
        owner: observedOwner, nativeStatus: observedNative, underlying: error,
        nativeRefresh: observedRefresh, local: admittedLocal ?? local)
    }
  }

  private func checkAdmission(_ token: UUID) throws {
    guard admission == token, !closing else { throw PhoneProfileCoordinationRefusal.closed }
  }
  private func check(_ token: UUID) async throws {
    try checkAdmission(token)
    let loaded = try await profiles.load()
    try checkAdmission(token)
    guard loaded == registry else { throw PhoneProfileCoordinationRefusal.profileChanged }
    if let source {
      let current = try await identity.authenticatedSession(for: source.connection)
      try checkAdmission(token)
      guard current == source else { throw PhoneProfileCoordinationRefusal.accountChanged }
      if let accountAnchor, accountAnchor != current.snapshot.identity {
        throw PhoneProfileCoordinationRefusal.accountChanged
      }
    }
  }
  private func selectedRegistry() throws -> PhoneProfiles {
    guard let registry else { throw PhoneProfileCoordinationRefusal.noProfile }
    try registry.validate()
    return registry
  }
  private func selected() throws -> PhoneProfile {
    let registry = try selectedRegistry()
    guard let profile = registry.profiles.first(where: { $0.id == registry.selected }) else {
      throw PhoneProfileCoordinationRefusal.noProfile
    }
    return profile
  }
  private func activeProfile() throws -> PhoneProfile {
    let profile = try selected()
    guard profile.phase == .prepared else { throw PhoneProfileCoordinationRefusal.retired }
    return profile
  }
  private func readableProfile() throws -> PhoneProfile {
    let profile = try activeProfile()
    guard profile.nativeReceiver != nil else {
      throw PhoneProfileCoordinationRefusal.receiverUnavailable
    }
    return profile
  }
  private func owner(_ token: UUID) async throws -> NativeOwner {
    let profile = try activeProfile()
    if let source, profile.identity != source.snapshot.identity {
      throw PhoneProfileCoordinationRefusal.accountChanged
    }
    if let native {
      guard native.profileID == profile.id else {
        throw PhoneProfileCoordinationRefusal.profileChanged
      }
      return native
    }
    _ = try await credentials.load(reference: profile.credentialReference)
    try await check(token)
    let location = try await locations.prepare(profile)
    try await check(token)
    let session = try await factory.open(location)
    // Install before checking closure: the shared close owner must also drain late construction.
    let opened = NativeOwner(profileID: profile.id, session: session)
    native = opened
    try await check(token)
    return opened
  }
  private func releaseNative(_ token: UUID) async throws {
    if let captured = native {
      try await captured.session.close()
      try checkAdmission(token)
      guard native?.id == captured.id else { throw PhoneProfileCoordinationRefusal.profileChanged }
      native = nil
      local = nil
    }
  }
  private func publish(_ profile: PhoneProfile, token: UUID) async throws {
    try await check(token)
    let old = try selectedRegistry()
    let next = PhoneProfiles(
      revision: revision(), selected: old.selected,
      profiles: old.profiles.map { $0.id == profile.id ? profile : $0 })
    do { try await profiles.save(next, replacing: old) } catch {
      needsRecovery = true
      throw error
    }
    registry = next
    try await check(token)
  }
  private func validateSource(_ actual: AuthenticatedGatewaySession) throws {
    guard actual == source else { throw PhoneProfileCoordinationRefusal.receiptSourceChanged }
  }
  private func saveOwner(_ status: GatewayPairingStatus, token: UUID) async throws {
    let profile = try selected()
    try PhonePairingCorrelation.validate(status, profile: profile)
    if let local { try PhonePairingCorrelation.validate(status, local: local, profile: profile) }
    try await publish(
      profile.recording(
        pairingStatus: status, nativeReceiver: profile.nativeReceiver,
        nativeStatus: profile.lastNativeStatus, recoveredPurge: profile.recoveredPurge,
        retired: profile.phase == .retired), token: token)
  }
  private func readOwner(on lease: GatewayConnectionLease, token: UUID) async throws {
    let profile = try activeProfile()
    guard let invitation = profile.pairingStatus?.invitationID else {
      throw PhoneProfileCoordinationRefusal.noInvitation
    }
    let receipt = try await pairing.pairingStatus(invitation, on: lease)
    observedOwner = receipt.value
    try validateSource(receipt.source)
    try await check(token)
    try await saveOwner(receipt.value, token: token)
  }
  private func captureLocal(_ token: UUID) async throws -> NativeOwner {
    let owner = try await owner(token)
    local = try await owner.session.localEnrollment()
    if let local {
      if let prior = admittedLocal {
        guard prior.publicIntent == local.publicIntent, prior.deviceKey == local.deviceKey,
          prior.gatewayPin == local.gatewayPin, prior.issued == nil || prior.issued == local.issued
        else { throw PhoneProfileCoordinationRefusal.correlationChanged }
      } else {
        admittedLocal = local
      }
    }
    try await check(token)
    let profile = try selected()
    if let local, let status = profile.pairingStatus {
      try PhonePairingCorrelation.validate(status, local: local, profile: profile)
    }
    if let receiver = local?.issued?.receiver {
      if let saved = profile.nativeReceiver {
        guard PhonePairingCorrelation.equal(saved, receiver) else {
          throw PhoneProfileCoordinationRefusal.correlationChanged
        }
      } else {
        // status and refresh can unlink revoked private state. Save its selector first.
        try await publish(
          profile.recording(
            pairingStatus: profile.pairingStatus, nativeReceiver: receiver,
            nativeStatus: profile.lastNativeStatus, recoveredPurge: profile.recoveredPurge,
            retired: false), token: token)
      }
    }
    return owner
  }
  private func captureNative(_ token: UUID, status captured: RetainedStatus? = nil) async throws {
    let owner = try await captureLocal(token)
    let profile = try selected()
    var recovered = profile.recoveredPurge
    if let receiver = profile.nativeReceiver {
      recovered = try await owner.session.purgeReceipt(receiver: receiver) ?? recovered
      try await check(token)
    }
    let status: RetainedStatus
    if let captured { status = captured } else { status = try await owner.session.status() }
    observedNative = status
    try await check(token)
    try validateNative(status, local: admittedLocal ?? local, profile: profile)
    if let saved = profile.nativeReceiver, let issued = local?.issued?.receiver,
      !PhonePairingCorrelation.equal(saved, issued)
    {
      throw PhoneProfileCoordinationRefusal.correlationChanged
    }
    let receiver = profile.nativeReceiver ?? local?.issued?.receiver ?? status.receipt?.receiver
    let updated = profile.recording(
      pairingStatus: profile.pairingStatus, nativeReceiver: receiver,
      nativeStatus: profile.lastNativeStatus?.receipt?.phase == .terminal
        ? profile.lastNativeStatus : status, recoveredPurge: recovered, retired: false)
    if updated.hasRetirementEvidence {
      // Preserve receiver and terminal evidence before cleanup can fail or the app exits.
      try await publish(updated, token: token)
      // Fence legacy hydration even if the following metadata publication fails.
      try await suppress(updated, token: token)
      try await publish(updated.changingPhase(to: .retired), token: token)
    } else {
      try await publish(updated, token: token)
    }
  }
  private func validateNative(
    _ status: RetainedStatus, local: RetainedLocalEnrollment?, profile: PhoneProfile
  ) throws {
    guard let receipt = status.receipt else { return }
    try PhonePairingCorrelation.validate(receipt, profile: profile)
    if let local {
      guard receipt.publicIntent == local.publicIntent else {
        throw PhoneProfileCoordinationRefusal.correlationChanged
      }
      if let issued = local.issued {
        if let receiver = receipt.receiver,
          !PhonePairingCorrelation.equal(receiver, issued.receiver)
        {
          throw PhoneProfileCoordinationRefusal.correlationChanged
        }
        if let credential = receipt.credential,
          !PhonePairingCorrelation.equal(credential, issued.credential)
        {
          throw PhoneProfileCoordinationRefusal.correlationChanged
        }
      }
    }
  }
  private func suppress(_ profile: PhoneProfile, token: UUID) async throws {
    let credential = try await credentials.load(reference: profile.credentialReference)
    try await check(token)
    try await withdrawal.withdraw(
      .init(
        address: profile.productAddress, credential: credential, instance: profile.instance))
    try await check(token)
  }
  private func snapshot() throws -> PhoneProfileSnapshot {
    try .init(
      registry: selectedRegistry(), local: local, nativeStatus: observedNative,
      source: source, activationStopped: stopped, nativeRefresh: observedRefresh)
  }
}
