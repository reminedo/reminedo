//
//  RootTabView.swift
//  reminedo
//
//  하단 탭 셸. PRD §3.1대로 표준 SwiftUI TabView를 쓰고(커스텀 바 금지 — safe-area inset·
//  모달 덮기를 공짜로 얻음), 컴포넌트화 대상은 탭 "정의"(라벨·심볼·틴트)뿐이다.
//  Phase 1a에서 각 탭 내용(알림 목록/설정)을 채운다.
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
        .preferredColorScheme(.dark)
}
