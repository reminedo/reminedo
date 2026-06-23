//
//  ReminderRow.swift
//  reminedo
//
//  home.png 알림 셀의 순수 표현 행(SwiftData/서비스 의존 없음 — 위젯 6a와 공통 어휘).
//  레이아웃: [타입 칩] · 시각 + 제목(굵게) + 부제(회색) · ReminderToggle(트레일링).
//  side-effect는 isOn 바인딩/onChange로 호출부(ReminderCell)에 위임한다.
//

import SwiftUI

struct ReminderRow: View {
    let time: Date
    let type: ContentType
    let title: String
    /// 이미지 알람 셀 썸네일(§3.2). 호출부(ReminderCell)가 ImageStore로 해소해 전달 —
    /// Row는 표현 전용이라 ImageStore를 만지지 않는다(위젯 공유 어휘 유지). nil이면 칩만 표시.
    var thumbnail: UIImage? = nil
    /// 이미지 알람인데 파일이 없거나 깨졌을 때 깨짐 표시(§8).
    var thumbnailBroken: Bool = false
    @Binding var isOn: Bool
    var isEnabled: Bool = true
    var dimmed: Bool = false
    var showWarning: Bool = false
    var interactive: Bool = true
    var onToggle: ((Bool) -> Void)? = nil
    /// 예약 실패 경고 배지 탭 → 한도 안내(§4.12). 표시 전용(위젯)에선 nil.
    var onWarningTap: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: Tokens.Spacing.gutter) {
            leading

            VStack(alignment: .leading, spacing: 4) {
                // 시간(상단) — 제목과 동일 폰트/사이즈(§3.2/이슈6). 부제는 미표시(home.png 최소 유지).
                HStack(spacing: 6) {
                    Text(DateFormatting.scheduledTimeText(time))
                        .font(Tokens.Typography.rowPrimary.monospacedDigit())
                        .foregroundStyle(Tokens.Palette.textSecondary)
                    if showWarning {
                        warningBadge
                    }
                    // 권한 꺼짐 셀 표시: 음소거 아이콘(거짓신호 방지, §3.2/§13.1).
                    if !isEnabled {
                        Image(systemName: Tokens.Symbols.muted)
                            .font(.title3)
                            .foregroundStyle(Tokens.Palette.textSecondary)
                    }
                    Spacer(minLength: 0)
                }
                // 제목(하단) — 시간과 동일 폰트/사이즈(이슈6).
                Text(title)
                    .font(Tokens.Typography.rowPrimary)
                    .foregroundStyle(Tokens.Palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: Tokens.Spacing.row)

            ReminderToggle(
                isOn: $isOn,
                isEnabled: isEnabled,
                dimmed: dimmed,
                interactive: interactive,
                onChange: onToggle
            )
        }
        .padding(Tokens.Spacing.gutter)
        .background(Tokens.Palette.card)
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous))
        .opacity(dimmed ? 0.55 : 1)
    }

    /// 예약 실패 경고 배지(§4.12/§13.2). 탭하면 한도 안내(onWarningTap). 셀 탭과 충돌하지 않도록
    /// 콜백이 있을 때만 별도 탭 제스처를 high-priority로 받는다.
    @ViewBuilder
    private var warningBadge: some View {
        let icon = Image(systemName: Tokens.Symbols.warning)
            .font(.caption)
            .foregroundStyle(Tokens.Palette.destructive)
        if let onWarningTap {
            icon
                .contentShape(Rectangle())
                .highPriorityGesture(TapGesture().onEnded { onWarningTap() })
                .accessibilityAddTraits(.isButton)
        } else {
            icon
        }
    }

    /// 선두 영역(§3.2): 이미지 알람이면 썸네일/깨짐 표시, 그 외엔 타입 칩.
    @ViewBuilder
    private var leading: some View {
        if type == .image {
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else if thumbnailBroken {
                // 파일 없음/깨짐(§8): 깨진 이미지 표시.
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Tokens.Palette.background)
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: "photo.badge.exclamationmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Tokens.Palette.textSecondary)
                    )
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Tokens.Palette.textSecondary.opacity(0.4), lineWidth: 1))
            } else {
                typeChip
            }
        } else {
            typeChip
        }
    }

    private var typeChip: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(type.tint.opacity(0.22))
            .frame(width: 40, height: 40)
            .overlay(
                Image(systemName: type.symbolName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(type.tint)
            )
    }
}

#Preview("ReminderRow") {
    struct Host: View {
        @State private var on = true
        @State private var off = false
        var body: some View {
            VStack(spacing: Tokens.Spacing.row) {
                ReminderRow(time: .now, type: .memo, title: "자기 전 스트레칭", isOn: $on)
                ReminderRow(time: .now, type: .url, title: "유튜브 운동 영상", isOn: $on)
                ReminderRow(time: .now, type: .image, title: "참고 이미지", isOn: $off, dimmed: true)
                ReminderRow(time: .now, type: .memo, title: "예약 실패 예시", isOn: $on, showWarning: true)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Tokens.Palette.background)
        }
    }
    return Host()
}
