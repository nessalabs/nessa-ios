import NessaFeatures
import UIKit

/// Contract controls the viewer. This native object supplies only decoded image pixels.
final class ExactComposerPhoto: ExactNativeInstance {
  private let pixels: UIView

  @MainActor init(composers: ExactComposers, props: [String: String], events: ExactNativeEvents) {
    pixels = composers.photo(token: props["editorKey"] ?? "", attachment: props["attachmentID"] ?? "",
      preview: props["photoMode"] == "preview")
    super.init(events: events)
  }

  override var view: ExactNativeView { pixels }
}
