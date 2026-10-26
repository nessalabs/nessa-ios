import NessaDesignSystem
import SwiftUI

#if os(iOS)
  import AVFoundation
  import UIKit
#endif

/// Pair this phone with a desktop: point the camera at the orb in Settings ›
/// Linked devices › Pair a device on the Mac, or type the code beside it.
/// The Mac's owner then approves the phone there.
struct PairWithDesktopView: View {
  @ObservedObject var store: DesktopLinkViewModel
  @State private var typed = ""
  @State private var camera: CameraState = .asking
  @Environment(\.dismiss) private var dismiss
  #if os(iOS)
    @State private var reader = CameraOrbReader()
  #endif

  enum CameraState { case asking, ready, denied }

  var body: some View {
    ScrollView {
      VStack(spacing: NessaSpacing.lg) {
        Group {
          switch store.phase {
          case .idle, .failed:
            scanning
          case .finding:
            step("Looking for your Mac…", detail: nil)
          case .choosing(let found):
            choosing(found)
          case .enrolling(let gateway):
            step("Pairing with \(gateway.name)…", detail: nil)
          case .approving(let gateway):
            step(
              "Approve on \(gateway.name)",
              detail: "On your Mac, approve this phone in the Pair a device window.")
          case .linked(let desktop):
            linked(desktop)
          }
        }
        .transition(.opacity)
      }
      .animation(PairingStyle.stepAnimation, value: phaseKey)
      .padding(.horizontal, MessagesStyle.horizontal)
      .padding(.vertical, NessaSpacing.md)
    }
    .messagesScrollEdges()
    .messagesBar(edge: .top) { header.messagesHeaderGrain() }
    .foregroundStyle(MessagesStyle.foreground)
    .messagesAmbientGround()
    .task { await startCamera() }
    .onDisappear {
      #if os(iOS)
        reader.stop()
      #endif
      if store.busy { store.reset() }
    }
    .onChange(of: phaseKey) { _, key in
      #if os(iOS)
        // Not on a failure: the Mac still shows the same orb, which would be
        // read and sent again at once. Scanning resumes from "Scan again".
        if key == "idle" {
          if camera == .ready { start() }
        } else {
          reader.stop()
        }
      #else
        _ = key
      #endif
    }
  }

  private var phaseKey: String {
    switch store.phase {
    case .idle: return "idle"
    case .finding: return "finding"
    case .choosing: return "choosing"
    case .enrolling: return "enrolling"
    case .approving: return "approving"
    case .linked: return "linked"
    case .failed: return "failed"
    }
  }

  private var header: some View {
    HStack(spacing: NessaSpacing.sm) {
      Text("Pair with your Mac").font(AgentDetailsStyle.title)
        .accessibilityAddTraits(.isHeader)
      Spacer(minLength: NessaSpacing.xs)
      Button { dismiss() } label: {
        Image(systemName: "xmark").font(MessagesStyle.icon)
          .frame(width: MessagesStyle.controlHeight, height: MessagesStyle.controlHeight)
          .messagesGlass()
      }
      .buttonStyle(.nessaPress)
      .accessibilityLabel("Close pairing")
    }
    .frame(minHeight: MessagesStyle.controlHeight)
    .padding(.horizontal, MessagesStyle.horizontal)
    .padding(.top, NessaSpacing.sm)
  }

  @ViewBuilder private var scanning: some View {
    VStack(spacing: NessaSpacing.md) {
      cameraWindow
      Text("On your Mac, open Settings › Linked devices › Pair a device, then point your camera at the orb.")
        .font(MessagesStyle.body).foregroundStyle(MessagesStyle.secondary)
        .multilineTextAlignment(.center)
      if case .failed(let failure) = store.phase {
        Text(DesktopLinkViewModel.sentence(failure)).font(MessagesStyle.caption)
          .foregroundStyle(MessagesStyle.danger).multilineTextAlignment(.center)
        Button("Scan again") { store.reset() }
          .font(MessagesStyle.body).foregroundStyle(MessagesStyle.secondary)
          .buttonStyle(.nessaPress)
      }
      VStack(spacing: 0) {
        TextField("Or type the code", text: $typed)
          .font(PairingStyle.codeFont).multilineTextAlignment(.center)
          .nessaCodeInput()
          .frame(maxWidth: .infinity, minHeight: MessagesStyle.controlHeight)
          .onSubmit(submitTyped)
      }
      .nessaCard()
      Button(action: submitTyped) {
        Text("Pair").frame(maxWidth: .infinity)
      }
      .buttonStyle(.nessaPrimary).disabled(OrbCode.parse(typed) == nil)
    }
  }

