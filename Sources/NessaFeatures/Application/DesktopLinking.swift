import Foundation

/// Finds desktops announcing on the local network. Behind a port so the
/// network side is injected.
public protocol GatewayFinding: Sendable {
  /// The desktops heard within `seconds`, each with a numeric address.
  func find(within seconds: Double) async -> [FoundGateway]
}

/// Keeps the one desktop this phone is linked to.
public protocol LinkedDesktopStoring: Sendable {
  func load() async throws -> LinkedDesktop?
  func save(_ desktop: LinkedDesktop) async throws
  func remove() async throws
}

/// Prepares the private directory a desktop's native state lives in.
public protocol LinkedDesktopLocating: Sendable {
  func prepare(id: UUID, address: String) async throws -> RetainedSessionLocation
  /// Remove what pairing left for `id`.
  func discard(id: UUID) async
}

/// Pairs this phone with a desktop by the code the desktop shows, then reads
/// the chats that desktop shares with it. The phone never decides access:
/// the gateway checks the code, the owner approves on the desktop, and every
/// read is checked again there.
public actor DesktopLinking {
  private let finder: any GatewayFinding
  private let store: any LinkedDesktopStoring
  private let locations: any LinkedDesktopLocating
  private let sessions: any RetainedSessionFactory
  private let pause: @Sendable (Double) async throws -> Void
  private let now: @Sendable () -> UInt64
  /// How long a desktop has to answer the search.
  public let findSeconds: Double
  /// How often the desktop is asked whether the owner approved.
  public let statusSeconds: Double

  public init(
    finder: any GatewayFinding, store: any LinkedDesktopStoring,
    locations: any LinkedDesktopLocating, sessions: any RetainedSessionFactory,
    pause: @escaping @Sendable (Double) async throws -> Void = {
      try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000))
    },
    now: @escaping @Sendable () -> UInt64 = {
      UInt64(Date().timeIntervalSince1970 * 1_000)
    },
    findSeconds: Double = 3, statusSeconds: Double = 2
  ) {
    self.finder = finder
    self.store = store
    self.locations = locations
    self.sessions = sessions
    self.pause = pause
    self.now = now
    self.findSeconds = findSeconds
    self.statusSeconds = statusSeconds
  }

  public func linked() async throws -> LinkedDesktop? { try await store.load() }

  /// The desktops on this network.
  public func find() async -> [FoundGateway] {
    await finder.find(within: findSeconds)
  }

  /// Pair with `gateway` using `code`. `progress` hears when the code was
  /// accepted and the owner's approval is awaited. Returns once the desktop
  /// issued this phone its read access; throws a `DesktopLinkFailure`.
  public func link(
    code: String, with gateway: FoundGateway,
    progress: @Sendable (DesktopLinkPhase) async -> Void = { _ in }
  ) async throws -> LinkedDesktop {
    guard let symbols = OrbCode.parse(code) else { throw DesktopLinkFailure.wrongCode }
    let formatted = OrbCode.format(symbols)
    let id = UUID()
    let session: any RetainedSession
    do {
      let location = try await locations.prepare(id: id, address: gateway.address)
      session = try await sessions.open(location)
    } catch {
      await locations.discard(id: id)
      throw Self.failure(error)
    }
    do {
      let desktop = try await enroll(
        session, code: formatted, id: id, gateway: gateway, progress: progress)
      try? await session.close()
      do {
        try await store.save(desktop)
      } catch {
        throw DesktopLinkFailure.storage
      }
      return desktop
    } catch {
      try? await session.close()
      await locations.discard(id: id)
      throw Self.failure(error)
    }
  }

  private func enroll(
    _ session: any RetainedSession, code: String, id: UUID, gateway: FoundGateway,
    progress: @Sendable (DesktopLinkPhase) async -> Void
  ) async throws -> LinkedDesktop {
    var receipt = try await session.enroll(code: code)
    var announced = false
    while true {
      try Task.checkCancellation()
      if let failure = Self.ended(receipt) { throw failure }
      if receipt.phase == .active, let receiver = receipt.receiver, !receiver.isEmpty {
        return LinkedDesktop(
          id: id, name: gateway.name, gateway: gateway.gateway, address: gateway.address,
          receiver: receiver, linkedAtMs: now())
      }
      if !announced, receipt.phase != .pending {
        announced = true
        await progress(.approving(gateway))
      }
      if receipt.publicIntent.expiryMs <= now(), Self.awaitsApproval(receipt.phase) {
        throw DesktopLinkFailure.expired
      }
      try await pause(statusSeconds)
      let status = try await session.status()
      if let failure = status.failure, status.receipt == nil {
        throw Self.enrollmentFailure(failure)
      }
      if let next = status.receipt { receipt = next }
    }
  }

  /// Forget the linked desktop on this phone. Access itself is revoked on
  /// the desktop, in Settings › Linked devices.
  public func unlink() async throws {
    guard let desktop = try await store.load() else { return }
    try await store.remove()
    await locations.discard(id: desktop.id)
  }

  /// The chats `desktop` shares with this phone, read fresh from it.
  public func chats(of desktop: LinkedDesktop) async throws -> [NessaConversation] {
    try await reading(desktop) { session in
      let refresh = try await session.refresh()
      if let failure = refresh.read?.failure { throw Self.readFailure(failure) }
      var conversations: [NessaConversation] = []
      var after: RetainedEntryKey?
      var seen: Set<String> = []
      for _ in 0..<200 {
        guard let page = try await session.cataloguePage(after: after, maximum: 50) else {
          break
        }
        guard page.scope.receiver.utf8.elementsEqual(desktop.receiver.utf8) else {
          throw DesktopLinkFailure.other("receiver changed")
        }
        for entry in page.entries where !entry.deleted && entry.archived != true {
          guard seen.insert(entry.key.id).inserted else { continue }
          conversations.append(
            NessaConversation(
              conversationId: entry.key.id, title: entry.title, preview: entry.preview,
              updatedAtMs: Double(entry.updatedAtMs ?? entry.createdAtMs ?? entry.key.creation),
              running: false))
        }
        guard let next = page.next, next != after else { break }
        after = next
      }
      return conversations.sorted { $0.updatedAtMs > $1.updatedAtMs }
    }
  }

  /// One chat as this phone last read it from `desktop`.
  public func transcript(_ conversation: String, of desktop: LinkedDesktop) async throws
    -> NessaConversationView
  {
    try await reading(desktop) { session in
      let revision = UUID()
      let transcript = try await session.transcript(
        conversation: conversation, revision: revision)
      guard transcript.state == .retained, case .available(let projection) = transcript.view,
        projection.display.conversationId.utf8.elementsEqual(conversation.utf8)
      else { throw DesktopLinkFailure.other("transcript unavailable") }
      return projection.display
    }
  }

  private func reading<Value: Sendable>(
    _ desktop: LinkedDesktop,
    _ body: (any RetainedSession) async throws -> Value
  ) async throws -> Value {
    let session: any RetainedSession
    do {
      let location = try await locations.prepare(id: desktop.id, address: desktop.address)
      session = try await sessions.open(location)
    } catch {
      throw Self.failure(error)
    }
    do {
      let value = try await body(session)
      try? await session.close()
      return value
    } catch {
      try? await session.close()
      throw Self.failure(error)
    }
  }

  // MARK: What the native answers mean here

  private static func awaitsApproval(_ phase: RetainedEnrollmentPhase) -> Bool {
    phase == .pending || phase == .claimed
  }

  /// The enrollment ended, or its attempt failed, in a way waiting will not mend.
  static func ended(_ receipt: RetainedEnrollmentReceipt) -> DesktopLinkFailure? {
    if receipt.phase == .terminal {
      switch receipt.terminalCause {
      case .denied: return .denied
      case .cancelled: return .cancelled
      case .expired: return .expired
      case .credentialRevoked, .restarted, .none: return .other("terminal")
      }
    }
    if receipt.phase == .unclaimed || receipt.attemptState == .failed
      || receipt.attemptState == .superseded
    {
      switch receipt.attemptFailure {
      case .invalidProof: return .wrongCode
      case .connectionClosed, .handshakeDeadline: return .unreachable
      case .verifierUnavailable, .none: return .wrongCode
      }
    }
    return nil
  }

  static func enrollmentFailure(_ failure: RetainedEnrollmentFailure) -> DesktopLinkFailure {
    switch failure.kind {
    case .crypto:
      return failure.crypto == .invalidCode || failure.crypto == .invalidProof
        ? .wrongCode : .other("crypto")
    case .wire:
      switch failure.wire?.correlation {
      case .expired: return .expired
      case .invalid, .attemptsExhausted, .wrongActor, .staleGeneration: return .wrongCode
      default: return .other("wire")
      }
    case .refused: return .wrongCode
    case .io, .handshake: return .unreachable
    case .storage: return .storage
    default: return .other(failure.kind.rawValue)
    }
  }

  static func readFailure(_ failure: RetainedReadFailure) -> DesktopLinkFailure {
    switch failure {
    case .unreachable, .away: return .unreachable
    case .refused: return .denied
    case .quota, .cache, .cacheDamaged, .cacheUncertain: return .storage
    default: return .other(failure.rawValue)
    }
  }

  static func failure(_ error: Error) -> DesktopLinkFailure {
    if let failure = error as? DesktopLinkFailure { return failure }
    if let error = error as? RetainedSessionError, case .session(let session) = error {
      if let enrollment = session.enrollment { return enrollmentFailure(enrollment) }
      if let cache = session.cache { return readFailure(cache) }
      if session.kind == .privateState || session.kind == .cache { return .storage }
      return .other(session.kind.rawValue)
    }
    if error is CancellationError { return .other("cancelled") }
    return .other(String(describing: error))
  }
}
