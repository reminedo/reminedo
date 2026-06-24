//
//  ShareViewController.swift
//  ReminedoShare
//
//  공유 시트 → 리마인두 익스텐션(§2.3/§4.10). 공유된 URL을 추출해 App Group에 1건 기록한 뒤
//  reminedo://add로 메인 앱을 호출하고 즉시 종료한다. 다중 공유 시 첫 URL만 저장(+안내), 미지원 시 안내.
//
//  ※ 단일 출처 SharedConstants를 확장은 공유하지 않아 필요한 값만 로컬 정의(App Group/스킴 일치 필수).
//    페이로드 형식은 메인 앱 SharePayload(Codable)와 정확히 합의됨:
//    App Group UserDefaults 키 "sharedPayload"에 JSON Data 1건 → { "url": String, "sharedAt": Double(epoch seconds) }.
//    메인 앱은 JSONDecoder + .secondsSince1970 로 디코드하므로 여기서도 epoch seconds로 인코딩한다.
//

import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {

    // MARK: - 로컬 상수(메인 앱 SharedConstants와 값 동기 필수)
    private enum Local {
        static let appGroupID = "group.com.geniusjun.reminedo"
        static let urlScheme = "reminedo"
        static let payloadKey = "sharedPayload"
        static let addURL = "reminedo://add"
    }

    // MARK: - 로컬 카피(메인 앱 Strings.Share와 동기 — 확장은 앱 모듈을 공유하지 않음, §4.10/§8)
    private enum Copy {
        static let multiple = "첫 번째 링크만 저장됐어요."
        static let unsupported = "URL을 리마인두에 저장할 수 없어요."
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        extractAndHandle()
    }

    // MARK: - 추출

    /// inputItems → NSItemProvider에서 web URL(public.url)을 우선 추출하고, 없으면
    /// 텍스트(public.text)에서 첫 http(s) 링크를 추출한다(유튜브 등은 URL을 텍스트로 공유, §4.10).
    /// 다중 URL이면 첫 번째만 사용(+안내), 둘 다 없으면 미지원 안내 후 종료.
    private func extractAndHandle() {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem])?
            .compactMap { $0.attachments }
            .flatMap { $0 } ?? []

        let urlProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) }

        if let firstProvider = urlProviders.first {
            let isMultiple = urlProviders.count > 1
            firstProvider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] item, _ in
                guard let self else { return }
                let url: URL?
                switch item {
                case let value as URL: url = value
                case let value as String: url = URL(string: value)
                default: url = nil
                }
                self.handleExtracted(url: url, isMultiple: isMultiple)
            }
            return
        }

        // web URL이 없으면 텍스트에서 링크 추출 시도(유튜브 앱 공유 등).
        if let textProvider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.text.identifier) }) {
            textProvider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { [weak self] item, _ in
                guard let self else { return }
                let url = (item as? String).flatMap(Self.firstURL(in:))
                self.handleExtracted(url: url, isMultiple: false)
            }
            return
        }

        // 공유 항목 중 web URL·텍스트 링크가 모두 없으면 미지원 안내 후 종료.
        presentNoticeThenFinish(Copy.unsupported)
    }

    /// 추출된 URL을 검증해 저장·앱 호출하거나 미지원 안내. 메인 스레드로 마샬링한다.
    private func handleExtracted(url: URL?, isMultiple: Bool) {
        DispatchQueue.main.async {
            guard let url, url.scheme == "http" || url.scheme == "https" else {
                self.presentNoticeThenFinish(Copy.unsupported)
                return
            }
            self.persist(url: url.absoluteString)
            self.openMainApp()
            if isMultiple {
                self.presentNoticeThenFinish(Copy.multiple)
            } else {
                self.finish()
            }
        }
    }

    /// 텍스트에서 첫 http(s) 링크를 NSDataDetector로 추출한다.
    private static func firstURL(in text: String) -> URL? {
        if let direct = URL(string: text), direct.scheme == "http" || direct.scheme == "https" {
            return direct
        }
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        return detector?.firstMatch(in: text, options: [], range: range)?.url
    }

    // MARK: - 저장(App Group)

    /// { url, sharedAt(epoch seconds) } JSON Data를 App Group UserDefaults에 1건 기록한다(§4.10).
    /// 메인 앱 SharePayload가 .secondsSince1970 로 디코드하므로 동일 스키마로 인코딩.
    private func persist(url: String) {
        let payload: [String: Any] = [
            "url": url,
            "sharedAt": Date().timeIntervalSince1970
        ]
        guard
            let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
            let defaults = UserDefaults(suiteName: Local.appGroupID)
        else { return }
        defaults.set(data, forKey: Local.payloadKey)
        defaults.synchronize()
    }

    // MARK: - 메인 앱 호출

    /// reminedo://add로 메인 앱을 연다. 확장은 UIApplication.shared를 쓸 수 없어
    /// extensionContext.open(_:)을 사용한다. 일부 호스트에서 false를 반환할 수 있으나(best-effort),
    /// 메인 앱이 다음 활성화 시 페이로드를 소비하므로 허용 한계다(§4.10).
    private func openMainApp() {
        guard let url = URL(string: Local.addURL) else { return }
        extensionContext?.open(url, completionHandler: nil)
    }

    // MARK: - 종료

    private func finish() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }

    /// 간단한 안내 알럿을 띄운 뒤 종료한다.
    private func presentNoticeThenFinish(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "확인", style: .default) { [weak self] _ in
            self?.finish()
        })
        present(alert, animated: true)
    }
}
