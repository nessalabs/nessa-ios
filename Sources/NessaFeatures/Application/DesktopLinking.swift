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
  /// Forget the kept desktop if it is still `id`; a desktop paired since
  /// stays.
  func remove(_ id: UUID) async throws
  /// Keep `tunnel` with the kept desktop if it is still `id`, in one step:
  /// a desktop forgotten or paired since is left as it is.
  func remember(tunnel: String, for id: UUID) async throws
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
  /// Milliseconds on a clock that never jumps, for timing the wait.
  private let elapsed: @Sendable () -> UInt64
  /// How long a desktop has to answer the search.
  public let findSeconds: Double
  /// How often the desktop is asked whether the owner approved.
  public let statusSeconds: Double
  /// How long this phone waits for the owner, timed on this phone's clock
  /// alone. The code's own expiry is the desktop's to judge: it ends the
  /// enrollment as expired, so no deadline set by its clock is compared here.
  public let approvalSeconds: Double
  /// Reads under way per desktop, and who waits for them to finish before
  /// that desktop's directory is removed.
  private var reads: [UUID: Int] = [:]
  private var drained: [UUID: [CheckedContinuation<Void, Never>]] = [:]
  /// Desktops forgotten on this phone: no new read opens their directory.
  private var forgotten: Set<UUID> = []
  /// Desktops a read could not close cleanly: a native worker may still be
  /// writing there, so their directory is left in place.
  private var unclean: Set<UUID> = []
  /// Previous desktops being retired after a new pairing returned.
  private var retiring: [UUID: Task<Void, Never>] = [:]

  public init(
    finder: any GatewayFinding, store: any LinkedDesktopStoring,
    locations: any LinkedDesktopLocating, sessions: any RetainedSessionFactory,
    pause: @escaping @Sendable (Double) async throws -> Void = {
      try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000))
    },
    now: @escaping @Sendable () -> UInt64 = {
      UInt64(Date().timeIntervalSince1970 * 1_000)
    },
    elapsed: @escaping @Sendable () -> UInt64 = {
      DispatchTime.now().uptimeNanoseconds / 1_000_000
    },
    findSeconds: Double = 3, statusSeconds: Double = 2, approvalSeconds: Double = 900
  ) {
    self.finder = finder
    self.store = store
    self.locations = locations
    self.sessions = sessions
    self.pause = pause
    self.now = now
    self.elapsed = elapsed
    self.findSeconds = findSeconds
    self.statusSeconds = statusSeconds
    self.approvalSeconds = approvalSeconds
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
    let desktop: LinkedDesktop
    do {
      desktop = try await enroll(
        session, code: formatted, id: id, gateway: gateway, progress: progress)
    } catch {
      await abandon(session, id: id)
      throw Self.failure(error)
    }
    let closed = (try? await session.close()) != nil
    if !closed { unclean.insert(id) }
    do {
      // A pairing cancelled on this phone keeps nothing, even once approved.
      try Task.checkCancellation()
      let previous = try? await store.load()
      try await store.save(desktop)
      // Retired in the background: a read of the old desktop may sit on the
      // network, and this pairing is done. New reads of it are refused now.
      if let previous, previous.id != desktop.id {
        forgotten.insert(previous.id)
        retiring[previous.id] = Task {
          await self.retire(previous.id)
          self.retiring[previous.id] = nil
        }
      }
      return desktop
    } catch {
      if closed { await locations.discard(id: id) }
      throw error is CancellationError ? Self.failure(error) : DesktopLinkFailure.storage
    }
  }

  /// Close a session that pairing gives up on, and remove its directory once
  /// nothing native is left writing to it.
  private func abandon(_ session: any RetainedSession, id: UUID) async {
    if (try? await session.close()) != nil { await locations.discard(id: id) }
  }

  private func enroll(
    _ session: any RetainedSession, code: String, id: UUID, gateway: FoundGateway,
    progress: @Sendable (DesktopLinkPhase) async -> Void
  ) async throws -> LinkedDesktop {
    let deadline = elapsed() + UInt64(approvalSeconds * 1_000)
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
      if elapsed() >= deadline { throw DesktopLinkFailure.expired }
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
    try await store.remove(desktop.id)
    await retire(desktop.id)
  }

  /// Waits for previous desktops still being retired.
  func settled() async {
    for task in retiring.values { await task.value }
  }

  /// Stop new reads of `id`, wait for the ones under way, then remove its
  /// directory, so no native worker is left writing into a removed one.
  private func retire(_ id: UUID) async {
    forgotten.insert(id)
    if reads[id, default: 0] > 0 {
      await withCheckedContinuation { drained[id, default: []].append($0) }
    }
    guard !unclean.contains(id) else { return }
    await locations.discard(id: id)
  }

  private func endRead(_ id: UUID) {
    let left = reads[id, default: 1] - 1
    guard left == 0 else {
      reads[id] = left
      return
    }
    reads[id] = nil
    for waiter in drained.removeValue(forKey: id) ?? [] { waiter.resume() }
  }

  /// Open the product session to `desktop` through `products`. It counts as
  /// a read until it closes, so forgetting the desktop waits for it before
  /// that desktop's directory is removed.
  func openProduct(
    _ desktop: LinkedDesktop, instance: String, through products: any LinkedProductOpening
  ) async throws -> any GatewayProductExchange {
    guard !forgotten.contains(desktop.id) else { throw DesktopLinkFailure.other("forgotten") }
    reads[desktop.id, default: 0] += 1
    // The kept record is the one place the tunnel is learned into: a caller's
    // copy of the desktop can be older than the last `server.reach`.
    let kept = try? await store.load()
    let dialed = kept?.id == desktop.id ? desktop.reaching(kept?.tunnel) : desktop
    let exchange: any GatewayProductExchange
    do {
      exchange = try await products.open(dialed, instance: instance)
    } catch {
      endRead(desktop.id)
      throw error
    }
    return HeldProductExchange(
      exchange,
      ready: { [weak self] exchange in await self?.learnReach(desktop.id, from: exchange) },
      closed: { [weak self] released in
        await self?.productClosed(desktop.id, released: released)
      })
  }

  /// Ask the desktop where else it can be reached and keep the answer with its
  /// record, so the next dial away from its network can use it. No tunnel in
  /// the answer keeps the last one: the desktop says none while its tunnel is
  /// still starting, and a stale address only costs a dial that fails, since
  /// the pinned key decides which desktop answers. A desktop that does not
  /// answer, one forgotten or paired over since, or an address that is not
  /// an `https` origin changes nothing.
  private func learnReach(_ id: UUID, from exchange: any GatewayProductExchange) async {
    guard let answer = try? await exchange.request(method: "server.reach", parameters: Data("{}".utf8)),
      let frame = try? JSONDecoder().decode(ReachFrame.self, from: answer), frame.ok,
      let tunnel = frame.payload?.tunnel, LinkedDesktop.isTunnelOrigin(tunnel),
      !forgotten.contains(id)
    else { return }
    try? await store.remember(tunnel: tunnel, for: id)
  }

  private func productClosed(_ id: UUID, released: Bool) {
    if !released { unclean.insert(id) }
    endRead(id)
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
    guard !forgotten.contains(desktop.id) else { throw DesktopLinkFailure.other("forgotten") }
    reads[desktop.id, default: 0] += 1
    defer { endRead(desktop.id) }
    let session: any RetainedSession
    do {
      let location = try await locations.prepare(id: desktop.id, address: desktop.address)
      session = try await sessions.open(location)
    } catch {
      throw Self.failure(error)
    }
    let result: Result<Value, Error>
    do {
      result = .success(try await body(session))
    } catch {
      result = .failure(error)
    }
    if (try? await session.close()) == nil { unclean.insert(desktop.id) }
    switch result {
    case .success(let value): return value
    case .failure(let error): throw Self.failure(error)
    }
  }

  // MARK: What the native answers mean here

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
      case .connectionClosed, .handshakeDeadline, .verifierUnavailable: return .unreachable
      case .none: return .other("attempt ended")
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

