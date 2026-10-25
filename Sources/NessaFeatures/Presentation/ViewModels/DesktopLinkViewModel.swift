import Combine
import Foundation

/// Pairing with a desktop by its code, and reading the chats it shares.
/// The code comes from the camera (the orb) or the keyboard; either way it
/// goes through the same `submit`.
@MainActor public final class DesktopLinkViewModel: ObservableObject {
  @Published public private(set) var phase: DesktopLinkPhase = .idle
  @Published public private(set) var linked: LinkedDesktop?
  @Published public private(set) var chats: [NessaConversation] = []
  @Published public private(set) var chatsLoading = false
  @Published public private(set) var chatsError: String?
  /// The code being paired with, held while the person picks a desktop.
  private var pendingCode: String?
  private var task: Task<Void, Never>?
  private let linking: DesktopLinking?

  public init(linking: DesktopLinking?) { self.linking = linking }

  public var available: Bool { linking != nil }
  public var busy: Bool {
    switch phase {
    case .finding, .enrolling, .approving: return true
    default: return false
    }
  }

  public func load() async {
    linked = try? await linking?.linked()
  }

  /// Pair with the desktop showing `code`. With one desktop on the network
  /// it is used; with several the person picks (`choose`).
  public func submit(code: String) {
    guard let linking, !busy else { return }
    guard OrbCode.parse(code) != nil else {
      phase = .failed(.wrongCode)
      return
    }
    pendingCode = code
    phase = .finding
    task = Task { [weak self] in
      let found = await linking.find()
      guard let self, !Task.isCancelled else { return }
      switch found.count {
      case 0: self.phase = .failed(.noDesktop)
      case 1: self.pair(with: found[0])
      default: self.phase = .choosing(found)
      }
    }
  }

  public func choose(_ gateway: FoundGateway) {
    guard case .choosing = phase else { return }
    pair(with: gateway)
  }

  private func pair(with gateway: FoundGateway) {
    guard let linking, let code = pendingCode else { return }
    phase = .enrolling(gateway)
    let progress: @Sendable (DesktopLinkPhase) async -> Void = { [weak self] next in
      await self?.advance(to: next)
    }
    task = Task { [weak self] in
      do {
        let desktop = try await linking.link(code: code, with: gateway, progress: progress)
        guard let self, !Task.isCancelled else { return }
        self.pendingCode = nil
        self.linked = desktop
        self.phase = .linked(desktop)
      } catch {
        guard let self, !Task.isCancelled else { return }
        self.pendingCode = nil
        self.phase = .failed(DesktopLinking.failure(error))
      }
    }
  }

  private func advance(to next: DesktopLinkPhase) {
    guard !Task.isCancelled else { return }
    phase = next
  }

  /// Back to scanning; a pairing in flight is abandoned on this phone.
  public func reset() {
    task?.cancel()
    task = nil
    pendingCode = nil
    phase = .idle
  }

  public func unlink() async {
    try? await linking?.unlink()
    linked = nil
    chats = []
    phase = .idle
  }

  public func refreshChats() async {
    guard let linking, let linked, !chatsLoading else { return }
    chatsLoading = true
    defer { chatsLoading = false }
    do {
      chats = try await linking.chats(of: linked)
      chatsError = nil
    } catch {
      chatsError = Self.sentence(DesktopLinking.failure(error))
    }
  }

  public func transcript(_ conversation: String) async throws -> NessaConversationView {
    guard let linking, let linked else { throw DesktopLinkFailure.other("not linked") }
    return try await linking.transcript(conversation, of: linked)
  }

  /// What a failure says to the person.
  public static func sentence(_ failure: DesktopLinkFailure) -> String {
    switch failure {
    case .noDesktop:
      return "No desktop found on this network. Turn on Native linking in Nessa on your Mac."
    case .wrongCode: return "That code didn't work. Check it and try again."
    case .expired: return "That code expired. Make a new one on your Mac."
    case .denied: return "Your Mac declined this phone."
    case .cancelled: return "The code was cancelled on your Mac."
    case .unreachable: return "Couldn't reach your Mac. Check you're on the same network."
    case .storage: return "This phone couldn't save the pairing."
    case .other: return "Pairing stopped. Try again."
    }
  }
}
