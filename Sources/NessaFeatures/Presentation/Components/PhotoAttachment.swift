import ImageIO
import NessaDesignSystem
import SwiftUI

struct PhotoAttachment: View {
  let id: String
  var draft = false
  var onOpen: (() -> Void)? = nil
  let load: () async -> Data?
  @State private var image: CGImage?
  @State private var data: Data?
  @State private var loaded = false
  @State private var preview = false
  var body: some View {
    Button {
      if let onOpen { onOpen() } else { preview = true }
    } label: {
      Group {
        if let image {
          Image(decorative: image, scale: 1).resizable()
            .aspectRatio(contentMode: draft ? .fill : .fit)
        } else {
          ZStack {
            MessagesStyle.control
            if loaded {
              VStack(spacing: NessaSpacing.xs) {
                Image(systemName: "photo")
                Text("Photo unavailable on this device").font(MessagesStyle.caption)
              }.foregroundStyle(MessagesStyle.secondary).padding(NessaSpacing.sm)
            } else {
              ProgressView().tint(MessagesStyle.foreground)
            }
          }.frame(
            height: draft ? MessagesStyle.photoDraftHeight : MessagesStyle.photoPlaceholderHeight)
        }
      }
      .frame(
        maxWidth: draft ? MessagesStyle.photoDraftWidth : MessagesStyle.photoWidth,
        maxHeight: draft ? MessagesStyle.photoDraftHeight : MessagesStyle.photoHeight
      )
      .frame(
        width: draft ? MessagesStyle.photoDraftWidth : nil,
        height: draft ? MessagesStyle.photoDraftHeight : nil
      )
      .clipped()
      .clipShape(
        RoundedRectangle(
          cornerRadius: draft ? MessagesStyle.photoDraftRadius : MessagesStyle.photoRadius)
      )
      .contentShape(RoundedRectangle(cornerRadius: MessagesStyle.photoRadius))
    }.buttonStyle(.plain).disabled(image == nil)
      .accessibilityLabel("Photo attachment. Open full screen")
      .task(id: id) {
        image = nil
        data = nil
        loaded = false
        let bytes = await load()
        let thumbnail =
          if let bytes {
            await PhotoProcessing.thumbnail(bytes, maximumDimension: draft ? 240 : 960)
          } else { nil as CGImage? }
        guard !Task.isCancelled else { return }
        data = bytes
        image = thumbnail
        loaded = true
      }
      .nessaPhotoPresentation(isPresented: $preview) {
        if let data { PhotoPreview(data: data) }
      }
  }
}

struct PhotoCanvas: View {
  let data: Data
  @State private var image: CGImage?
  @State private var scale: CGFloat = 1
  @GestureState private var magnification: CGFloat = 1
  var body: some View {
    GeometryReader { geometry in
      ScrollView(scale > 1 ? [.horizontal, .vertical] : [.vertical]) {
        Group {
          if let image {
            Image(decorative: image, scale: 1).resizable().scaledToFit()
          } else {
            ProgressView()
          }
        }.frame(
          width: geometry.size.width * scale * magnification,
          height: geometry.size.height * scale * magnification
        )
        .gesture(
          MagnifyGesture().updating($magnification) { value, state, _ in state = value.magnification
          }
          .onEnded { scale = min(max(scale * $0.magnification, 1), 4) }
        )
        .onTapGesture(count: 2) { withAnimation(NessaMotion.morph) { scale = scale == 1 ? 2 : 1 } }
      }.scrollDisabled(scale <= 1).scrollIndicators(.hidden)
    }.background(MessagesStyle.background)
      .task { image = await PhotoProcessing.thumbnail(data, maximumDimension: 2048) }
  }
}

private struct PhotoPreview: View {
  let data: Data
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    NavigationStack {
      PhotoCanvas(data: data).navigationTitle("Photo").nessaInlineNavigationTitle()
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
  }
}

extension View {
  @ViewBuilder func nessaPhotoPresentation<Preview: View>(
    isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Preview
  ) -> some View {
    #if os(iOS)
      self.fullScreenCover(isPresented: isPresented, content: content)
    #else
      self.sheet(isPresented: isPresented, content: content)
    #endif
  }
}