/// `server.reach`'s answer frame: where else the desktop can be reached.
private struct ReachFrame: Decodable {
  struct Reach: Decodable { let tunnel: String? }
  let ok: Bool
  let payload: Reach?
}

/// A product exchange that tells its desktop when it was first ready and when
/// it first closed, and whether its native session let go then.
private final class HeldProductExchange: GatewayProductExchange, @unchecked Sendable {
  private let inner: any GatewayProductExchange
  private let readied: @Sendable (any GatewayProductExchange) async -> Void
  private let closed: @Sendable (Bool) async -> Void
  private let lock = NSLock()
  private var announced = false
  private var reported = false
  init(
    _ inner: any GatewayProductExchange,
    ready: @escaping @Sendable (any GatewayProductExchange) async -> Void,
    closed: @escaping @Sendable (Bool) async -> Void
  ) {
    self.inner = inner
    self.readied = ready
    self.closed = closed
  }
  func ready() async throws -> Data {
    let ready = try await inner.ready()
    let first = lock.withLock {
      defer { announced = true }
      return !announced
    }
    // Off the caller's path: the session is usable before the answer comes.
    if first { Task { [inner, readied] in await readied(inner) } }
    return ready
  }
  func request(method: String, parameters: Data) async throws -> Data {
    try await inner.request(method: method, parameters: parameters)
  }
  func events() async throws -> [Data] { try await inner.events() }
  func requestClose() { inner.requestClose() }
  func close() async -> GatewayProductCloseObservation {
    let observation = await inner.close()
    let first = lock.withLock {
      defer { reported = true }
      return !reported
    }
    if first { await closed(observation.released) }
    return observation
  }
}
