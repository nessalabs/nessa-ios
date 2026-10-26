/// Read side of the person's channels, in the order the gateway keeps them: the default
/// channel first, then the rest as they were made.
public protocol ChannelDirectory: Sendable {
  func channels() async throws -> [NessaChannel]
}
