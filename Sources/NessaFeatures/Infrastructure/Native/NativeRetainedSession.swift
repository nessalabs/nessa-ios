import Foundation
import NessaNative

public struct NativeRetainedSessionFactory: RetainedSessionFactory {
  private let opening: @Sendable (RetainedSessionLocation) async throws -> NativeSessionWorker
  public init() {
    opening = { location in
      try await NativeSessionWorker.open(
        root: location.root, directory: location.directory, address: location.address)
    }
  }
  // Infrastructure-only seam for proving ownership after actual native construction.
  init(opening: @escaping @Sendable (RetainedSessionLocation) async throws -> NativeSessionWorker) {
    self.opening = opening
  }
  public func open(_ location: RetainedSessionLocation) async throws -> any RetainedSession {
    let opening = opening
    return try await NativeRetainedExecutor.run {
      let worker = try await opening(location)
      // Queued native construction cannot be abandoned. A cancelled opener drains it.
      if Task.isCancelled {
        try await worker.close()
        throw RetainedSessionError.cancelled
      }
      return NativeRetainedSession(worker: worker)
    }
  }
}

private final class NativeRetainedSession: RetainedSession {
  private let worker: NativeSessionWorker
  init(worker: NativeSessionWorker) { self.worker = worker }

  func enroll(code: String) async throws -> RetainedEnrollmentReceipt {
    try await NativeRetainedExecutor.run { [worker] in
      try await worker.enroll(code: code, capture: { NativeRetainedCapture.capture($0) })
    }
  }
  func retry(code: String) async throws -> RetainedRetry {
    try await NativeRetainedExecutor.run { [worker] in
      try await worker.retry(code: code, capture: { NativeRetainedCapture.capture($0) })
    }
  }
  func status() async throws -> RetainedStatus {
    try await NativeRetainedExecutor.run { [worker] in
      try await worker.status(capture: { NativeRetainedCapture.capture($0) })
    }
  }
  func refresh() async throws -> RetainedRefresh {
    try await NativeRetainedExecutor.run { [worker] in
      try await worker.refresh(capture: { NativeRetainedCapture.capture($0) })
    }
  }
  func cataloguePage(after: RetainedEntryKey?, maximum: UInt32) async throws
    -> RetainedCataloguePage?
  {
    try await NativeRetainedExecutor.run { [worker] in
      let key = try after.map { try NativeEntryKey(creation: $0.creation, id: $0.id) }
      return try await worker.cataloguePage(
        after: key, maximum: maximum, capture: { $0.map { NativeRetainedCapture.capture($0) } })
    }
  }
  func transcript(conversation: String, revision: UUID) async throws -> RetainedTranscript {
    try await NativeRetainedExecutor.run { [worker] in
      try await worker.transcript(
        conversation: conversation, revision: revision.uuidString.lowercased(),
        capture: {
          NativeRetainedCapture.transcript($0, conversation: conversation, revision: revision)
        })
    }
  }
  func purgeReceipt(receiver: String) async throws -> RetainedPurge? {
    try await NativeRetainedExecutor.run { [worker] in
      try await worker.purgeReceipt(
        receiver: receiver, capture: { $0.map { NativeRetainedCapture.capture($0) } })
    }
  }
  func close() async throws {
    try await NativeRetainedExecutor.run(cancellable: false) { [worker] in
      try await worker.close()
    }
  }
}

/// Success capture stays in worker admission. Immutable error getters are also off UI.
enum NativeRetainedExecutor {
  static func run<Value: Sendable>(
    cancellable: Bool = true, operation: @escaping @Sendable () async throws -> Value
  ) async throws -> Value {
    let task = Task.detached {
      do {
        if cancellable { try Task.checkCancellation() }
        return try await operation()
      } catch { throw NativeRetainedCapture.error(error) }
    }
    return try await withTaskCancellationHandler {
      try await task.value
    } onCancel: {
      if cancellable { task.cancel() }
    }
  }
}
