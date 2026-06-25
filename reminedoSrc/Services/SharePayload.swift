//
//  SharePayload.swift
//  reminedo
//
//  Share Extension이 App Group에 기록하는 공유 페이로드(§4.10). 메인 앱은 reminedo://add
//  수신 시 이걸 읽어(소비·삭제) 추가 시트를 URL/사진 프리필로 연다(§2.3). Foundation만 의존한다.
//
//  페이로드 형식(확장과 합의된 단일 스키마):
//    App Group UserDefaults 키 "sharedPayload"에 JSON Data 1건.
//    JSON 객체 { "contentTypeRaw": String, "url"?: String, "imageFileName"?: String, "sharedAt": Double(epoch seconds) }.
//    인코딩/디코딩은 .secondsSince1970 날짜 전략으로 양쪽이 동일하게 맞춘다.
//

import Foundation

struct SharePayload: Codable {
    /// 확장이 미리 발급한 reminder UUID 문자열(없으면 nil). 앱이 같은 id로 레코드를 생성해
    /// 확장이 임시 예약한 알림(식별자=이 id)을 정식 예약으로 교체한다 — 중복 발화 방지.
    let id: String?
    let contentTypeRaw: String?
    let url: String?
    let imageFileName: String?
    let sharedAt: Date
    /// 공유 확장 폼에서 입력받는 제목·시각(없으면 nil — 이미지/구버전 하위호환).
    let title: String?
    let scheduledAt: Date?
    /// RepeatRule.rawValue 문자열(none/daily/weekly). weekly 요일은 확장 UI에서 미지원 → none/daily만.
    let repeatRuleRaw: String?

    /// App Group 공유 UserDefaults. 확장·메인 앱이 같은 suite로 접근한다(§7).
    private static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: SharedConstants.appGroupID)
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }

    /// App Group에서 페이로드를 디코드한다. 없거나 손상되면 nil.
    static func read() -> SharePayload? {
        guard let data = sharedDefaults?.data(forKey: SharedConstants.UserDefaultsKey.sharedPayload) else {
            return nil
        }
        return try? decoder.decode(SharePayload.self, from: data)
    }

    /// 읽은 뒤 키를 삭제한다(§4.10 소비/삭제). 1회 소비 보장.
    static func consume() -> SharePayload? {
        let payload = read()
        sharedDefaults?.removeObject(forKey: SharedConstants.UserDefaultsKey.sharedPayload)
        return payload
    }
}
