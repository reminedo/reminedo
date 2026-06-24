//
//  ShareViewController.swift
//  ReminedoShare
//
//  공유 시트 → 리마인두 익스텐션(§2.3/§4.10, 이슈2 재설계). 공유된 URL을 추출해
//  **확장 내 간단 추가 화면**(URL 자동 채움 + 제목 + 시간 + 반복 + 저장)을 띄운다.
//  저장 시 App Group에 {url, sharedAt, title, scheduledAt, repeatRuleRaw} JSON을 기록하고
//  reminedo://add 로 메인 앱을 깨워 Reminder를 직접 생성+예약하게 한다(추가 시트 미오픈, "저장→끝").
//
//  ※ 단일 출처 SharedConstants를 확장은 공유하지 않아 필요한 값만 로컬 정의(App Group/스킴 일치 필수).
//    페이로드 스키마는 메인 앱 SharePayload(Codable, .secondsSince1970)와 정확히 합의된다.
//    다중 공유 시 첫 URL만 사용, 미지원 시 안내 후 종료.
//

import UIKit
import SwiftUI
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {

    // MARK: - 로컬 상수(메인 앱 SharedConstants와 값 동기 필수)
    private enum Local {
        static let appGroupID = "group.com.geniusjun.reminedo"
        static let payloadKey = "sharedPayload"
        static let addURL = "reminedo://add"
    }

    // MARK: - 로컬 카피(메인 앱 Strings.Share와 동기)
    private enum Copy {
        static let multiple = "첫 번째 링크만 저장됐어요."
        static let unsupported = "URL을 리마인두에 저장할 수 없어요."
    }

    /// 추출된 공유 URL(화면 표시·저장용). nil이면 미지원 안내.
    private var extractedURL: String?
    private var isMultiple = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        extractAndHandle()
    }

    // MARK: - 추출

    /// inputItems → NSItemProvider에서 web URL(public.url)을 우선 추출하고, 없으면 텍스트에서
    /// 첫 http(s) 링크를 추출한다(유튜브 등은 URL을 텍스트로 공유). 추출 후 폼 표시.
    private func extractAndHandle() {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem])?
            .compactMap { $0.attachments }
            .flatMap { $0 } ?? []

        let urlProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) }

        if let firstProvider = urlProviders.first {
            isMultiple = urlProviders.count > 1
            firstProvider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] item, _ in
                guard let self else { return }
                let url: URL?
                switch item {
                case let value as URL: url = value
                case let value as String: url = URL(string: value)
                default: url = nil
                }
                DispatchQueue.main.async {
                    self.handleExtracted(url: url)
                }
            }
            return
        }

        // web URL이 없으면 텍스트에서 링크 추출 시도(유튜브 앱 공유 등).
        if let textProvider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.text.identifier) }) {
            textProvider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { [weak self] item, _ in
                guard let self else { return }
                let url = (item as? String).flatMap(Self.firstURL(in:))
                DispatchQueue.main.async {
                    self.handleExtracted(url: url)
                }
            }
            return
        }

        // 공유 항목 중 web URL·텍스트 링크가 모두 없으면 미지원 안내 후 종료.
        presentNoticeThenFinish(Copy.unsupported)
    }

    /// 추출된 URL을 검증해 폼을 띄우거나 미지원 안내.
    private func handleExtracted(url: URL?) {
        guard let url, url.scheme == "http" || url.scheme == "https" else {
            presentNoticeThenFinish(Copy.unsupported)
            return
        }
        extractedURL = url.absoluteString
        if isMultiple {
            // 다중 공유: 첫 URL로 진행하되 안내 토스트는 저장 후 노출(여기선 플래그만 유지).
        }
        presentForm()
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

    // MARK: - 추가 폼(SwiftUI)

    /// 확장 내 간단 추가 화면을 UIHostingController로 표시한다(URL 자동 채움).
    private func presentForm() {
        guard let url = extractedURL else {
            presentNoticeThenFinish(Copy.unsupported)
            return
        }

        let form = ShareAddForm(
            url: url,
            multipleNotice: isMultiple ? Copy.multiple : nil,
            onSave: { [weak self] title, scheduledAt, repeatRuleRaw in
                self?.persist(url: url, title: title, scheduledAt: scheduledAt, repeatRuleRaw: repeatRuleRaw)
                self?.openMainApp()
                self?.finish()
            },
            onCancel: { [weak self] in
                self?.cancel()
            }
        )
        let host = UIHostingController(rootView: form)
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        host.didMove(toParent: self)
    }

    // MARK: - 저장(App Group)

    /// { url, sharedAt, title?, scheduledAt?, repeatRuleRaw? } JSON Data를 App Group UserDefaults에 기록.
    /// 메인 앱 SharePayload가 .secondsSince1970 로 디코딩하므로 날짜는 epoch seconds(Double)로 인코딩.
    private func persist(url: String, title: String?, scheduledAt: Date?, repeatRuleRaw: String?) {
        var payload: [String: Any] = [
            "url": url,
            "sharedAt": Date().timeIntervalSince1970
        ]
        if let title { payload["title"] = title }
        if let scheduledAt { payload["scheduledAt"] = scheduledAt.timeIntervalSince1970 }
        if let repeatRuleRaw { payload["repeatRuleRaw"] = repeatRuleRaw }
        guard
            let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
            let defaults = UserDefaults(suiteName: Local.appGroupID)
        else { return }
        defaults.set(data, forKey: Local.payloadKey)
        defaults.synchronize()
    }

    // MARK: - 메인 앱 호출

    /// reminedo://add로 메인 앱을 깨운다. 확장은 UIApplication.shared를 쓸 수 없어
    /// extensionContext.open(_:)을 사용한다(best-effort).
    private func openMainApp() {
        guard let url = URL(string: Local.addURL) else { return }
        extensionContext?.open(url, completionHandler: nil)
    }

    // MARK: - 종료

    private func finish() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }

    private func cancel() {
        extensionContext?.cancelRequest(withError: NSError(domain: "ReminedoShare", code: -1))
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

// MARK: - SwiftUI 추가 폼

/// 공유 확장 내 간단 추가 화면(이슈2). URL 자동 채움 + 제목 + 시간 + 반복(none/daily) + 저장/취소.
private struct ShareAddForm: View {
    let url: String
    let multipleNotice: String?
    let onSave: (String?, Date, String?) -> Void
    let onCancel: () -> Void

    @State private var title: String = ""
    @State private var time: Date = Date()
    @State private var repeatsDaily: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let multipleNotice {
                        Label(multipleNotice, systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("링크")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text(url)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("제목")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        TextField("알림에 표시될 제목", text: $title)
                            .textFieldStyle(.plain)
                            .padding(12)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("알림 시간")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        DatePicker("알림 시간", selection: $time, displayedComponents: .hourAndMinute)
                            .datePickerStyle(.wheel)
                            .labelsHidden()
                            .environment(\.locale, Locale(identifier: "ko_KR"))
                            .frame(maxWidth: .infinity)
                    }

                    Toggle("매일 반복", isOn: $repeatsDaily)
                        .padding(.vertical, 4)
                }
                .padding(16)
            }
            .background(Color(.systemBackground))
            .navigationTitle("리마인두")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("취소") { onCancel() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("저장") {
                        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(
                            trimmed.isEmpty ? nil : trimmed,
                            time,
                            repeatsDaily ? RepeatRule.daily.rawValue : RepeatRule.none.rawValue
                        )
                    }
                    .bold()
                }
            }
        }
        // Share Extension에서 공유 enum(RepeatRule) 접근이 불가하므로 rawValue 문자열 리터럴로 폴백.
        // (아래 RepeatRule은 확장 로컬 정의 — 메인 앱 RepeatRule.rawValue와 동일 문자열이어야 함.)
    }
}

/// 확장 로컬 RepeatRule(메인 앱 RepeatRule.rawValue "none"/"daily"/"weekly"와 동일).
private enum RepeatRule: String {
    case none = "none"
    case daily = "daily"
}
