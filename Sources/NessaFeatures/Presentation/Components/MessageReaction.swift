import NessaDesignSystem
import SwiftUI

#if os(iOS)
  import UIKit
#endif

struct MessageContextSelection: Identifiable {
  let id = UUID()
  let sourceID: UUID
  let image: Image
  let frame: CGRect
  let imageSize: CGSize
  let outgoing: Bool
  let reaction: String?
  let react: (String) -> Void
  let copy: (() -> Void)?
  let reply: (() -> Void)?
  let shareText: String?
}

@MainActor final class MessageContextController: ObservableObject {
  @Published var selection: MessageContextSelection?
}
private struct MessageContextKey: EnvironmentKey {
  static let defaultValue: MessageContextController? = nil
}
extension EnvironmentValues {
  var messageContext: MessageContextController? {
    get { self[MessageContextKey.self] }
    set { self[MessageContextKey.self] = newValue }
  }
}

#if os(iOS)
  @MainActor private final class MessageCapture {
    weak var view: UIView?
    var frame: CGRect? {
      guard let view, let window = view.window, !view.bounds.isEmpty else { return nil }
      return view.convert(view.bounds, to: window)
    }
  }
  private struct MessageCaptureProbe: UIViewRepresentable {
    let capture: MessageCapture
    func makeUIView(context: Context) -> UIView {
      let view = UIView()
      view.isUserInteractionEnabled = false
      capture.view = view
      return view
    }
    func updateUIView(_ view: UIView, context: Context) { capture.view = view }
  }
#endif

private struct MessageReaction: ViewModifier {
  let reaction: String?
  let showBadge: Bool
  let outgoing: Bool
  let onReact: ((String) -> Void)?
  let onCopy: (() -> Void)?
  let onReply: (() -> Void)?
  let shareText: String?
  let preview: AnyView?
  @State private var sourceID = UUID()
  @Environment(\.displayScale) private var displayScale
  @Environment(\.messageContext) private var context
  #if os(iOS)
    @State private var capture = MessageCapture()
  #endif
  func body(content: Content) -> some View {
    content
      .background {
        #if os(iOS)
          MessageCaptureProbe(capture: capture)
        #endif
      }
      .messagesTapback(showBadge ? reaction : nil, outgoing: outgoing)
      // A reaction hold must coexist with the native photo pager's pan recognizer.
      // Giving this gesture priority suppresses horizontal swipes in hosted cards.
      .simultaneousGesture(
        LongPressGesture().onEnded { _ in
          guard let context, let onReact else { return }
          #if os(iOS)
            guard let frame = capture.frame else { return }
          #else
            let frame = CGRect(
              x: NessaSpacing.md, y: MessagesStyle.messageContextTopInset,
              width: MessagesStyle.previewWidth, height: MessagesStyle.previewHeight)
          #endif
          let snapshotSize = CGSize(
            width: frame.width, height: min(frame.height, MessagesStyle.messageSnapshotMaxHeight))
          let renderer = ImageRenderer(
            content: (preview ?? AnyView(content))
              .fixedSize(horizontal: false, vertical: true)
              .frame(width: snapshotSize.width, height: snapshotSize.height, alignment: .top)
              .clipped())
          renderer.scale = displayScale
          #if os(iOS)
            guard let rendered = renderer.uiImage else { return }
            let image = Image(uiImage: rendered)
            capture.view?.window?.endEditing(true)
          #else
            guard let rendered = renderer.nsImage else { return }
            let image = Image(nsImage: rendered)
          #endif
          context.selection = MessageContextSelection(
            sourceID: sourceID, image: image, frame: frame, imageSize: snapshotSize,
            outgoing: outgoing,
            reaction: reaction,
            react: onReact, copy: onCopy, reply: onReply, shareText: shareText)
        }
      )
      .messageSourceVisibility(context: context, sourceID: sourceID)
  }
}
extension View {
  func messageReaction(
    reaction: String?, outgoing: Bool, showBadge: Bool = true, onReact: ((String) -> Void)?,
    onCopy: (() -> Void)? = nil, onReply: (() -> Void)? = nil, shareText: String? = nil,
    preview: AnyView? = nil
  ) -> some View {
    modifier(
      MessageReaction(
        reaction: reaction, showBadge: showBadge, outgoing: outgoing, onReact: onReact,
        onCopy: onCopy, onReply: onReply, shareText: shareText, preview: preview))
  }
}

private struct MessageSourceVisibility: ViewModifier {
  @ObservedObject var context: MessageContextController
  let sourceID: UUID
  func body(content: Content) -> some View {
    content.opacity(context.selection?.sourceID == sourceID ? 0 : 1)
  }
}
extension View {
  @ViewBuilder fileprivate func messageSourceVisibility(
    context: MessageContextController?, sourceID: UUID
  ) -> some View {
    if let context {
      modifier(MessageSourceVisibility(context: context, sourceID: sourceID))
    } else {
      self
    }
  }
}
