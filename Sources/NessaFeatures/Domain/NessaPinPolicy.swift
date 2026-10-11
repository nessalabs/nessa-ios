/// Initial product limit for the pinned-agent row.
public enum NessaPinPolicy {
  public static let maximumAgents = 3
  public static func normalize(_ agents: [String]) -> [String] {
    var result: [String] = []
    for agent in agents where !result.contains(agent) {
      guard result.count < maximumAgents else { break }
      result.append(agent)
    }
    return result
  }
}
