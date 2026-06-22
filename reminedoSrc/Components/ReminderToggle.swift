//
//  ReminderToggle.swift
//  reminedo
//
//  on.png / off.png 디자인을 네이티브로 재현한 커스텀 토글. 표준 SwiftUI Toggle은 "꽉 찬
//  초록 트랙 + 흰 노브"라 시안과 다르다 → Shape(Capsule 외곽선 + Circle 노브)로 직접 그린다.
//    · ON  : 투명 트랙 + 초록 외곽선 + 초록 노브(우)
//    · OFF : 어두운 트랙 + 회색 외곽선 + 밝은 노브(좌)
//  순수 표현 컴포넌트 — NotificationService 등 앱 로직에 의존하지 않아 위젯과도 공유 가능하다.
//  side-effect(재예약·햅틱)는 onChange로 호출부에 위임한다(§4.4).
//

import SwiftUI

struct ReminderToggle: View {
    @Binding var isOn: Bool

    /// false면 회색·비인터랙티브(권한 꺼짐 등 — 거짓 신호 방지, §3.2/§13.1).
    var isEnabled: Bool = true
    /// Off 알람을 목록에서 "충분히 흐림" 처리할 때(§3.2).
    var dimmed: Bool = false
    /// false면 탭 입력을 받지 않는 표시 전용(위젯 6a, §14.6).
    var interactive: Bool = true
    /// 값이 바뀐 뒤 호출 — 호출부에서 재예약/햅틱/경고를 수행한다.
    var onChange: ((Bool) -> Void)? = nil

    private let trackWidth: CGFloat = 51
    private let trackHeight: CGFloat = 31
    private let knobInset: CGFloat = 3

    var body: some View {
        ZStack {
            Capsule()
                .fill(trackFill)
                .overlay(Capsule().strokeBorder(trackStroke, lineWidth: 2))

            Circle()
                .fill(knobFill)
                .padding(knobInset)
                .frame(maxWidth: .infinity, alignment: isOn ? .trailing : .leading)
        }
        .frame(width: trackWidth, height: trackHeight)
        .opacity(dimmed ? 0.4 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: isOn)
        .contentShape(Capsule())
        .allowsHitTesting(interactive && isEnabled)
        .onTapGesture {
            isOn.toggle()
            onChange?(isOn)
        }
        .accessibilityElement()
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(isOn ? "켜짐" : "꺼짐")
    }

    private var trackFill: Color {
        guard isEnabled else { return Color(white: 0.18) }
        return isOn ? .clear : Tokens.Palette.toggleOffTrack
    }

    private var trackStroke: Color {
        guard isEnabled else { return Color(white: 0.3) }
        return isOn ? Tokens.Palette.accent : Tokens.Palette.toggleOffStroke
    }

    private var knobFill: Color {
        guard isEnabled else { return Tokens.Palette.disabled }
        return isOn ? Tokens.Palette.accent : Tokens.Palette.toggleOffKnob
    }
}

#Preview("ReminderToggle 상태") {
    struct PreviewHost: View {
        @State private var on = true
        @State private var off = false
        var body: some View {
            VStack(alignment: .leading, spacing: 24) {
                row("On") { ReminderToggle(isOn: $on) }
                row("Off") { ReminderToggle(isOn: $off) }
                row("Off · dimmed") { ReminderToggle(isOn: $off, dimmed: true) }
                row("Disabled(권한 꺼짐)") { ReminderToggle(isOn: $on, isEnabled: false) }
                row("위젯 표시 전용") { ReminderToggle(isOn: $on, interactive: false) }
            }
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Tokens.Palette.background)
        }

        func row(_ label: String, @ViewBuilder _ toggle: () -> some View) -> some View {
            HStack(spacing: 16) {
                toggle()
                Text(label).foregroundStyle(Tokens.Palette.textSecondary)
            }
        }
    }
    return PreviewHost()
}
