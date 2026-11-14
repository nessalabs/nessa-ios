#if os(iOS)
import Combine
import UIKit

/// Supplies pixels to the Contract photo viewer, bound to the same draft, attachment and
/// delivery scope. The full-resolution image never enters the data store or view snapshot.
@MainActor final class ExactDraftPhoto: UIImageView {
  private var subscriptions = Set<AnyCancellable>()
  private var loading: Task<Void, Never>?

  init(editor: ExactComposerDraft, id: UUID, preview: Bool) {
    super.init(frame: .zero)
    contentMode = preview ? .scaleAspectFit : .scaleAspectFill
    clipsToBounds = true
    isUserInteractionEnabled = false
    guard let file = editor.draft.attachments.first(where: { $0.id == id && $0.isImage }) else { return }
    editor.phone.messages.$deliveryScopeRevision.removeDuplicates().dropFirst()
      .sink { [weak self] _ in self?.clear() }.store(in: &subscriptions)
    editor.draft.$attachments.sink { [weak self] files in
      if !files.contains(where: { $0.id == id }) { self?.clear() }
    }.store(in: &subscriptions)
    loading = Task { [weak self, weak editor] in
      let pixels = await PhotoProcessing.thumbnail(file.data, maximumDimension: preview ? 2048 : 192)
      guard let self, let editor, editor.valid, !Task.isCancelled,
        editor.draft.attachments.contains(where: { $0.id == id }) else { return }
      self.image = pixels.map { UIImage(cgImage: $0) }
    }
  }

  @available(*, unavailable) required init?(coder: NSCoder) { fatalError("Use init(editor:id:)") }

  private func clear() {
    loading?.cancel()
    image = nil
  }
}
#endif
