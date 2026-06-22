//
//  DateFormatting.swift
//  reminedo
//
//  알림 시각의 한국어 표기 헬퍼. "오전/오후 H:MM"(§3.2/§8 마이크로카피) 단일 출처.
//  순수 Foundation 포매팅이라 어디서든 안전하지만, 표현 계층 관심사라 DesignSystem에 둔다.
//

import Foundation

enum DateFormatting {
    /// 알림 시각 표기 "오전 6:30" / "오후 3:05" (시·분만, 12시간제).
    static func scheduledTimeText(_ date: Date) -> String {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        let hour = comps.hour ?? 0
        let minute = comps.minute ?? 0
        let isAM = hour < 12
        var hour12 = hour % 12
        if hour12 == 0 { hour12 = 12 }
        return String(format: "%@ %d:%02d", isAM ? "오전" : "오후", hour12, minute)
    }

    /// lock 화면 큰 시각 표기 "6:30" (오전/오후 표기 없이 12시간제 시:분, §3.5).
    static func lockClockText(_ date: Date) -> String {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        let hour = comps.hour ?? 0
        let minute = comps.minute ?? 0
        var hour12 = hour % 12
        if hour12 == 0 { hour12 = 12 }
        return String(format: "%d:%02d", hour12, minute)
    }

    /// lock 화면 날짜 표기 "5월 18일 토요일"(오늘 기준, ko_KR).
    static func lockDateText(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.setLocalizedDateFormatFromTemplate("MMMMd EEEE")
        return formatter.string(from: date)
    }
}
