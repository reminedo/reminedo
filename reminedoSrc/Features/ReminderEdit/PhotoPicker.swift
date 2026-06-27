//
//  PhotoPicker.swift
//  reminedo
//
//  PHPickerViewController를 UIKit present(_:animated:)로 띄우는 사진 선택기.
//  보이지 않는 host UIViewController를 SwiftUI .background에 두되, present는 host가 아니라
//  key window의 '최상위 present된 VC'(= 이 시트의 hosting controller)에서 수행한다.
//
//  배경(왜 host가 아니라 top VC에서 present하나):
//   - 시트(이미 모달) 안에서 또 SwiftUI .sheet로 PHPicker를 띄우면 해제 시 부모 시트 위에 투명
//     잔여 프레젠테이션 레이어가 남아 시트 전체 터치가 죽는 버그가 있었다(과거 수정).
//   - UIKit present로 바꿔 데드락은 잡혔으나, present를 '시트 .background에 묻힌 host'에서 하면
//     해제 시 시트 윈도우가 key 상태를 되찾지 못해 TextField가 first responder가 못 되고
//     (= 키보드가 안 뜨고) 제목 입력이 막히는 문제가 남았다.
//   - 그래서 present 주체를 top VC로 올려 해제 시 responder/key 복귀가 시트로 정상 환원되게 하고,
//     dismiss 완료 콜백에서 key window를 명시 복원(makeKey)해 이중으로 보장한다.
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
        // 배경 호스트일 뿐 — 전경 컨트롤의 hit-test를 절대 가로채지 않도록 완전 비활성/투명/0크기 처리.
        host.view.isUserInteractionEnabled = false
        host.view.backgroundColor = .clear
        host.view.frame = .zero
        return host
    }

    func updateUIViewController(_ host: UIViewController, context: Context) {
        // Binding/onPick 최신화(콜백 시점에 최신 parent 사용).
        context.coordinator.parent = self

        if isPresented {
            // 이미 떠 있으면 중복 present 방지.
            guard context.coordinator.picker == nil else { return }

            var config = PHPickerConfiguration()
            config.filter = .images
            config.selectionLimit = 1
            let picker = PHPickerViewController(configuration: config)
            picker.delegate = context.coordinator
            // 스와이프-다운 등 인터랙티브 해제 감지용.
            picker.presentationController?.delegate = context.coordinator

            DispatchQueue.main.async {
                // host가 윈도우 계층에 올라온 뒤에만 present. present 주체는 host가 아니라
                // 최상위 present VC(이 시트의 hosting controller) — 해제 시 responder가 시트로 정상 복귀.
                guard let presenter = host.topmostPresenter,
                      presenter.presentedViewController == nil else { return }
                // 가드 통과 후에 picker를 기록해야 present가 끝내 안 불리는 경우의 영구 데드락을 피한다.
                context.coordinator.picker = picker
                // 해제 후 key 상태를 되돌릴 윈도우 보관(키보드/first responder 복원용).
                context.coordinator.keyWindow = host.view.window
                presenter.present(picker, animated: true)
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
        // present 직전의 시트 윈도우 — 해제 후 key 상태를 되돌려 TextField 포커스(키보드)를 복원한다.
        weak var keyWindow: UIWindow?

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
                self.restoreKeyWindow()
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
            restoreKeyWindow()
        }

        /// PHPicker 모달 해제 후 시트 윈도우의 key 상태를 복원한다. 이게 없으면 시트의 TextField가
        /// first responder가 못 돼 키보드가 안 뜨는(제목 입력 불가) 증상이 남는다.
        private func restoreKeyWindow() {
            keyWindow?.makeKey()
        }
    }
}

private extension UIViewController {
    /// 이 VC가 속한 윈도우의 rootViewController에서 시작해, present 체인을 끝까지 따라간 최상위 VC.
    /// PHPicker를 이 VC에서 present하면 해제 시 responder/key가 시트로 정상 복귀한다.
    var topmostPresenter: UIViewController? {
        var top = view.window?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
