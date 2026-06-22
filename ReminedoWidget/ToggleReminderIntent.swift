//
//  ToggleReminderIntent.swift
//  ReminedoWidget
//
//  Phase 6b 인터랙티브 토글 스켈레톤(§14.6b). 현재는 6a(읽기 전용) 단계이므로 위젯 토글은
//  비인터랙티브 표시(DisplayToggle)이고 이 Intent는 어디에도 연결되어 있지 않다.
//
//  6b 구현 시(차기): 이 Intent를 앱+위젯 양 타깃 멤버십 + ForegroundContinuableIntent로 두어
//  **앱 프로세스에서 실행**한다 → isEnabled 토글 → 기존 NotificationService.reschedule(reminder)
//  단일 경로 → save() → WidgetReloader.reload(). 재예약 실패(권한 꺼짐/64한도/백그라운드 깨우기
//  실패) 시 변경 미적용 + 셀 경고로 거짓신호를 차단한다(§14.6 채택 금지 ⓐⓑ 회피).
//
//  주의: 위젯 익스텐션이 직접 UNUserNotificationCenter로 재예약하거나(샌드박스 제약),
//  토글만 바꾸고 재예약을 미루는 방식은 거짓신호이므로 채택 금지(§14.6).
//

import AppIntents
import Foundation

struct ToggleReminderIntent: AppIntent {
    static var title: LocalizedStringResource = "알람 켜고 끄기"

    @Parameter(title: "알람 ID")
    var reminderID: String

    init() {}

    init(reminderID: String) {
        self.reminderID = reminderID
    }

    func perform() async throws -> some IntentResult {
        // Phase 6b: 앱 프로세스에서 isEnabled 토글 + reschedule + save + reload 수행.
        // 6a 단계에선 미연결(no-op) — 위젯 토글은 표시 전용이고 탭은 편집 시트 딥링크로 처리한다.
        return .result()
    }
}
