//
//  NotificationService.swift
//  reminedo
//
//  로컬 알림 예약의 단일 척추(§4.2). add/edit/on-off/snooze가 전부 reschedule(_:)/scheduleSnooze(_:)
//  하나로 funnel하고, 식별자 스킴·트리거 구성·취소·64한도·재시도 로직은 여기에만 둔다.
//  앱 전역에 하나만 존재(ReminedoApp이 .environment로 주입) — delegate가 스누즈를 이 인스턴스로
//  걸고, 권한 상태를 화면들이 관찰한다. 공유 SwiftData 컨텍스트를 직접 들어 알람을 조회/영속한다.
//
//  Phase 1b: weekly 요일 전개 · 64한도(임계 60) all-or-nothing · 자동 재시도 · 스누즈 · 권한 상태.
//

import Foundation
import SwiftData
import UserNotifications

@Observable
final class NotificationService {
    private let center = UNUserNotificationCenter.current()

    /// 뷰가 @Environment(\.modelContext)로 받는 것과 동일한 공유 컨텍스트(§refactor).
    /// 스누즈 조회·재예약 일괄·재시도와 schedulingFailed 영속에 쓴다.
    private let modelContext = SharedModelContainer.shared.mainContext

    /// 64한도 보수 임계치(§4.12). pending + 신규 > 60이면 신규를 넣지 않는다.
    private let capacityThreshold = 60

    /// 현재 알림 권한 상태(§3.2/§4.12). scenePhase==.active마다 refreshAuthorization()로 갱신.
    /// 화면들이 관찰해 배너·셀 토글 활성 여부를 결정한다(거짓신호 방지, §13.1).
    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    /// 권한이 알람을 울릴 수 있는 상태인지(authorized/provisional/ephemeral).
    var isAuthorized: Bool {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }

    // MARK: - 권한

