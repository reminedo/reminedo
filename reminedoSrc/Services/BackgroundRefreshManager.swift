//
//  BackgroundRefreshManager.swift
//  reminedo
//
//  BGAppRefreshTask 백그라운드 복구(§9 Phase 5 "후보"/best-effort). 앱이 백그라운드에서
//  깨어날 때 실패 예약 재시도 + 활성 알람 전체 재예약을 수행한다. 이는 보조 메커니즘이며,
//  주 복구 경로는 scenePhase==.active(앱 진입) 처리다(§4.12, Phase 1b). 앱을 한 번도 안 열고
//  시스템 깨우기도 없으면 복구되지 않는다(MVP 수용 한계, §1).
//
//  Info.plist 요구: UIBackgroundModes=[fetch], BGTaskSchedulerPermittedIdentifiers=[식별자].
//  register()는 앱 시작(앱 finishLaunching 이전, ReminedoApp.init)에서 1회 호출해야 한다.
//

import Foundation
import BackgroundTasks

enum BackgroundRefreshManager {
    private static let identifier = SharedConstants.backgroundRefreshTaskID

    /// BGTask 핸들러 등록(앱 시작 1회). notificationService를 캡처해 깨어날 때 복구를 위임한다.
    static func register(notificationService: NotificationService) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            // 다음 깨우기를 다시 예약(주기적 복구 시도).
            schedule()
            handle(task: task, notificationService: notificationService)
        }
    }

    /// 다음 BGAppRefreshTask 예약(best-effort). 시스템이 시점을 결정한다.
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)   // 최소 15분 후
        try? BGTaskScheduler.shared.submit(request)
    }

    /// 깨어났을 때: 실패 예약 재시도 + 활성 알람 전체 재예약. NotificationService는 @MainActor가
    /// 아니라 동기 트리거 메서드를 그대로 호출할 수 있다(내부에서 Task로 async 작업을 돌린다).
    private static func handle(task: BGTask, notificationService: NotificationService) {
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }
        notificationService.retryFailedScheduling()
        notificationService.rescheduleAllEnabled()
        WatchdogScheduler.reschedule()   // 이슈9: 백그라운드 보조 틱 — watchdog도 계속 미루기.
        // 내부 Task가 비동기로 진행되므로 즉시 완료 신호(best-effort, 복구는 fire-and-forget).
        task.setTaskCompleted(success: true)
    }
}
