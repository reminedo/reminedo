//
//  LinkPreviewService.swift
//  reminedo
//
//  URL 미리보기 서비스(§4.9). 편집 시트 로컬 — 전역 주입이 아니라 시트 안 @State로
//  생성되어 시트 수명과 함께 산다. LinkPresentation은 이 파일에서만 import한다(Shared 청결 유지).
//  fetch: 디바운스(~0.4s) + 이전 작업/Provider 취소 → LPMetadataProvider로 제목·썸네일 로드.
//  성공/실패 모두 메인 액터에서 state 갱신. 실패 문구는 시트가 노출(여기선 도메인만 전달).
//

import Foundation
import LinkPresentation
import UIKit

@MainActor
@Observable
final class LinkPreviewService {
    /// 4상태(§4.9): 빈 / 로딩 / 성공(제목·썸네일) / 실패(도메인).
    enum PreviewState: Equatable {
        case empty
        case loading
        case success(title: String, image: UIImage?)
        case failure(domain: String)
    }

    private(set) var state: PreviewState = .empty

    /// 디바운스·취소 단위. 새 fetch가 들어오면 이전 작업과 Provider를 함께 취소한다.
    private var task: Task<Void, Never>?
    private var provider: LPMetadataProvider?

    /// 디바운스 간격(초, §4.9).
    private let debounce: Duration = .milliseconds(400)
    /// 메타데이터 타임아웃(초, §4.9).
    private let timeout: TimeInterval = 10

    /// URL 입력/시트 오픈 시점 호출(§4.9). 유효하지 않거나 비면 .empty로 되돌린다.
    func fetch(_ urlString: String) {
        // 이전 작업/Provider 취소(디바운스+취소, §4.9).
        task?.cancel()
        provider?.cancel()
        provider = nil

        guard let url = URLValidation.normalizedURL(from: urlString) else {
            state = .empty
            return
        }

        let domain = url.host ?? urlString
        state = .loading

        task = Task { [weak self] in
            guard let self else { return }
            // 디바운스: 입력이 계속되면 이 시점 전에 다음 fetch가 취소한다.
            try? await Task.sleep(for: self.debounce)
            if Task.isCancelled { return }

            let metadata = await self.loadMetadata(for: url)
            if Task.isCancelled { return }

            guard let metadata else {
                self.state = .failure(domain: domain)
                return
            }

            let title = metadata.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            let image = await Self.loadImage(from: metadata.imageProvider)
            if Task.isCancelled { return }

            let resolvedTitle = (title?.isEmpty == false) ? title! : domain
            self.state = .success(title: resolvedTitle, image: image)
        }
    }

    /// 새 LPMetadataProvider로 메타데이터 로드(타임아웃 포함, §4.9).
    private func loadMetadata(for url: URL) async -> LPLinkMetadata? {
        let provider = LPMetadataProvider()
        provider.timeout = timeout
        self.provider = provider
        defer { if self.provider === provider { self.provider = nil } }
        return try? await provider.startFetchingMetadata(for: url)
    }

    /// 썸네일 이미지 로드(metadata.imageProvider). 실패 시 nil(성공 상태는 유지).
    private static func loadImage(from imageProvider: NSItemProvider?) async -> UIImage? {
        guard let imageProvider, imageProvider.canLoadObject(ofClass: UIImage.self) else { return nil }
        return await withCheckedContinuation { continuation in
            imageProvider.loadObject(ofClass: UIImage.self) { object, _ in
                continuation.resume(returning: object as? UIImage)
            }
        }
    }
}
