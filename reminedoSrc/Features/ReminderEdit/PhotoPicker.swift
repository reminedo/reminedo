//
//  PhotoPicker.swift
//  reminedo
//
//  PHPickerViewController를 UIKit present(_:animated:)로 띄우는 사진 선택기.
//  보이지 않는 host UIViewController를 SwiftUI .background에 두고, 그 host에서 PHPicker를 모달로
//  present한다. (시트 안에서 또 SwiftUI .sheet로 PHPicker를 띄우면 — 중첩 시트 + PHPicker를
//  representable 루트로 embed — 시트 해제 시 부모 시트 위에 투명 잔여 프레젠테이션 레이어가 남아
//  시트 전체 터치가 죽는 iOS 버그가 있었다. UIKit present는 PHPicker를 부모 시트 '위' 모달로
//  올려 윈도우/first responder 복원을 정상화한다.)
//
//  타입명/이니셜라이저 시그니처(PhotoPicker(isPresented:onPick:))는 기존 호출부 호환을 위해 유지한다.
//

import SwiftUI
import UIKit
import PhotosUI

struct PhotoPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    var onPick: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        let host = UIViewController()
        // 배경 호스트일 뿐 — 전경 컨트롤의 hit-test를 막지 않도록 터치 비활성.
        host.view.isUserInteractionEnabled = false
        return host
    }

    func updateUIViewController(_ host: UIViewController, context: Context) {
        // Binding/onPick 최신화(콜백 시점에 최신 parent 사용).
        context.coordinator.parent = self

        if isPresented {
            // 이미 떠 있으면 중복 present 방지.
            guard context.coordinator.picker == nil, host.presentedViewController == nil else { return }

            var config = PHPickerConfiguration()
            config.filter = .images
            config.selectionLimit = 1
            let picker = PHPickerViewController(configuration: config)
            picker.delegate = context.coordinator
            // 스와이프-다운 등 인터랙티브 해제 감지용.
            picker.presentationController?.delegate = context.coordinator

            DispatchQueue.main.async {
                // host가 윈도우 계층에 올라온 뒤에만 present. 가드 통과 후에 picker를 기록해야
                // present가 끝내 안 불리는 경우의 영구 데드락(picker가 비-nil로 박힘)을 피한다.
                guard host.view.window != nil, host.presentedViewController == nil else { return }
                context.coordinator.picker = picker
                host.present(picker, animated: true)
            }
        } else if let picker = context.coordinator.picker {
            // 외부에서 바인딩이 내려간 경우 정리.
            context.coordinator.picker = nil
            picker.dismiss(animated: true)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate, UIAdaptivePresentationControllerDelegate {
        var parent: PhotoPicker
        weak var picker: PHPickerViewController?

        init(_ parent: PhotoPicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            let provider = results.first?.itemProvider
            // 핵심: 모달을 완전히 내린 뒤(teardown 완료) 상태 복원 + 콜백 → 윈도우/responder 복원이 깨끗.
            // (picker = nil 을 isPresented = false 보다 먼저 둬, isPresented 변경으로 인한
            //  updateUIViewController 재호출 시 else 분기의 재-dismiss를 막는다. 순서 유지 필수.)
            picker.dismiss(animated: true) { [weak self] in
                guard let self else { return }
                self.picker = nil
                self.parent.isPresented = false
                guard let provider, provider.canLoadObject(ofClass: UIImage.self) else { return }
                provider.loadObject(ofClass: UIImage.self) { object, _ in
                    guard let image = object as? UIImage else { return }
                    DispatchQueue.main.async { self.parent.onPick(image) }
                }
            }
        }

        // 스와이프-다운으로 닫는 인터랙티브 해제: didFinishPicking이 안 불릴 수 있으므로 여기서
        // 상태를 복원해 stale(isPresented=true 잠금) / 유령 재표시를 방지.
        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            picker = nil
            parent.isPresented = false
        }
    }
}
