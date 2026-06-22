//
//  SnoozeActivityAttributes.swift
//  reminedo (Shared)
//
//  스누즈 카운트다운 Live Activity의 공유 속성(§4.6 확장). 앱(시작/종료)과 위젯 확장(UI)이
//  같은 타입을 봐야 하므로 Shared에 둔다. Foundation+ActivityKit만 import(위젯 타깃과 그대로 공유).
//  `nonisolated`: MainActor 기본 격리 회피(위젯·인텐트 등 비격리 컨텍스트에서 안전 사용).
//

import ActivityKit
import Foundation

nonisolated struct SnoozeActivityAttributes: ActivityAttributes {
    /// 카운트다운 구간(startDate…fireDate). 변하는 상태.
    struct ContentState: Codable, Hashable {
        /// 스누즈를 누른 시각(타이머 시작).
        var startDate: Date
        /// 다시 울릴 시각(타이머 종료).
        var fireDate: Date
    }

    /// 어느 알람의 스누즈인지(고정). 삭제·만료 시 해당 Activity를 정확히 종료하는 키.
    var reminderID: UUID
    /// 알람 제목(고정).
    var title: String
    /// 콘텐츠 타입 SF Symbol 이름(메모/URL/사진). 앱이 ContentType에서 계산해 전달.
    var symbolName: String
}
