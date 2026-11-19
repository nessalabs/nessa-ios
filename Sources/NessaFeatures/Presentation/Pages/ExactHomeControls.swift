#if os(iOS)
import NessaDesignSystem
import SwiftUI
import UIKit

extension ExactPhoneSession {
  public func composer(channel key: String, navigate: @escaping (String) -> Void,
    size: @escaping (CGSize) -> Void) -> UIViewController {
    let view = ExactNewChatInput(session: self, key: key, navigate: navigate, size: size)
    let host = UIHostingController(rootView: view)
    host.view.backgroundColor = .clear
    host.safeAreaRegions = []
    return host
  }
}

private struct ExactNewChatInput: View {
  let session: ExactPhoneSession
  let key: String
  let navigate: (String) -> Void
  let size: (CGSize) -> Void
  @ObservedObject var store: MessagesViewModel
  @StateObject var dictation: DictationViewModel

  init(session: ExactPhoneSession, key: String, navigate: @escaping (String) -> Void,
    size: @escaping (CGSize) -> Void) {
    self.session = session
    self.key = key
    self.navigate = navigate
    self.size = size
    store = session.messages
    _dictation = StateObject(wrappedValue: session.dependencies.makeDictationViewModel())
  }

  var body: some View {
    let channel = store.channels.first { $0.id == key }
    if key.isEmpty || channel != nil {
      NewChatComposer(store: store, dictation: dictation, channel: channel) { id, first in
        session.firstMessages[id] = first
        navigate("/chat/" + (id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""))
      }
      .fixedSize(horizontal: false, vertical: true)
      .onGeometryChange(for: CGSize.self, of: { $0.size }, action: size)
      .preferredColorScheme(.dark)
    }
  }
}

public struct ExactPhoneArtwork: View {
  let kind: String
  let value: String
  let position: Int
  public init(_ props: [String: String]) {
    kind = props["kind"] ?? ""
    value = props["seed"] ?? ""
    position = Int(props["tileOrder"] ?? "") ?? 0
  }
  public var body: some View {
    Group {
      switch kind {
      case "home": NessaHomeLight()
      case "channel": NessaChannelTile(name: value, position: position)
      case "profile": NessaProfileDisc(size: MessagesStyle.homeButton)
      case "avatar": AgentAvatar(seed: value, size: MessagesStyle.rowAvatar)
      case "menu": NessaIcon(.menu)
      case "compose": NessaIcon(.compose)
      case "agents": NessaIcon(.agents)
      default: EmptyView()
      }
    }.foregroundStyle(MessagesStyle.foreground).accessibilityHidden(true)
  }
}
#endif