  @ViewBuilder private var cameraWindow: some View {
    ZStack {
      RoundedRectangle(cornerRadius: PairingStyle.windowRadius).fill(MessagesStyle.control)
      switch camera {
      case .ready:
        #if os(iOS)
          CameraPreview(session: reader.session)
            .clipShape(RoundedRectangle(cornerRadius: PairingStyle.windowRadius))
        #endif
      case .asking:
        Image(systemName: "camera").font(MessagesStyle.icon)
          .foregroundStyle(MessagesStyle.secondary)
      case .denied:
        Text("Allow the camera in Settings to scan the orb, or type the code below.")
          .font(MessagesStyle.caption).foregroundStyle(MessagesStyle.secondary)
          .multilineTextAlignment(.center).padding(NessaSpacing.md)
      }
    }
    .frame(width: PairingStyle.window, height: PairingStyle.window)
    .overlay(
      RoundedRectangle(cornerRadius: PairingStyle.windowRadius)
        .strokeBorder(NessaColor.hairline, lineWidth: PairingStyle.windowRim)
    )
    .accessibilityLabel("Camera")
  }

  private func step(_ title: String, detail: String?) -> some View {
    VStack(spacing: NessaSpacing.sm) {
      LoadingLabel(text: title)
      if let detail {
        Text(detail).font(MessagesStyle.body).foregroundStyle(MessagesStyle.secondary)
          .multilineTextAlignment(.center)
      }
      Button("Cancel") { store.reset() }
        .font(MessagesStyle.body).foregroundStyle(MessagesStyle.secondary)
        .buttonStyle(.nessaPress)
    }
    .frame(maxWidth: .infinity, minHeight: PairingStyle.window)
  }

  private func choosing(_ found: [FoundGateway]) -> some View {
    VStack(alignment: .leading, spacing: NessaSpacing.sm) {
      Text("Which Mac?").font(MessagesStyle.title)
      VStack(spacing: 0) {
        ForEach(found) { gateway in
          Button { store.choose(gateway) } label: {
            HStack {
              Image(systemName: "desktopcomputer")
              Text(gateway.name)
              Spacer()
              Image(systemName: "chevron.right").font(MessagesStyle.smallIcon)
                .foregroundStyle(MessagesStyle.separator)
            }
            .padding(.horizontal, NessaSpacing.md)
            .frame(maxWidth: .infinity, minHeight: MessagesStyle.controlHeight)
          }
          .buttonStyle(.nessaPress)
        }
      }
      .font(MessagesStyle.body).nessaCard()
    }
  }

  private func linked(_ desktop: LinkedDesktop) -> some View {
    VStack(spacing: NessaSpacing.md) {
      Image(systemName: "checkmark.circle").font(MessagesStyle.icon)
        .foregroundStyle(NessaColor.accent)
      Text("Paired with \(desktop.name)").font(MessagesStyle.title)
      Text("Chats your Mac shares with this phone appear here. Share one from its Share menu on the Mac.")
        .font(MessagesStyle.body).foregroundStyle(MessagesStyle.secondary)
        .multilineTextAlignment(.center)
      Button { dismiss() } label: { Text("Done").frame(maxWidth: .infinity) }
        .buttonStyle(.nessaPrimary)
    }
    .frame(maxWidth: .infinity, minHeight: PairingStyle.window)
  }

  private func submitTyped() {
    guard OrbCode.parse(typed) != nil else { return }
    store.submit(code: typed)
  }

  private func startCamera() async {
    #if os(iOS)
      let availability = await CameraOrbReader.availability()
      // Closed while the camera prompt was up: nothing is left to stop it.
      guard !Task.isCancelled else { return }
      switch availability {
      case .ready:
        camera = .ready
        if phaseKey == "idle" { start() }
      default:
        camera = .denied
      }
    #else
      camera = .denied
    #endif
  }

  #if os(iOS)
    private func start() {
      reader.start { code in
        Task { @MainActor in
          guard !store.busy else { return }
          typed = code
          UIImpactFeedbackGenerator(style: .light).impactOccurred()
          store.submit(code: code)
        }
      }
    }
  #endif
}

/// A plain label that shimmers while something is under way.
private struct LoadingLabel: View {
  let text: String
  var body: some View {
    Text(text).font(MessagesStyle.title).nessaShimmer(active: true)
      .multilineTextAlignment(.center)
  }
}

#if os(iOS)
  /// The camera's live picture, filling its window.
  private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> PreviewView {
      let view = PreviewView()
      view.preview.session = session
      view.preview.videoGravity = .resizeAspectFill
      return view
    }
    func updateUIView(_ view: PreviewView, context: Context) {}
    final class PreviewView: UIView {
      override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
      var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
  }
#endif
