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
      "nessa-avatar": ExactNativeFactory(for: PhoneModule.self) { module, props, events in
        MainActor.assumeIsolated {
          ExactNativeScreen(screen: module.phone.avatar(props["identifier"] ?? ""), events: events)
        }
      },
      "nessa-lifecycle": ExactNativeFactory(for: PhoneModule.self) { module, _, events in
        MainActor.assumeIsolated {
          ExactNativeScreen(screen: module.phone.lifecycle(navigate: events.message), events: events)
        }
      },
    ]
  }

  override func later(_ request: [String: Any], reply: ExactReply) {
    Task { @MainActor in
      switch request["op"] as? String {
      case "create":
        reply.send(["id": await phone.createChat() ?? ""])
      case "refresh":
        await phone.refresh(request["screen"] as? String ?? "")
        reply.send(["done": true])
      case "unarchive":
        guard let id = request["id"] as? String else { return reply.fail("Missing conversation") }
        await phone.unarchive(id)
        reply.send(["done": true])
      default: reply.fail("Unknown phone command")
      }
    }
  }

  override func call(_ request: [String: Any]) throws -> [String: Any] {
    try MainActor.assumeIsolated {
      switch request["op"] as? String {
      case "status": return phone.status
      case "list": return phone.list(request["screen"] as? String ?? "")
      default: throw ExactNativeRefusal("Unknown phone query")
      }
    }
  }
}

let exactModule: ExactModule.Type = PhoneModule.self
