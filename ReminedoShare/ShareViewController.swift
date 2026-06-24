//
//  ShareViewController.swift
//  ReminedoShare
//
//  The share extension only imports shared content and opens the main app.
//  Reminder creation, validation, scheduling, and widget refresh stay in the app.
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

    private enum Copy {
        static let unsupported = "URL 또는 사진을 리마인두에 추가할 수 없어요."
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

        presentNoticeThenFinish(Copy.unsupported)
    }

    private func loadURL(from provider: NSItemProvider) {
        provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] item, _ in
            guard let self else { return }
            let url: URL?
            switch item {
            case let value as URL:
                url = value
            case let value as String:
                url = URL(string: value)
            default:
                url = nil
            }
            DispatchQueue.main.async {
                self.handle(url: url)
            }
        }
    }

    private func loadTextURL(from provider: NSItemProvider) {
        provider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { [weak self] item, _ in
            guard let self else { return }
            let url = (item as? String).flatMap(Self.firstURL(in:))
            DispatchQueue.main.async {
                self.handle(url: url)
            }
        }
    }

    private func loadImage(from provider: NSItemProvider) {
        provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { [weak self] item, _ in
            guard let self else { return }
            guard let data = Self.imageData(from: item),
                  let fileName = self.saveImportedImage(data)
            else {
                DispatchQueue.main.async { self.presentNoticeThenFinish(Copy.unsupported) }
                return
            }
            DispatchQueue.main.async {
                guard self.persist(payload: [
                    "contentTypeRaw": "image",
                    "imageFileName": fileName,
                    "sharedAt": Date().timeIntervalSince1970
                ]) else {
                    self.presentNoticeThenFinish(Copy.unsupported)
                    return
                }
                self.openMainAppThenFinish()
            }
        }
    }

    private func handle(url: URL?) {
        guard let url, url.scheme == "http" || url.scheme == "https" else {
            presentNoticeThenFinish(Copy.unsupported)
            return
        }
        guard persist(payload: [
            "contentTypeRaw": "url",
            "url": url.absoluteString,
            "sharedAt": Date().timeIntervalSince1970
        ]) else {
            presentNoticeThenFinish(Copy.unsupported)
            return
        }
        openMainAppThenFinish()
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
        return defaults.synchronize()
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
