import Foundation
import NessaNative
import Testing

@testable import NessaFeatures

private let precomposed = "é"
private let decomposed = "e\u{301}"

@Test func retainedOpaqueIdentityEqualityMatchesNativeUTF8InsteadOfSwiftNormalization() async throws
{
  #expect(precomposed == decomposed)
  #expect(!precomposed.utf8.elementsEqual(decomposed.utf8))
  try await Task.detached {
    let first = try NativeEntryKey(creation: UInt64.max, id: precomposed)
    let second = try NativeEntryKey(creation: UInt64.max, id: decomposed)
    let firstKey = NativeRetainedCapture.capture(first)
    let secondKey = NativeRetainedCapture.capture(second)
    #expect(firstKey != secondKey)
    #expect(firstKey.id.utf8.elementsEqual(precomposed.utf8))
    #expect(secondKey.id.utf8.elementsEqual(decomposed.utf8))
    let firstScope = NativeRetainedCapture.capture(FixtureNativeScope(origin: precomposed))
    let secondScope = NativeRetainedCapture.capture(FixtureNativeScope(origin: decomposed))
    #expect(firstScope != secondScope)
    let firstReceipt = NativeRetainedCapture.capture(
      FixtureNativeEnrollmentReceipt(receiver: precomposed))
    let secondReceipt = NativeRetainedCapture.capture(
      FixtureNativeEnrollmentReceipt(receiver: decomposed))
    #expect(firstReceipt != secondReceipt)
    let firstPurge = NativeRetainedCapture.capture(FixtureNativePurge(receiver: precomposed))
    let secondPurge = NativeRetainedCapture.capture(FixtureNativePurge(receiver: decomposed))
    #expect(firstPurge != secondPurge)
    let firstRead = NativeRetainedCapture.capture(FixtureNativeRead(withdrawn: [precomposed]))
    let secondRead = NativeRetainedCapture.capture(FixtureNativeRead(withdrawn: [decomposed]))
    #expect(firstRead != secondRead)
  }.value
}

@Test func retainedProjectionTargetComparisonAlsoPreservesOpaqueUTF8() async {
  await Task.detached {
    let revision = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    let json = """
      {"conversationId":"é","revision":"00000000-0000-4000-8000-000000000001:1",
       "messages":[],"permissions":[],"truncated":false}
      """
    let value = NativeRetainedCapture.transcript(
      FixtureNativeTranscript(json: .success(json)), conversation: decomposed, revision: revision)
    #expect(value.view == .failed(.init(failure: .targetMismatch, json: Data(json.utf8))))
  }.value
}
