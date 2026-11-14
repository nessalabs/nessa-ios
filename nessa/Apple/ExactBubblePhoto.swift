import NessaFeatures
import UIKit

/// Exact lays out and owns the controls around this scope-bound, read-only pixel surface.
final class ExactBubblePhoto: ExactNativeInstance {
  private let photo: ExactBubblePhotoView

  @MainActor init(phone: ExactPhoneSession, props: [String: String], events: ExactNativeEvents) {
    photo = phone.makeBubblePhoto(status: events.message)
    super.init(events: events)
    photo.configure(props)
  }

  override var view: ExactNativeView { photo }

  override func setProps(_ props: [String: String]) throws {
    MainActor.assumeIsolated { photo.configure(props) }
  }

  override func destroy() { MainActor.assumeIsolated { photo.stop() } }
}
