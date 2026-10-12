import Foundation
import NessaNative
import Testing

@testable import NessaFeatures

private actor ExecutionGate {
  private var entered = false
  private var released = false
  private var entryWaiters: [CheckedContinuation<Void, Never>] = []
  private var releaseWaiters: [CheckedContinuation<Void, Never>] = []
  func enter() {
    entered = true
    entryWaiters.forEach { $0.resume() }
    entryWaiters.removeAll()
  }
  func waitForEntry() async {
    if !entered { await withCheckedContinuation { entryWaiters.append($0) } }
  }
  func waitForRelease() async {
    if !released { await withCheckedContinuation { releaseWaiters.append($0) } }
  }
  func release() {
    released = true
    releaseWaiters.forEach { $0.resume() }
    releaseWaiters.removeAll()
  }
}

@Test func retainedExecutorRelaysCancellationIntoItsOffUIOperation() async throws {
  let gate = ExecutionGate()
  let operation = Task {
    try await NativeRetainedExecutor.run {
      await gate.enter()
      try await Task.sleep(for: .milliseconds(200))
      return 42
    }
  }
  await gate.waitForEntry()
  operation.cancel()
  await #expect(throws: RetainedSessionError.cancelled) { try await operation.value }
}

@Test func retainedExecutorKeepsAnAdmittedOutcomeInsteadOfSyntheticCancellation() async throws {
  let gate = ExecutionGate()
  let operation = Task {
    try await NativeRetainedExecutor.run {
      await gate.enter()
      await gate.waitForRelease()
      return RetainedRead(
        complete: false, conversations: UInt64.max, failure: .stopped, moved: true,
        withdrawn: ["saved-chat"])
    }
  }
  await gate.waitForEntry()
  operation.cancel()
  await gate.release()
  let outcome = try await operation.value
  #expect(outcome.failure == .stopped && outcome.conversations == UInt64.max)
  #expect(outcome.withdrawn == ["saved-chat"])
}

@Test @MainActor func cancelledRetainedOpenerDrainsItsActuallyConstructedNativeOwner() async throws
{
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    .resolvingSymlinksInPath()
  try FileManager.default.createDirectory(
    at: root.appendingPathComponent("session"), withIntermediateDirectories: true,
    attributes: [.posixPermissions: 0o700])
  defer { try? FileManager.default.removeItem(at: root) }
  let location = RetainedSessionLocation(
    root: root.path, directory: "session", address: "127.0.0.1:9")
  let gate = ExecutionGate()
  let factory = NativeRetainedSessionFactory(opening: { location in
    let worker = try await NativeSessionWorker.open(
      root: location.root, directory: location.directory, address: location.address)
    await gate.enter()
    await gate.waitForRelease()
    return worker
  })
  let opening = Task { try await factory.open(location) }
  await gate.waitForEntry()  // Real construction has completed and holds its private lock.
  opening.cancel()
  await gate.release()
  do {
    let unexpected = try await opening.value
    try await unexpected.close()
    Issue.record("cancelled construction escaped as a usable session")
  } catch RetainedSessionError.cancelled {}
  let reused = try await NativeRetainedSessionFactory().open(location)
  try await reused.close()
  let files = try FileManager.default.contentsOfDirectory(
    atPath: root.appendingPathComponent("session").path)
  #expect(!files.isEmpty)
}
