import NessaDesignSystem
import SwiftUI

/// A screen-level highlight keeps the selected message between two separate surfaces.
struct MessageContextOverlay: View {
  @ObservedObject var controller: MessageContextController
  @State private var emojiRequest: MessageContextSelection?
  private let favorites = ["❤️", "👍", "👎", "😂", "‼️", "❓", "💀", "😁"]
  private let more = [
    "😊", "🎉", "🔥", "👀", "🙏", "✅", "🤔", "🥰", "😮", "😢", "🙌", "💯", "💙", "⭐️", "🚀", "🤝", "😅", "💪", "💀",
    "😭", "😎", "✨", "🫶", "🤯",
  ]
  var body: some View {
    GeometryReader { geometry in
      if let selected = controller.selection {
        MessageContextStage(
          selected: selected, geometry: geometry, palette: palette(selected),
          paletteCount: favorites.count,
          actions: actions(selected), selector: selector(selected),
          dismiss: { controller.selection = nil }
        )
        .id(selected.id)
        .transition(.asymmetric(insertion: .identity, removal: .opacity))
      }
    }.sheet(item: $emojiRequest) { selected in
      NavigationStack {
        ScrollView {
          LazyVGrid(
            columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: NessaSpacing.sm
          ) {
            ForEach(favorites + more.filter { !favorites.contains($0) }, id: \.self) { emoji in
              reactionButton(emoji, selected: selected)
            }
          }.padding(NessaSpacing.md)
        }.navigationTitle("Choose a reaction").nessaInlineNavigationTitle()
          .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { emojiRequest = nil } }
          }
      }.presentationDetents([.medium, .large])
    }
  }
  private func palette(_ selected: MessageContextSelection) -> some View {
    ScrollView(.horizontal) {
      HStack(spacing: MessagesStyle.reactionPaletteSpacing) {
        ForEach(favorites, id: \.self) { emoji in reactionButton(emoji, selected: selected) }
      }.padding(NessaSpacing.xs)
    }.scrollIndicators(.hidden)
      // Opaque under the glass, so the bubble behind never tints an emoji, and clipped to the
      // capsule, so a scrolled item ends at its rounded edge.
      .background(MessagesStyle.incoming, in: Capsule()).clipShape(Capsule()).messagesGlass()
  }
  private func selector(_ selected: MessageContextSelection) -> some View {
    Button {
      emojiRequest = selected
      controller.selection = nil
    } label: {
      TapbackMoreSymbol()
    }
    .buttonStyle(.plain).accessibilityLabel("More emoji reactions")
  }

  private func reactionButton(_ emoji: String, selected: MessageContextSelection) -> some View {
    Button {
      selected.react(emoji)
      controller.selection = nil
      emojiRequest = nil
    } label: {
      TapbackSymbol(value: emoji)
        .frame(
          width: MessagesStyle.reactionPaletteControl, height: MessagesStyle.reactionPaletteControl
        )
        .background(selected.reaction == emoji ? MessagesStyle.outgoing : .clear, in: Circle())
    }.buttonStyle(.plain).accessibilityLabel(
      selected.reaction == emoji ? "Remove \(emoji) reaction" : "React \(emoji)")
  }
  private func actions(_ selected: MessageContextSelection) -> some View {
    VStack(spacing: 0) {
      if let reply = selected.reply {
        Button {
          controller.selection = nil
          reply()
        } label: {
          actionLabel("Reply", icon: "arrowshape.turn.up.left")
        }
      }
      if let copy = selected.copy {
        Button {
          controller.selection = nil
          copy()
        } label: {
          actionLabel("Copy", icon: "doc.on.doc")
        }
      }
      if selected.shareText != nil || selected.reaction != nil {
        Menu {
          if let text = selected.shareText {
            ShareLink(item: text) { Label("Share", systemImage: "square.and.arrow.up") }
          }
          if let reaction = selected.reaction {
            Button("Remove reaction", systemImage: "minus.circle") {
              selected.react(reaction)
              controller.selection = nil
            }
          }
        } label: {
          actionLabel("More…", icon: "ellipsis.circle")
        }
      }
    }.buttonStyle(.plain)
  }
  private func actionLabel(_ title: String, icon: String) -> some View {
    HStack(spacing: NessaSpacing.md) {
      Image(systemName: icon).font(MessagesStyle.icon).frame(width: MessagesStyle.sendButton)
      Text(title).font(MessagesStyle.body)
      Spacer()
    }.foregroundStyle(MessagesStyle.foreground).padding(.horizontal, NessaSpacing.md)
      .frame(height: MessagesStyle.actionRowHeight).contentShape(Rectangle())
  }
}

