import Foundation

public enum PhoneRetainedHistoryRefusal: Error, Equatable, Sendable {
  case retired, unavailable, changed, quota, invalidProjection
}
public struct PhoneRetainedCatalogue: Sendable {
  public let profileID: UUID
  public let revision: UUID
  public let pages: [RetainedCataloguePage]
  public let list: NessaConversationList
  public init(
    profileID: UUID, revision: UUID, pages: [RetainedCataloguePage], list: NessaConversationList
  ) {
    self.profileID = profileID
    self.revision = revision
    self.pages = pages
    self.list = list
  }
}
public struct PhoneRetainedHistoryFailure: Error, Sendable {
  public let profileID: UUID
  public let revision: UUID
  public let pages: [RetainedCataloguePage]
  public let transcript: RetainedTranscript?
  public let underlying: any Error
  public init(
    profileID: UUID, revision: UUID, pages: [RetainedCataloguePage],
    transcript: RetainedTranscript?, underlying: any Error
  ) {
    self.profileID = profileID
    self.revision = revision
    self.pages = pages
    self.transcript = transcript
    self.underlying = underlying
  }
}
public protocol PhoneRetainedHistoryReading: Sendable {
  func catalogue(for snapshot: PhoneProfileSnapshot) async throws -> PhoneRetainedCatalogue
  func transcript(_ conversation: String, for snapshot: PhoneProfileSnapshot, revision: UUID)
    async throws
    -> PhoneScopedRetention<RetainedTranscript>
}

/// Bounded UI projections retain their complete native observations; never a second checkpoint.
public struct PhoneRetainedHistory: PhoneRetainedHistoryReading {
  private let session: any PhoneProfileCoordinating
  private let pageSize: UInt32
  private let maximumPages: Int
  public init(session: any PhoneProfileCoordinating, pageSize: UInt32 = 50, maximumPages: Int = 200)
  {
    precondition(pageSize > 0 && maximumPages > 0)
    self.session = session
    self.pageSize = pageSize
    self.maximumPages = maximumPages
  }
  public func catalogue(for snapshot: PhoneProfileSnapshot) async throws -> PhoneRetainedCatalogue {
    var pages: [RetainedCataloguePage] = []
    do {
      let receiver = try receiver(snapshot)
      var after: RetainedEntryKey?
      var cursors: [RetainedEntryKey] = []
      var ids: Set<Data> = []
      var entries: [NessaConversation] = []
      while pages.count < maximumPages {
        let captured = try await session.cataloguePage(after: after, maximum: pageSize)
        try validate(captured, snapshot: snapshot)
        guard let page = captured.value else { throw PhoneRetainedHistoryRefusal.unavailable }
        guard page.scope.receiver.utf8.elementsEqual(receiver.utf8) else {
          throw PhoneRetainedHistoryRefusal.changed
        }
        if let first = pages.first {
          guard first.scope == page.scope, first.generation == page.generation,
            first.activeBoundary == page.activeBoundary, first.activeCursor == page.activeCursor
          else { throw PhoneRetainedHistoryRefusal.changed }
        }
        pages.append(page)
        for entry in page.entries {
          guard ids.insert(Data(entry.key.id.utf8)).inserted else {
            throw PhoneRetainedHistoryRefusal.invalidProjection
          }
          if !entry.deleted {
            entries.append(
              .init(
                conversationId: entry.key.id, title: entry.title, preview: entry.preview,
                updatedAtMs: Double(entry.updatedAtMs ?? entry.createdAtMs ?? entry.key.creation),
                running: false))
          }
        }
        guard let next = page.next else {
          return .init(
            profileID: snapshot.profile.id, revision: snapshot.registry.revision, pages: pages,
            list: .init(conversations: entries, complete: true))
        }
        guard !cursors.contains(next) else { throw PhoneRetainedHistoryRefusal.invalidProjection }
        cursors.append(next)
        after = next
      }
      throw PhoneRetainedHistoryRefusal.quota
    } catch {
      throw PhoneRetainedHistoryFailure(
        profileID: snapshot.profile.id, revision: snapshot.registry.revision,
        pages: pages, transcript: nil, underlying: error)
    }
  }
  public func transcript(_ conversation: String, for snapshot: PhoneProfileSnapshot, revision: UUID)
    async throws -> PhoneScopedRetention<RetainedTranscript>
  {
    var observed: RetainedTranscript?
    do {
      let receiver = try receiver(snapshot)
      let captured = try await session.transcript(conversation: conversation, revision: revision)
      observed = captured.value
      try validate(captured, snapshot: snapshot)
      guard let scope = captured.value.scope, scope.receiver.utf8.elementsEqual(receiver.utf8)
      else {
        throw PhoneRetainedHistoryRefusal.unavailable
      }
      guard captured.value.state == .retained, case .available(let projection) = captured.value.view
      else {
        throw PhoneRetainedHistoryRefusal.unavailable
      }
      guard projection.revisionEpoch == revision,
        projection.display.conversationId.utf8.elementsEqual(conversation.utf8)
      else {
        throw PhoneRetainedHistoryRefusal.invalidProjection
      }
      return captured
    } catch {
      throw PhoneRetainedHistoryFailure(
        profileID: snapshot.profile.id, revision: snapshot.registry.revision,
        pages: [], transcript: observed, underlying: error)
    }
  }
  private func receiver(_ snapshot: PhoneProfileSnapshot) throws -> String {
    guard snapshot.profile.phase != .retired else { throw PhoneRetainedHistoryRefusal.retired }
    guard let receiver = snapshot.profile.nativeReceiver else {
      throw PhoneRetainedHistoryRefusal.unavailable
    }
    return receiver
  }
  private func validate<Value>(_ value: PhoneScopedRetention<Value>, snapshot: PhoneProfileSnapshot)
    throws
  {
    guard value.profileID == snapshot.profile.id, value.revision == snapshot.registry.revision
    else {
      throw PhoneRetainedHistoryRefusal.changed
    }
  }
}
