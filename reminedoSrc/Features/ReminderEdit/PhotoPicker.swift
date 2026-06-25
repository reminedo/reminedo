//
//  PhotoPicker.swift
//  reminedo
//
//  UIKit PHPickerViewController를 SwiftUI로 감싼 사진 선택기. SwiftUI 기본 PhotosPicker가 시트
//  안에서 TextField 포커스(first responder)를 깨는 이슈를 피하려고 직접 래핑한다. 단일 이미지만.
//  .sheet(isPresented:)로 띄우고, 선택/취소 시 isPresented를 내려 닫는다.
//

import SwiftUI
import UIKit
import PhotosUI

struct PhotoPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    var onPick: (UIImage) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let parent: PhotoPicker

        init(_ parent: PhotoPicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            // 선택/취소 모두 시트를 닫는다(바인딩을 내려 SwiftUI가 dismiss).
            parent.isPresented = false

            guard let provider = results.first?.itemProvider,
                  provider.canLoadObject(ofClass: UIImage.self) else { return }
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                guard let image = object as? UIImage else { return }
                DispatchQueue.main.async { self.parent.onPick(image) }
            }
        }
    }
}
