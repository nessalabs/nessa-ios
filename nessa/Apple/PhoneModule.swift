import NessaFeatures
import UIKit

final class PhoneModule: ExactModule {
  // Exact constructs its module and invokes its factories on the main thread.
  @MainActor private lazy var phone = ExactPhoneSession { [weak self] topic in
    self?.context.changed(topic)
  }

  @MainActor private lazy var threads = ExactThreads(phone: phone) { [weak self] in
    self?.context.changed("thread")
  }
  @MainActor private lazy var link = phone.connectionBridge { [weak self] in
    self?.context.changed("link")
  }

  override class var views: [String: ExactNativeFactory] {
    [
      "nessa-thread-part": ExactNativeFactory(for: PhoneModule.self) { module, props, events in
        MainActor.assumeIsolated {
          ExactNativeScreen(screen: module.threads.part(props["widget"] ?? "", chat: props["chat"] ?? "",
            item: props["item"] ?? "", size: { events.intrinsicSize($0) }), events: events)
        }
      },
      "nessa-connection-input": ExactNativeFactory(for: PhoneModule.self) { module, props, events in
        MainActor.assumeIsolated {
          ExactNativeScreen(screen: module.link.control(props["kind"] ?? ""), events: events)
        }
      },
      "nessa-artwork": ExactNativeFactory { props, events in
        MainActor.assumeIsolated { PhoneArtwork(props, events: events) }
      },
      "nessa-new-chat-input": ExactNativeFactory(for: PhoneModule.self) { module, props, events in
        MainActor.assumeIsolated {
          ExactNativeScreen(screen: module.phone.composer(channel: props["channel"] ?? "",
            navigate: events.message, size: events.intrinsicSize), events: events)
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
      case "sharedTranscript":
        reply.send(await phone.sharedTranscript(request["id"] as? String ?? "", owner: request["owner"] as? String ?? ""))
      case "threadCommand":
        await threads.command(request["command"] as? String ?? "", chat: request["chat"] as? String ?? "",
          review: request["review"] as? String ?? "", option: request["option"] as? String ?? "")
        reply.send(["done": true])
      case "connectionCommand":
        await link.perform(request["action"] as? String ?? "", key: request["key"] as? String ?? "")
        reply.send(["done": true])
      case "agentCommand":
        reply.send(await phone.performAgentCommand(request))
      case "create":
        reply.send(["id": await phone.createChat() ?? ""])
      case "refresh":
        await phone.refresh(request["screen"] as? String ?? "")
        reply.send(["done": true])
      case "retryLink":
        await phone.retryLink()
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
      case "threadSnapshot": return threads.snapshot(request["chat"] as? String ?? "")
      case "connectionState": return link.state
      case "agents": return phone.agentsSnapshot
      case "status": return phone.status
      case "list": return phone.list(request["screen"] as? String ?? "", key: request["key"] as? String ?? "")
      default: throw ExactNativeRefusal("Unknown phone query")
      }
    }
  }
}

let exactModule: ExactModule.Type = PhoneModule.self
