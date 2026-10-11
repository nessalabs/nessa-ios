import NessaDesignSystem
import SwiftUI

struct DevelopmentInfoPage: View {
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    NavigationStack {
      VStack(spacing: NessaSpacing.md) {
        Text("Dev mode").font(MessagesStyle.title)
        Text("Things are mocked.").font(MessagesStyle.body)
      }.padding(NessaSpacing.lg)
        .navigationTitle("Nessa")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
  }
}
