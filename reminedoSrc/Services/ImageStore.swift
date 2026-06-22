//
//  ImageStore.swift
//  reminedo
//
//  이미지 영속 서비스(§4.7). <Documents>/reminder-images/ 아래에 알람 이미지를 JPEG로
//  저장·로드·삭제하고, 셀용 다운샘플 썸네일을 NSCache로 캐시한다. UIKit/ImageIO는 이 파일
//  (+ 이미지 뷰)에서만 import한다(Shared 청결 유지). 환경 주입 단일 객체(NotificationService와 동류).
//
//  파일명 규칙: 메인 이미지 = "{reminderId}.jpg", 링크 썸네일 = "{reminderId}-link.jpg"
//   (이미지 알람 사진과 URL 알람 링크 썸네일이 충돌하지 않도록 분리, §4.7).
//

import UIKit
import ImageIO
import UniformTypeIdentifiers

@MainActor
@Observable
final class ImageStore {
    /// 저장 최대 용량(§4.7). 인코딩 결과가 이 크기를 넘으면 다운스케일/품질 저하 반복.
    private let maxBytes = 10 * 1024 * 1024   // ~10MB
    /// JPEG 인코딩 시작 품질.
    private let startQuality: CGFloat = 0.9

    /// 셀 썸네일 캐시(§4.7). 키는 파일명, 값은 다운샘플 UIImage.
    private let thumbnailCache = NSCache<NSString, UIImage>()

    private let fileManager = FileManager.default

    // MARK: - 경로

    /// <Documents>/reminder-images/ 디렉터리. 없으면 생성.
    private var directory: URL {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = documents.appendingPathComponent("reminder-images", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func url(for fileName: String) -> URL {
        directory.appendingPathComponent(fileName, isDirectory: false)
    }

    /// 메인 이미지 파일명(§4.7).
    private func mainFileName(for id: UUID) -> String { "\(id.uuidString).jpg" }
    /// 링크 썸네일 파일명(§4.7) — 메인 이미지와 충돌 방지.
    private func linkFileName(for id: UUID) -> String { "\(id.uuidString)-link.jpg" }

    // MARK: - 저장

    /// 메인 이미지를 항상 JPEG로 재인코딩해 "{id}.jpg"에 덮어쓴다(§4.7). 10MB 초과 시
    /// 품질·해상도를 줄여 한도 아래로 맞춘다. 파일명(전체 경로 아님)을 반환한다.
    func save(_ image: UIImage, for id: UUID) throws -> String {
        let fileName = mainFileName(for: id)
        let data = try encodedJPEG(from: image)
        try data.write(to: url(for: fileName), options: .atomic)
        thumbnailCache.removeObject(forKey: fileName as NSString)
        return fileName
    }

    /// 링크 썸네일을 "{id}-link.jpg"에 JPEG로 저장(best-effort). 실패 시 nil(§4.9 영속).
    func saveLinkThumbnail(_ image: UIImage, for id: UUID) -> String? {
        let fileName = linkFileName(for: id)
        guard let data = try? encodedJPEG(from: image) else { return nil }
        guard (try? data.write(to: url(for: fileName), options: .atomic)) != nil else { return nil }
        thumbnailCache.removeObject(forKey: fileName as NSString)
        return fileName
    }

    /// 항상 JPEG 재인코딩(§4.7). 10MB 초과면 품질을 먼저 낮추고, 그래도 크면 해상도를 줄인다.
    private func encodedJPEG(from image: UIImage) throws -> Data {
        var working = image
        var quality = startQuality

        while true {
            guard let data = working.jpegData(compressionQuality: quality) else {
                throw ImageStoreError.encodingFailed
            }
            if data.count <= maxBytes { return data }

            if quality > 0.4 {
                // 1차: 품질 단계 하향.
                quality -= 0.15
            } else {
                // 2차: 해상도를 70%로 줄여 다시 시도(품질 리셋).
                let newSize = CGSize(width: working.size.width * 0.7,
                                     height: working.size.height * 0.7)
                guard newSize.width >= 1, newSize.height >= 1,
                      let downscaled = working.resized(to: newSize) else {
                    // 더 줄일 수 없으면 마지막 인코딩 결과로 반환(best-effort).
                    return data
                }
                working = downscaled
                quality = startQuality
            }
        }
    }

    // MARK: - 로드

    /// 풀 이미지 로드(풀스크린 뷰어용, §3.5). 없으면 nil.
    func loadImage(named fileName: String) -> UIImage? {
        UIImage(contentsOfFile: url(for: fileName).path)
    }

    /// 셀용 다운샘플 썸네일(§4.7). ImageIO로 maxPixel 이하로 디코드해 NSCache에 캐시한다
    /// — 풀 이미지를 셀에 올리지 않는다.
    func thumbnail(named fileName: String, maxPixel: CGFloat = 120) -> UIImage? {
        let key = fileName as NSString
        if let cached = thumbnailCache.object(forKey: key) { return cached }

        let fileURL = url(for: fileName)
        guard fileManager.fileExists(atPath: fileURL.path),
              let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let thumb = UIImage(cgImage: cgImage)
        thumbnailCache.setObject(thumb, forKey: key)
        return thumb
    }

    // MARK: - 삭제

    /// 단일 파일 삭제(best-effort). 캐시도 함께 비운다.
    func delete(named fileName: String) {
        try? fileManager.removeItem(at: url(for: fileName))
        thumbnailCache.removeObject(forKey: fileName as NSString)
    }

    /// 여러 파일 일괄 삭제(지연 삭제 큐 정리용, §4.3).
    func deleteAll(in fileNames: [String]) {
        for name in fileNames where !name.isEmpty { delete(named: name) }
    }

    /// reminder-images 디렉터리 전체 삭제(데이터 삭제용, §3.6). 캐시도 비운다.
    /// directory 게터가 다음 접근 시 빈 디렉터리를 재생성한다(best-effort).
    func deleteAllImages() {
        try? fileManager.removeItem(at: directory)
        thumbnailCache.removeAllObjects()
    }

    enum ImageStoreError: Error {
        case encodingFailed
    }
}

private extension UIImage {
    /// 지정 크기로 비트맵 리드로(다운스케일 인코딩 보조).
    func resized(to size: CGSize) -> UIImage? {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
