#if DEBUG
  import Foundation
  import Testing
  @testable import NessaFeatures

  @Test @MainActor func distributedNativePackageOpensClosesAndReopensItsPrivateScope() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("Nessa native package \(UUID().uuidString)")
      .resolvingSymlinksInPath()
    try FileManager.default.createDirectory(
      at: root.appendingPathComponent("session"), withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    defer { try? FileManager.default.removeItem(at: root) }
    try await NativePackageVerification.run(
      root: root.path, directory: "session", address: "127.0.0.1:9")
    // A no-op check must not pass without the native private-store effect.
    let files = try FileManager.default.contentsOfDirectory(
      atPath: root.appendingPathComponent("session").path)
    #expect(!files.isEmpty)
  }
#endif
