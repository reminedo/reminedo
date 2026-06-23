//
//  Tokens.swift
//  reminedo
//
//  디자인 토큰의 단일 출처(PRD §11, 잠정값). 다크 단일 테마라 색·간격·반경·SF Symbol을
//  한 파일에 모아 두고 여기서만 튜닝한다. (컬러셋 대신 코드 토큰 — 단일 테마에 유리)
//

import SwiftUI

enum Tokens {
    enum Palette {
        static let background = Color(hex: 0x000000)
        static let card = Color(hex: 0x1C1C1E)
        static let accent = Color(hex: 0x00C853)   // 그린

        static let textPrimary = Color.white
        static let textSecondary = Color(white: 0.6)
        static let disabled = Color(white: 0.35)

        static let destructive = Color(hex: 0xFF453A)   // 파괴 액션(삭제) 빨강(§8)

        // 콘텐츠 타입 칩 틴트(§11)
        static let typeURL = Color(hex: 0x0A84FF)
        static let typeImage = Color(hex: 0xFF9F0A)

        // 토글
        static let toggleOffTrack = Color(hex: 0x1C1C1E)
        static let toggleOffStroke = Color(white: 0.3)
        static let toggleOffKnob = Color(white: 0.95)
    }

    enum Radius {
        static let card: CGFloat = 14
    }

    /// 타포그래피 토큰(단일 출처). 홈 셀 시간·제목은 동일 사이즈로 통일(이슈6).
    enum Typography {
        /// 홈/위젯 행의 시간·제목(동일 사이즈, §3.2/이슈6).
        static let rowPrimary = Font.title3.weight(.semibold)
    }

    enum Spacing {
        static let row: CGFloat = 12
        static let gutter: CGFloat = 16
    }

    /// SF Symbol 이름의 단일 출처(§11).
    enum Symbols {
        static let memo = "text.bubble"
        static let url = "link"
        static let image = "photo"
        static let warning = "exclamationmark.triangle.fill"
        static let muted = "bell.slash"
        static let tabReminders = "bell.fill"
        static let tabSettings = "gearshape"
    }
}
