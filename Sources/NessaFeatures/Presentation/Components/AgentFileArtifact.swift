import NessaDesignSystem
import SwiftUI

struct AgentFileArtifact: View {
  let file: NessaFileAttachment
  var body: some View {
    VStack(alignment: .leading, spacing: NessaSpacing.sm) {
      HStack(spacing: NessaSpacing.sm) {
        Image(systemName: "doc").foregroundStyle(MessagesStyle.secondary)
        VStack(alignment: .leading, spacing: NessaSpacing.xs) {
          Text(file.name).font(MessagesStyle.body).lineLimit(2)
          Text(file.mimeType).font(MessagesStyle.caption)
            .foregroundStyle(MessagesStyle.secondary)
        }
      }.padding(.vertical, NessaSpacing.sm)
      Divider().overlay(MessagesStyle.separator)
    }.frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityElement(children: .combine)
  }
}
