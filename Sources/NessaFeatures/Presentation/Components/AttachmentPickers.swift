import SwiftUI
import UniformTypeIdentifiers

#if os(iOS)
  import UIKit

  struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (Data) -> Void
    @Environment(\.dismiss) private var dismiss
    func makeUIViewController(context: Context) -> UIImagePickerController {
      let picker = UIImagePickerController()
      picker.sourceType = .camera
      picker.delegate = context.coordinator
      return picker
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    final class Coordinator: NSObject, UIImagePickerControllerDelegate,
      UINavigationControllerDelegate
    {
      let parent: CameraPicker
      init(parent: CameraPicker) { self.parent = parent }
      func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
      ) {
        if let image = info[.originalImage] as? UIImage {
          Task {
            let data = await Task.detached(priority: .userInitiated) {
              image.jpegData(compressionQuality: 0.85)
            }.value
            if let data { parent.onImage(data) }
          }
        }
        parent.dismiss()
      }
      func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
  }
#endif
