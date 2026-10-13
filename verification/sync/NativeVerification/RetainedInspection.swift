import Foundation
import NessaFeatures

/// Explicit test selectors only; never inspect a running app's private owner concurrently.
enum RetainedInspection {
  private struct Scope: Encodable {
    let accessEpoch, incarnation, origin, receiver, schema, stream: String
    init(_ value: RetainedScope) {
      accessEpoch = value.accessEpoch
      incarnation = value.incarnation
      origin = value.origin
      receiver = value.receiver
      schema = value.schema
      stream = value.stream
    }
  }
  private struct Key: Encodable {
    let creation: UInt64
    let id: String
    init(_ value: RetainedEntryKey) {
      creation = value.creation
      id = value.id
    }
  }
  private struct Entry: Encodable {
    let agent: String?
    let archived: Bool?
    let createdAtMs: UInt64?
    let deleted: Bool
    let key: Key
    let model, preview: String?
    let revision: UInt64
    let title: String?
    let updatedAtMs: UInt64?
    init(_ value: RetainedCatalogueEntry) {
      agent = value.agent
      archived = value.archived
      createdAtMs = value.createdAtMs
      deleted = value.deleted
      key = Key(value.key)
      model = value.model
      preview = value.preview
      revision = value.revision
      title = value.title
      updatedAtMs = value.updatedAtMs
    }
  }
  private struct Page: Encodable {
    let activeBoundary: UInt64?
    let activeCursor: Key?
    let completed, generation: UInt64
    let entries: [Entry]
    let next: Key?
    let scope: Scope
    init(_ value: RetainedCataloguePage) {
      activeBoundary = value.activeBoundary
      activeCursor = value.activeCursor.map(Key.init)
      completed = value.completed
      generation = value.generation
      entries = value.entries.map(Entry.init)
      next = value.next.map(Key.init)
      scope = Scope(value.scope)
    }
  }
  private struct Transcript: Encodable {
    let state: String
    let scope: Scope?
    let downloaded: UInt64?
    let applied: UInt64?
    let facts: UInt64?
    let generation: UInt64?
    let viewJSON: String?
    let failure: String?
  }
  private struct Report: Encodable {
    let status: RetainedStatus
    let page: Page?
    let target: String
    let transcript: Transcript
  }
  static func run(_ arguments: [String]) async throws {
    let session = try await NativeRetainedSessionFactory().open(
      .init(root: arguments[0], directory: arguments[1], address: arguments[2]))
    do {
      let status = try await session.status()
      let page = try await session.cataloguePage(after: nil, maximum: 50)
      let value = try await session.transcript(conversation: arguments[3], revision: UUID())
      let json: String?
      let failure: String?
      switch value.view {
      case .available(let projection):
        json = String(data: projection.json, encoding: .utf8)
        failure = nil
      case .failed(let capture):
        json = capture.json.flatMap { String(data: $0, encoding: .utf8) }
        failure = String(describing: capture.failure)
      case .absent:
        json = nil
        failure = nil
      }
      let report = Report(
        status: status, page: page.map(Page.init), target: arguments[3],
        transcript: .init(
          state: value.state.rawValue, scope: value.scope.map(Scope.init),
          downloaded: value.downloaded,
          applied: value.applied, facts: value.facts, generation: value.generation,
          viewJSON: json, failure: failure))
      try await session.close()
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      FileHandle.standardOutput.write(try encoder.encode(report))
      FileHandle.standardOutput.write(Data("\n".utf8))
    } catch {
      try? await session.close()
      throw error
    }
  }
}
