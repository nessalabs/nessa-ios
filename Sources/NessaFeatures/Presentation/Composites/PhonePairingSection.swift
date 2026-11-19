import NessaDesignSystem
import SwiftUI

/// Explicit choices render actual owner/native observations without deriving read permission.
struct PhonePairingSection: View {
  @ObservedObject var store: MessagesViewModel
  @State private var nativeAddress = ""
  @FocusState private var editingAddress: Bool
  private var snapshot: PhoneProfileSnapshot? { store.phoneProfile }
  private var profile: PhoneProfile? { snapshot?.profile }
  private var remoteReady: Bool { store.connected && store.acceptedLease != nil }
  private var idle: Bool { !store.busy && !store.phoneSetupBusy }

  var body: some View {
    Section {
      TextField("Native address (IP:port)", text: $nativeAddress).nessaCredentialInput()
        .focused($editingAddress)
      action(
        profile == nil ? "Prepare phone" : "Resume setup",
        .prepare(nativeAddress: nativeAddress, newProfile: false),
        enabled: !nativeAddress.isEmpty
          && (profile == nil
            || profile?.nativeAddress.utf8.elementsEqual(nativeAddress.utf8) == true)
          && profile?.phase != .retired)
      if profile != nil {
        action(
          "New setup", .prepare(nativeAddress: nativeAddress, newProfile: true),
          enabled: !nativeAddress.isEmpty)
        action("Restore saved setup", .restore)
        if !store.connected {
          Button("Reconnect saved profile") {
            Task {
              await store.connect(
                address: profile?.productAddress ?? "", credential: "",
                instance: profile?.instance ?? "", restoringSavedProfile: true)
            }
          }.disabled(!idle)
        }
      }
      if let profile {
        LabeledContent("Setup", value: profile.phase.rawValue)
        if profile.phase == .prepared {
          if profile.creationAttempt == nil, profile.pairingStatus == nil,
            snapshot?.local == nil, profile.nativeReceiver == nil
          {
            action("Pair this phone", .pair)
          }
          if profile.pairingStatus != nil {
            action("Refresh pairing", .observe)
            action(
              profile.pairingStatus?.phase == .active ? "Revoke device" : "Cancel pairing",
              .cancel, destructive: true)
          }
          if profile.creationAttempt != nil, profile.pairingStatus == nil {
            action("Find pending invitations", .findInvitations)
            ForEach(store.phoneInvitations, id: \.invitationID) { invitation in
              action(
                "Recover \(invitation.invitationID.base64EncodedString())",
                .recover(invitation.invitationID)
              )
              .font(MessagesStyle.caption.monospaced())
            }
          }
          if snapshot?.local == nil, profile.nativeReceiver == nil,
            snapshot?.nativeStatus?.receipt == nil,
            profile.pairingStatus?.claimedDeviceKey == nil,
            profile.pairingStatus?.credentialID == nil, profile.pairingStatus?.receiver == nil
          {
            action("Stop local setup", .discard, destructive: true)
          }
        }
        if let owner = profile.pairingStatus {
          LabeledContent("Pairing", value: owner.phase.rawValue)
        }
        if let native = snapshot?.nativeStatus?.receipt {
          LabeledContent("Native status", value: native.phase.rawValue)
        }
        if let confirmation = snapshot?.confirmation {
          VStack(alignment: .leading, spacing: NessaSpacing.xs) {
            Text("Device key").font(MessagesStyle.caption)
            Text(confirmation.deviceKey.map { String(format: "%02x", $0) }.joined())
              .font(MessagesStyle.caption.monospaced()).textSelection(.enabled)
          }
          action("Approve this device", .approve(confirmation))
        }
        DisclosureGroup("Details") {
          PhonePairingDetails(snapshot: snapshot)
        }
      }
      if store.phoneSetupBusy { ProgressView("Updating phone sync…") }
      if let error = store.phoneSyncError { Text(error).font(MessagesStyle.caption) }
    } header: {
      Text("Phone sync")
    } footer: {
      Text(
        "Confirm the device key before approval. Stopping locally does not cancel an invitation.")
    }
    .onAppear { nativeAddress = profile?.nativeAddress ?? "" }
  }

  private func action(
    _ title: String, _ operation: PhoneSetupOperation,
    enabled: Bool = true, destructive: Bool = false
  ) -> some View {
    Button(title, role: destructive ? .destructive : nil) {
      editingAddress = false
      Task { await store.performPhoneSetup(operation) }
    }.disabled(!idle || !enabled || (operation.requiresProductConnection && !remoteReady))
  }
}

private struct PhonePairingDetails: View {
  let snapshot: PhoneProfileSnapshot?
  var body: some View {
    if let profile = snapshot?.profile {
      detail("Profile", profile.id.uuidString)
      detail("Gateway", profile.identity.gatewayID)
      detail("Principal", profile.identity.principalID)
      detail("Product address", profile.productAddress)
      detail("Native address", profile.nativeAddress)
      if let owner = profile.pairingStatus {
        detail("Invitation", owner.invitationID.base64EncodedString())
        detail("Consent", owner.consentID.base64EncodedString())
        detail("Consent class", owner.consentClass)
        detail("Generation", String(owner.generation))
        detail("Expires at (ms)", String(owner.expiresAtMs))
        if let receiver = owner.receiver {
          detail("Receiver", receiver.id)
          detail("Access epoch", String(receiver.accessEpoch))
        }
        if let terminal = owner.terminal {
          detail("Terminal cause", terminal.cause.rawValue)
          detail("Initiator", String(describing: terminal.initiator))
        }
        LabeledContent("Cleanup pending", value: owner.cleanupPending ? "Yes" : "No")
      }
      if let receiver = profile.nativeReceiver { detail("Saved receiver", receiver) }
      if let failure = snapshot?.nativeStatus?.failure {
        detail("Native failure", String(describing: failure))
      }
      if let failure = snapshot?.nativeStatus?.purgeFailure {
        detail("Cleanup failure", String(describing: failure))
      }
      if let stopped = snapshot?.activationStopped { detail("Activation", stopped.rawValue) }
    }
  }
  private func detail(_ label: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: NessaSpacing.xxs) {
      Text(label).font(MessagesStyle.caption).foregroundStyle(MessagesStyle.secondary)
      Text(value).font(MessagesStyle.caption.monospaced()).textSelection(.enabled)
    }
  }
}
