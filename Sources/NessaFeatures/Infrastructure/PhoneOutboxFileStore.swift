import Foundation

/// One file for typed sends and one for Stop. A failed write leaves the previous file in place.
actor PhoneOutboxFileStore: PhoneOutboxStoring {
  private let file: URL
  private var records: [PhoneOutboxRecord] = []
  private var loaded = false
  init(directory: URL) {
    file = directory.appendingPathComponent("sends.json")
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }
  func load(_ id: String) async throws -> PhoneOutboxRecord? {
    try read()
    return records.first { $0.intent.commandID == id }
  }
  func insert(_ record: PhoneOutboxRecord) async throws {
    try read()
    guard !records.contains(where: { $0.intent.commandID == record.intent.commandID }) else {
      throw PhoneOutboxStoreFailure.conflict
    }
    var next = records
    next.append(record)
    try write(next)
    records = next
  }
  func replace(_ previous: PhoneOutboxRecord, with next: PhoneOutboxRecord) async throws {
    try read()
    guard let index = records.firstIndex(where: { $0 == previous }) else {
      throw PhoneOutboxStoreFailure.conflict
    }
    var updated = records
    updated[index] = next
    try write(updated)
    records = updated
  }
  func replaceAndInsert(
    previous: PhoneOutboxRecord, next: PhoneOutboxRecord, draft: PhoneOutboxRecord
  ) async throws {
    try read()
    guard let index = records.firstIndex(where: { $0 == previous }) else {
      throw PhoneOutboxStoreFailure.conflict
    }
    guard !records.contains(where: { $0.intent.commandID == draft.intent.commandID }) else {
      throw PhoneOutboxStoreFailure.conflict
    }
    var updated = records
    updated[index] = next
    updated.append(draft)
    try write(updated)
    records = updated
  }
  func list() async throws -> [PhoneOutboxRecord] {
    try read()
    return records
  }
  private func read() throws {
    guard !loaded else { return }
    guard let data = try? Data(contentsOf: file) else {
      loaded = true
      return
    }
    guard let decoded = try? JSONDecoder().decode([PhoneOutboxRecord].self, from: data) else {
      throw PhoneOutboxStoreFailure.corrupt
    }
    records = decoded
    loaded = true
  }
  private func write(_ records: [PhoneOutboxRecord]) throws {
    let data: Data
    do { data = try JSONEncoder().encode(records) } catch { throw PhoneOutboxStoreFailure.corrupt }
    let temporary = file.appendingPathExtension("tmp")
    do {
      try data.write(to: temporary, options: .atomic)
      if FileManager.default.fileExists(atPath: file.path) {
        _ = try FileManager.default.replaceItemAt(file, withItemAt: temporary)
      } else {
        try FileManager.default.moveItem(at: temporary, to: file)
      }
    } catch {
      throw PhoneOutboxStoreFailure.unavailable
    }
  }
}

actor PhoneStopFileStore: PhoneStopStoring {
  private let file: URL
  init(directory: URL) {
    file = directory.appendingPathComponent("stops.json")
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }
  func load() async throws -> [PhoneStopRecord] {
    guard let data = try? Data(contentsOf: file) else { return [] }
    guard let decoded = try? JSONDecoder().decode([PhoneStopRecord].self, from: data) else {
      throw PhoneOutboxFailure.corrupt
    }
    return decoded
  }
  func save(_ records: [PhoneStopRecord]) async throws {
    let data: Data
    do { data = try JSONEncoder().encode(records) } catch { throw PhoneOutboxFailure.corrupt }
    let temporary = file.appendingPathExtension("tmp")
    do {
      try data.write(to: temporary, options: .atomic)
      if FileManager.default.fileExists(atPath: file.path) {
        _ = try FileManager.default.replaceItemAt(file, withItemAt: temporary)
      } else {
        try FileManager.default.moveItem(at: temporary, to: file)
      }
    } catch {
      throw PhoneOutboxFailure.unavailable
    }
  }
}
