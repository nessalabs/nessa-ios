import NessaDesignSystem
import SwiftUI

#if os(iOS)
  import UIKit
#else
  import AppKit
#endif

struct MessageBubble: View {
  let text: String
  let outgoing: Bool
  var onReply: (() -> Void)? = nil
  var reaction: String? = nil
  var onReact: ((String) -> Void)? = nil
  var body: some View {
    HStack(alignment: .bottom, spacing: 0) {
      if outgoing { Spacer(minLength: MessagesStyle.bubbleGutter) }
      TextMessageContent(text: text, outgoing: outgoing, selectable: onReact == nil)
        .messageReaction(
          reaction: reaction, outgoing: outgoing, onReact: onReact,
          onCopy: { MessageClipboard.copy(text) }, onReply: onReply, shareText: text,
          preview: AnyView(TextMessageContent(text: text, outgoing: outgoing, selectable: false)))
      if !outgoing { Spacer(minLength: MessagesStyle.bubbleGutter) }
    }
  }
}

private struct TextMessageContent: View {
  let text: String
  let outgoing: Bool
  let selectable: Bool
  var body: some View {
    Text(.init(text))
      .font(MessagesStyle.body)
      .foregroundStyle(MessagesStyle.foreground)
      .tint(MessagesStyle.outgoing)
      .nessaTextSelection(enabled: selectable)
      .padding(.horizontal, MessagesStyle.bubbleInset + 6)
      .padding(.vertical, MessagesStyle.bubbleInset)
      .background(
        outgoing ? MessagesStyle.outgoing : MessagesStyle.incoming,
        in: MessagesBubbleShape(outgoing: outgoing)
      )
  }
}

extension View {
  @ViewBuilder fileprivate func nessaTextSelection(enabled: Bool) -> some View {
    if enabled { self.textSelection(.enabled) } else { self.textSelection(.disabled) }
  }
}

private enum MessageClipboard {
  static func copy(_ text: String) {
    #if os(iOS)
      UIPasteboard.general.string = text
    #else
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(text, forType: .string)
    #endif
  }
}
