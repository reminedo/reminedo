//
//  ActionRouterView.swift
//  reminedo
//
//  알림 진입/딥링크 라우팅 소비기(§4.11). scenePhase==.active에서 AppState.pendingRoute를
//  1회 소비해 fullScreenCover를 띄운다. 삭제된 reminder면 무시(consume-once).
//
//  진입 분기(§3.5):
//   · .act(id)        알림 본문 탭 → 먼저 인앱 lock 화면(다시알림/닫기/지금보기) → "지금 보기" 시 콘텐츠.
//   · .actContent(id) 네이티브 "지금 보기" 액션 → lock 화면 생략, 콘텐츠로 직행.
//  콘텐츠: memo→MemoActionView, image→ImageActionView, url→외부 열기(인앱 화면 없음, §4.8).
//

import SwiftUI
import SwiftData

struct ActionRouterView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Environment(NotificationService.self) private var notificationService
    @Environment(SnoozeActivityController.self) private var snoozeActivity
    @Environment(AlarmAudioService.self) private var alarmAudio

    private enum ActionPhase { case lock, content }

    @State private var actingReminder: Reminder?
    @State private var phase: ActionPhase = .lock

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active { consumeRoute() }
            }
            .onChange(of: appState.pendingRoute) { _, _ in
                if scenePhase == .active { consumeRoute() }
            }
            .onAppear { consumeRoute() }
            .fullScreenCover(item: $actingReminder) { reminder in
                coverContent(for: reminder)
            }
    }

    @ViewBuilder
    private func coverContent(for reminder: Reminder) -> some View {
        switch phase {
        case .lock:
            LockScreenActionView(
                title: reminder.title,
                scheduledAt: reminder.scheduledAt,
                snoozeEnabled: reminder.snoozeEnabled,
                snoozeMinutes: reminder.snoozeMinutes,
                onSnooze: { snooze(reminder) },
                onDismiss: { alarmAudio.stopRinging(); actingReminder = nil },
                onOpen: { alarmAudio.stopRinging(); withAnimation { phase = .content } }
            )
        case .content:
            contentScreen(for: reminder)
        }
    }

    @ViewBuilder
    private func contentScreen(for reminder: Reminder) -> some View {
        switch reminder.contentType {
        case .memo:
            MemoActionView(
                title: reminder.title,
                memo: reminder.memo ?? "",
                onClose: { actingReminder = nil }
            )
        case .url:
            // URL 행동(§3.5/§4.8): 인앱 화면 없이 곧장 외부로 연다(처리 앱 우선, Safari 폴백).
            Color.clear.onAppear {
                URLActionHandler.open(reminder.targetURL)
                actingReminder = nil
            }
        case .image:
            // 이미지 행동(§3.5): 순수 Black 풀스크린 뷰어(핀치/더블탭 확대, 쓸어내려 닫기).
            ImageActionView(
                fileName: reminder.imageFileName,
                onClose: { actingReminder = nil }
            )
        }
    }

    /// lock 화면 "다시 알림": 카운트다운 Live Activity 시작 + 스누즈 알림 재예약 + 오디오 스누즈 등록 + 닫기.
    private func snooze(_ reminder: Reminder) {
        snoozeActivity.start(
            reminderID: reminder.id,
            title: reminder.title,
            symbolName: reminder.contentType.symbolName,
            minutes: reminder.snoozeMinutes
        )
        notificationService.scheduleSnooze(reminderId: reminder.id, completion: {})
        alarmAudio.snooze(reminderID: reminder.id, minutes: reminder.snoozeMinutes)
        actingReminder = nil
    }

    /// .act/.actContent를 1회 소비한다. .edit(위젯 딥링크)는 ReminderListScreen이 소비(consume-once 분리).
    private func consumeRoute() {
        switch appState.pendingRoute {
        case .act(let id):
            guard let reminder = fetchReminder(id: id) else { appState.pendingRoute = nil; return }
            phase = .lock
            actingReminder = reminder
            appState.pendingRoute = nil
        case .actContent(let id):
            guard let reminder = fetchReminder(id: id) else { appState.pendingRoute = nil; return }
            phase = .content
            actingReminder = reminder
            appState.pendingRoute = nil
        default:
            return   // .edit / nil은 건드리지 않음
        }
    }

    private func fetchReminder(id: UUID) -> Reminder? {
        let descriptor = FetchDescriptor<Reminder>(predicate: #Predicate { $0.id == id })
        return try? modelContext.fetch(descriptor).first
    }
}
