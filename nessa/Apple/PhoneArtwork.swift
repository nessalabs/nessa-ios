import NessaFeatures
import SwiftUI

/// Reused rows can receive new names or positions without replacing their host.
final class PhoneArtwork: ExactNativeScreen {
  private let host: UIHostingController<ExactPhoneArtwork>

  @MainActor init(_ props: [String: String], events: ExactNativeEvents) {
    host = UIHostingController(rootView: ExactPhoneArtwork(props))
    host.safeAreaRegions = []
    host.view.backgroundColor = .clear
    host.view.isUserInteractionEnabled = false
    super.init(screen: host, events: events)
  }

  override func setProps(_ props: [String: String]) throws {
    MainActor.assumeIsolated { host.rootView = ExactPhoneArtwork(props) }
  }
}