private struct MessageContextStage<Palette: View, Actions: View, Selector: View>: View {
  let selected: MessageContextSelection
  let geometry: GeometryProxy
  let palette: Palette
  let paletteCount: Int
  let actions: Actions
  let selector: Selector
  let dismiss: () -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var revealed = false
  var body: some View {
    ZStack {
      let inset = NessaSpacing.md
      let actionCount =
        (selected.reply == nil ? 0 : 1) + (selected.copy == nil ? 0 : 1)
        + (selected.shareText == nil && selected.reaction == nil ? 0 : 1)
      let menuHeight = CGFloat(actionCount) * MessagesStyle.actionRowHeight
      let topRoom = MessagesStyle.reactionPaletteHeight + NessaSpacing.sm
      let bottomRoom = menuHeight + NessaSpacing.md
      let maxHeight = max(
        MessagesStyle.controlHeight,
        geometry.size.height - MessagesStyle.messageContextTopInset
          - MessagesStyle.messageContextBottomInset - topRoom - bottomRoom)
      let height = min(selected.imageSize.height, maxHeight)
      let width = min(selected.frame.width, geometry.size.width - inset * 2)
      let originalTop = selected.frame.minY - geometry.frame(in: .global).minY
      let originalX = selected.frame.midX - geometry.frame(in: .global).minX
      let top = min(
        max(originalTop, MessagesStyle.messageContextTopInset + topRoom),
        geometry.size.height - MessagesStyle.messageContextBottomInset - height - bottomRoom)
      let x = min(max(originalX, inset + width / 2), geometry.size.width - inset - width / 2)
      // As wide as a whole number of reactions, so none rests cut in half at the edge.
      let paletteItem = MessagesStyle.reactionPaletteControl + MessagesStyle.reactionPaletteSpacing
      let paletteRoom = min(MessagesStyle.reactionPickerWidth, geometry.size.width - inset * 2)
      let paletteFit = min(
        CGFloat(paletteCount),
        ((paletteRoom - NessaSpacing.xs * 2 + MessagesStyle.reactionPaletteSpacing) / paletteItem)
          .rounded(.down))
      let paletteWidth =
        paletteFit * paletteItem - MessagesStyle.reactionPaletteSpacing + NessaSpacing.xs * 2
      let paletteX =
        selected.outgoing
        ? geometry.size.width - inset - paletteWidth / 2 : inset + paletteWidth / 2
      let menuX =
        selected.outgoing
        ? geometry.size.width - inset - MessagesStyle.actionMenuWidth / 2
        : inset + MessagesStyle.actionMenuWidth / 2
      MessagesStyle.background.opacity(revealed ? MessagesStyle.messageContextDim : 0)
        .contentShape(Rectangle()).onTapGesture { dismiss() }
      selected.image.resizable()
        .frame(width: width, height: selected.imageSize.height * width / selected.imageSize.width)
        .frame(width: width, height: height, alignment: .top).clipped()
        .position(x: x, y: revealed || reduceMotion ? top + height / 2 : originalTop + height / 2)
        .allowsHitTesting(false)
      palette.frame(width: paletteWidth, height: MessagesStyle.reactionPaletteHeight)
        .scaleEffect(revealed || reduceMotion ? 1 : MessagesStyle.contextPopScale, anchor: .bottom)
        .opacity(revealed ? 1 : 0)
        .position(x: paletteX, y: top - NessaSpacing.sm - MessagesStyle.reactionPaletteHeight / 2)
      let selectorHalf = MessagesStyle.reactionPaletteControl / 2
      let selectorX =
        selected.outgoing
        ? max(
          inset + selectorHalf, x - width / 2 - MessagesStyle.reactionSelectorGap - selectorHalf)
        : min(
          geometry.size.width - inset - selectorHalf,
          x + width / 2 + MessagesStyle.reactionSelectorGap + selectorHalf)
      selector.frame(
        width: MessagesStyle.reactionPaletteControl, height: MessagesStyle.reactionSelectorHeight
      )
      .scaleEffect(revealed || reduceMotion ? 1 : MessagesStyle.contextPopScale, anchor: .top)
      .opacity(revealed ? 1 : 0)
      .position(x: selectorX, y: top + MessagesStyle.reactionSelectorHeight / 2)
      if actionCount > 0 {
        actions.frame(width: MessagesStyle.actionMenuWidth, height: menuHeight)
          .background(
            .regularMaterial, in: RoundedRectangle(cornerRadius: MessagesStyle.actionMenuRadius)
          )
          .scaleEffect(
            revealed || reduceMotion ? 1 : MessagesStyle.contextActionScale, anchor: .top
          )
          .opacity(revealed ? 1 : 0)
          .position(x: menuX, y: top + height + NessaSpacing.md + menuHeight / 2)
      }
    }.onAppear {
      withAnimation(
        reduceMotion
          ? .easeOut(duration: MessagesStyle.contextFadeDuration)
          : .spring(
            duration: MessagesStyle.contextSpringDuration, bounce: MessagesStyle.contextSpringBounce
          )
      ) {
        revealed = true
      }
    }
  }
}
