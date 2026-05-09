import SwiftUI

#if os(iOS)
import AVFoundation
import UIKit

struct QRCodeScannerView: UIViewControllerRepresentable {
    let onCodeScanned: (String) -> Void
    let onFailure: (String) -> Void

    func makeUIViewController(context: Context) -> QRCodeScannerViewController {
        QRCodeScannerViewController(onCodeScanned: onCodeScanned, onFailure: onFailure)
    }

    func updateUIViewController(_ uiViewController: QRCodeScannerViewController, context: Context) {}
}

@MainActor
final class QRCodeScannerViewController: UIViewController, @preconcurrency AVCaptureMetadataOutputObjectsDelegate {
    private let onCodeScanned: (String) -> Void
    private let onFailure: (String) -> Void
    private let captureSession = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var didFinishScanning = false

    init(onCodeScanned: @escaping (String) -> Void, onFailure: @escaping (String) -> Void) {
        self.onCodeScanned = onCodeScanned
        self.onFailure = onFailure
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        requestCameraAccessIfNeeded()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
    }

    private func requestCameraAccessIfNeeded() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] isGranted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if isGranted {
                        self.configureSession()
                    } else {
                        self.onFailure("Camera access is needed to scan the pairing code.")
                    }
                }
            }
        case .denied, .restricted:
            onFailure("Camera access is needed to scan the pairing code.")
        @unknown default:
            onFailure("Camera access is unavailable.")
        }
    }

    private func configureSession() {
        guard previewLayer == nil else { return }
        guard let captureDevice = AVCaptureDevice.default(for: .video) else {
            onFailure("This device does not have an available camera.")
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: captureDevice)
            guard captureSession.canAddInput(input) else {
                onFailure("Camera input is unavailable.")
                return
            }
            captureSession.addInput(input)
        } catch {
            onFailure("Camera input is unavailable.")
            return
        }

        let metadataOutput = AVCaptureMetadataOutput()
        guard captureSession.canAddOutput(metadataOutput) else {
            onFailure("QR scanning is unavailable.")
            return
        }
        captureSession.addOutput(metadataOutput)
        metadataOutput.setMetadataObjectsDelegate(self, queue: .main)
        metadataOutput.metadataObjectTypes = [.qr]

        let layer = AVCaptureVideoPreviewLayer(session: captureSession)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.insertSublayer(layer, at: 0)
        previewLayer = layer

        DispatchQueue.global(qos: .userInitiated).async { [captureSession] in
            captureSession.startRunning()
        }
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !didFinishScanning,
              let metadataObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              metadataObject.type == .qr,
              let code = metadataObject.stringValue
        else {
            return
        }

        didFinishScanning = true
        captureSession.stopRunning()
        onCodeScanned(code)
    }
}
#else
struct QRCodeScannerView: View {
    let onCodeScanned: (String) -> Void
    let onFailure: (String) -> Void

    var body: some View {
        Text("QR scanning is available on iPhone.")
            .onAppear {
                onFailure("QR scanning is available on iPhone.")
            }
    }
}
#endif
