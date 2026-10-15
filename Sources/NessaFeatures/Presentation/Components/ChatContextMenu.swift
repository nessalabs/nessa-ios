import NessaDesignSystem
import SwiftUI

#if os(iOS)
  import UIKit

  /// Native preview commit owns navigation; content and menu actions stay shared SwiftUI values.
  private struct NativeChatContextMenu: UIViewRepresentable {
    let onTap: () -> Void
    let makeConfiguration: () -> Configuration
    var enabled: Bool
    struct Configuration {
      let preview: AnyView
      let actions: [ChatMenuAction]
      let prepare: () -> Void
      let commit: () -> Void
    }
    func makeUIView(context: Context) -> Control { Control() }
    func updateUIView(_ view: Control, context: Context) {
      view.onTap = onTap
      view.makeConfiguration = makeConfiguration
      view.isUserInteractionEnabled = enabled
    }
    static func dismantleUIView(_ view: Control, coordinator: Void) {
      if !view.isCommitting { view.contextMenu.dismissMenu() }
    }
    final class Control: UIView, UIContextMenuInteractionDelegate {
      private(set) var isCommitting = false
      var onTap: (() -> Void)?
      var makeConfiguration: (() -> Configuration)?
      private final class FrozenConfiguration: NSObject, NSCopying {
        let value: Configuration
        init(_ value: Configuration) { self.value = value }
        func copy(with zone: NSZone? = nil) -> Any { self }
      }
      lazy var contextMenu = UIContextMenuInteraction(delegate: self)
      override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isAccessibilityElement = false
        addInteraction(contextMenu)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
      }
      required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
      @objc private func tapped() { onTap?() }
      func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        configurationForMenuAtLocation location: CGPoint
      ) -> UIContextMenuConfiguration? {
        guard isUserInteractionEnabled, let selected = makeConfiguration?() else { return nil }
        selected.prepare()
        return UIContextMenuConfiguration(
          identifier: FrozenConfiguration(selected),
          previewProvider: {
            let controller = UIHostingController(rootView: selected.preview)
            controller.preferredContentSize = CGSize(
              width: MessagesStyle.previewWidth, height: MessagesStyle.previewHeight)
            controller.view.backgroundColor = UIColor(MessagesStyle.background)
            controller.overrideUserInterfaceStyle = .dark
            return controller
          },
          actionProvider: { _ in
            UIMenu(
              children: selected.actions.map { value in
                var attributes: UIMenuElement.Attributes = []
                if value.destructive { attributes.insert(.destructive) }
                if !value.enabled { attributes.insert(.disabled) }
                return UIAction(
                  title: value.title, image: UIImage(systemName: value.symbol),
                  attributes: attributes
                ) { _ in value.perform() }
              })
          })
      }
      func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration,
        animator: any UIContextMenuInteractionCommitAnimating
      ) {
        guard let frozen = configuration.identifier as? FrozenConfiguration else { return }
        isCommitting = true
        animator.preferredCommitStyle = .pop
        animator.addAnimations {
          var transaction = Transaction(animation: nil)
          transaction.disablesAnimations = true
          withTransaction(transaction) { frozen.value.commit() }
        }
        // Navigation can dismantle the source; keep it alive through UIKit's commit.
        animator.addCompletion { self.isCommitting = false }
      }

    }
  }
#endif

private struct ChatMenuModifier: ViewModifier {
  @ObservedObject var store: MessagesViewModel
  let identifier: String
  let enabled: Bool
  let onTap: () -> Void
  let onCommit: (String) -> Void
  let onArchive: (String) -> Void
  let onDelete: (String) -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  /// Pinning from the menu moves the inbox's list and grid on one spring.
  private var layoutAnimation: Animation? { reduceMotion ? nil : NessaMotion.enter }
  private func configurationSelection() -> ChatMenuSelection {
    .init(identifier: identifier, store: store)
  }
  func body(content: Content) -> some View {
    #if os(iOS)
      content.accessibilityActions {
        if enabled {
          let selected = configurationSelection()
          Button("Open conversation") {
            if selected.isCurrent(in: store), let id = selected.conversationID { onCommit(id) }
          }.disabled(selected.conversationID == nil)
          ForEach(chatMenuActions(
            selection: selected, store: store, layoutAnimation: layoutAnimation, onArchive: onArchive,
            onDelete: onDelete)) {
            action in
            Button(action.title, action: action.perform).disabled(!action.enabled)
          }
        }
      }.overlay {
        NativeChatContextMenu(
          onTap: onTap,
          makeConfiguration: {
            let selected = configurationSelection()
            return .init(
              preview: AnyView(ChatConversationPreview(store: store, selection: selected)),
              actions: chatMenuActions(
            selection: selected, store: store, layoutAnimation: layoutAnimation, onArchive: onArchive,
            onDelete: onDelete),
              prepare: {
                Task {
                  if selected.isCurrent(in: store) { await store.loadPreview(selected.identifier) }
                }
              },
              commit: {
                guard selected.isCurrent(in: store), let id = selected.conversationID else {
                  return
                }
                onCommit(id)
              })
          }, enabled: enabled)
      }
    #else
      if enabled {
        let selected = configurationSelection()
        content.contextMenu {
          Button("Open conversation") {
            if selected.isCurrent(in: store), let id = selected.conversationID { onCommit(id) }
          }.disabled(selected.conversationID == nil)
          ForEach(chatMenuActions(
            selection: selected, store: store, layoutAnimation: layoutAnimation, onArchive: onArchive,
            onDelete: onDelete)) {
            action in
            Button(
              action.title, systemImage: action.symbol,
              role: action.destructive ? .destructive : nil
            ) { action.perform() }
            .disabled(!action.enabled)
          }
        } preview: {
          ChatConversationPreview(store: store, selection: selected).task {
            await store.loadPreview(identifier)
          }
        }
      } else {
        content
      }
    #endif
  }
}
extension View {
  func chatContextMenu(
    store: MessagesViewModel, identifier: String, enabled: Bool = true,
    onTap: @escaping () -> Void, onCommit: @escaping (String) -> Void,
    onArchive: @escaping (String) -> Void, onDelete: @escaping (String) -> Void
  ) -> some View {
    modifier(
      ChatMenuModifier(
        store: store, identifier: identifier, enabled: enabled,
        onTap: onTap, onCommit: onCommit, onArchive: onArchive, onDelete: onDelete))
  }
}
