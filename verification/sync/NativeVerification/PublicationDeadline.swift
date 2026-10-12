import Foundation
import NessaFeatures

/// A successful registration acknowledgment does not guarantee a first publication.
func firstPublication(
  _ stream: AsyncThrowingStream<ConversationUpdate, Error>,
  within deadline: Duration = .seconds(5)
) async throws -> ConversationUpdate? {
  try await withThrowingTaskGroup(of: ConversationUpdate?.self) { group in
    defer { group.cancelAll() }
    group.addTask {
      var iterator = stream.makeAsyncIterator()
      return try await iterator.next()
    }
    group.addTask {
      try await Task.sleep(for: deadline)
      throw NessaGatewayError.timeout
    }
    return try await group.next() ?? nil
  }
}
