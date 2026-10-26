#if os(iOS)
  import AVFoundation
  import Foundation

  /// The back camera, read for the desktop's signal orb. Frames are averaged
  /// down to at most `longSide` pixels on the long side, so sparse grains read
  /// as their region's level as they do in the kit's reader, and read off the
  /// main thread, a few times a second.
  /// A code is reported once two readings agree (`OrbScanner`).
  public final class CameraOrbReader: NSObject, @unchecked Sendable {
    public enum Availability: Equatable, Sendable { case ready, denied, unavailable }

    public let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "nessa.orb.camera")
    private let longSide: Int
    private let interval: TimeInterval
    // Touched only on `queue`.
    private var scanner = OrbScanner()
    private var lastRead = Date.distantPast
    private var onCode: (@Sendable (String) -> Void)?
    private var configured = false

    public init(longSide: Int = 960, interval: TimeInterval = 0.15) {
      self.longSide = longSide
      self.interval = interval
    }

    /// Ask for the camera when it has not been answered yet.
    public static func availability() async -> Availability {
      switch AVCaptureDevice.authorizationStatus(for: .video) {
      case .authorized: return .ready
      case .notDetermined:
        return await AVCaptureDevice.requestAccess(for: .video) ? .ready : .denied
      default: return .denied
      }
    }

    /// Start reading; `onCode` is called on a background queue with each
    /// agreed code.
    public func start(onCode: @escaping @Sendable (String) -> Void) {
      queue.async { [self] in
        self.onCode = onCode
        scanner.reset()
        if !configured { configure() }
        if configured, !session.isRunning { session.startRunning() }
      }
    }

    public func stop() {
      queue.async { [self] in
        onCode = nil
        if session.isRunning { session.stopRunning() }
      }
    }

    private func configure() {
      guard
        let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
        let input = try? AVCaptureDeviceInput(device: camera)
      else { return }
      session.beginConfiguration()
      session.sessionPreset = .hd1280x720
      guard session.canAddInput(input) else {
        session.commitConfiguration()
        return
      }
      session.addInput(input)
      let output = AVCaptureVideoDataOutput()
      output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
      output.alwaysDiscardsLateVideoFrames = true
      output.setSampleBufferDelegate(self, queue: queue)
      guard session.canAddOutput(output) else {
        session.commitConfiguration()
        return
      }
      session.addOutput(output)
      session.commitConfiguration()
      if (try? camera.lockForConfiguration()) != nil {
        if camera.isFocusModeSupported(.continuousAutoFocus) {
          camera.focusMode = .continuousAutoFocus
        }
        camera.unlockForConfiguration()
      }
      configured = true
    }

    /// A BGRA buffer averaged down by a whole factor, each output pixel the
    /// mean of its factor-by-factor block. The reader measures
    /// colour as max minus min of the three channels, so their order does
    /// not matter.
    static func frame(from buffer: CVPixelBuffer, longSide: Int) -> OrbFrame? {
      CVPixelBufferLockBaseAddress(buffer, .readOnly)
      defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
      guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
      let width = CVPixelBufferGetWidth(buffer)
      let height = CVPixelBufferGetHeight(buffer)
      let stride = CVPixelBufferGetBytesPerRow(buffer)
      let factor = max(1, Int((Double(max(width, height)) / Double(longSide)).rounded(.up)))
      let outWidth = width / factor
      let outHeight = height / factor
      guard outWidth > 0, outHeight > 0 else { return nil }
      let source = base.assumingMemoryBound(to: UInt8.self)
      var pixels = [UInt8](repeating: 0, count: outWidth * outHeight * 4)
      let area = factor * factor
      pixels.withUnsafeMutableBufferPointer { out in
        for y in 0..<outHeight {
          for x in 0..<outWidth {
            var b = 0, g = 0, r = 0
            for dy in 0..<factor {
              let row = (y * factor + dy) * stride + x * factor * 4
              for dx in 0..<factor {
                let from = row + dx * 4
                b += Int(source[from])
                g += Int(source[from + 1])
                r += Int(source[from + 2])
              }
            }
            let to = (y * outWidth + x) * 4
            out[to] = UInt8((b + area / 2) / area)
            out[to + 1] = UInt8((g + area / 2) / area)
            out[to + 2] = UInt8((r + area / 2) / area)
            out[to + 3] = 255
          }
        }
      }
      return OrbFrame(pixels: pixels, width: outWidth, height: outHeight)
    }
  }

  extension CameraOrbReader: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(
      _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
      from connection: AVCaptureConnection
    ) {
      guard let onCode, Date().timeIntervalSince(lastRead) >= interval,
        let buffer = CMSampleBufferGetImageBuffer(sampleBuffer),
        let frame = Self.frame(from: buffer, longSide: longSide)
      else { return }
      lastRead = Date()
      if let code = scanner.read(frame) { onCode(code) }
    }
  }
#endif
