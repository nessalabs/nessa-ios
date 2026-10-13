import CryptoKit
import Foundation

/// A private phone-persistence identity, not a retained receiver or access epoch.
public struct PhoneCacheScope: Sendable, Equatable {
  public let key: String
  public init(address: String, credential: String, instance: String) {
    var bytes = Data()
    for part in [address, instance, credential] {
      var count = UInt64(part.utf8.count).bigEndian
      withUnsafeBytes(of: &count) { bytes.append(contentsOf: $0) }
      bytes.append(contentsOf: part.utf8)
    }
    key = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
  }
}

public struct PhoneSnapshot: Codable, Sendable, Equatable {
  public var schema = 1
  public var list: NessaConversationList?
  public var agents: [AgentProfile] = []
  public var views: [String: NessaConversationView] = [:]
  public var recentViews: [String] = []
  public init() {}
  public func validate() throws {
    let ids = list?.conversations.map(\.id) ?? []
    guard schema == 1, views.count <= 20,
      Set(recentViews).count == recentViews.count, Set(recentViews) == Set(views.keys),
      Set(ids).count == ids.count, Set(agents.map(\.id)).count == agents.count,
      views.allSatisfy({ $0.key == $0.value.conversationId }),
      views.values.allSatisfy({ Set($0.messages.map(\.id)).count == $0.messages.count })
    else { throw PhoneSnapshotError.corrupt }
  }
}
public enum PhoneSnapshotError: Error, Sendable, Equatable {
  case corrupt, quota, unavailable, withdrawn
  case withdrawal(PhoneSnapshotMarkerFailure)
}
public protocol PhoneSnapshotStoring: Sendable {
  func load(_ scope: PhoneCacheScope) async throws -> PhoneSnapshot?
  func save(_ snapshot: PhoneSnapshot, scope: PhoneCacheScope) async throws
}

/// One coalescing writer: an older save finishes before the newer snapshot starts.
/// These derived display values never establish physical retained progress.
public actor PhoneSnapshotSession: PhoneSnapshotWithdrawing {
  public struct Lease: Sendable, Equatable {
    fileprivate let id = UUID()
    fileprivate let scope: PhoneCacheScope
  }
  private let store: any PhoneSnapshotStoring
  private let delay: Duration
  private var lease: Lease?
  private var snapshot = PhoneSnapshot()
  private var removed: Set<String> = []
  private var pending: (PhoneSnapshot, Lease)?
  private var writer: Task<Void, Never>?
  private var blockedScopes: [String: PhoneSnapshotError] = [:]
  public private(set) var failure: PhoneSnapshotError?
  public init(store: any PhoneSnapshotStoring, coalescingDelay: Duration = .milliseconds(250)) {
    self.store = store
    delay = coalescingDelay
  }
  public func prepare(_ scope: PhoneCacheScope) async throws -> (Lease, PhoneSnapshot?) {
    if let failure = blockedScopes[scope.key] { throw failure }
    let next = Lease(scope: scope)
    lease = next
    // Fence callers before settling their last owned save and reading disk.
    await writer?.value
    guard lease == next else { throw CancellationError() }
    snapshot = PhoneSnapshot()
    removed = []
    failure = nil
    let loaded: PhoneSnapshot?
    do { loaded = try await store.load(scope) } catch {
      guard lease == next else { throw CancellationError() }
      failure = (error as? PhoneSnapshotError) ?? .unavailable
      if let failure, Self.blocksHydration(failure) {
        blockedScopes[scope.key] = failure
        lease = nil
        throw failure
      }
      loaded = nil
    }
    guard lease == next else { throw CancellationError() }
    snapshot = loaded ?? PhoneSnapshot()
    return (next, loaded)
  }
  public func record(_ update: ConversationUpdate, lease expected: Lease) {
    guard lease == expected else { return }
    switch update {
    case .list(let list):
      // This list selects unarchived chats; absence is not a retained tombstone.
      snapshot.list = NessaConversationList(
        conversations: list.conversations.filter { !removed.contains($0.id) },
        complete: list.complete)
    case .view(_, let view):
      guard !removed.contains(view.conversationId) else { return }
      snapshot.views[view.conversationId] = view
      snapshot.recentViews.removeAll { $0 == view.conversationId }
      snapshot.recentViews.append(view.conversationId)
      while snapshot.recentViews.count > 20 {
        snapshot.views.removeValue(forKey: snapshot.recentViews.removeFirst())
      }
    }
    schedule(expected)
  }
  public func recordAgents(_ agents: [AgentProfile], lease expected: Lease) {
    guard lease == expected else { return }
    snapshot.agents = agents
    schedule(expected)
  }
  public func remove(_ id: String, lease expected: Lease) {
    guard lease == expected else { return }
    removed.insert(id)
    if let list = snapshot.list {
      snapshot.list = NessaConversationList(
        conversations: list.conversations.filter { $0.id != id }, complete: list.complete)
    }
    snapshot.views.removeValue(forKey: id)
    snapshot.recentViews.removeAll { $0 == id }
    schedule(expected)
  }
  public func flush() async { await writer?.value }
  // Passive barrier observation for deterministic held-writer verification.
  func withdrawalFailure(_ scope: PhoneCacheScope) -> PhoneSnapshotError? {
    blockedScopes[scope.key]
  }
  public func withdraw(_ scope: PhoneCacheScope) async throws {
    // Fence before suspension: callbacks and new preparation cannot resurrect this scope.
    blockedScopes[scope.key] = .withdrawn
    if lease?.scope == scope {
      lease = nil
      snapshot = PhoneSnapshot()
      removed = []
    }
    if pending?.1.scope == scope { pending = nil }
    await writer?.value
    guard let withdrawing = store as? any PhoneSnapshotWithdrawing else {
      throw PhoneSnapshotWithdrawalError.unsupported
    }
    try await withdrawing.withdraw(scope)
  }
  private static func blocksHydration(_ failure: PhoneSnapshotError) -> Bool {
    switch failure {
    case .withdrawn, .withdrawal: return true
    case .corrupt, .quota, .unavailable: return false
    }
  }
  private func schedule(_ lease: Lease) {
    pending = (snapshot, lease)
    guard writer == nil else { return }
    writer = Task { await drain() }
  }
  private func drain() async {
    while pending != nil {
      try? await Task.sleep(for: delay)
      guard let (next, writingLease) = pending else { break }
      pending = nil
      guard blockedScopes[writingLease.scope.key] == nil else { continue }
      do {
        try await store.save(next, scope: writingLease.scope)
        if lease == writingLease { failure = nil }
      } catch {
        if lease == writingLease { failure = (error as? PhoneSnapshotError) ?? .unavailable }
      }
    }
    writer = nil
  }
}
