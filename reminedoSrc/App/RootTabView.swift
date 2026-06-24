//
//  RootTabView.swift
//  reminedo
//
//  하단 탭 셸. PRD §3.1대로 표준 SwiftUI TabView를 쓰고(커스텀 바 금지 — safe-area inset·
//  모델 덮기를 공짜로 얻음), 컴포넌트화 대상은 탭 "정의"(라벨·심볼·틴트)뿐이다.
//  Phase 1a에서 각 탭 내용(알림 목록/설정)을 채운다.
//
//  이슈10: 포그라운드 알람 발화 시 시스템 기본 알림과 함께 on_notice.png 커스텀 배너를 최상위
//  오버레이로 띄운다(appState.ringingReminderID 관찰). 잠금/비포그라운드에선 willPresent가 안 불려
//  이 배너는 뜨지 않는다(시스템 알림만 → 탭 시 이슈8 lock 화면).
//

import SwiftUI
import SwiftData

enum AppTab: Hashable, CaseIterable {
    case reminders
    case settings

    var label: String {
        switch self {
        case .reminders: Strings.Tab.reminders
        case .settings: Strings.Tab.settings
        }
    }

    var systemImage: String {
        switch self {
        case .reminders: Tokens.Symbols.tabReminders
        case .settings: Tokens.Symbols.tabSettings
        }
    }
}

struct RootTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Environment(NotificationService.self) private var notificationService
    @Environment(SnoozeActivityController.self) private var snoozeActivity
    @Environment(AlarmAudioService.self) private var alarmAudio

    @State private var selection: AppTab = .reminders

    /// 온보딩 게이트(§3.7). hasOnboarded==false면 탭 위에 fullScreenCover로 1회 노출한다.
    @AppStorage(SharedConstants.UserDefaultsKey.hasOnboarded) private var hasOnboarded = false

    var body: some View {
        ZStack {
            TabView(selection: $selection) {
                ForEach(AppTab.allCases, id: \.self) { tab in
                    content(for: tab)
                        .tabItem { Label(tab.label, systemImage: tab.systemImage) }
                        .tag(tab)
                }
            }
            .tint(Tokens.Palette.accent)

            // 이슈10: 포그라운드 알람 발화 → on_notice.png 커스텀 배너(상단 오버레이).
            if let ringingID = appState.ringingReminderID,
               let reminder = fetchReminder(id: ringingID) {
                VStack {
                    RingingAlarmBanner(
                        title: reminder.title,
                        onSnooze: { handleSnooze(reminder) },
                        onCancel: { handleCancel() },
                        onOpen: { handleOpen(reminder) }
                    )
                    .padding(.top, 8)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        // 온보딩(§3.7): 최초 1회만. 종료 시 hasOnboarded=true로 다시 노출되지 않는다.
        .fullScreenCover(isPresented: .constant(!hasOnboarded)) {
            OnboardingView(onFinish: { hasOnboarded = true })
        }
        .animation(.easeInOut(duration: 0.25), value: appState.ringingReminderID)
        // 이슈10: 알람이 auto-stop 등으로 울림을 멈추면 커스텀 배너도 함께 닫는다(잔류 방지).
        .onChange(of: alarmAudio.isRinging) { _, ringing in
            if !ringing { appState.ringingReminderID = nil }
        }
        .onChange(of: appState.pendingAddRequested) { _, requested in
            if requested { selection = .reminders }
        }
        .onAppear {
            if appState.pendingAddRequested { selection = .reminders }
        }
    }

    @ViewBuilder
    private func content(for tab: AppTab) -> some View {
        switch tab {
        case .reminders: ReminderListScreen()       // Phase 1a 실제 화면
        case .settings: SettingsScreen()             // 설정 탭(§3.6)
        }
    }

    // MARK: - 커스텀 배너 액션(이슈10) — 기존 스누즈/종료/콘텐츠 경로 재사용.

    /// 다시 알림: 스누즈 LA 시작 + UN 재예약 + 오디오 스누즈 + 배너 닫기.
    private func handleSnooze(_ reminder: Reminder) {
        snoozeActivity.start(
            reminderID: reminder.id,
            title: reminder.title,
            symbolName: reminder.contentType.symbolName,
            minutes: reminder.snoozeMinutes
        )
        notificationService.scheduleSnooze(reminderId: reminder.id, completion: {})
        alarmAudio.snooze(reminderID: reminder.id, minutes: reminder.snoozeMinutes)
        appState.ringingReminderID = nil
    }

    /// 취소: 풀볼륨 정지 + 배너 닫기(이번 회차 종료, 반복 알람은 유지).
    private func handleCancel() {
        alarmAudio.stopRinging()
        appState.ringingReminderID = nil
    }

    /// 지금 보기: 정지 + 배너 닫기 + reminders 탭 전환 후 콘텐츠 직행 라우팅.
    private func handleOpen(_ reminder: Reminder) {
        alarmAudio.stopRinging()
        appState.ringingReminderID = nil
        selection = .reminders   // ActionRouterView가 reminders 탭에 있으므로 탭 전환.
        appState.pendingRoute = .actContent(reminder.id)
    }

    private func fetchReminder(id: UUID) -> Reminder? {
        let descriptor = FetchDescriptor<Reminder>(predicate: #Predicate { $0.id == id })
        return try? modelContext.fetch(descriptor).first
    }
}

#Preview {
    RootTabView()
        .modelContainer(for: Reminder.self, inMemory: true)
        .environment(AppState())
        .environment(NotificationService())
        .environment(DeletionManager())
        .environment(ImageStore())
        .environment(SnoozeActivityController())
        .environment(AlarmAudioService.shared)
        .preferredColorScheme(.dark)
}
