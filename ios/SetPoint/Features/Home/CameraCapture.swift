import SwiftUI
import UIKit

/// "Take photo" / "Choose from library" — the items of every add-photo menu.
struct PhotoSourceButtons: View {
    let model: LogMealViewModel

    var body: some View {
        Button { model.openCamera() } label: {
            Label("Take photo", systemImage: "camera")
        }
        Button { model.openPhotoLibrary() } label: {
            Label("Choose from library", systemImage: "photo.on.rectangle")
        }
    }
}

/// The system camera for a meal photo. `PhotosPicker` only reaches the library,
/// so taking a picture of the plate in front of you goes through here.
struct CameraCapture: UIViewControllerRepresentable {
    var onPhoto: (Data) -> Void
    var onCancel: () -> Void

    @MainActor static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func makeCoordinator() -> Coordinator { Coordinator(onPhoto: onPhoto, onCancel: onCancel) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
        context.coordinator.onPhoto = onPhoto
        context.coordinator.onCancel = onCancel
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        var onPhoto: (Data) -> Void
        var onCancel: () -> Void

        init(onPhoto: @escaping (Data) -> Void, onCancel: @escaping () -> Void) {
            self.onPhoto = onPhoto
            self.onCancel = onCancel
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            // Full quality here; MealPhoto downsizes and recompresses for upload.
            if let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.9) {
                onPhoto(data)
            } else {
                onCancel()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }
    }
}
