import SwiftUI

public struct ReplyConnector: View {
  let outgoing: Bool
  public init(outgoing: Bool) { self.outgoing = outgoing }
  public var body: some View {
    ReplyConnectorShape()
      .stroke(
        MessagesStyle.secondary.opacity(MessagesStyle.replyPreviewOpacity),
        style: StrokeStyle(lineWidth: MessagesStyle.replyConnectorStroke, lineCap: .round)
      )
      .frame(width: MessagesStyle.replyConnectorWidth, height: MessagesStyle.replyConnectorHeight)
      .scaleEffect(x: outgoing ? -1 : 1, y: 1)
      .accessibilityHidden(true)
  }
}

private struct ReplyConnectorShape: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: rect.width * 0.2, y: 0))
    path.addLine(to: CGPoint(x: rect.width * 0.2, y: rect.height * 0.25))
    path.addQuadCurve(
      to: CGPoint(x: rect.width * 0.75, y: rect.height * 0.85),
      control: CGPoint(x: rect.width * 0.2, y: rect.height * 0.85))
    path.addLine(to: CGPoint(x: rect.width, y: rect.height * 0.85))
    return path
  }
}
