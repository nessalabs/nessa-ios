import Foundation

/// A desktop gateway heard on the local network, announcing that it takes
/// pairings (`_nessa-link._tcp`). The announcement grants nothing: the code
/// and the owner's approval on the desktop still decide.
public struct FoundGateway: Equatable, Hashable, Sendable, Identifiable {
  /// What the desktop calls itself: the machine's name.
  public let name: String
  /// The gateway's public id, from the announcement's `gw` value.
  public let gateway: String
  /// The native listener, numeric (`192.168.1.20:47650`): the native opener
  /// looks up no host names.
  public let address: String
  public var id: String { gateway + "@" + address }
  public init(name: String, gateway: String, address: String) {
    self.name = name
    self.gateway = gateway
    self.address = address
  }
}

/// A desktop this phone paired with by its code. The phone reads the chats
/// the desktop shares with it; the gateway checks that access on every read,
/// so this record is where to read, never permission to.
public struct LinkedDesktop: Codable, Equatable, Sendable, Identifiable {
  public let id: UUID
  public let name: String
  public let gateway: String
  public let address: String
  /// The native receiver the enrollment issued; reads are scoped to it.
  public let receiver: String
  public let linkedAtMs: UInt64
  public init(
    id: UUID, name: String, gateway: String, address: String, receiver: String,
    linkedAtMs: UInt64
  ) {
    self.id = id
    self.name = name
    self.gateway = gateway
    self.address = address
    self.receiver = receiver
    self.linkedAtMs = linkedAtMs
  }
  /// Where this desktop's native state lives under the trusted root.
  public var nativeDirectoryComponents: [String] {
    LinkedDesktop.directoryComponents(for: id)
  }
  public static func directoryComponents(for id: UUID) -> [String] {
    ["LinkedDesktops", id.uuidString.lowercased()]
  }
}

/// Why pairing with a desktop stopped, in the terms the phone can say.
public enum DesktopLinkFailure: Error, Equatable, Sendable {
  /// No desktop answered on this network.
  case noDesktop
  /// The desktop did not accept the code: mistyped, misread, or already used.
  case wrongCode
  /// The code ran out before it was used or approved.
  case expired
  /// The owner denied this phone on the desktop.
  case denied
  /// The code was cancelled on the desktop.
  case cancelled
  /// The desktop could not be reached at the address it announced.
  case unreachable
  /// This phone could not keep what pairing needs.
  case storage
  /// Anything else; the detail is for diagnostics, not for the person.
  case other(String)
}

/// Where pairing with a desktop stands.
public enum DesktopLinkPhase: Equatable, Sendable {
  case idle
  /// Looking for desktops on this network.
  case finding
  /// More than one desktop answered: the person picks.
  case choosing([FoundGateway])
  /// Proving the code to the desktop.
  case enrolling(FoundGateway)
  /// The code was accepted; the desktop's owner approves this phone there.
  case approving(FoundGateway)
  case linked(LinkedDesktop)
  case failed(DesktopLinkFailure)
}
