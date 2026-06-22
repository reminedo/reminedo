//
//  OnboardingView.swift
//  reminedo
//
//  온보딩(§3.7). hasOnboarded==false일 때 1회만 fullScreenCover로 노출된다(RootTabView가 게이팅).
//  앱 아이콘 + 소개 + [알림 허용]/[건너뛰기]. 둘 중 무엇으로든 종료하면 hasOnboarded=true로
//  플래그를 세팅하고 닫힌다(권한 거부해도 진행, §3.7). 권한 요청은 여기서만 일어난다(§3.7) —
//  Phase 1a의 임시 .task 요청은 ReminderListScreen에서 제거되었다(이중 프롬프트 방지).
//

import SwiftUI

struct OnboardingView: View {
    @Environment(NotificationService.self) private var notificationService

    /// 완료 시 RootTabView가 hasOnboarded 플래그를 세팅·커버를 닫는다.
    let onFinish: () -> Void

    @State private var requesting = false

    var body: some View {
        ZStack {
            Tokens.Palette.background.ignoresSafeArea()
            VStack(spacing: 32) {
                Spacer()

                appIcon

                VStack(spacing: 12) {
                    Text(Strings.Onboarding.title)
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(Tokens.Palette.textPrimary)
                    Text(Strings.Onboarding.intro)
                        .font(.body)
                        .foregroundStyle(Tokens.Palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Tokens.Spacing.gutter)
                }

                Spacer()

                VStack(spacing: Tokens.Spacing.row) {
                    Button(action: allow) {
                        Text(Strings.Onboarding.allow)
                            .font(.headline)
                            .foregroundStyle(Tokens.Palette.background)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Tokens.Spacing.row)
                            .background(Tokens.Palette.accent)
                            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous))
                    }
                    .disabled(requesting)

                    Button(action: onFinish) {
                        Text(Strings.Onboarding.skip)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Tokens.Palette.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Tokens.Spacing.row)
                    }
                    .disabled(requesting)
                }
                .padding(.horizontal, Tokens.Spacing.gutter)
                .padding(.bottom, 24)
            }
        }
    }

    /// 앱 로고(실제 아이콘 이미지 AppLogo). 라운드 처리로 앱 아이콘 룩과 일치.
    private var appIcon: some View {
        Image("AppLogo")
            .resizable()
            .scaledToFill()
            .frame(width: 110, height: 110)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    /// [알림 허용](§3.7): 권한 요청 후 권한 결과와 무관하게 진행한다.
    private func allow() {
        requesting = true
        Task {
            await notificationService.requestAuthorization()
            requesting = false
            onFinish()
        }
    }
}

#Preview {
    OnboardingView(onFinish: {})
        .environment(NotificationService())
        .preferredColorScheme(.dark)
}
