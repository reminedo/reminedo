//
//  SnoozeLiveActivity.swift
//  ReminedoWidget
//
//  스누즈 카운트다운 Live Activity UI(§4.6 확장). 잠금화면/배너 + 다이내믹 아일랜드에
//  "다시 알림까지 남은 시간"을 실시간 표시한다. Text(timerInterval:)로 시스템이 자동 갱신.
//  색·심볼은 위젯 관례대로 이 파일에서 자급한다(앱 토큰 비공유).
//

import ActivityKit
import WidgetKit
import SwiftUI

private enum LAColor {
    static let accent = Color(red: 0x00 / 255, green: 0xC8 / 255, blue: 0x53 / 255)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.6)
}

struct SnoozeLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SnoozeActivityAttributes.self) { context in
            // 잠금화면 / 배너
            lockScreenView(context: context)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .widgetURL(activityURL(context))
                .activityBackgroundTint(Color.black.opacity(0.6))
                .activitySystemActionForegroundColor(LAColor.accent)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.attributes.symbolName)
                        .foregroundStyle(LAColor.accent)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.isStale {
                        Image(systemName: "bell.fill").foregroundStyle(LAColor.accent)
                    } else {
                        countdown(context: context)
                            .font(.title3.weight(.semibold).monospacedDigit())
                            .foregroundStyle(LAColor.accent)
                            .frame(maxWidth: 64)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(LAColor.textPrimary)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.isStale ? "알림이 울렸어요" : "다시 알림까지")
                        .font(.caption)
                        .foregroundStyle(LAColor.textSecondary)
                }
            } compactLeading: {
                Image(systemName: "bell.fill")
                    .foregroundStyle(LAColor.accent)
            } compactTrailing: {
                if context.isStale {
                    Image(systemName: "bell.fill")
                        .foregroundStyle(LAColor.accent)
                } else {
                    countdown(context: context)
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(LAColor.accent)
                        .frame(maxWidth: 44)
                }
            } minimal: {
                Image(systemName: "bell.fill")
                    .foregroundStyle(LAColor.accent)
            }
            .widgetURL(activityURL(context))
        }
    }

    private func activityURL(_ context: ActivityViewContext<SnoozeActivityAttributes>) -> URL {
        URL(string: "\(SharedConstants.urlScheme)://act/\(context.attributes.reminderID.uuidString)")!
    }

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<SnoozeActivityAttributes>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: context.attributes.symbolName)
                .font(.title3)
                .foregroundStyle(LAColor.accent)
                .frame(width: 36, height: 36)
                .background(LAColor.accent.opacity(0.15), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(context.attributes.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(LAColor.textPrimary)
                    .lineLimit(1)
                Text(context.isStale ? "알림이 울렸어요" : "다시 알림까지")
                    .font(.caption)
                    .foregroundStyle(LAColor.textSecondary)
            }

            Spacer(minLength: 8)

            // fireDate 경과(isStale) 후엔 0:00 대신 종료 표시.
            if context.isStale {
                Image(systemName: "bell.fill")
                    .font(.title2)
                    .foregroundStyle(LAColor.accent)
            } else {
                countdown(context: context)
                    .font(.title2.weight(.bold).monospacedDigit())
                    .foregroundStyle(LAColor.accent)
            }
        }
    }

    /// startDate…fireDate 카운트다운(시스템 자동 갱신).
    private func countdown(context: ActivityViewContext<SnoozeActivityAttributes>) -> Text {
        Text(timerInterval: context.state.startDate...context.state.fireDate,
             countsDown: true)
    }
}
