import Foundation

/// Explicit storage selector. The native opener validates paths and the numeric endpoint.
public struct RetainedSessionLocation: Equatable, Sendable {
  public let root: String
  public let directory: String
  public let address: String
  public init(root: String, directory: String, address: String) {
    self.root = root
    self.directory = directory
    self.address = address
  }
  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.root.utf8.elementsEqual(rhs.root.utf8)
      && lhs.directory.utf8.elementsEqual(rhs.directory.utf8)
      && lhs.address.utf8.elementsEqual(rhs.address.utf8)
  }
}

/// Full native-produced bytes accompany the limited projection used by today's UI.
/// The display view and its transient revision are never durable sync progress.
public struct RetainedConversationProjection: Equatable, Sendable {
  public let json: Data
  public let revision: String
  public let revisionEpoch: UUID
  public let display: NessaConversationView
  public init(json: Data, revision: String, revisionEpoch: UUID, display: NessaConversationView) {
    self.json = json
    self.revision = revision
    self.revisionEpoch = revisionEpoch
    self.display = display
  }
}

public enum RetainedProjectionFailure: Equatable, Sendable {
  case native(RetainedViewFailure)
  case invalidDocument, targetMismatch, bridge
}

public struct RetainedViewFailureCapture: Equatable, Sendable {
  public let failure: RetainedProjectionFailure
  /// Present when native serialization succeeded but local interpretation failed.
  public let json: Data?
  public init(failure: RetainedProjectionFailure, json: Data?) {
    self.failure = failure
    self.json = json
  }
}

public enum RetainedViewOutcome: Equatable, Sendable {
  case absent
  case available(RetainedConversationProjection)
  case failed(RetainedViewFailureCapture)
}

public struct RetainedTranscript: Equatable, Sendable {
  public let state: RetainedTranscriptState
  public let scope: RetainedScope?
  public let downloaded: UInt64?
  public let applied: UInt64?
  public let facts: UInt64?
  public let generation: UInt64?
  public let view: RetainedViewOutcome
  public init(
    state: RetainedTranscriptState, scope: RetainedScope?, downloaded: UInt64?,
    applied: UInt64?, facts: UInt64?, generation: UInt64?, view: RetainedViewOutcome
  ) {
    self.state = state
    self.scope = scope
    self.downloaded = downloaded
    self.applied = applied
    self.facts = facts
    self.generation = generation
    self.view = view
  }
}

public protocol RetainedSession: Sendable {
  /// Historical local correlation; current gateway evidence must establish authority.
  func localEnrollment() async throws -> RetainedLocalEnrollment?
  func enroll(code: String) async throws -> RetainedEnrollmentReceipt
  func retry(code: String) async throws -> RetainedRetry
  func status() async throws -> RetainedStatus
  func refresh() async throws -> RetainedRefresh
  func cataloguePage(after: RetainedEntryKey?, maximum: UInt32) async throws
    -> RetainedCataloguePage?
  func transcript(conversation: String, revision: UUID) async throws -> RetainedTranscript
  func purgeReceipt(receiver: String) async throws -> RetainedPurge?
  /// Successful return means the private native owner actually drained.
  func close() async throws
}

public protocol RetainedSessionFactory: Sendable {
  func open(_ location: RetainedSessionLocation) async throws -> any RetainedSession
}
