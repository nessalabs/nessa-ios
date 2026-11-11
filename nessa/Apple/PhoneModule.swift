import NessaFeatures
import UIKit

final class PhoneModule: ExactModule {
  // Exact constructs its module and invokes its factories on the main thread.
  @MainActor private lazy var phone = ExactPhoneSession { [weak self] topic in
    self?.context.changed(topic)
  }

  override class var views: [String: ExactNativeFactory] {
    [
      "nessa-page": ExactNativeFactory(for: PhoneModule.self) { module, props, events in
        try MainActor.assumeIsolated {
          guard let screen = props["screen"] else { throw ExactNativeRefusal("Missing phone screen") }
          let controller = module.phone.page(screen, identifier: props["identifier"] ?? "",
            navigate: events.message)
          return ExactNativeScreen(screen: controller, events: events)
        }
      },
      "nessa-lifecycle": ExactNativeFactory(for: PhoneModule.self) { module, _, events in
        MainActor.assumeIsolated {
          ExactNativeScreen(screen: module.phone.lifecycle(navigate: events.message), events: events)
        }
      },
    ]
  }

  override func call(_ request: [String: Any]) throws -> [String: Any] {
    try MainActor.assumeIsolated {
      guard request["op"] as? String == "status" else { throw ExactNativeRefusal("Unknown phone query") }
      return phone.status
    }
  }
}

let exactModule: ExactModule.Type = PhoneModule.self
