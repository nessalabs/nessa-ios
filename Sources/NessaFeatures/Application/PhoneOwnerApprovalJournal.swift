import Foundation

/// Owns original durable preparation only. It cannot select, authorize or connect a phone.
public actor PhoneOwnerApprovalJournal {
  private let store: any PhoneOwnerApprovalStoring
  private let native: any PhoneOwnerApprovalPreparing
  private let source: any AuthenticatedGatewaySessionProviding
  private let makeID: @Sendable () -> UUID
  private let maximumRecords: Int
  private var admission: UUID?
  private var operation: Task<PhoneOwnerApprovalRecord, Error>?
  private var closeTask: Task<Void, Error>?
  private var capturedSource: AuthenticatedGatewaySession?
  private var original: PhoneOwnerApprovalReservation?
  private var observed: PhoneOwnerApprovalPreparation?
  public init(
    store: any PhoneOwnerApprovalStoring, native: any PhoneOwnerApprovalPreparing,
    source: any AuthenticatedGatewaySessionProviding, maximumRecords: Int = 64,
    makeID: @escaping @Sendable () -> UUID = { UUID() }
  ) {
    precondition(maximumRecords > 0)
    self.store = store
    self.native = native
    self.source = source
    self.maximumRecords = maximumRecords
    self.makeID = makeID
  }
  deinit {
    if closeTask == nil {
      let native = native
      Task.detached { try? await native.close() }
    }
  }

  /// Historical read only. No preparation, source authentication or durable success is inferred.
  public func records() async throws -> [PhoneOwnerApprovalRecord] {
    try validate(try await store.load())
  }

  public func reserve(
    _ context: PhoneOwnerApprovalContext, on lease: GatewayConnectionLease,
    current: @escaping @Sendable () async throws -> Void
  ) async throws -> PhoneOwnerApprovalReservation {
    let record = try await perform { journal, token in
      try await journal.reserveAdmitted(context, on: lease, current: current, token: token)
    }
    return record.reservation
  }

  public func prepare(
    _ reservation: PhoneOwnerApprovalReservation, on lease: GatewayConnectionLease,
    current: @escaping @Sendable () async throws -> Void
  ) async throws -> PhoneOwnerApprovalPreparation {
    let record = try await perform { journal, token in
      try await journal.prepareAdmitted(reservation, on: lease, current: current, token: token)
    }
    guard let preparation = record.preparation else { throw PhoneOwnerApprovalRefusal.invalid }
    return preparation
  }

  /// Observer cancellation cannot abandon close or its admitted factual publication.
  public func close() async throws {
    if let closeTask { return try await closeTask.value }
    let active = operation
    let native = native
    let closing = Task {
      let result: Result<Void, Error>
      do {
        try await native.close()
        result = .success(())
      } catch { result = .failure(error) }
      _ = await active?.result
      try result.get()
    }
    closeTask = closing
    try await closing.value
  }

  private func perform(
    _ body:
      @escaping @Sendable (PhoneOwnerApprovalJournal, UUID) async throws
      -> PhoneOwnerApprovalRecord
  ) async throws -> PhoneOwnerApprovalRecord {
    guard closeTask == nil else { throw PhoneOwnerApprovalRefusal.closed }
    guard admission == nil else { throw PhoneOwnerApprovalRefusal.busy }
    try Task.checkCancellation()
    let token = UUID()
    admission = token
    capturedSource = nil
    original = nil
    observed = nil
    let owned = Task { try await self.run(body, token: token) }
    operation = owned
    return try await owned.value
  }
  private func run(
    _ body: @Sendable (PhoneOwnerApprovalJournal, UUID) async throws -> PhoneOwnerApprovalRecord,
    token: UUID
  ) async throws -> PhoneOwnerApprovalRecord {
    defer {
      if admission == token {
        admission = nil
        operation = nil
      }
    }
    do { return try await body(self, token) } catch {
      throw PhoneOwnerApprovalFailure(
        source: capturedSource, reservation: original, preparation: observed, underlying: error)
    }
  }
  private func check(_ token: UUID) throws {
    guard admission == token, closeTask == nil else { throw PhoneOwnerApprovalRefusal.closed }
  }
  private func validate(_ records: [PhoneOwnerApprovalRecord]) throws -> [PhoneOwnerApprovalRecord]
  {
    guard records.count <= maximumRecords,
      Set(records.map { $0.reservation.requestID }).count == records.count,
      Set(records.map { $0.reservation.profileID }).count == records.count
    else { throw PhoneOwnerApprovalRefusal.invalid }
    for (index, record) in records.enumerated() {
      try record.validate()
      guard
        !records.prefix(index).contains(where: {
          $0.reservation.context.bootstrap == record.reservation.context.bootstrap
        })
      else {
        throw PhoneOwnerApprovalRefusal.invalid
      }
    }
    return records
  }
  private func capture(
    _ context: PhoneOwnerApprovalContext, on lease: GatewayConnectionLease,
    current: @Sendable () async throws -> Void, token: UUID
  ) async throws -> AuthenticatedGatewaySession {
    try context.validate()
    try check(token)
    try await current()
    try check(token)
    let captured = try await source.authenticatedSession(for: lease)
    capturedSource = captured
    try check(token)
    try await current()
    try check(token)
    guard captured.connection == lease, captured.snapshot.identity == context.bootstrap else {
      throw PhoneOwnerApprovalRefusal.changed
    }
    return captured
  }
  private func currentSource(
    _ captured: AuthenticatedGatewaySession, current: @Sendable () async throws -> Void, token: UUID
  ) async throws {
    try check(token)
    try await current()
    try check(token)
    let fresh = try await source.authenticatedSession(for: captured.connection)
    try check(token)
    try await current()
    try check(token)
    guard fresh == captured else { throw PhoneOwnerApprovalRefusal.changed }
  }

  private func reserveAdmitted(
    _ context: PhoneOwnerApprovalContext, on lease: GatewayConnectionLease,
    current: @Sendable () async throws -> Void, token: UUID
  ) async throws -> PhoneOwnerApprovalRecord {
    let captured = try await capture(context, on: lease, current: current, token: token)
    let prior = try validate(try await store.load())
    try await currentSource(captured, current: current, token: token)
    let record: PhoneOwnerApprovalRecord
    let next: [PhoneOwnerApprovalRecord]
    let pending = prior.filter { $0.reservation.context.bootstrap == context.bootstrap }
    if let existing = pending.first {
      original = existing.reservation
      guard pending.count == 1, existing.reservation.context == context else {
        throw PhoneOwnerApprovalRefusal.unresolved
      }
      record = existing
      next = prior
    } else {
      guard prior.count < maximumRecords else { throw PhoneOwnerApprovalRefusal.capacity }
      let reservation = PhoneOwnerApprovalReservation(
        profileID: makeID(), requestID: makeID(), context: context)
      original = reservation
      record = .init(reservation: reservation)
      next = prior + [record]
      _ = try validate(next)
    }
    try await store.publish(next, replacing: prior)
    try await currentSource(captured, current: current, token: token)
    return record
  }

  private func prepareAdmitted(
    _ reservation: PhoneOwnerApprovalReservation, on lease: GatewayConnectionLease,
    current: @Sendable () async throws -> Void, token: UUID
  ) async throws -> PhoneOwnerApprovalRecord {
    original = reservation
    let captured = try await capture(reservation.context, on: lease, current: current, token: token)
    let prior = try validate(try await store.load())
    try await currentSource(captured, current: current, token: token)
    guard let index = prior.firstIndex(where: { $0.reservation == reservation }) else {
      throw PhoneOwnerApprovalRefusal.noOriginal
    }
    // Visible bytes from an earlier failed write must be durably republished first.
    try await store.publish(prior, replacing: prior)
    try await currentSource(captured, current: current, token: token)
    let prepared = try await native.prepare(reservation)
    observed = prepared
    try prepared.validate()
    guard prepared.reservation == reservation,
      prior[index].preparation == nil || prior[index].preparation == prepared
    else { throw PhoneOwnerApprovalRefusal.changed }
    var next = prior
    next[index] = .init(reservation: reservation, preparation: prepared)
    // Original native facts remain attributable after observer/source retirement.
    try await store.publish(next, replacing: prior)
    try await currentSource(captured, current: current, token: token)
    return next[index]
  }
}
