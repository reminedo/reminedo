//
//  RootTabView.swift
//  reminedo
//
//  하단 탭 셸. PRD §3.1대로 표준 SwiftUI TabView를 쓰고(커스텀 바 금지 — safe-area inset·
//  모델 덮기를 공짜로 얻음), 컴포넌트화 대상은 탭 "정의"(라벨·심볼·틴트)뿐이다.
//  Phase 1a에서 각 탭 내용(알림 목록/설정)을 채운다.
//
//  포그라운드 알람 발화 시엔 NotificationDelegate.willPresent가 곧장 인앱 lock 화면(.act)으로
//  라우팅한다(커스텀 배너 없음). 백그라운드/잠금에선 시스템 알림만 뜨고, 탭 시 lock 화면으로 간다.
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
    @Environment(AppState.self) private var appState

    @State private var selection: AppTab = .reminders

    /// 온보딩 게이트(§3.7). hasOnboarded==false면 탭 위에 fullScreenCover로 1회 노출한다.
    @AppStorage(SharedConstants.UserDefaultsKey.hasOnboarded) private var hasOnboarded = false

    var body: some View {
        TabView(selection: $selection) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                content(for: tab)
                    .tabItem { Label(tab.label, systemImage: tab.systemImage) }
                    .tag(tab)
            }
        }
        .tint(Tokens.Palette.accent)
        // 온보딩(§3.7): 최초 1회만. 종료 시 hasOnboarded=true로 다시 노출되지 않는다.
        .fullScreenCover(isPresented: .constant(!hasOnboarded)) {
            OnboardingView(onFinish: { hasOnboarded = true })
        }
        .onChange(of: appState.pendingAddRequested) { _, requested in
            if requested { selection = .reminders }
        }
        // 알림/Live Activity/위젯 라우트(.act/.actContent/.edit)는 모두 reminders 탭의 화면
        // (ActionRouterView·편집 시트)이 소비한다. 설정 탭에 있어도 lock 화면/시트가 확실히 뜨도록
        // 라우트가 생기면 reminders 탭으로 전환한다(포그라운드 알람이 설정 탭에서 울리는 경우 대비).
        .onChange(of: appState.pendingRoute) { _, route in
            if route != nil { selection = .reminders }
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
