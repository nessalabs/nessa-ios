import Foundation
import Testing

@testable import NessaFeatures

@MainActor private final class ControlledSpeech: SpeechTranscribing {
  var streams: [AsyncThrowingStream<SpeechTranscript, Error>.Continuation] = []
  var finishCount = 0
  var failure: DictationError?
  func start() throws -> AsyncThrowingStream<SpeechTranscript, Error> {
    if let failure { throw failure }
    let (stream, continuation) = AsyncThrowingStream<SpeechTranscript, Error>.makeStream()
    streams.append(continuation)
    return stream
  }
  func finish() { finishCount += 1 }
  // Retain the old stream to simulate callbacks arriving after cancellation.
  func cancel() {}
}
@MainActor private func settle(_ condition: () -> Bool) async {
  for _ in 0..<2000 {
    if condition() { return }
    await Task.yield()
  }
  #expect(condition())
}
@Test @MainActor func dictationReplacesPartialTextAndWaitsForFinalAfterStop() async {
  let speech = ControlledSpeech()
  let model = DictationViewModel(transcriber: speech)
  model.start()
  await settle { model.state == .listening }
  speech.streams[0].yield(.init(text: "Hello", isFinal: false))
  await settle { model.transcript == "Hello" }
  speech.streams[0].yield(.init(text: "Hello there", isFinal: false))
  await settle { model.transcript == "Hello there" }
  model.toggle()
  #expect(model.state == .finishing)
  #expect(speech.finishCount == 1)
  model.toggle()
  #expect(speech.finishCount == 1)
  speech.streams[0].yield(.init(text: "Hello there!", isFinal: true))
  speech.streams[0].finish()
  await settle { model.state == .idle }
  #expect(model.transcript == "Hello there!")
}
@Test @MainActor func cancelledDictationCannotReplaceANewerTranscript() async {
  let speech = ControlledSpeech()
  let model = DictationViewModel(transcriber: speech)
  model.start()
  await settle { speech.streams.count == 1 }
  model.cancel()
  model.start()
  await settle { speech.streams.count == 2 }
  speech.streams[1].yield(.init(text: "New recording", isFinal: true))
  await settle { model.transcript == "New recording" }
  speech.streams[0].yield(.init(text: "Stale recording", isFinal: true))
  speech.streams[0].finish(throwing: DictationError.failed)
  speech.streams[1].finish()
  await settle { model.state == .idle }
  #expect(model.transcript == "New recording")
  #expect(model.error == nil)
}
@Test @MainActor func permissionFailureIsActionableAndAllowsRetry() async {
  let speech = ControlledSpeech()
  speech.failure = .microphonePermission
  let model = DictationViewModel(transcriber: speech)
  model.start()
  await settle { model.state == .idle }
  #expect(model.error == DictationError.microphonePermission.localizedDescription)
  speech.failure = nil
  model.start()
  await settle { model.state == .listening }
  #expect(model.error == nil)
  model.cancel()
}
@Test @MainActor func developmentDictationUsesInjectedMockWithoutMicrophone() async {
  let model = NessaDependencies.development().makeDictationViewModel()
  model.start()
  await settle { model.state == .idle }
  #expect(model.transcript == "This is a mocked voice message.")
}

@Test @MainActor func endingWithoutAFinalTranscriptReportsIncompleteAndKeepsPartialText() async {
  let speech = ControlledSpeech()
  let model = DictationViewModel(transcriber: speech)
  model.start()
  await settle { model.state == .listening }
  speech.streams[0].yield(.init(text: "Partial text", isFinal: false))
  await settle { model.transcript == "Partial text" }
  model.toggle()
  speech.streams[0].finish()
  await settle { model.state == .idle }
  #expect(model.error == DictationError.incomplete.localizedDescription)
  #expect(model.transcript == "Partial text")
}
@Test @MainActor func identicalDictationHasANewDeliveryRevision() async {
  let model = NessaDependencies.development().makeDictationViewModel()
  model.start()
  await settle { model.state == .idle }
  let revision = model.transcriptRevision
  let text = model.transcript
  model.start()
  await settle { model.state == .idle }
  #expect(model.transcript == text)
  #expect(model.transcriptRevision != revision)
}
