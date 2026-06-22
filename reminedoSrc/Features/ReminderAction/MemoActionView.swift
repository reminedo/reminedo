//
//  MemoActionView.swift
//  reminedo
//
//  메모 알람의 행동(O 액션) 화면(§3.5). 앱 배경 풀스크린, 제목 + 본문(스크롤), 상단 닫기.
//  알림 "지금 보기"가 곧장 행동으로 이어지는 핵심 가치를 구현한다.
//

import SwiftUI

struct MemoActionView: View {
    let title: String
    let memo: String
    var onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Tokens.Palette.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Spacing.gutter) {
                    Text(title)
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(Tokens.Palette.textPrimary)
                    Text(memo)
                        .font(.body)
                        .foregroundStyle(Tokens.Palette.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(Tokens.Spacing.gutter)
                .padding(.top, 60)
            }

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Tokens.Palette.textPrimary)
                    .padding(12)
                    .background(Tokens.Palette.card, in: Circle())
            }
            .padding(Tokens.Spacing.gutter)
            .accessibilityLabel(Strings.Action.close)
        }
    }
}

#Preview {
    MemoActionView(title: "자기 전 스트레칭", memo: "목·어깨 스트레칭 10분\n물 한 컵 마시기", onClose: {})
        .preferredColorScheme(.dark)
}
