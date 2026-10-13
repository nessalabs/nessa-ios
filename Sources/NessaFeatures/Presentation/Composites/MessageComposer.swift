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
  var placeholder: String? = nil
  var autoFocus = false
  let onSend: () -> Void
  @FocusState private var focused: Bool
  @Environment(\.scenePhase) private var scenePhase
  var body: some View {
    VStack(spacing: NessaSpacing.xs) {
      if !attachments.isEmpty { DraftAttachmentsTray(attachments: $attachments, sending: sending) }
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
          Image(systemName: "plus").font(MessagesStyle.icon)
            .frame(width: MessagesStyle.controlHeight, height: MessagesStyle.controlHeight)
            .messagesGlass()
        }.disabled(sending || dictation.active || preparing).accessibilityLabel("Message actions")
        HStack(alignment: .bottom, spacing: NessaSpacing.xs) {
          TextField(placeholder ?? "Message \(recipient)", text: $draft, axis: .vertical)
            .focused($focused)
            .disabled(dictation.active)
            .font(MessagesStyle.body).lineLimit(1...6)
            .padding(.vertical, NessaSpacing.sm)
          Group {
            if preparing || dictation.state == .finishing {
              ProgressView().accessibilityLabel(
                preparing ? "Preparing photos" : "Finishing dictation")
            } else if dictation.active
              || (draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && attachments.isEmpty)
            {
              Button {
                dictation.toggle()
              } label: {
                Image(systemName: dictation.active ? "stop.circle.fill" : "waveform")
                  .font(MessagesStyle.icon)
                  .foregroundStyle(
                    dictation.active ? MessagesStyle.danger : MessagesStyle.secondary
                  )
                  .frame(width: MessagesStyle.controlHeight, height: MessagesStyle.controlHeight)
                  .contentShape(Rectangle())
              }
              .disabled(sending || dictation.state == .finishing)
              .accessibilityLabel(dictation.active ? "Stop dictation" : "Dictate message")
            } else {
              Button(action: onSend) {
                Image(systemName: "arrow.up").font(MessagesStyle.title)
                  .frame(width: MessagesStyle.sendButton, height: MessagesStyle.sendButton)
                  .background(MessagesStyle.outgoing, in: Circle())
              }.disabled(sending || preparing || !connected || !submissionAllowed)
                .accessibilityLabel("Send message")
            }
          }
          .frame(height: MessagesStyle.composerHeight)
        }.padding(.horizontal, NessaSpacing.md)
          .frame(minHeight: MessagesStyle.composerHeight).messagesComposerSurface()
      }.foregroundStyle(MessagesStyle.foreground)
        .padding(.horizontal, MessagesStyle.horizontal)
        .padding(.bottom, MessagesStyle.bottomInset)
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
