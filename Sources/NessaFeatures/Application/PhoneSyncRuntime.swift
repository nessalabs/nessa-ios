import Foundation

/// Ephemeral connection material stays outside Codable and published UI state.
public struct PhoneProductConnection: Sendable {
  public let address: String
  public let credential: String
  public let instance: String
  public init(address: String, credential: String, instance: String) {
    self.address = address
    self.credential = credential
    self.instance = instance
  }
}
public struct PhoneSyncStartup: Sendable {
  public let snapshot: PhoneProfileSnapshot
  public let connection: PhoneProductConnection?
  public init(snapshot: PhoneProfileSnapshot, connection: PhoneProductConnection?) {
    self.snapshot = snapshot
    self.connection = connection
  }
}
public enum PhoneSyncRuntimeRefusal: Error, Equatable, Sendable {
  case busy, suspended, closed, changed, unavailable, preparationRequired
}
public struct PhoneSyncRuntimeFailure: Error, Sendable {
  public let operation: UUID
  public let snapshot: PhoneProfileSnapshot?
  public let underlying: any Error
  public init(operation: UUID, snapshot: PhoneProfileSnapshot?, underlying: any Error) {
    self.operation = operation
    self.snapshot = snapshot
    self.underlying = underlying
  }
}
public protocol PhoneSyncRunning: PhoneProfileCoordinating {
  func startup() async throws -> PhoneSyncStartup?
  func savedProfiles() async throws -> PhoneProfiles?
  /// Temporary physical drain. Only actual success permits a new child on foreground.
  func suspend() async throws
}

