import Foundation

/// Unlike display snapshots, uncertain command records cannot be dropped on storage failure.
public actor PhoneCommandStore: CommandJournalStoring {
  private let files: PrivatePhoneFiles
  public init(root: URL? = nil, maximumBytes: Int = 1024 * 1024) {
    files = PrivatePhoneFiles(
      root: root
        ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Nessa/Commands", isDirectory: true), maximumBytes: maximumBytes)
  }
  public func load(_ scope: PhoneCacheScope) throws -> PhoneCommands? {
    do {
      guard let data = try files.read(scope.key) else { return nil }
      let commands = try JSONDecoder().decode(PhoneCommands.self, from: data)
      try commands.validate()
      return commands
    } catch PrivatePhoneFileError.quota { throw PhoneCommandStoreError.quota } catch let error
      as PhoneCommandStoreError
    { throw error } catch is DecodingError { throw PhoneCommandStoreError.corrupt } catch {
      throw PhoneCommandStoreError.unavailable
    }
  }
  public func save(
    _ commands: PhoneCommands, scope: PhoneCacheScope, replacing expected: PhoneCommands?
  ) throws {
    do {
      try commands.validate()
      try files.withLock(scope.key) {
        guard try load(scope) == expected else { throw PhoneCommandStoreError.changed }
        try files.write(JSONEncoder().encode(commands), key: scope.key)
      }
    } catch PrivatePhoneFileError.quota { throw PhoneCommandStoreError.quota } catch let error
      as PhoneCommandStoreError
    { throw error } catch { throw PhoneCommandStoreError.unavailable }
  }
}
public actor InMemoryCommandJournalStore: CommandJournalStoring {
  private var values: [String: PhoneCommands] = [:]
  public init() {}
  public func load(_ scope: PhoneCacheScope) -> PhoneCommands? { values[scope.key] }
  public func save(
    _ commands: PhoneCommands, scope: PhoneCacheScope, replacing expected: PhoneCommands?
  ) throws {
    try commands.validate()
    guard values[scope.key] == expected else { throw PhoneCommandStoreError.changed }
    values[scope.key] = commands
  }
}
