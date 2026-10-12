#if DEBUG
  import Foundation
  import NessaNative

  /// Explicit disposable package verification, separate from product enrollment.
  enum NativePackageVerification {
    enum Failure: Error {
      case expectedNoCredential, expectedClosed, expectedCapturedStatusAndCursor
    }

    static func run(root: String, directory: String, address: String) async throws {
      try await Task.detached {
        let worker = try await NativeSessionWorker.open(
          root: root, directory: directory, address: address)
        do {
          let captured = try await worker.status(capture: { status in
            let cursor = try NativeEntryKey(creation: UInt64.max, id: "  saved-id  ")
            do {
              _ = try NativeEntryKey(creation: 1, id: " ")
              return false
            } catch NativeCallError.InvalidArgument {}
            return !Thread.isMainThread && !status.completionCaptured()
              && status.failure()?.kind() == .io && !status.purgeAttempted()
              && status.purge() == nil && cursor.creation() == UInt64.max
              && cursor.id() == "  saved-id  "
          })
          guard captured else { throw Failure.expectedCapturedStatusAndCursor }
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
