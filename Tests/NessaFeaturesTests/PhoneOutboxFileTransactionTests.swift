import Foundation
import Testing
@testable import NessaFeatures

private func transactionRecord(_ id: String) throws -> PhoneOutboxRecord {
  .held(try PhoneSendIntent(conversationID: "00000000-0000-4000-8000-0000000000aa",
    commandID: id, turnID: "turn-" + id, text: id, images: []))
}

@Test func separateFileOwnersKeepConcurrentDistinctInserts() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  let first = PhoneOutboxFileStore(directory: directory)
  let second = PhoneOutboxFileStore(directory: directory)
  _ = try await first.list()
  _ = try await second.list()
  try await withThrowingTaskGroup(of: Void.self) { group in
    for index in 0..<40 {
      let store = index.isMultiple(of: 2) ? first : second
      group.addTask { try await store.insert(transactionRecord("command-\(index)")) }
    }
    try await group.waitForAll()
  }
  let expected = Set((0..<40).map { "command-\($0)" })
  #expect(Set(try await first.list().map { $0.intent.commandID }) == expected)
  #expect(Set(try await second.list().map { $0.intent.commandID }) == expected)
}

@Test func staleFileOwnerCannotReplaceNewerOutcomeOrInsertItsSuccessor() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  let first = PhoneOutboxFileStore(directory: directory)
  let second = PhoneOutboxFileStore(directory: directory)
  let original = try transactionRecord("original")
  try await first.insert(original)
  _ = try await second.load("original")
  var committed = original
  committed.outcome = .accepted
  try await first.replace(original, with: committed)
  var stale = original
  stale.outcome = .unknown(.lookupFailed)
  await #expect(throws: PhoneOutboxStoreFailure.conflict) {
    try await second.replace(original, with: stale)
  }
  let draft = try transactionRecord("successor")
  await #expect(throws: PhoneOutboxStoreFailure.conflict) {
    try await second.replaceAndInsert(previous: original, next: stale, draft: draft)
  }
  #expect(try await second.list() == [committed])
  let unrelated = try transactionRecord("unrelated")
  try await first.insert(unrelated)
  try await second.replaceAndInsert(previous: committed, next: stale, draft: draft)
  #expect(try await first.list() == [stale, unrelated, draft])
}

@Test func previouslyReadFileOwnerDoesNotOverwriteCorruption() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = PhoneOutboxFileStore(directory: directory)
  let record = try transactionRecord("saved")
  try await store.insert(record)
  let file = directory.appendingPathComponent("sends.json")
  let damaged = Data("not JSON".utf8)
  try damaged.write(to: file)
  await #expect(throws: PhoneOutboxStoreFailure.corrupt) {
    try await store.insert(transactionRecord("new"))
  }
  #expect(try Data(contentsOf: file) == damaged)
}

@Test func failedFileTransactionKeepsPreviouslySavedRows() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = PhoneOutboxFileStore(directory: directory)
  try await store.insert(transactionRecord("saved"))
  let file = directory.appendingPathComponent("sends.json")
  let before = try Data(contentsOf: file)
  // A directory at the temporary-file path forces the atomic write to fail.
  try FileManager.default.createDirectory(at: file.appendingPathExtension("tmp"), withIntermediateDirectories: false)
  await #expect(throws: PhoneOutboxStoreFailure.unavailable) {
    try await store.insert(transactionRecord("new"))
  }
  #expect(try Data(contentsOf: file) == before)
}
