import NessaDesignSystem
import SwiftUI
import UniformTypeIdentifiers

#if os(iOS)
  import PhotosUI
  import UIKit
#endif

struct MessageComposer: View {
  @Binding var draft: String
  @Binding var reply: MessageReply?
  @Binding var attachments: [DraftAttachment]
  @State private var preparation: Task<Void, Never>?
  @State private var preparationID = UUID()
  @State private var preparing = false
  @State private var filesPresented = false
  @State private var pickerError: String?
  #if os(iOS)
    @State private var cameraPresented = false
    @State private var photosPresented = false
    @State private var photoSelection: [PhotosPickerItem] = []
  #endif
  let recipient: String
  @ObservedObject var dictation: DictationViewModel
  let sending: Bool
  let connected: Bool
  let attachmentPolicy: AttachmentPolicy
  var submissionAllowed = true
  var submissionUnavailableReason: String? = nil
  var placeholder: String? = nil
  var autoFocus = false
  /// Lights the composer's rim while the agent is answering.
  var working = false
  let onSend: () -> Void
  @FocusState private var focused: Bool
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private enum Trailing: Equatable { case busy, dictate, send }
  private var trailing: Trailing {
    if preparing || dictation.state == .finishing { return .busy }
    if dictation.active
      || (draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachments.isEmpty)
    {
      return .dictate
    }
    return .send
  }
  private var sendAvailable: Bool { !sending && !preparing && connected && submissionAllowed }
  var body: some View {
    VStack(spacing: NessaSpacing.xs) {
      if let submissionUnavailableReason {
        Text(submissionUnavailableReason).font(MessagesStyle.caption)
          .foregroundStyle(MessagesStyle.secondary)
          .padding(.horizontal, MessagesStyle.horizontal)
      }
      if !attachments.isEmpty {
        DraftAttachmentsTray(attachments: $attachments, sending: sending)
          .transition(.move(edge: .bottom).combined(with: .opacity))
      }
      HStack(alignment: .bottom, spacing: NessaSpacing.sm) {
        Menu {
          #if os(iOS)
            Button("Camera", systemImage: "camera") {
              if UIImagePickerController.isSourceTypeAvailable(.camera) {
                cameraPresented = true
              } else {
                pickerError =
                  "Camera is unavailable on this device. Choose Photos or Add Files instead."
              }
            }
            Button("Photos", systemImage: "photo.on.rectangle") { photosPresented = true }
          #endif
          Button("Add Files", systemImage: "doc") { filesPresented = true }
        } label: {
          // As tall as the message field beside it, so the two share a centre line.
          NessaIcon(.plus)
            .frame(width: MessagesStyle.composerHeight, height: MessagesStyle.composerHeight)
            .contentShape(Circle())
            .messagesGlass()
        }.buttonStyle(.nessaPress)
          .disabled(sending || dictation.active || preparing).accessibilityLabel("Message actions")
        HStack(alignment: .bottom, spacing: NessaSpacing.xs) {
          TextField(placeholder ?? "Message \(recipient)", text: $draft, axis: .vertical)
            .focused($focused)
            .disabled(dictation.active)
            .font(MessagesStyle.body).lineLimit(1...6)
            .padding(.vertical, NessaSpacing.sm)
          Group {
            switch trailing {
            case .busy:
              ProgressView().accessibilityLabel(
                preparing ? "Preparing photos" : "Finishing dictation")
                .transition(.scale(scale: MessagesStyle.swapScale).combined(with: .opacity))
            case .dictate:
              Button {
                dictation.toggle()
              } label: {
                // The two glyphs cross-fade as dictation starts and stops.
                ZStack {
                  if dictation.active {
                    Image(systemName: "stop.circle.fill").font(MessagesStyle.icon)
                      .transition(.opacity)
                  } else {
                    NessaIcon(.wave).transition(.opacity)
                  }
                }
                  .animation(reduceMotion ? nil : NessaMotion.standard(), value: dictation.active)
                  .foregroundStyle(
                    dictation.active ? MessagesStyle.danger : MessagesStyle.secondary
                  )
                  .frame(width: MessagesStyle.controlHeight, height: MessagesStyle.controlHeight)
                  .contentShape(Rectangle())
              }
              .buttonStyle(.nessaPress)
              .disabled(sending || dictation.state == .finishing)
              .accessibilityLabel(dictation.active ? "Stop dictation" : "Dictate message")
              .transition(.scale(scale: MessagesStyle.swapScale).combined(with: .opacity))
            case .send:
              Button(action: onSend) {
                Image(systemName: "arrow.up").font(MessagesStyle.title)
                  .frame(width: MessagesStyle.sendButton, height: MessagesStyle.sendButton)
                  .background(
                    sendAvailable
                      ? AnyShapeStyle(MessagesStyle.outgoingFill)
                      : AnyShapeStyle(MessagesStyle.control),
                    in: Circle())
              }.buttonStyle(NessaPressStyle(scale: MessagesStyle.sendPressScale)).disabled(!sendAvailable)
                .accessibilityLabel("Send message")
                .accessibilityHint(submissionUnavailableReason ?? "")
                .transition(.scale(scale: MessagesStyle.swapScale).combined(with: .opacity))
            }
          }
          .frame(height: MessagesStyle.composerHeight)
          .animation(reduceMotion ? nil : NessaMotion.morph, value: trailing)
          .animation(reduceMotion ? nil : NessaMotion.standard(), value: sendAvailable)
        }.padding(.horizontal, NessaSpacing.md)
          .frame(minHeight: MessagesStyle.composerHeight).messagesComposerSurface()
          .nessaRim(
            active: working,
            in: RoundedRectangle(cornerRadius: MessagesStyle.composerRadius, style: .continuous))
      }.foregroundStyle(MessagesStyle.foreground)
        .padding(.horizontal, MessagesStyle.horizontal)
        .padding(.bottom, MessagesStyle.bottomInset)
    }
    .animation(reduceMotion ? nil : NessaMotion.enter, value: attachments.isEmpty)
    .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.7), trigger: sending) { old, new in
      !old && new
    }
    .fileImporter(
      isPresented: $filesPresented,
      allowedContentTypes: attachmentPolicy.allowsFiles ? [.item] : [.image],
      allowsMultipleSelection: true
    ) { result in
      startPreparation {
        do {
          for url in try result.get() {
            guard !Task.isCancelled else { return }
            add(try await PhotoProcessing.loadFile(url))
          }
        } catch {
          if !Task.isCancelled { pickerError = error.localizedDescription }
        }
      }
    }
    .onDisappear {
      cancelPreparation()
      dictation.cancel()
      // A composer off screen (its screen pushed under another, or gone back from) keeps no
      // keyboard up over the screen that took its place.
      focused = false
    }
    .onChange(of: dictation.transcriptRevision) { _, _ in
      if !dictation.transcript.isEmpty { draft = dictation.transcript }
    }
    .onChange(of: scenePhase) { _, phase in
      if phase == .background || (phase != .active && dictation.state != .requesting) {
        dictation.cancel()
      }
    }
    .onChange(of: autoFocus, initial: true) { _, value in if value { focused = true } }
    .onChange(of: reply?.id) { _, _ in if autoFocus { focused = true } }
    .alert(
      "Attachment",
      isPresented: Binding(get: { pickerError != nil }, set: { if !$0 { pickerError = nil } })
    ) {
      Button("OK") { pickerError = nil }
    } message: {
      Text(pickerError ?? "")
    }
    .alert(
      "Dictation",
      isPresented: Binding(
        get: { dictation.error != nil }, set: { if !$0 { dictation.error = nil } })
    ) {
      Button("OK") { dictation.error = nil }
    } message: {
      Text(dictation.error ?? "")
    }
    #if os(iOS)
      .photosPicker(
        isPresented: $photosPresented, selection: $photoSelection,
        maxSelectionCount: max(1, attachmentPolicy.maximumCount - attachments.count),
        matching: .images
      )
      .onChange(of: photoSelection) { _, selection in
        guard !selection.isEmpty else { return }
        startPreparation {
          for item in selection {
            guard !Task.isCancelled else { return }
            do {
              guard let raw = try await item.loadTransferable(type: Data.self)
              else { throw NessaGatewayError.rejected("This photo could not be loaded.") }
              guard !Task.isCancelled else { return }
              add(try await PhotoProcessing.prepare(raw, name: "Photo.jpg"))
            } catch {
              if !Task.isCancelled { pickerError = error.localizedDescription }
            }
          }
          photoSelection = []
        }
      }
      .sheet(isPresented: $cameraPresented) {
        CameraPicker { data in
          startPreparation {
            do { add(try await PhotoProcessing.prepare(data, name: "Camera.jpg")) } catch {
              if !Task.isCancelled { pickerError = error.localizedDescription }
            }
          }
        }.ignoresSafeArea()
      }
    #endif
  }
  private func cancelPreparation() {
    preparationID = UUID()
    preparation?.cancel()
    preparation = nil
    preparing = false
  }
  private func startPreparation(_ operation: @escaping @MainActor () async -> Void) {
    cancelPreparation()
    let id = preparationID
    preparing = true
    preparation = Task {
      await operation()
      if preparationID == id {
        preparing = false
        preparation = nil
      }
    }
  }
  private func add(_ attachment: DraftAttachment) {
    guard !sending, !Task.isCancelled else { return }
    do { try attachmentPolicy.validate(attachments + [attachment]) } catch {
      pickerError = error.localizedDescription
      return
    }
    attachments.append(attachment)
  }
}
