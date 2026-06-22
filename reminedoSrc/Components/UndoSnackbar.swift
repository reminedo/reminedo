//
//  UndoSnackbar.swift
//  reminedo
//
//  삭제 Undo 스낵바(§4.3/§8/§13.5). "삭제됨 [실행 취소]"를 하단에 띄우고 ~4초 후 자동 만료한다.
//  순수 표현 — 표시 여부·자동 만료·Undo/만료 콜백은 호출부(List 루트)가 관리한다.
//

import SwiftUI

struct UndoSnackbar: View {
    var onUndo: () -> Void

    var body: some View {
        HStack(spacing: Tokens.Spacing.gutter) {
            Text(Strings.Snackbar.deleted)
                .font(.subheadline)
                .foregroundStyle(Tokens.Palette.textPrimary)
            Spacer(minLength: 8)
            Button(action: onUndo) {
                Text(Strings.Snackbar.undo)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Tokens.Palette.accent)
            }
        }
        .padding(.horizontal, Tokens.Spacing.gutter)
        .padding(.vertical, Tokens.Spacing.row)
        .background(Tokens.Palette.card)
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous))
        .shadow(color: .black.opacity(0.4), radius: 8, y: 2)
        .padding(.horizontal, Tokens.Spacing.gutter)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

#Preview {
    ZStack(alignment: .bottom) {
        Tokens.Palette.background.ignoresSafeArea()
        UndoSnackbar(onUndo: {})
            .padding(.bottom, 40)
    }
    .preferredColorScheme(.dark)
}
