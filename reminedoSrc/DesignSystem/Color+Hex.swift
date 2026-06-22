//
//  Color+Hex.swift
//  reminedo
//
//  16진수 리터럴로 Color를 만드는 헬퍼. 디자인 토큰을 한눈에 읽히게 한다.
//

import SwiftUI

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}
