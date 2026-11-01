//
//  VoiceNoteComponents.swift
//  Construction Estimate
//

import SwiftUI

// MARK: - Photo Picker (PHPickerViewController wrapper)

import PhotosUI

struct PhotoPickerView: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let completion: (Data) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoPickerView
        init(_ parent: PhotoPickerView) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            // Dismiss through SwiftUI only. Calling picker.dismiss() here as
            // well pops the parent presentation (the whole chat) too.
            parent.dismiss()
            guard let provider = results.first?.itemProvider,
                  provider.canLoadObject(ofClass: UIImage.self) else { return }
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                guard let image = object as? UIImage,
                      let data = image.jpegData(compressionQuality: 0.8) else { return }
                DispatchQueue.main.async { self.parent.completion(data) }
            }
        }
    }
}

// MARK: - Camera Picker (UIImagePickerController wrapper)

struct CameraPickerView: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let completion: (Data) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPickerView
        init(_ parent: CameraPickerView) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            // Dismiss through SwiftUI only (see PhotoPickerView note).
            parent.dismiss()
            guard let image = info[.originalImage] as? UIImage,
                  let data = image.jpegData(compressionQuality: 0.8) else { return }
            parent.completion(data)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