    /// 알림 권한 요청(alert/sound/badge). 정식 온보딩(§3.7)에서 [알림 허용] 시 호출한다.
    func requestAuthorization() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        await refreshAuthorization()
    }

    /// 모든 pending 로컬 알림 일괄 취소(데이터 삭제용, §3.6). 레코드 삭제는 호출부가 담당한다.
    func cancelAll() {
        center.removeAllPendingNotificationRequests()
    }

    /// scenePhase==.active마다 권한 재조회(§4.12). 거부→허용 전이를 감지하면 전체 재예약.
    func refreshAuthorization() async {
        let settings = await center.notificationSettings()
        let wasAuthorized = isAuthorized
        authorizationStatus = settings.authorizationStatus
        if !wasAuthorized && isAuthorized {
            rescheduleAllEnabled()
        }
    }

    // MARK: - 재예약 단일 경로

    /// 재예약 단일 경로(§4.2): ① 기존 pending 일괄 취소 ② 활성이면 현재 상태로 예약.
    /// best-effort — throw하지 않고 reminder.schedulingFailed에만 기록한다(§4.4).
    /// 64한도 검사를 위해 내부는 async(pending 조회). 호출부는 동기 호출로 유지하고 Task로 위임한다.
    func reschedule(_ reminder: Reminder) {
        let id = reminder.id
        Task {
            await rescheduleAsync(reminderID: id)
            // 단일 재예약(add/edit/on-off/Undo) 직후 위젯 reload(§14.2 ①③).
            WidgetReloader.reload()
        }
    }

    /// id로 reminder를 다시 조회해(컨텍스트 일관) 재예약. 삭제됐으면 취소만 남는다.
    private func rescheduleAsync(reminderID: UUID) async {
        await cancelAsync(idPrefix: reminderID.uuidString)
        SnoozeStateStore.clear(reminderID: reminderID)

        guard let reminder = fetch(id: reminderID) else { return }

        guard reminder.isEnabled else {
            setSchedulingFailed(reminder, false)
            return
        }

        switch reminder.repeatRule {
        case .none:
            await scheduleSingle(reminder, trigger: nextOccurrenceTrigger(for: reminder))
        case .daily:
            await scheduleSingle(reminder, trigger: dailyTrigger(for: reminder))
        case .weekly:
            await scheduleWeekly(reminder)
        }
    }

    /// none/daily: 1건 예약. 64한도 검사 후 over면 schedulingFailed.
    private func scheduleSingle(_ reminder: Reminder, trigger: UNNotificationTrigger) async {
        let pending = await pendingCount()
        guard pending + 1 <= capacityThreshold else {
            setSchedulingFailed(reminder, true)
            return
        }
        let request = UNNotificationRequest(
            identifier: SharedConstants.NotificationID.base(reminder.id),
            content: content(for: reminder, isSnooze: false),
            trigger: trigger
        )
        let ok = await add(request)
        setSchedulingFailed(reminder, !ok)
    }

    /// weekly: 선택 요일마다 1건씩 반복 예약(§4.5). 64한도는 all-or-nothing(§4.12) —
    /// 요일 칸 전부가 임계 안에 안 들어가면 NONE을 걸고 schedulingFailed 유지.
    private func scheduleWeekly(_ reminder: Reminder) async {
        let iosWeekdays = Weekday.iosWeekdays(fromMask: reminder.repeatWeekdaysMask)
        guard !iosWeekdays.isEmpty else {
            // ≥1 요일 필수(§3.4). 선택 없으면 예약 불가 — 실패로 표시.
            setSchedulingFailed(reminder, true)
            return
        }
        let pending = await pendingCount()
        guard pending + iosWeekdays.count <= capacityThreshold else {
            setSchedulingFailed(reminder, true)   // all-or-nothing
            return
        }
        let comps = Calendar.current.dateComponents([.hour, .minute], from: reminder.scheduledAt)
        var allOK = true
        for iosWeekday in iosWeekdays {
            var dateMatching = DateComponents()
            dateMatching.hour = comps.hour
            dateMatching.minute = comps.minute
            dateMatching.weekday = iosWeekday
            let trigger = UNCalendarNotificationTrigger(dateMatching: dateMatching, repeats: true)
            let request = UNNotificationRequest(
                identifier: SharedConstants.NotificationID.weekly(reminder.id, weekday: iosWeekday),
                content: content(for: reminder, isSnooze: false),
                trigger: trigger
            )
            let ok = await add(request)
            allOK = allOK && ok
        }
        setSchedulingFailed(reminder, !allOK)
    }

    // MARK: - 취소

    /// Off/삭제용 취소 헬퍼(§4.4/§4.3). 식별자 prefix로 base·#wd·#snooze를 한 번에 제거한다.
    /// 수정 시 진행 중 스누즈(#snooze)도 prefix 매칭으로 함께 취소된다(§4.2 의도).
    func cancel(_ reminder: Reminder) {
        let prefix = reminder.id.uuidString
        SnoozeStateStore.clear(reminderID: reminder.id)
        WidgetReloader.reload()
        Task { await cancelAsync(idPrefix: prefix) }
    }

    private func cancelAsync(idPrefix: String) async {
        let requests = await center.pendingNotificationRequests()
        let ids = requests.map(\.identifier).filter { $0.hasPrefix(idPrefix) }
        guard !ids.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    // MARK: - 64한도 자동 재시도(§4.12)

    /// pending 감소 mutation(삭제/Off) 후 + scenePhase==.active 시 호출.
    /// schedulingFailed=true & 활성 알람을 다음 발생 시각이 가까운 순으로 재시도(용량 허용 한).
    func retryFailedScheduling() {
        Task { await retryFailedSchedulingAsync() }
    }

    private func retryFailedSchedulingAsync() async {
        let descriptor = FetchDescriptor<Reminder>(
            predicate: #Predicate { $0.schedulingFailed && $0.isEnabled }
        )
        guard let failed = try? modelContext.fetch(descriptor), !failed.isEmpty else { return }
        // 재시도 우선순위만 nextFireDate 기준(목록 정렬과 별개, §4.12).
        let ordered = failed.sorted { NextFireDate.next(for: $0) < NextFireDate.next(for: $1) }
        for reminder in ordered {
            await rescheduleAsync(reminderID: reminder.id)
        }
        // 64한도 자동 재시도 결과 반영 후 1회 reload(§14.2 ④).
        WidgetReloader.reload()
    }

    /// 발사된 일회성 알람 정리(scenePhase==.active). 앱이 죽어 UN만 발사된 경우 isEnabled가
    /// 안 꺼져 목록에 "켜짐"으로 남는 발산을 보정한다(오디오 fireAlarm 경로와 수렴). 시계 앱처럼
    /// 일회성은 1회 후 꺼진다. 가드: .none·미실패·예정시각 경과·pending base 없음 → 발사된 것.
    func disableFiredOneShots() {
        Task {
            let pending = await center.pendingNotificationRequests()
            let pendingIDs = Set(pending.map(\.identifier))
            let descriptor = FetchDescriptor<Reminder>(predicate: #Predicate { $0.isEnabled })
            guard let reminders = try? modelContext.fetch(descriptor) else { return }
            let now = Date()
            var changed = false
            for reminder in reminders
            where reminder.repeatRule == .none
                && !reminder.schedulingFailed
                && reminder.scheduledAt < now
                && !pendingIDs.contains(SharedConstants.NotificationID.base(reminder.id))
                // 이슈5(a): 활성 스누즈(#snooze)가 pending이면 발사된 게 아니라 스누즈 대기 중 —
                // disable하지 않는다(홈에서 꺼짐 표시 방지).
                && !pendingIDs.contains(SharedConstants.NotificationID.snooze(reminder.id)) {
                reminder.isEnabled = false
                changed = true
            }
            if changed {
                try? modelContext.save()
                WidgetReloader.reload()
            }
        }
    }

    /// 권한 새로 켜졌을 때 활성 알람 전체 재예약(§4.12).
    func rescheduleAllEnabled() {
        Task { await rescheduleAllEnabledAsync() }
    }

    private func rescheduleAllEnabledAsync() async {
        let descriptor = FetchDescriptor<Reminder>(predicate: #Predicate { $0.isEnabled })
        guard let reminders = try? modelContext.fetch(descriptor) else { return }
        let ordered = reminders.sorted { NextFireDate.next(for: $0) < NextFireDate.next(for: $1) }
        for reminder in ordered {
            await rescheduleAsync(reminderID: reminder.id)
        }
        // 권한 재활성 전체 재예약 완료 후 1회(배치) reload(§14.2 ⑤).
        WidgetReloader.reload()
    }

    // MARK: - 스누즈(§4.6)

    /// SNOOZE 액션 처리. reminderId로 reminder 조회 → snoozeEnabled면 분 단위 1회 재예약.
    /// 반복 원본은 미변경(§4.6). add 완료 후 completion을 호출한다.
    func scheduleSnooze(reminderId: UUID, completion: @escaping () -> Void) {
        Task {
            defer { completion() }
            guard let reminder = fetch(id: reminderId), reminder.snoozeEnabled else { return }
            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: TimeInterval(reminder.snoozeMinutes * 60),
                repeats: false
            )
            let fireDate = Date().addingTimeInterval(TimeInterval(reminder.snoozeMinutes * 60))
            let request = UNNotificationRequest(
                identifier: SharedConstants.NotificationID.snooze(reminderId),
                content: content(for: reminder, isSnooze: true),
                trigger: trigger
            )
            if await add(request) {
                SnoozeStateStore.set(reminderID: reminderId, until: fireDate)
                WidgetReloader.reload()
            }
        }
    }

    // MARK: - 내부 구성

    /// 콘텐츠(§4.5): 제목만 노출, body 비움, userInfo·thread·category 구성.
    private func content(for reminder: Reminder, isSnooze: Bool) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = ""
        // 앱 생존 시 keep-alive가 같은 alarm.caf를 풀볼륨 재생하므로 UN 사운드도 동일 파일로 통일한다
        // (겹쳐도 같은 소리). 앱 사망 시엔 이 알림이 알람음으로 백스톱한다(§오디오 알람). silent는 무음.
        content.sound = (reminder.soundType == .defaultSound)
            ? UNNotificationSound(named: UNNotificationSoundName("alarm.caf"))
            : nil
        content.userInfo = [
            "reminderId": reminder.id.uuidString,
            "isSnooze": isSnooze,
        ]
        content.categoryIdentifier = SharedConstants.NotificationCategory.reminder
        content.threadIdentifier = threadIdentifier(for: reminder)
        // Time Sensitive(§4.5/§1): 무음·집중 모드를 (허용된 경우) 뚫고 울리게 한다.
        // 프로덕션: Time Sensitive 엔타이틀먼트(com.apple.developer.usernotifications.time-sensitive) 필요.
        return content
    }

    /// 동시각 그룹핑용 thread = "HHmm"(§4.5).
    private func threadIdentifier(for reminder: Reminder) -> String {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: reminder.scheduledAt)
        return String(format: "%02d%02d", comps.hour ?? 0, comps.minute ?? 0)
    }

    /// none: 다음 발생 시각의 날짜 구성으로 1회성(§4.1/§4.5).
    private func nextOccurrenceTrigger(for reminder: Reminder) -> UNCalendarNotificationTrigger {
        let fireDate = NextFireDate.next(for: reminder)
        let comps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: fireDate
        )
        return UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
    }

    /// daily: 시·분 반복(§4.5).
    private func dailyTrigger(for reminder: Reminder) -> UNCalendarNotificationTrigger {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: reminder.scheduledAt)
        return UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
    }

    // MARK: - 저수준 헬퍼

    private func pendingCount() async -> Int {
        await center.pendingNotificationRequests().count
    }

    /// center.add를 async/throws-free로 감싸 성공 여부 Bool로 반환.
    private func add(_ request: UNNotificationRequest) async -> Bool {
        do {
            try await center.add(request)
            return true
        } catch {
            return false   // best-effort: 호출부가 schedulingFailed에 반영(§4.4).
        }
    }

    private func fetch(id: UUID) -> Reminder? {
        let descriptor = FetchDescriptor<Reminder>(predicate: #Predicate { $0.id == id })
        return try? modelContext.fetch(descriptor).first
    }

    /// schedulingFailed 변경 + 영속(§4.4). 값이 같으면 저장 생략.
    private func setSchedulingFailed(_ reminder: Reminder, _ failed: Bool) {
        guard reminder.schedulingFailed != failed else { return }
        reminder.schedulingFailed = failed
        try? modelContext.save()
    }
}
