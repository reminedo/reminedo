//
//  SharedConstants.swift
//  reminedo
//
//  앱·확장(공유/위젯) 공통 상수의 단일 출처. App Group id·URL scheme·알림 식별자 prefix·
//  UserDefaults 키를 한 곳에 모아 타깃 간 문자열 불일치를 원천 차단한다(§7, §4.5).
//

import Foundation

nonisolated enum SharedConstants {
    /// SwiftData 스토어·공유 페이로드가 사는 App Group(§7, Phase 0 확정).
    static let appGroupID = "group.com.geniusjun.reminedo"

    /// 딥링크 scheme(`reminedo://`). 위젯 edit / 공유 add 진입(§4.11, §2.3).
    static let urlScheme = "reminedo"

    /// 로컬 알림 식별자 스킴(§4.5). prefix 매칭으로 reschedule 시 일괄 취소한다.
    enum NotificationID {
        static func base(_ id: UUID) -> String { id.uuidString }
        static func weekly(_ id: UUID, weekday: Int) -> String { "\(id.uuidString)#wd\(weekday)" }
        static func snooze(_ id: UUID) -> String { "\(id.uuidString)#snooze" }
    }

    enum NotificationCategory {
        static let reminder = "REMINDER_CATEGORY"
    }

    enum NotificationAction {
        static let open = "OPEN"
        static let dismiss = "DISMISS"
        static let snooze = "SNOOZE"   // 핸들러는 Phase 1b에서 추가
    }

    enum UserDefaultsKey {
        static let hasOnboarded = "hasOnboarded"
        static let hasSeenLockHint = "hasSeenLockHint"
        static let hasSeenImageSwipeHint = "hasSeenImageSwipeHint"   // 이미지 뷰어 "쓸어내려 닫기" 1회 안내(§3.5)
        static let pendingImageDeletes = "pendingImageDeletes"
        static let sharedPayload = "sharedPayload"   // Share Extension이 기록하는 공유 페이로드(App Group, §4.10)
        static let defaultSound = "defaultSound"   // 신규 알람 기본 사운드(설정 §3.6). SoundType.rawValue 저장.
    }

    /// 백그라운드 복구용 BGAppRefreshTask 식별자(§9 Phase 5 후보). Info.plist
    /// `BGTaskSchedulerPermittedIdentifiers`에 동일 값을 등록해야 한다.
    static let backgroundRefreshTaskID = "com.geniusjun.reminedo.refresh"
}
