//
//  RingingAlarmBanner.swift
//  reminedo
//
//  포그라운드 알람 발화 시 최상위 오버레이에 뜨는 on_notice.png 스타일 커스텀 알림 배너(이슈10).
//  시스템 기본 알림과 함께 표시된다 — NotificationDelegate.willPresent가 시스템 배너를 유지한 채
//  appState.ringingReminderID를 세팅하면 RootTabView 최상위 오버레이가 이 배너를 그린다.
//  하단 3 원형 버튼(다시 알림/취소/지금 보기)이 기존 스누즈/종료/콘텐츠 로직에 연결된다.
//  잠금화면(비포그라운드)에선 willPresent가 호출되지 않아 이 배너는 뜨지 않는다(시스템 알림만).
//

import SwiftUI

struct RingingAlarmBanner: View {
    let title: String
    var onSnooze: () -> Void
    var onCancel: () -> Void
    var onOpen: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            // 헤더: 초록 알람시계 아이콘 + "리마인두" + 알람 제목(on_notice.png).
            HStack(spacing: 12) {
                Image(systemName: "alarm.fill")
                    .font(.title2)
                    .foregroundStyle(Tokens.Palette.accent)
                    .frame(width: 44, height: 44)
                    .background(Tokens.Palette.accent.opacity(0.15), in: Circle())
                    .overlay(Circle().strokeBorder(Tokens.Palette.accent, lineWidth: 1.5))
                VStack(alignment: .leading, spacing: 2) {
                    Text(Strings.Action.brand)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Tokens.Palette.accent)
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Tokens.Palette.textPrimary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }

            // 하단 3 원형 버튼 행: 다시 알림 / 취소 / 지금 보기(on_notice.png).
            HStack(spacing: 10) {
                circleButton(title: Strings.Action.snoozeShort, symbol: "clock.arrow.circlepath", tint: Tokens.Palette.accent, action: onSnooze)
                circleButton(title: Strings.Action.cancelShort, symbol: "xmark", tint: Tokens.Palette.destructive, action: onCancel)
                circleButton(title: Strings.Action.openButton, symbol: "play.fill", tint: Tokens.Palette.accent, action: onOpen)
            }
        }
        .padding(16)
        .background(Tokens.Palette.card)
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous)
                .strokeBorder(Tokens.Palette.accent, lineWidth: 1.5)
        )
        .padding(.horizontal, Tokens.Spacing.gutter)
    }

    @ViewBuilder
    private func circleButton(title: String, symbol: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(tint)
                    .frame(width: 40, height: 40)
                    .background(tint.opacity(0.15), in: Circle())
                    .overlay(Circle().strokeBorder(tint.opacity(0.6), lineWidth: 1))
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Tokens.Palette.textPrimary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    RingingAlarmBanner(
        title: "유튜브 운동 영상",
        onSnooze: {}, onCancel: {}, onOpen: {}
    )
    .preferredColorScheme(.dark)
}
