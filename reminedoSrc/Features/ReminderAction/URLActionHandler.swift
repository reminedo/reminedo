//
//  URLActionHandler.swift
//  reminedo
//
//  URL 외부 열기(§3.5/§4.8). 인앱 URL 화면은 없다 — 처리 앱 우선, 실패 시 Safari 폴백.
//  O 액션(ActionRouterView)과 편집 시트의 "다시 보기" 탭이 함께 쓴다.
//

import UIKit

enum URLActionHandler {
    /// 유효한 http/https URL이면 외부로 연다(§4.8). 처리 앱 우선, 열기 실패 시 Safari로 폴백.
    /// 잘못되거나 비어 있으면 graceful no-op.
    static func open(_ urlString: String?) {
        guard let urlString,
              let url = URLValidation.normalizedURL(from: urlString) else { return }
        UIApplication.shared.open(url, options: [:]) { opened in
            // 처리 앱이 열지 못했으면 Safari로 폴백.
            if !opened {
                UIApplication.shared.open(url, options: [.universalLinksOnly: false])
            }
        }
    }
}
