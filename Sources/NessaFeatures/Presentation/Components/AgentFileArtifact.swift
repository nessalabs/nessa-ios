import NessaDesignSystem
import SwiftUI

struct AgentFileArtifact: View {
  let file: NessaFileAttachment
  var body: some View {
    HStack(spacing: NessaSpacing.sm) {
      Image(systemName: "doc.text").font(MessagesStyle.icon).foregroundStyle(MessagesStyle.link)
        .frame(width: AgentDetailsStyle.fileIcon, height: AgentDetailsStyle.fileIcon)
        .background(MessagesStyle.control, in: Circle())
      VStack(alignment: .leading, spacing: NessaSpacing.xxs) {
        Text(file.name).font(MessagesStyle.body).lineLimit(2)
        Text(file.mimeType).font(MessagesStyle.caption).foregroundStyle(MessagesStyle.secondary)
      }
      Spacer(minLength: 0)
    }
    .padding(NessaSpacing.sm)
    .frame(maxWidth: .infinity, alignment: .leading)
    .nessaCard()
    .accessibilityElement(children: .combine)
  }
}
