#if os(iOS)
import AVFoundation
import PhotosUI
import UIKit
import UniformTypeIdentifiers

/// A non-rendering child controller attached to the owning Exact route. UIKit delivers
/// appearance/scene and system-picker events here; all composer controls live in Contract.
@MainActor final class ExactComposerAnchor: UIViewController, @preconcurrency PHPickerViewControllerDelegate,
  UIDocumentPickerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate
{
  private let editor: ExactComposerDraft
  private let released: @MainActor () -> Void
  private var didAttach = false
  private var presentingPicker = false

  init(editor: ExactComposerDraft, released: @escaping @MainActor () -> Void) {
    self.editor = editor
    self.released = released
    super.init(nibName: nil, bundle: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(resigned(_:)),
      name: UIScene.willDeactivateNotification, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(background(_:)),
      name: UIScene.didEnterBackgroundNotification, object: nil)
  }

  @available(*, unavailable) required init?(coder: NSCoder) { fatalError("Use init(editor:released:)") }

  override func loadView() {
    view = UIView()
    view.backgroundColor = .clear
    view.isUserInteractionEnabled = false
    view.accessibilityElementsHidden = true
  }

  override func didMove(toParent parent: UIViewController?) {
    super.didMove(toParent: parent)
    if parent != nil { didAttach = true }
    else if didAttach { didAttach = false; released() }
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    editor.appeared()
  }

  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    if !presentingPicker { editor.disappeared() }
  }

  @objc private func resigned(_ notification: Notification) {
    guard notification.object as? UIScene === viewIfLoaded?.window?.windowScene,
      editor.dictation.state != .requesting else { return }
    editor.dictation.cancel()
  }

  @objc private func background(_ notification: Notification) {
    guard notification.object as? UIScene === viewIfLoaded?.window?.windowScene else { return }
    editor.dictation.cancel()
  }

  func choose(_ kind: String, policy: AttachmentPolicy, count: Int) {
    guard editor.valid, !presentingPicker, viewIfLoaded?.window != nil else { return }
    let picker: UIViewController
    switch kind {
    case "camera":
      guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
        editor.failPicker("Camera is unavailable on this device. Choose Photos or Add Files instead.")
        return
      }
      switch AVCaptureDevice.authorizationStatus(for: .video) {
      case .denied, .restricted:
        editor.failPicker("Allow camera access in Settings, or choose Photos or Add Files instead.")
        return
      default: break
      }
      let camera = UIImagePickerController()
      camera.sourceType = .camera
      camera.mediaTypes = [UTType.image.identifier]
      camera.delegate = self
      picker = camera
    case "photos":
      var settings = PHPickerConfiguration(photoLibrary: .shared())
      settings.filter = .images
      settings.selectionLimit = max(1, policy.maximumCount - count)
      let photos = PHPickerViewController(configuration: settings)
      photos.delegate = self
      picker = photos
    case "files":
      let documents = UIDocumentPickerViewController(forOpeningContentTypes: policy.allowsFiles ? [.item] : [.image])
      documents.allowsMultipleSelection = true
      documents.delegate = self
      picker = documents
    default: return
    }
    presentingPicker = true
    picker.presentationController?.delegate = self
    present(picker, animated: true)
  }

  func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
    dismissPicker(picker)
      editor.prepare(results.map { result in
      { @MainActor in
          let data: Data = try await withCheckedThrowingContinuation { continuation in
            result.itemProvider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, error in
              if let data { continuation.resume(returning: data) }
              else { continuation.resume(throwing: error ?? NessaGatewayError.rejected("This photo could not be loaded.")) }
            }
          }
          return try await PhotoProcessing.prepare(data, name: "Photo.jpg")
        }
    })
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    dismissPicker(controller)
    editor.prepare(urls.map { url in { @MainActor in try await PhotoProcessing.loadFile(url) } })
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { dismissPicker(controller) }
  func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { dismissPicker(picker) }
  func imagePickerController(_ picker: UIImagePickerController,
    didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
    dismissPicker(picker)
    guard let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.9) else {
      editor.failPicker("This photo could not be loaded.")
      return
    }
    editor.prepare([{ try await PhotoProcessing.prepare(data, name: "Camera.jpg") }])
  }

  private func dismissPicker(_ picker: UIViewController) {
    picker.dismiss(animated: true)
    presentingPicker = false
  }
}

extension ExactComposerAnchor: UIAdaptivePresentationControllerDelegate {
  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    presentingPicker = false
  }
}
#endif
