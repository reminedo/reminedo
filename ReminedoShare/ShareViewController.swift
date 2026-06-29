//
//  ShareViewController.swift
//  ReminedoShare
//
//  공유 확장: 제목·링크·시간만 입력받아 (1) iOS 로컬 알림을 직접 예약하고 (2) App Group에
//  페이로드를 기록한다. 앱을 열지 않아도 알림이 울리며, 앱은 다음 실행 시 페이로드로 레코드를
//  생성하고 같은 식별자로 정식 재예약한다(중복 발화 없음). 나머지 설정은 앱에서 수정한다.
//
//  ※ 확장에서의 알림 예약은 iOS 동작이 기기/버전에 따라 다를 수 있어 실기기 검증이 필요하다.
//    설령 확장 예약이 안 떠도, 앱을 한 번 열면 페이로드로 정식 예약되어 동작은 보장된다.
//

import UIKit
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

final class ShareViewController: UIViewController {
    private enum Local {
        static let appGroupID = "group.com.geniusjun.reminedo"
        static let payloadKey = "sharedPayload"
        static let importDirectoryName = "shared-imports"
        static let categoryID = "REMINDER_CATEGORY"   // 앱의 NotificationCategory.reminder와 동일해야 함.
    }

    private enum Copy {
        static let imageFailed = "사진을 불러오지 못했어요."
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let providers = collectProviders()

