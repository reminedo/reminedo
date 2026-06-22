//
//  NotificationDelegate.swift
//  reminedo
//
//  로컬 알림 응답을 AppState 라우트로 매핑하는 UN delegate(§4.11). 콜드스타트 탭을 놓치지
//  않도록 UI보다 먼저 앱 시작 시 delegate로 등록한다. 소비는 scenePhase==.active에서 1회.
//

import Foundation
import UserNotifications

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    private unowned let appState: AppState
    private let notificationService: NotificationService
    private let snoozeActivity: SnoozeActivityController
    private let alarmAudio: AlarmAudioService

    init(
        appState: AppState,
        notificationService: NotificationService,
        snoozeActivity: SnoozeActivityController,
        alarmAudio: AlarmAudioService
    ) {
        self.appState = appState
        self.notificationService = notificationService
        self.snoozeActivity = snoozeActivity
        self.alarmAudio = alarmAudio
    }

    /// 본문 탭 → 인앱 lock 화면(.act). 네이티브 "지금 보기" 액션 → 콘텐츠 직행(.actContent, 중복 방지).
    /// SNOOZE → 분 단위 1회 재예약(§4.6). DISMISS는 회차 종료(§2.1).
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let reminderId: UUID? = (userInfo["reminderId"] as? String).flatMap(UUID.init(uuidString:))

        // 스누즈 알림이 울린 뒤의 응답이면 카운트다운 Live Activity는 역할을 다했으므로 종료.
        if (userInfo["isSnooze"] as? Bool) == true, let reminderId {
            snoozeActivity.end(reminderID: reminderId)
        }

        switch response.actionIdentifier {
        case UNNotificationDefaultActionIdentifier:
            // 알림 본문 탭 → lock 화면(다시알림/닫기/지금보기).
            if let reminderId { appState.pendingRoute = .act(reminderId) }
            completionHandler()
        case SharedConstants.NotificationAction.open:
            // 네이티브 길게-누르기 "지금 보기" → lock 화면 생략하고 콘텐츠로 직행.
            if let reminderId { appState.pendingRoute = .actContent(reminderId) }
            completionHandler()
        case SharedConstants.NotificationAction.snooze:
            // add 완료 후 completionHandler 호출(§4.6). reminderId로 분 결정·반복 원본 미변경.
            // 풀볼륨이 울리는 중이면 오디오도 스누즈(현재 알람 기준).
            alarmAudio.snoozeCurrent()
            if let reminderId {
                notificationService.scheduleSnooze(reminderId: reminderId, completion: completionHandler)
            } else {
                completionHandler()
            }
        case SharedConstants.NotificationAction.dismiss:
            // 알림 닫기: 울리는 풀볼륨 소리 정지. 라우팅 없음.
            alarmAudio.stopRinging()
            completionHandler()
        default:
            // 기타: 회차 종료. 라우팅 없음.
            completionHandler()
        }
    }

    /// 포그라운드 표시(§4.5): 배너 + 사운드. 스누즈 알림이 포그라운드에서 울리면
    /// 카운트다운 Live Activity를 종료한다(역할 종료).
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo
        if (userInfo["isSnooze"] as? Bool) == true,
           let reminderId = (userInfo["reminderId"] as? String).flatMap(UUID.init(uuidString:)) {
            snoozeActivity.end(reminderID: reminderId)
        }
        completionHandler([.banner, .sound])
    }
}
