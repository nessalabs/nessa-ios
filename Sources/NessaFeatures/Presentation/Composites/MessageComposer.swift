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
  let sending: Bool
  let connected: Bool
  let attachmentPolicy: AttachmentPolicy
  let onSend: () -> Void
  var body: some View {
    VStack(spacing: NessaSpacing.xs) {
      if let reply {
        HStack(spacing: NessaSpacing.sm) {
          Rectangle().fill(MessagesStyle.outgoing).frame(width: NessaSpacing.xs)
          VStack(alignment: .leading, spacing: NessaSpacing.xs) {
            Text("Replying to " + reply.author).font(MessagesStyle.caption).foregroundStyle(
              MessagesStyle.secondary)
            Text(reply.text).font(MessagesStyle.preview).lineLimit(2)
          }
          Spacer()
          Button {
            self.reply = nil
          } label: {
            Image(systemName: "xmark.circle.fill").font(MessagesStyle.icon)
          }
          .accessibilityLabel("Cancel reply")
        }.frame(maxHeight: MessagesStyle.photoDraftHeight).padding(NessaSpacing.sm)
          .background(
            MessagesStyle.control,
            in: RoundedRectangle(cornerRadius: MessagesStyle.photoDraftRadius)
          )
          .padding(.horizontal, MessagesStyle.horizontal)
      }
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
          Button("Clear draft") {
            cancelPreparation()
            reply = nil
            draft = ""
            attachments = []
          }.disabled(draft.isEmpty && attachments.isEmpty && !preparing && reply == nil)
        } label: {
          Image(systemName: "plus").font(MessagesStyle.icon)
            .frame(width: MessagesStyle.controlHeight, height: MessagesStyle.controlHeight)
            .messagesGlass()
        }.disabled(sending).accessibilityLabel("Message actions")
        HStack(spacing: NessaSpacing.xs) {
          TextField("Message \(recipient)", text: $draft, axis: .vertical)
            .font(MessagesStyle.body).lineLimit(1...6)
            .padding(.vertical, NessaSpacing.sm)
          if preparing {
            ProgressView().accessibilityLabel("Preparing photos")
          } else if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && attachments.isEmpty
          {
            Image(systemName: "waveform").font(MessagesStyle.icon).foregroundStyle(
              MessagesStyle.secondary
            )
            .accessibilityHidden(true)
          } else {
            Button(action: onSend) {
              Image(systemName: "arrow.up").font(MessagesStyle.title)
                .frame(width: MessagesStyle.sendButton, height: MessagesStyle.sendButton)
                .background(MessagesStyle.outgoing, in: Circle())
            }.disabled(sending || preparing || !connected).accessibilityLabel("Send message")
          }
        }.padding(.horizontal, NessaSpacing.md)
          .frame(minHeight: MessagesStyle.composerHeight).messagesGlass()
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
    .onDisappear { cancelPreparation() }
    .alert(
      "Attachment",
      isPresented: Binding(get: { pickerError != nil }, set: { if !$0 { pickerError = nil } })
    ) {
      Button("OK") { pickerError = nil }
    } message: {
      Text(pickerError ?? "")
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
