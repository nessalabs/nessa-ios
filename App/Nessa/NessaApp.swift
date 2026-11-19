import NessaFeatures
import SwiftUI

@main
struct NessaApp: App {
  private let dependencies = NessaDependencies.configured()
  var body: some Scene {
    WindowGroup {
      NessaMessagesView(dependencies: dependencies)
        .task { await NessaDependencies.verifyNativePackageIfRequested() }
    }
  }
}
