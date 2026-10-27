import ImageIO
import NessaDesignSystem
import SwiftUI

/// One message owns one swipeable photo stack; occurrence indices allow duplicate images.
struct PhotoAttachmentsGroup: View {
  let attachments: [NessaStoredAttachment]
  var reaction: String? = nil
  var onReact: ((String) -> Void)? = nil
  var onReply: (() -> Void)? = nil
  let load: (NessaStoredAttachment) async -> Data?
  @State private var page = 0
  @Environment(\.messageContext) private var messageContext
  @State private var thumbnails: [String: CGImage] = [:]
  @State private var loaded: Set<String> = []
  private struct GalleryRequest: Identifiable {
    let id = UUID()
    let initialPage: Int?
  }
  @State private var galleryRequest: GalleryRequest?
  var body: some View {
    VStack(spacing: NessaSpacing.xs) {
      PhotoCardStack(count: attachments.count, selection: $page) { index in
        let attachment = attachments[index]
        PhotoStackCard(
          image: thumbnails[attachment.digest], loaded: loaded.contains(attachment.digest)
        ) {
          guard messageContext?.selection == nil else { return }
          galleryRequest = GalleryRequest(initialPage: index)
        }
      }.frame(width: MessagesStyle.photoWidth, height: MessagesStyle.photoStackHeight)
        .messageReaction(
          reaction: reaction, outgoing: true, onReact: onReact, onReply: onReply,
          preview: AnyView(
            PhotoStackCard(
              image: attachments.isEmpty
                ? nil : thumbnails[attachments[min(page, attachments.count - 1)].digest],
              loaded: !attachments.isEmpty
                && loaded.contains(attachments[min(page, attachments.count - 1)].digest)
            ) {})
        )
        .padding(.top, reaction == nil && attachments.count > 1 ? NessaSpacing.sm : 0)
      if attachments.count > 1 {
        HStack {
          Spacer()
          Button("View all") {
            galleryRequest = GalleryRequest(initialPage: nil)
          }.font(MessagesStyle.caption)
        }.foregroundStyle(MessagesStyle.secondary).frame(width: MessagesStyle.photoWidth)
      }
    }.task(id: attachments.map(\.digest)) {
      let activeDigests = Set(attachments.map(\.digest))
      thumbnails = thumbnails.filter { activeDigests.contains($0.key) }
      loaded.formIntersection(activeDigests)
      // Prepare each distinct image once. Paging only moves already-decoded cards.
      for attachment in attachments where !loaded.contains(attachment.digest) {
        let bytes = await load(attachment)
        guard !Task.isCancelled else { return }
        let image =
          if let bytes {
            await PhotoProcessing.thumbnail(bytes, maximumDimension: 960)
          } else { nil as CGImage? }
        guard !Task.isCancelled else { return }
        thumbnails[attachment.digest] = image
        loaded.insert(attachment.digest)
      }
    }.onChange(of: attachments.count) { _, count in
      page = min(page, max(0, count - 1))
    }.nessaGalleryPresentation(item: $galleryRequest) { request in
      PhotoGallery(attachments: attachments, initialPage: request.initialPage, load: load)
    }
  }
}

private struct PhotoGallery: View {
  let attachments: [NessaStoredAttachment]
  let load: (NessaStoredAttachment) async -> Data?
  @State private var selected: Int?
  @Environment(\.dismiss) private var dismiss
  init(
    attachments: [NessaStoredAttachment], initialPage: Int?,
    load: @escaping (NessaStoredAttachment) async -> Data?
  ) {
    self.attachments = attachments
    self.load = load
    _selected = State(initialValue: initialPage)
  }
  var body: some View {
    NavigationStack {
      Group {
        if selected != nil {
          LoopingPhotoPager(
            count: attachments.count,
            selection: Binding(get: { selected ?? 0 }, set: { selected = $0 })
          ) { index in
            GalleryPhotoPage(attachment: attachments[index], load: load)
          }
        } else {
          ScrollView {
            LazyVGrid(
              columns: Array(
                repeating: GridItem(.flexible(), spacing: MessagesStyle.gallerySpacing), count: 3),
              spacing: MessagesStyle.gallerySpacing
            ) {
              ForEach(Array(attachments.enumerated()), id: \.offset) { index, attachment in
                PhotoAttachment(id: attachment.digest, draft: true, onOpen: { selected = index }) {
                  await load(attachment)
                }
              }
            }.padding(NessaSpacing.sm)
          }
        }
      }.background(MessagesStyle.background)
        .navigationTitle(selected == nil ? "All photos" : "Photos")
        .nessaInlineNavigationTitle()
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            if selected != nil {
              Button("View all", systemImage: "square.grid.2x2") { selected = nil }
            }
          }
          ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
    }
  }
}

private struct GalleryPhotoPage: View {
  let attachment: NessaStoredAttachment
  let load: (NessaStoredAttachment) async -> Data?
  @State private var data: Data?
  @State private var loaded = false
  var body: some View {
    Group {
      if let data {
        PhotoCanvas(data: data)
      } else if loaded {
        Text("Photo unavailable on this device").font(MessagesStyle.body).foregroundStyle(
          MessagesStyle.secondary)
      } else {
        ProgressView()
      }
    }.task(id: attachment.digest) {
      let bytes = await load(attachment)
      guard !Task.isCancelled else { return }
      data = bytes
      loaded = true
    }
  }
}

extension View {
  @ViewBuilder fileprivate func nessaGalleryPresentation<Item: Identifiable, Content: View>(
    item: Binding<Item?>, @ViewBuilder content: @escaping (Item) -> Content
  ) -> some View {
    #if os(iOS)
      self.fullScreenCover(item: item, content: content)
    #else
      self.sheet(item: item, content: content)
    #endif
  }

}