        // 이미지 공유: 이미지를 App Group에 저장한 뒤 입력 폼(제목·시간)을 띄운다.
        if let imageProvider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }) {
            handleImage(imageProvider)
            return
        }

        // URL/텍스트 공유: 링크가 있으면 URL 폼, 순수 텍스트(링크 없음)면 메모 폼을 띄운다.
        resolveShareContent(from: providers) { [weak self] content in
            DispatchQueue.main.async {
                switch content {
                case .url(let urlString): self?.presentForm(prefilledURL: urlString)
                case .memo(let text): self?.presentMemoForm(prefilledMemo: text)
                }
            }
        }
    }

    // MARK: - 입력 폼

    private func presentForm(prefilledURL: String) {
        embed(ShareComposeView(
            kind: .url,
            initialURL: prefilledURL,
            onSave: { [weak self] title, urlText, _, date in
                self?.saveURLReminder(title: title, urlText: urlText, date: date)
            },
            onCancel: { [weak self] in self?.cancel() }
        ))
    }

    private func presentImageForm(fileName: String) {
        embed(ShareComposeView(
            kind: .image,
            onSave: { [weak self] title, _, _, date in
                self?.saveImageReminder(title: title, date: date, fileName: fileName)
            },
            onCancel: { [weak self] in self?.cancel() }
        ))
    }

    private func presentMemoForm(prefilledMemo: String) {
        embed(ShareComposeView(
            kind: .memo,
            initialMemo: prefilledMemo,
            onSave: { [weak self] title, _, memo, date in
                self?.saveMemoReminder(title: title, memo: memo, date: date)
            },
            onCancel: { [weak self] in self?.cancel() }
        ))
    }

    private func embed(_ compose: ShareComposeView) {
        let host = UIHostingController(rootView: compose)
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        host.didMove(toParent: self)
    }

    private func saveURLReminder(title: String, urlText: String, date: Date) {
        let id = UUID()
        scheduleNotification(id: id, title: title, date: date)
        let trimmedURL = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        var payload: [String: Any] = [
            "id": id.uuidString,
            "contentTypeRaw": trimmedURL.isEmpty ? "memo" : "url",
            "title": title,
            "scheduledAt": date.timeIntervalSince1970,
            "sharedAt": Date().timeIntervalSince1970,
        ]
        if !trimmedURL.isEmpty { payload["url"] = trimmedURL }
        persist(payload: payload)
        finish()
    }

    private func saveImageReminder(title: String, date: Date, fileName: String) {
        let id = UUID()
        scheduleNotification(id: id, title: title, date: date)
        persist(payload: [
            "id": id.uuidString,
            "contentTypeRaw": "image",
            "imageFileName": fileName,
            "title": title,
            "scheduledAt": date.timeIntervalSince1970,
            "sharedAt": Date().timeIntervalSince1970,
        ])
        finish()
    }

    private func saveMemoReminder(title: String, memo: String, date: Date) {
        let id = UUID()
        scheduleNotification(id: id, title: title, date: date)
        let trimmedMemo = memo.trimmingCharacters(in: .whitespacesAndNewlines)
        var payload: [String: Any] = [
            "id": id.uuidString,
            "contentTypeRaw": "memo",
            "title": title,
            "scheduledAt": date.timeIntervalSince1970,
            "sharedAt": Date().timeIntervalSince1970,
        ]
        if !trimmedMemo.isEmpty { payload["memo"] = trimmedMemo }
        persist(payload: payload)
        finish()
    }

    // MARK: - 알림 직접 예약 (확장)

    private func scheduleNotification(id: UUID, title: String, date: Date) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = ""
        // 커스텀 사운드는 번들 의존이 있어 .default로 둔다. 앱이 열리면 정식(alarm.caf)으로 재예약된다.
        content.sound = .default
        content.userInfo = ["reminderId": id.uuidString, "isSnooze": false]
        content.categoryIdentifier = Local.categoryID

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        // 식별자 = id.uuidString → 앱의 NotificationID.base(reminder.id)와 동일 스킴(prefix 취소로 교체됨).
        let request = UNNotificationRequest(identifier: id.uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    // MARK: - 이미지 공유 (이미지 저장 → 입력 폼)

    private func handleImage(_ provider: NSItemProvider) {
        provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { [weak self] item, _ in
            guard let self else { return }
            guard let data = Self.imageData(from: item),
                  let fileName = self.saveImportedImage(data)
            else {
                DispatchQueue.main.async { self.presentNoticeThenFinish(Copy.imageFailed) }
                return
            }
            DispatchQueue.main.async { self.presentImageForm(fileName: fileName) }
        }
    }

    // MARK: - URL 추출 (loadItem → loadObject → 콘텐츠 텍스트)

    private func collectProviders() -> [NSItemProvider] {
        (extensionContext?.inputItems as? [NSExtensionItem])?
            .compactMap { $0.attachments }
            .flatMap { $0 } ?? []
    }

    /// 공유 콘텐츠 분기: 링크가 있으면 .url, 순수 텍스트(링크 없음)면 .memo(본문).
    private enum ShareContent {
        case url(String)
        case memo(String)   // 메모 본문(빈 문자열 가능)
    }

    private func resolveShareContent(from providers: [NSItemProvider], completion: @escaping (ShareContent) -> Void) {
        if let urlProvider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) }) {
            urlProvider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] item, _ in
                guard let self else { return }
                if let url = Self.url(from: item) { completion(.url(url.absoluteString)); return }
                _ = urlProvider.loadObject(ofClass: URL.self) { url, _ in
                    if let s = url?.absoluteString { completion(.url(s)) }
                    else if let s = self.firstURLFromContentText()?.absoluteString { completion(.url(s)) }
                    else { completion(.memo(self.contentText() ?? "")) }
                }
            }
            return
        }
        if let textProvider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.text.identifier) }) {
            textProvider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { [weak self] item, _ in
                guard let self else { return }
                let text = (item as? String) ?? ""
                // 텍스트 안에 링크가 있으면 기존처럼 URL로 취급(동작 보존), 없으면 메모 본문으로.
                if let textURL = Self.firstURL(in: text) { completion(.url(textURL.absoluteString)) }
                else if let s = self.firstURLFromContentText()?.absoluteString { completion(.url(s)) }
                else { completion(.memo(text.isEmpty ? (self.contentText() ?? "") : text)) }
            }
            return
        }
        if let s = firstURLFromContentText()?.absoluteString { completion(.url(s)) }
        else { completion(.memo(contentText() ?? "")) }
    }

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

    /// 공유 항목의 첨부 텍스트(attributedContentText) 원문. 메모 본문 프리필용.
    private func contentText() -> String? {
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        for item in items {
            if let text = item.attributedContentText?.string, !text.isEmpty { return text }
        }
        return nil
    }

    // MARK: - 파싱 헬퍼

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

    @discardableResult
    private func persist(payload: [String: Any]) -> Bool {
        guard
            let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
            let defaults = UserDefaults(suiteName: Local.appGroupID)
        else { return false }
        defaults.set(data, forKey: Local.payloadKey)
        return true
    }

    // MARK: - 종료

    private func finish() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }

    private func cancel() {
        extensionContext?.cancelRequest(withError: NSError(domain: "ReminedoShare", code: 0))
    }

    private func presentNoticeThenFinish(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "확인", style: .default) { [weak self] _ in
            self?.finish()
        })
        present(alert, animated: true)
    }
}
