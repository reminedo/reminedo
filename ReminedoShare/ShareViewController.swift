//
//  ShareViewController.swift
//  ReminedoShare
//
//  The share extension only imports shared content and opens the main app.
//  Reminder creation, validation, scheduling, and widget refresh stay in the app.
//
//  추출은 견고성을 위해 다단 폴백을 둔다: URL provider는 loadItem → loadObject(URL) → 콘텐츠
//  텍스트(attributedContentText) 순으로 시도한다(YouTube처럼 loadItem이 실패/빈값을 주는 소스 대응).
//  실패 메시지는 단계별로 분리해 어느 지점에서 막혔는지 화면에서 바로 구분되게 한다.
//

import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private enum Local {
        static let appGroupID = "group.com.geniusjun.reminedo"
        static let payloadKey = "sharedPayload"
        static let addURL = "reminedo://add"
        static let importDirectoryName = "shared-imports"
    }

    /// 실패 단계별 메시지(진단용). 어느 가지에서 막혔는지 디바이스에서 바로 구분된다.
    private enum Copy {
        static let noContent = "공유할 URL이나 사진을 찾지 못했어요. (콘텐츠 없음)"
        static let urlLoadFailed = "링크를 불러오지 못했어요. (URL 로드 실패)"
        static let badURL = "지원하지 않는 링크예요. (http/https만 가능)"
        static let imageFailed = "사진을 불러오지 못했어요. (이미지 로드 실패)"
        static let saveFailed = "저장에 실패했어요. (앱 그룹 저장 실패)"
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        extractAndOpenApp()
    }

    private func extractAndOpenApp() {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem])?
            .compactMap { $0.attachments }
            .flatMap { $0 } ?? []

        if let urlProvider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) }) {
            loadURL(from: urlProvider)
            return
        }

        if let textProvider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.text.identifier) }) {
            loadTextURL(from: textProvider)
            return
        }

        if let imageProvider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }) {
            loadImage(from: imageProvider)
            return
        }

        // 폴백: attachment provider가 없으면 NSExtensionItem.attributedContentText에서 URL 검출.
        if let url = firstURLFromContentText() {
            handle(url: url)
            return
        }

        presentNoticeThenFinish(Copy.noContent)
    }

    // MARK: - URL 로드 (loadItem → loadObject → 콘텐츠 텍스트 폴백)

    private func loadURL(from provider: NSItemProvider) {
        provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] item, _ in
            guard let self else { return }
            if let url = Self.url(from: item) {
                DispatchQueue.main.async { self.handle(url: url) }
            } else {
                // loadItem이 nil/예상 밖 타입 → loadObject(URL)로 재시도.
                self.loadURLViaObject(from: provider)
            }
        }
    }

    private func loadURLViaObject(from provider: NSItemProvider) {
        // loadObject는 provider가 URL을 못 주면 completion에 nil/에러를 주므로 canLoadObject 가드 없이 안전.
        _ = provider.loadObject(ofClass: URL.self) { [weak self] url, _ in
            guard let self else { return }
            DispatchQueue.main.async {
                if let url {
                    self.handle(url: url)
                } else {
                    self.fallbackToContentTextOrFail()
                }
            }
        }
    }

    private func loadTextURL(from provider: NSItemProvider) {
        provider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { [weak self] item, _ in
            guard let self else { return }
            let textURL = (item as? String).flatMap(Self.firstURL(in:))
            DispatchQueue.main.async {
                if let url = textURL ?? self.firstURLFromContentText() {
                    self.handle(url: url)
                } else {
                    self.presentNoticeThenFinish(Copy.urlLoadFailed)
                }
            }
        }
    }

    /// loadItem/loadObject가 모두 실패했을 때 마지막으로 콘텐츠 텍스트에서 URL을 찾는다.
    private func fallbackToContentTextOrFail() {
        if let url = firstURLFromContentText() {
            handle(url: url)
        } else {
            presentNoticeThenFinish(Copy.urlLoadFailed)
        }
    }

    /// NSExtensionItem.attributedContentText(제목/본문 텍스트)에서 첫 http(s) URL을 검출한다.
    private func firstURLFromContentText() -> URL? {
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        for item in items {
            if let text = item.attributedContentText?.string,
               let url = Self.firstURL(in: text) {
                return url
            }
        }
        return nil
    }

    // MARK: - 이미지 로드

    private func loadImage(from provider: NSItemProvider) {
        provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { [weak self] item, _ in
            guard let self else { return }
            guard let data = Self.imageData(from: item),
                  let fileName = self.saveImportedImage(data)
            else {
                DispatchQueue.main.async { self.presentNoticeThenFinish(Copy.imageFailed) }
                return
            }
            DispatchQueue.main.async {
                guard self.persist(payload: [
                    "contentTypeRaw": "image",
                    "imageFileName": fileName,
                    "sharedAt": Date().timeIntervalSince1970
                ]) else {
                    self.presentNoticeThenFinish(Copy.saveFailed)
                    return
                }
                self.openMainAppThenFinish()
            }
        }
    }

    // MARK: - 저장 + 앱 열기

    private func handle(url: URL?) {
        guard let url, url.scheme == "http" || url.scheme == "https" else {
            presentNoticeThenFinish(Copy.badURL)
            return
        }
        guard persist(payload: [
            "contentTypeRaw": "url",
            "url": url.absoluteString,
            "sharedAt": Date().timeIntervalSince1970
        ]) else {
            presentNoticeThenFinish(Copy.saveFailed)
            return
        }
        openMainAppThenFinish()
    }

    // MARK: - 파싱 헬퍼

    /// loadItem이 돌려주는 다양한 표현(URL/NSURL/String/Data)을 URL로 정규화한다.
    private static func url(from item: NSSecureCoding?) -> URL? {
        switch item {
        case let value as URL:
            return value
        case let value as String:
            return URL(string: value)
        case let value as Data:
            return URL(dataRepresentation: value, relativeTo: nil)
                ?? String(data: value, encoding: .utf8).flatMap(URL.init(string:))
        default:
            return nil
        }
    }

    private static func firstURL(in text: String) -> URL? {
        if let direct = URL(string: text), direct.scheme == "http" || direct.scheme == "https" {
            return direct
        }
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        return detector?.firstMatch(in: text, options: [], range: range)?.url
    }

    private static func imageData(from item: NSSecureCoding?) -> Data? {
        switch item {
        case let image as UIImage:
            return image.jpegData(compressionQuality: 0.92)
        case let data as Data:
            return UIImage(data: data)?.jpegData(compressionQuality: 0.92)
        case let url as URL:
            guard let data = try? Data(contentsOf: url) else { return nil }
            return UIImage(data: data)?.jpegData(compressionQuality: 0.92)
        default:
            return nil
        }
    }

    private func saveImportedImage(_ data: Data) -> String? {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Local.appGroupID) else {
            return nil
        }
        let directory = container.appendingPathComponent(Local.importDirectoryName, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let fileName = "\(UUID().uuidString).jpg"
        let url = directory.appendingPathComponent(fileName, isDirectory: false)
        do {
            try data.write(to: url, options: .atomic)
            return fileName
        } catch {
            return nil
        }
    }

    private func persist(payload: [String: Any]) -> Bool {
        guard
            let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
            let defaults = UserDefaults(suiteName: Local.appGroupID)
        else { return false }
        defaults.set(data, forKey: Local.payloadKey)
        return true
    }

    private func openMainAppThenFinish() {
        guard let url = URL(string: Local.addURL) else {
            finish()
            return
        }
        // Share extension에서 호스트 앱 열기: extensionContext.open(_:)은 iOS/기기에 따라 무시되는
        // 경우가 있어, responder chain을 타고 UIApplication을 찾아 직접 open한다(널리 쓰이는 우회책).
        openURLViaResponderChain(url)
        // open은 비동기로 앱을 띄우므로 약간 늦춰 종료한다 — 즉시 finish()하면 앱 전환이 끊길 수 있다.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.finish()
        }
    }

    private func openURLViaResponderChain(_ url: URL) {
        // open(_:options:completionHandler:)은 확장 타깃(APPLICATION_EXTENSION_API_ONLY)에서
        // 직접 호출이 막히므로, selector로 우회해 UIApplication의 openURL:을 perform한다.
        let selector = NSSelectorFromString("openURL:")
        var responder: UIResponder? = self
        while let current = responder {
            if current.responds(to: selector) {
                current.perform(selector, with: url)
                return
            }
            responder = current.next
        }
        // responder chain에서 처리자를 못 찾으면 기존 경로로 폴백.
        extensionContext?.open(url, completionHandler: nil)
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }

    private func presentNoticeThenFinish(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "확인", style: .default) { [weak self] _ in
            self?.finish()
        })
        present(alert, animated: true)
    }
}
