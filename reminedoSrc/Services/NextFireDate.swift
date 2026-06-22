//
//  NextFireDate.swift
//  reminedo
//
//  다음 발생 시각 계산(§4.5). 과거 시각 안내(§4.1/§8)와 none 트리거가 공유한다.
//  목록 정렬에는 쓰지 않는다 — 정렬은 §3.2 시·분 기준. 앱 로직이라 Services에 둔다.
//

import Foundation
import SwiftData

enum NextFireDate {
    /// reminder의 다음 발생 시각.
    /// - none/daily: 오늘 시·분이 미래면 오늘, 아니면 내일.
    /// - weekly: 선택 요일 중 가장 가까운 발생(§4.5). 재시도 우선순위(§4.12)에 사용.
    static func next(for reminder: Reminder, now: Date = .now) -> Date {
        let calendar = Calendar.current
        let timeComps = calendar.dateComponents([.hour, .minute], from: reminder.scheduledAt)

        switch reminder.repeatRule {
        case .none, .daily:
            return calendar.nextDate(
                after: now,
                matching: timeComps,
                matchingPolicy: .nextTime
            ) ?? now
        case .weekly:
            // 선택 요일별 다음 발생 중 최솟값. 요일 없으면 시·분만으로 폴백.
            let iosWeekdays = Weekday.iosWeekdays(fromMask: reminder.repeatWeekdaysMask)
            guard !iosWeekdays.isEmpty else {
                return calendar.nextDate(after: now, matching: timeComps, matchingPolicy: .nextTime) ?? now
            }
            let candidates: [Date] = iosWeekdays.compactMap { weekday in
                var comps = timeComps
                comps.weekday = weekday
                return calendar.nextDate(after: now, matching: comps, matchingPolicy: .nextTime)
            }
            return candidates.min() ?? now
        }
    }

    /// 전체 활성(`isEnabled`) 알람 중 가장 가까운 (id, 발사시각). 없으면 nil.
    /// 알람 keep-alive(오디오)가 "다음에 울릴 알람"을 정하는 데 쓴다(§오디오 알람).
    /// - excluding: 방금 발사한 알람 id를 제외 → 일회성/동시각 재발사 무한루프 방지.
    static func nextAcrossAll(
        in context: ModelContext,
        now: Date = .now,
        excluding: UUID? = nil
    ) -> (id: UUID, date: Date)? {
        let descriptor = FetchDescriptor<Reminder>(predicate: #Predicate { $0.isEnabled })
        guard let reminders = try? context.fetch(descriptor) else { return nil }
        return reminders
            .filter { $0.id != excluding }
            .map { (id: $0.id, date: next(for: $0, now: now)) }
            .min(by: { $0.date < $1.date })
    }

    /// 오늘 해당 시·분이 이미 지났는지(과거 시각 안내용, §4.1).
    static func isPastToday(_ reminder: Reminder, now: Date = .now) -> Bool {
        let calendar = Calendar.current
        let timeComps = calendar.dateComponents([.hour, .minute], from: reminder.scheduledAt)
        guard let todayAtTime = calendar.date(
            bySettingHour: timeComps.hour ?? 0,
            minute: timeComps.minute ?? 0,
            second: 0,
            of: now
        ) else {
            return false
        }
        return todayAtTime <= now
    }
}
