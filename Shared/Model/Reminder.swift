//
//  Reminder.swift
//  reminedo
//
//  알람(도메인 엔티티)의 SwiftData 모델. PRD §5의 v1 초기 스키마 — 전 필드를 처음부터
//  포함해 마이그레이션을 피한다. Shared 레이어이므로 Foundation + SwiftData만 import한다
//  (UIKit/SwiftUI·앱 전용 코드 금지 → 위젯/공유 확장 타깃과 그대로 공유).
//

import Foundation
import SwiftData

@Model
final class Reminder {
    /// UUID는 시트 진입 시 즉시 발급(§4.1). 알림 식별자 prefix의 기준이기도 하다.
    @Attribute(.unique) var id: UUID

    /// 알림에 노출되는 유일한 텍스트(§1, 프라이버시: 제목만 노출).
    var title: String

    /// 시·분은 항상 의미가 있고, 날짜는 RepeatRule.none일 때만 의미가 있다.
    var scheduledAt: Date

    var repeatRule: RepeatRule

    /// weekly 전용. bit0=일 … bit6=토 (iOS weekday = bit+1, UI는 월~일). §4.5
    var repeatWeekdaysMask: Int

    var isEnabled: Bool

    var contentType: ContentType

    // 타입별 콘텐츠 — contentType에 해당하는 값만 채워진다.
    var memo: String?
    var imageFileName: String?
    var targetURL: String?
    var linkTitle: String?
    var linkThumbnailFileName: String?

    // 다시 알림(스누즈)
    var snoozeEnabled: Bool
    var snoozeMinutes: Int

    var soundType: SoundType

    /// 예약 실패 시 셀에 상시 경고 배지를 띄우기 위한 플래그(§4.12, §13.2).
    var schedulingFailed: Bool

    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String = "",
        scheduledAt: Date = .now,
        repeatRule: RepeatRule = .none,
        repeatWeekdaysMask: Int = 0,
        isEnabled: Bool = true,
        contentType: ContentType = .memo,
        memo: String? = nil,
        imageFileName: String? = nil,
        targetURL: String? = nil,
        linkTitle: String? = nil,
        linkThumbnailFileName: String? = nil,
        snoozeEnabled: Bool = true,
        snoozeMinutes: Int = 5,
        soundType: SoundType = .defaultSound,
        schedulingFailed: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.scheduledAt = scheduledAt
        self.repeatRule = repeatRule
        self.repeatWeekdaysMask = repeatWeekdaysMask
        self.isEnabled = isEnabled
        self.contentType = contentType
        self.memo = memo
        self.imageFileName = imageFileName
        self.targetURL = targetURL
        self.linkTitle = linkTitle
        self.linkThumbnailFileName = linkThumbnailFileName
        self.snoozeEnabled = snoozeEnabled
        self.snoozeMinutes = snoozeMinutes
        self.soundType = soundType
        self.schedulingFailed = schedulingFailed
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
