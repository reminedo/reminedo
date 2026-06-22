//
//  PermissionBanner.swift
//  reminedo
//
//  권한 꺼짐 상단 경고 배너(§3.2/§8/§13.1). "저장≠울림" 원칙대로 권한이 없으면 목록 상단에
//  배너 + [iOS 설정에서 알림 켜기] 버튼을 띄워 거짓 신호를 막는다. 순수 표현 — openSettings는
//  호출부가 주입(UIApplication.openSettingsURLString 열기).
//

import SwiftUI

struct PermissionBanner: View {
    var onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: Tokens.Spacing.row) {
            Image(systemName: Tokens.Symbols.muted)
                .font(.body.weight(.semibold))
                .foregroundStyle(Tokens.Palette.destructive)
            Text(Strings.Permission.bannerOffMessage)
                .font(.footnote)
                .foregroundStyle(Tokens.Palette.textPrimary)
            Spacer(minLength: 8)
            Button(action: onOpenSettings) {
                Text(Strings.Permission.openSettings)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Tokens.Palette.accent)
            }
        }
        .padding(Tokens.Spacing.gutter)
        .background(Tokens.Palette.destructive.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous))
    }
}

#Preview {
    ZStack {
        Tokens.Palette.background.ignoresSafeArea()
        PermissionBanner(onOpenSettings: {})
            .padding()
    }
    .preferredColorScheme(.dark)
}
