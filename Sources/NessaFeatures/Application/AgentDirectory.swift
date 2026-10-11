/// Read side of agent discovery. A future registration service can supply this port
/// independently of whichever transport delivers conversations.
public protocol AgentDirectory: Sendable {
  func agents() async throws -> [AgentProfile]
}
