import Foundation
import Network

/// Browses for desktops taking pairings (`_nessa-link._tcp`, the service the
/// gateway announces and the app lists in `NSBonjourServices`), then resolves
/// each to the numeric IPv4 address the native opener needs. The desktop
/// listens on IPv4 (`0.0.0.0`), so only IPv4 is asked for.
public struct BonjourGatewayFinder: GatewayFinding {
  /// The DNS-SD service type the gateway announces.
  public static let service = "_nessa-link._tcp"
  /// The TXT key holding the gateway's public id.
  public static let gatewayKey = "gw"

  public init() {}

  public func find(within seconds: Double) async -> [FoundGateway] {
    let heard = await browse(for: seconds)
    return await withTaskGroup(of: FoundGateway?.self) { group in
      for (endpoint, name, gateway) in heard {
        group.addTask { await Self.resolve(endpoint, name: name, gateway: gateway) }
      }
      var found: [FoundGateway] = []
      for await gateway in group {
        if let gateway, !found.contains(where: { $0.gateway == gateway.gateway }) {
          found.append(gateway)
        }
      }
      return found.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
  }

  /// Each announced instance heard within `seconds`: its endpoint, name and
  /// gateway id.
  private func browse(for seconds: Double) async -> [(NWEndpoint, String, String)] {
    let browser = NWBrowser(
      for: .bonjourWithTXTRecord(type: Self.service, domain: nil), using: .tcp)
    let queue = DispatchQueue(label: "nessa.gateway.browse")
    let results = BrowseResults()
    browser.browseResultsChangedHandler = { latest, _ in results.replace(with: latest) }
    browser.start(queue: queue)
    try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    browser.cancel()
    return results.current().compactMap { result in
      guard case .service(let name, _, _, _) = result.endpoint else { return nil }
      var gateway = ""
      if case .bonjour(let record) = result.metadata,
        let value = record[Self.gatewayKey]
      {
        gateway = value
      }
      guard !gateway.isEmpty else { return nil }
      return (result.endpoint, name, gateway)
    }
  }

  /// The numeric address `endpoint` resolves to, by connecting once over
  /// IPv4 and reading the path's remote end. Nothing is sent.
  private static func resolve(_ endpoint: NWEndpoint, name: String, gateway: String) async
    -> FoundGateway?
  {
    let parameters = NWParameters.tcp
    if let ip = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
      ip.version = .v4
    }
    let connection = NWConnection(to: endpoint, using: parameters)
    let queue = DispatchQueue(label: "nessa.gateway.resolve")
    let address: String? = await withCheckedContinuation { continuation in
      let once = Once()
      connection.stateUpdateHandler = { state in
        switch state {
        case .ready:
          var text: String?
          if case .hostPort(let host, let port) = connection.currentPath?.remoteEndpoint,
            case .ipv4(let ip) = host
          {
            text = "\(ip.debugDescription.split(separator: "%").first ?? ""):\(port.rawValue)"
          }
          if once.claim() { continuation.resume(returning: text) }
          connection.cancel()
        case .failed, .cancelled:
          if once.claim() { continuation.resume(returning: nil) }
        case .waiting:
          if once.claim() { continuation.resume(returning: nil) }
          connection.cancel()
        default:
          break
        }
      }
      connection.start(queue: queue)
      queue.asyncAfter(deadline: .now() + 3) {
        if once.claim() { continuation.resume(returning: nil) }
        connection.cancel()
      }
    }
    guard let address else { return nil }
    return FoundGateway(name: name, gateway: gateway, address: address)
  }
}

/// The browser's latest results, read once browsing ends.
private final class BrowseResults: @unchecked Sendable {
  private let lock = NSLock()
  private var latest: Set<NWBrowser.Result> = []
  func replace(with results: Set<NWBrowser.Result>) {
    lock.lock()
    latest = results
    lock.unlock()
  }
  func current() -> Set<NWBrowser.Result> {
    lock.lock()
    defer { lock.unlock() }
    return latest
  }
}

/// Lets exactly one of several callbacks resume a continuation.
private final class Once: @unchecked Sendable {
  private let lock = NSLock()
  private var claimed = false
  func claim() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    if claimed { return false }
    claimed = true
    return true
  }
}
