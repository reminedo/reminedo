//
//  NotificationCategories.swift
//  reminedo
//
//  로컬 알림 카테고리/액션 등록(앱 시작 1회, §4.5). 디자인(lock.png) 순서대로
//  [SNOOZE, DISMISS, OPEN]. 이 액션들은 네이티브 길게-누르기/잠금화면용 보조 경로다 —
//  주 경로는 알림 본문 탭 → 인앱 lock 화면(LockScreenActionView). 네이티브 스누즈 라벨은
//  정적("다시 알림"); 동적 "N분 후"는 인앱 화면 버튼이 담당한다.
//

import Foundation
import UserNotifications

enum NotificationCategories {
    static func register() {
        // 정적 라벨 "다시 알림"(§4.5/§4.6). 시간은 reminder.snoozeMinutes로 결정.
        let snooze = UNNotificationAction(
            identifier: SharedConstants.NotificationAction.snooze,
            title: "다시 알림",
            options: []
        )
        let dismiss = UNNotificationAction(
            identifier: SharedConstants.NotificationAction.dismiss,
            title: "알림 닫기",
            options: [.destructive]
        )
        let open = UNNotificationAction(
            identifier: SharedConstants.NotificationAction.open,
            title: "지금 보기",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: SharedConstants.NotificationCategory.reminder,
            actions: [snooze, dismiss, open],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }
}