/// Application lifetime owns the child; Rust remains the owner of retained state and permission.
public actor PhoneSyncRuntime: PhoneSyncRunning {
  private let factory: @Sendable () -> any PhoneProfileCoordinating
  private let profiles: any PhoneProfileStoring
  private let credentials: any PhoneProfileCredentialStoring
  private var child: (any PhoneProfileCoordinating)?
  private var admission: UUID?
  private var observed: PhoneProfileSnapshot?
  private var suspending = false
  private var closed = false
  private var drainTask: Task<Void, Error>?
  private var settled: [CheckedContinuation<Void, Never>] = []
  public init(
    profiles: any PhoneProfileStoring, credentials: any PhoneProfileCredentialStoring,
    factory: @escaping @Sendable () -> any PhoneProfileCoordinating
  ) {
    self.profiles = profiles
    self.credentials = credentials
    self.factory = factory
  }
  deinit {
    if let child { Task.detached { try await child.close() } }
  }
  public func startup() async throws -> PhoneSyncStartup? {
    try await perform { runtime, token, child in
      guard let snapshot = try await child.restore() else {
        guard try await runtime.profiles.load() == nil else {
          throw PhoneSyncRuntimeRefusal.changed
        }
        try runtime.check(token)
        return nil
      }
      runtime.observed = snapshot
      try runtime.check(token)
      let profile = snapshot.profile
      let connection: PhoneProductConnection?
      if profile.phase == .retired {
        connection = nil
      } else {
        guard profile.phase == .prepared else { throw PhoneSyncRuntimeRefusal.preparationRequired }
        let secret = try await runtime.credentials.load(reference: profile.credentialReference)
        try runtime.check(token)
        connection = .init(
          address: profile.productAddress, credential: secret, instance: profile.instance)
      }
      guard try await runtime.profiles.load() == snapshot.registry else {
        throw PhoneSyncRuntimeRefusal.changed
      }
      try runtime.check(token)
      return .init(snapshot: snapshot, connection: connection)
    }
  }
  public func savedProfiles() async throws -> PhoneProfiles? {
    try await perform { runtime, token, _ in
      let registry = try await runtime.profiles.load()
      try runtime.check(token)
      try registry?.validate()
      return registry
    }
  }
  public func restore() async throws -> PhoneProfileSnapshot? {
    try await perform { runtime, _, child in
      let value = try await child.restore()
      runtime.observed = value
      return value
    }
  }
  public func prepare(_ desired: PhoneProfile, credential: String, on lease: GatewayConnectionLease)
    async throws -> PhoneProfileSnapshot
  {
    try await snapshot { child in
      try await child.prepare(desired, credential: credential, on: lease)
    }
  }
  public func startPairing(on lease: GatewayConnectionLease) async throws -> PhoneProfileSnapshot {
    try await snapshot { child in try await child.startPairing(on: lease) }
  }
  public func resolveInvitation(_ invitation: Data, on lease: GatewayConnectionLease) async throws
    -> PhoneProfileSnapshot
  {
    try await snapshot { child in try await child.resolveInvitation(invitation, on: lease) }
  }
  public func discardUnenrolled() async throws -> PhoneProfileSnapshot {
    try await snapshot { child in try await child.discardUnenrolled() }
  }
  public func observePairing(on lease: GatewayConnectionLease) async throws -> PhoneProfileSnapshot
  {
    try await snapshot { child in try await child.observePairing(on: lease) }
  }
  public func approve(_ confirmation: PhonePairingConfirmation, on lease: GatewayConnectionLease)
    async throws -> PhoneProfileSnapshot
  {
    try await snapshot { child in try await child.approve(confirmation, on: lease) }
  }
  public func cancelPairing(on lease: GatewayConnectionLease) async throws -> PhoneProfileSnapshot {
    try await snapshot { child in try await child.cancelPairing(on: lease) }
  }
  public func refresh(on lease: GatewayConnectionLease?) async throws -> PhoneProfileSnapshot {
    try await snapshot { child in try await child.refresh(on: lease) }
  }
  public func cataloguePage(after: RetainedEntryKey?, maximum: UInt32) async throws
    -> PhoneScopedRetention<RetainedCataloguePage?>
  {
    try await perform { _, _, child in try await child.cataloguePage(after: after, maximum: maximum)
    }
  }
  public func transcript(conversation: String, revision: UUID) async throws
    -> PhoneScopedRetention<RetainedTranscript>
  {
    try await perform { _, _, child in
      try await child.transcript(conversation: conversation, revision: revision)
    }
  }
  private func snapshot(
    _ operation: @Sendable (any PhoneProfileCoordinating) async throws -> PhoneProfileSnapshot
  ) async throws -> PhoneProfileSnapshot {
    try await perform { runtime, _, child in
      let value = try await operation(child)
      runtime.observed = value
      return value
    }
  }
  private func perform<Value: Sendable>(
    _ operation: (isolated PhoneSyncRuntime, UUID, any PhoneProfileCoordinating) async throws ->
      Value
  ) async throws -> Value {
    guard !closed else { throw PhoneSyncRuntimeRefusal.closed }
    guard !suspending else { throw PhoneSyncRuntimeRefusal.suspended }
    guard admission == nil else { throw PhoneSyncRuntimeRefusal.busy }
    let token = UUID()
    admission = token
    observed = nil
    let captured: any PhoneProfileCoordinating
    if let child {
      captured = child
    } else {
      captured = factory()
      child = captured
    }
    defer {
      admission = nil
      for waiter in settled { waiter.resume() }
      settled.removeAll()
    }
    do {
      let value = try await operation(self, token, captured)
      try check(token)
      return value
    } catch {
      throw PhoneSyncRuntimeFailure(operation: token, snapshot: observed, underlying: error)
    }
  }
  private func check(_ token: UUID) throws {
    guard !closed else { throw PhoneSyncRuntimeRefusal.closed }
    guard admission == token, !suspending else { throw PhoneSyncRuntimeRefusal.suspended }
  }
  public func suspend() async throws {
    if let drainTask { return try await drainTask.value }
    if closed { return }
    suspending = true
    let captured = child
    let task = Task { try await self.drain(captured) }
    drainTask = task
    try await task.value
  }
  public func close() async throws {
    closed = true
    if let drainTask { return try await drainTask.value }
    suspending = true
    let captured = child
    let task = Task { try await self.drain(captured) }
    drainTask = task
    try await task.value
  }
  private func drain(_ captured: (any PhoneProfileCoordinating)?) async throws {
    // Failure leaves the child/task strongly owned and the fence closed.
    try await captured?.close()
    if admission != nil { await withCheckedContinuation { settled.append($0) } }
    child = nil
    if !closed {
      suspending = false
      drainTask = nil
    }
  }
}
