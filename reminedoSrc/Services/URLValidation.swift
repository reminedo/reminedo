//
//  URLValidation.swift
//  reminedo
//
//  URL 유효성 검사(§4.8). 유효 조건: URL(string:)가 파싱되고 scheme∈{http,https}.
//  관대하게 — 스킴이 빠진 입력에 자동으로 https://를 붙이지 않고, 그대로 검증만 한다.
//  실패 시 시트가 "올바른 링크를 입력해주세요"(Strings.Edit.urlInvalid)를 노출한다.
//  Services 레이어 — Foundation만 사용(LinkPresentation/UIKit 의존 없음).
//

import Foundation

enum URLValidation {
    /// scheme∈{http,https}이고 host가 있는 정규 URL만 통과(§4.8).
    static func normalizedURL(from string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty
        else { return nil }
        return url
    }

    /// 입력이 유효한 http/https URL인지(§4.8).
    static func isValid(_ string: String) -> Bool {
        normalizedURL(from: string) != nil
    }
}
