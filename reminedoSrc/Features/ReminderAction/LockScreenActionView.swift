//
//  LockScreenActionView.swift
//  reminedo
//
//  iOS 기본 알림을 "탭"해 앱에 진입했을 때 뜨는 인앱 액션 화면(lock.png 재현, §3.5).
//  잠금화면이 아니라 앱 내부 화면이므로 자물쇠 아이콘은 없다. 날짜·큰 시각·녹색 벨·"리마인두"·
//  제목을 보여주고, 하단 3버튼(다시 알림 / 알림 닫기 / 지금 보기)으로 분기한다.
//  side-effect(스누즈 예약·Live Activity·콘텐츠 열기)는 모두 onXXX로 호출부에 위임한다.
//

import SwiftUI
struct LockScreenActionView: View {
    let title: String
    let scheduledAt: Date
    let snoozeEnabled: Bool
    let snoozeMinutes: Int

    var onSnooze: () -> Void
    var onDismiss: () -> Void
    var onOpen: () -> Void

    var body: some View {
        ZStack {
            Tokens.Palette.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // 상단: 날짜 + 큰 시각(자물쇠 없음).
                VStack(spacing: 6) {
                    Text(DateFormatting.lockDateText())
                        .font(.headline)
                        .foregroundStyle(Tokens.Palette.textSecondary)
                    Text(DateFormatting.lockClockText(scheduledAt))
                        .font(.system(size: 76, weight: .light))
                        .foregroundStyle(Tokens.Palette.textPrimary)
                }
                .padding(.top, 48)

                Spacer(minLength: 24)

                // 중앙: 녹색 벨 원형 + "리마인두" + 제목.
                VStack(spacing: 14) {
                    Image(systemName: Tokens.Symbols.tabReminders)
                        .font(.system(size: 34))
                        .foregroundStyle(Tokens.Palette.accent)
                        .frame(width: 84, height: 84)
                        .background(Tokens.Palette.accent.opacity(0.15), in: Circle())
                        .overlay(Circle().strokeBorder(Tokens.Palette.accent, lineWidth: 2))

                    Text(Strings.Action.brand)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Tokens.Palette.accent)

                    Text(title)
                        .font(.title.weight(.bold))
                        .foregroundStyle(Tokens.Palette.textPrimary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(.horizontal, Tokens.Spacing.gutter)
                }

                Spacer(minLength: 24)

                // 하단: 액션 버튼.
                VStack(spacing: Tokens.Spacing.row) {
                    if snoozeEnabled {
                        ActionBigButton(
                            title: Strings.Action.snoozeButton(snoozeMinutes),
                            symbolName: "clock.arrow.circlepath",
                            tint: Tokens.Palette.accent,
                            action: onSnooze
                        )
                    }
                    ActionBigButton(
                        title: Strings.Action.dismissButton,
                        symbolName: "xmark",
                        tint: Tokens.Palette.destructive,
                        action: onDismiss
                    )
                    ActionBigButton(
                        title: Strings.Action.openButton,
                        symbolName: "play.fill",
                        tint: Tokens.Palette.accent,
                        action: onOpen
                    )
                }
                .padding(.horizontal, Tokens.Spacing.gutter)
                .padding(.bottom, 32)
            }
        }
    }
}

#Preview {
    LockScreenActionView(
        title: "유튜브 운동 영상",
        scheduledAt: Date(),
        snoozeEnabled: true,
        snoozeMinutes: 5,
        onSnooze: {}, onDismiss: {}, onOpen: {}
    )
    .preferredColorScheme(.dark)
}
