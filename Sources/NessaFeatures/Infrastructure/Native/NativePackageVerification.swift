#if DEBUG
  import NessaNative

  /// Explicit disposable package verification, separate from product enrollment.
  enum NativePackageVerification {
    enum Failure: Error { case expectedNoCredential, expectedClosed }

    static func run(root: String, directory: String, address: String) async throws {
      try await Task.detached {
        let worker = try await NativeSessionWorker.open(
          root: root, directory: directory, address: address)
        do {
          do {
            _ = try await worker.cataloguePage(after: nil, maximum: 16)
            throw Failure.expectedNoCredential
          } catch NativeCallError.Session(let failure) {
            guard failure.kind() == .noCredential else {
              throw NativeCallError.Session(failure: failure)
            }
          }
          try await worker.close()
          do {
            _ = try await worker.cataloguePage(after: nil, maximum: 16)
            throw Failure.expectedClosed
          } catch NativeWorkerError.closed {}
          // Reusing the same private directory proves actual physical drain.
          let reopened = try await NativeSessionWorker.open(
            root: root, directory: directory, address: address)
          try await reopened.close()
        } catch {
          try? await worker.close()
          throw error
        }
      }.value
    }
  }
#endif
