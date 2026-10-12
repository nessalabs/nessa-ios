import Foundation

extension NessaDependencies {
  /// Runs only with three explicit disposable-scope inputs in a debug launch.
  /// It does not select or modify the user's product/native profile.
  public static func verifyNativePackageIfRequested(
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) async {
    #if DEBUG
      guard let root = environment["NESSA_NATIVE_PACKAGE_ROOT"],
        let directory = environment["NESSA_NATIVE_PACKAGE_DIRECTORY"],
        let address = environment["NESSA_NATIVE_PACKAGE_ADDRESS"]
      else { return }
      do {
        try await NativePackageVerification.run(root: root, directory: directory, address: address)
        print("NESSA_NATIVE_PACKAGE_PASS open/no-credential/closed/reopen")
      } catch {
        print("NESSA_NATIVE_PACKAGE_FAIL \(error)")
      }
    #endif
  }
}
