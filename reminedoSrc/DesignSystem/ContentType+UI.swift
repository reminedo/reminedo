//
//  ContentType+UI.swift
//  reminedo
//
//  ContentType의 표현 매핑(SF Symbol·색). 앱(SwiftUI) 전용이므로 Shared가 아닌 여기에 둔다
//  — Shared 레이어는 UIKit/SwiftUI를 import하지 않는다는 규율을 지키기 위함.
//

import SwiftUI

extension ContentType {
    var symbolName: String {
        switch self {
        case .memo: Tokens.Symbols.memo
        case .url: Tokens.Symbols.url
        case .image: Tokens.Symbols.image
        }
    }

    /// 행 타입 칩의 틴트(§11). 타입을 색으로도 구분해 흘끗 인지를 돕는다.
    var tint: Color {
        switch self {
        case .memo: Tokens.Palette.accent
        case .url: Tokens.Palette.typeURL
        case .image: Tokens.Palette.typeImage
        }
    }
}
