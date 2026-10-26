import SwiftUI

/// A small glass pill that says what the connection is doing, with one optional action
/// (Try again) once waiting has gone on long enough to be worth offering it.
public struct MessagesStatusPill: View {
  private let text: String
  private let working: Bool
  private let action: (title: String, perform: () -> Void)?
  public init(_ text: String, working: Bool, action: (title: String, perform: () -> Void)? = nil) {
    self.text = text
    self.working = working
    self.action = action
  }

  public var body: some View {
    HStack(spacing: NessaSpacing.xs) {
      if working { ProgressView().controlSize(.mini) }
      Text(text).font(MessagesStyle.caption).foregroundStyle(MessagesStyle.secondary)
      if let action {
        Button(action.title, action: action.perform)
          .font(MessagesStyle.caption.weight(.semibold))
          .foregroundStyle(MessagesStyle.foreground)
          .buttonStyle(.nessaPress)
      }
    }
    .padding(.horizontal, NessaSpacing.sm)
    .padding(.vertical, NessaSpacing.xs)
    .messagesGlass()
    .accessibilityElement(children: .combine)
  }
}
