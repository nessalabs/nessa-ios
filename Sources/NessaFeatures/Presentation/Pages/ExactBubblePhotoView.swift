#if os(iOS)
import Combine
import UIKit

/// Displays only pixels for an image occurrence in the active, readable conversation.
@MainActor public final class ExactBubblePhotoView: UIImageView {
  private let store: MessagesViewModel
  private let status: (String) -> Void
  private var chat = ""
  private var item = ""
  private var scope = -1
  private var detail = false
  private var attachment: NessaStoredAttachment?
  private var loading: Task<Void, Never>?
  private var changes: AnyCancellable?
  private var revision = 0

  init(store: MessagesViewModel, status: @escaping (String) -> Void) {
    self.store = store
    self.status = status
    super.init(frame: .zero)
    clipsToBounds = true
    isUserInteractionEnabled = false
    isAccessibilityElement = false
    changes = store.objectWillChange.receive(on: RunLoop.main).sink { [weak self] in self?.refresh() }
  }

  required init?(coder: NSCoder) { nil }

  public func configure(_ props: [String: String]) {
    let nextChat = props["chat"] ?? ""
    let nextItem = props["item"] ?? ""
    let nextScope = Int(props["deliveryRevision"] ?? "") ?? -1
    let nextDetail = props["highResolution"] == "true"
    contentMode = props["imageFit"] == "contain" ? .scaleAspectFit : .scaleAspectFill
    guard nextChat != chat || nextItem != item || nextScope != scope || nextDetail != detail else { return }
    chat = nextChat
    item = nextItem
    scope = nextScope
    detail = nextDetail
    clear()
    refresh(force: true)
  }

  public func stop() {
    changes = nil
    clear()
  }

  private func clear() {
    revision += 1
    loading?.cancel()
    loading = nil
    image = nil
    attachment = nil
  }

  private var readable: NessaStoredAttachment? {
    guard !store.accessRevoked, scope == store.deliveryScopeRevision,
      let turns = store.views[chat]?.messages else { return nil }
    return ExactBubbleProjection.attachment(item, in: turns)
  }

  private func refresh(force: Bool = false) {
    let next = readable
    guard force || attachment != next else { return }
    clear()
    guard let next else { status("unavailable"); return }
    attachment = next
    let current = revision
    let maximum = detail ? 2048 : 960
    status("loading")
    loading = Task { [weak self, store] in
      let bytes = await store.imageData(for: next)
      guard !Task.isCancelled else { return }
      let thumbnail = if let bytes {
        await PhotoProcessing.thumbnail(bytes, maximumDimension: maximum)
      } else { nil as CGImage? }
      guard let self, !Task.isCancelled, current == revision, readable == next else { return }
      image = thumbnail.map { UIImage(cgImage: $0) }
      status(image == nil ? "unavailable" : "ready")
    }
  }
}

extension ExactPhoneSession {
  public func makeBubblePhoto(status: @escaping (String) -> Void) -> ExactBubblePhotoView {
    ExactBubblePhotoView(store: messages, status: status)
  }
}
#endif
