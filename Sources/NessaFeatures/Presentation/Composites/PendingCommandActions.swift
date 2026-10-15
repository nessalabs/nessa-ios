import NessaDesignSystem
import SwiftUI

struct PendingCommandActions: View {
  let command: PreparedConversationCommand
  @ObservedObject var store: MessagesViewModel
  var onCreated: (String) -> Void = { _ in }
  private var title: String {
    if case .create = command { return "Pending chat" }
    return "Pending message"
  }
  var body: some View {
    HStack(spacing: NessaSpacing.sm) {
      Image(systemName: "clock").foregroundStyle(MessagesStyle.secondary)
      Text(title).font(MessagesStyle.caption)
      Spacer()
      if store.checkingCommands.contains(command.requestID) { ProgressView() }
      Button("Check") { recover(retry: false) }
      Button("Retry") { recover(retry: true) }
    }.font(MessagesStyle.caption).foregroundStyle(MessagesStyle.foreground)
      .padding(.horizontal, MessagesStyle.horizontal).padding(.vertical, NessaSpacing.sm)
      .disabled(!store.connected || store.checkingCommands.contains(command.requestID))
  }
  private func recover(retry: Bool) {
    Task {
      if let id = await store.recoverCommand(command.requestID, retry: retry) { onCreated(id) }
    }
  }
}
struct PhoneDeliveryRow: View {
  let delivery: PhoneOutboxView
  @ObservedObject var store: MessagesViewModel
  var body: some View {
    HStack(spacing: NessaSpacing.sm) {
      Image(systemName: "clock").foregroundStyle(MessagesStyle.secondary)
      Text(title).font(MessagesStyle.caption).lineLimit(2)
      Spacer()
      if case .unknown(.notAdmitted) = delivery.outcome {
        Button("Retry") { Task { await store.retryPhoneDelivery(delivery.commandID) } }
          .disabled(!store.connected || store.accessRevoked)
      }
    }.font(MessagesStyle.caption).foregroundStyle(MessagesStyle.foreground)
      .padding(.horizontal, MessagesStyle.horizontal).padding(.vertical, NessaSpacing.sm)
  }
  private var title: String {
    switch delivery.outcome {
    case .unknown: "Delivery not confirmed"
    case .failed: "Message not sent"
    default: "Message"
    }
  }
}
struct PendingDeliveryUnavailable: View {
  @ObservedObject var store: MessagesViewModel
  var body: some View {
    HStack {
      Text("Pending deliveries unavailable").font(MessagesStyle.caption)
        .foregroundStyle(MessagesStyle.secondary)
      Spacer()
      Button("Reconnect") { Task { await store.reconnectDeliveryState() } }
        .font(MessagesStyle.caption)
    }.padding(.horizontal, MessagesStyle.horizontal).padding(.vertical, NessaSpacing.sm)
  }
}
