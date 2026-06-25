//
//  WatchdogScheduler.swift
//  reminedo
//
//  이슈9: "앱이 꺼져 있으면 알람이 안 울린다"를 감지해 사용자에게 알리는 dead-man's switch.
//
//  원리: iOS는 앱 강제종료를 감지할 수 없지만, "살아있을 때 계속 미루는 알림"을 역이용한다.
//  앱이 살아있는 동안 watchdog 알림 1건을 now+N(≈15~20분) 뒤 발화로 예약해두고, 살아있는 매 틱마다
//  취소+재예약으로 계속 미룬다. 앱이 강제 종료되면 재예약이 멈추고 마지막으로 예약한 watchdog가
//  N분 뒤 발화 → "앱이 꺼져 있어 알람이 안 울릴 수 있어요. 앱을 다시 켜주세요." 경고 도달.
//
//  제약: 오디오 keep-alive/BGTask가 시스템에 의해 일시정지되면 정상일 때도 误발화할 수 있음 →
//  scenePhase==.active 진입 시 도달한(delivered) watchdog를 즉시 제거로 보정.
//

import Foundation
import UserNotifications

enum WatchdogScheduler {
    /// watchdog 발화까지의 간격(분). 앱 종료 후 경고 도착 시간을 좌우한다(작을수록 빠름).
    /// 정상 동작 시엔 절대 발화하지 않는다(계속 미뤄짐). 재예약 주기는 이 값에서 파생(max(60, N×60−60)초),
    /// 발화까지 항상 60초 안전마진 유지. 트리거 최소 60초 제약상 2분이 실용적 최저값.
    static let intervalMinutes: Int = 2

    private static let center = UNUserNotificationCenter.current()

    /// watchdog 알림을 now+N으로 (재)예약. 살아있는 동안 반복 호출해 계속 미룬다.
    static func reschedule() {
        let id = SharedConstants.NotificationID.watchdog
        center.removePendingNotificationRequests(withIdentifiers: [id])

        let content = UNMutableNotificationContent()
        content.title = Strings.Watchdog.title
        content.body = Strings.Watchdog.body
        content.sound = .default
        // 무음/집중을 너무 강하게 뚫진 않음 — active 수준.
        content.interruptionLevel = .active

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: TimeInterval(intervalMinutes * 60),
            repeats: false
        )
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        center.add(request, withCompletionHandler: nil)
    }

    /// 앱 활성화 시 호출 — 도달한(delivered) watchdog 경고를 즉시 제거(이미 앱을 켰으므로).
    static func clearDelivered() {
        let id = SharedConstants.NotificationID.watchdog
        center.removeDeliveredNotifications(withIdentifiers: [id])
    }

    /// watchdog 예약 취소(알람이 하나도 없을 때 등 불필요한 발화 방지).
    static func cancel() {
        let id = SharedConstants.NotificationID.watchdog
        center.removePendingNotificationRequests(withIdentifiers: [id])
    }
}
