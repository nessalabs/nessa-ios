import Foundation

#if os(iOS)
  @preconcurrency import AVFAudio
  @preconcurrency import Speech

  @MainActor public final class AppleSpeechTranscriber: SpeechTranscribing {
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognition: SFSpeechRecognitionTask?
    private var continuation: AsyncThrowingStream<SpeechTranscript, Error>.Continuation?
    private var timeout: Task<Void, Never>?
    private var token = UUID()
    private var tapped = false
    private var stopping = false
    private var audioActive = false
    public init() {}

    public func start() async throws -> AsyncThrowingStream<SpeechTranscript, Error> {
      cancel()
      let expected = token
      let authorization = await SpeechPermissionCallback.request(
        using: SFSpeechRecognizer.requestAuthorization)
      guard expected == token, !Task.isCancelled else { throw CancellationError() }
      guard authorization == .authorized else { throw DictationError.speechPermission }
      let microphone = await AVAudioApplication.requestRecordPermission()
      guard expected == token, !Task.isCancelled else { throw CancellationError() }
      guard microphone else { throw DictationError.microphonePermission }
      guard let recognizer = SFSpeechRecognizer(locale: .current), recognizer.isAvailable else {
        throw DictationError.unavailable
      }
      let (stream, continuation) = AsyncThrowingStream<SpeechTranscript, Error>.makeStream()
      self.continuation = continuation
      continuation.onTermination = { [weak self] _ in
        Task { @MainActor in if self?.token == expected { self?.cancel() } }
      }
      do {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        audioActive = true
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        self.request = request
        let node = engine.inputNode
        let format = node.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
          throw DictationError.unavailable
        }
        node.installTap(onBus: 0, bufferSize: 1024, format: format) { @Sendable buffer, _ in
          request.append(buffer)
        }
        tapped = true
        recognition = recognizer.recognitionTask(with: request) { @Sendable [weak self] result, error in
          let text = result?.bestTranscription.formattedString
          let final = result?.isFinal == true
          let failed = error != nil
          Task { @MainActor in
            guard let self, self.token == expected else { return }
            if let text { self.continuation?.yield(SpeechTranscript(text: text, isFinal: final)) }
            if final {
              self.end(error: nil)
            } else if failed {
              self.end(error: DictationError.failed)
            }
          }
        }
        engine.prepare()
        try engine.start()
        return stream
      } catch {
        end(error: error)
        throw error
      }
    }

    public func finish() {
      guard continuation != nil, !stopping else { return }
      stopping = true
      stopAudio()
      let expected = token
      timeout = Task {
        do { try await Task.sleep(for: .seconds(10)) } catch { return }
        if token == expected { end(error: DictationError.incomplete) }
      }
    }
    public func cancel() { end(error: nil) }
    private func stopAudio() {
      engine.stop()
      if tapped {
        engine.inputNode.removeTap(onBus: 0)
        tapped = false
      }
      request?.endAudio()
      if audioActive {
        audioActive = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
      }
    }
    private func end(error: Error?) {
      token = UUID()
      timeout?.cancel()
      timeout = nil
      stopAudio()
      recognition?.cancel()
      recognition = nil
      request = nil
      stopping = false
      let continuation = self.continuation
      self.continuation = nil
      if let error { continuation?.finish(throwing: error) } else { continuation?.finish() }
    }
  }
#else
  @MainActor public final class AppleSpeechTranscriber: SpeechTranscribing {
    public init() {}
    public func start() async throws -> AsyncThrowingStream<SpeechTranscript, Error> {
      throw DictationError.unavailable
    }
    public func finish() {}
    public func cancel() {}
  }
#endif
