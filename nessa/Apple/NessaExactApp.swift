import ExactGroupedLists
import ExactMarkdown
import ExactKit
import SwiftUI

@main
struct NessaExactApp: App {
  init() {
    ExactGroupedLists.install()
    ExactMarkdown.install()
  }

  var body: some Scene {
    WindowGroup {
      PhoneView().ignoresSafeArea().preferredColorScheme(.dark)
    }
  }
}

private struct PhoneView: UIViewRepresentable {
  func makeUIView(context: Context) -> ExactView {
    let session = ExactApp.shared.makeSession(label: "Nessa")
    return ExactView(session: session)
  }

  func updateUIView(_ view: ExactView, context: Context) {}

  static func dismantleUIView(_ view: ExactView, coordinator: ()) {
    view.session.destroy()
  }
}
