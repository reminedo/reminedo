//
//  ActionBigButton.swift
//  reminedo
//
//  lock.png 하단의 풀-width 액션 버튼(다시 알림 / 알림 닫기 / 지금 보기). 좌측 SF Symbol +
//  중앙 라벨, 둥근 모서리 + 색상 외곽선. tint로 강조색(녹색/빨강)을 받는 순수 표현 컴포넌트.
//

import SwiftUI

struct ActionBigButton: View {
    let title: String
    let symbolName: String
    var tint: Color = Tokens.Palette.accent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbolName)
                    .font(.headline)
                Text(title)
                    .font(.headline)
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(tint.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous)
                    .strokeBorder(tint.opacity(0.5), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    VStack(spacing: 12) {
        ActionBigButton(title: "5분 후 다시 알림", symbolName: "clock.arrow.circlepath") {}
        ActionBigButton(title: "알림 닫기", symbolName: "xmark", tint: Tokens.Palette.destructive) {}
        ActionBigButton(title: "지금 보기", symbolName: "play.fill") {}
    }
    .padding()
    .background(Color.black)
    .preferredColorScheme(.dark)
}
