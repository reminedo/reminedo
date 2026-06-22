//
//  SnoozeActivityController.swift
//  reminedo
//
//  스누즈 카운트다운 Live Activity 시작/종료 관리(§4.6 확장). ReminedoApp이 .environment로 주입.
//  reminder.id당 하나의 Activity를 추적해, 재스누즈 시 기존을 끝내고 새로 시작한다.
//
//  ※ Activity.request는 앱이 "포그라운드"일 때만 성공한다(ActivityKit 제약). 따라서 시작은
//    인앱 lock 화면의 "다시 알림" 버튼(포그라운드)에서만 호출한다.
//  ※ 종료는 스누즈 알림이 실제 울릴 때(willPresent/탭) 호출. 백그라운드 방치 시엔
//    staleDate(fireDate) 이후 시스템이 정리하며 카운트다운은 isStale로 "울렸어요"를 표시한다(best-effort).
//

import ActivityKit
import Foundation

@MainActor
@Observable
final class SnoozeActivityController {
    /// 스누즈 카운트다운 Live Activity 시작(포그라운드 전용). 재스누즈면 기존 종료 후 재시작.
    func start(reminderID: UUID, title: String, symbolName: String, minutes: Int) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        end(reminderID: reminderID)   // 재스누즈 정리

        let now = Date()
        let fireDate = now.addingTimeInterval(TimeInterval(max(1, minutes) * 60))
        let attributes = SnoozeActivityAttributes(reminderID: reminderID, title: title, symbolName: symbolName)
        let state = SnoozeActivityAttributes.ContentState(startDate: now, fireDate: fireDate)
        // staleDate=fireDate: 카운트다운 종료 시점에 콘텐츠를 stale로 표시(UI가 "울렸어요"로 전환).
        let content = ActivityContent(state: state, staleDate: fireDate)

        do {
            _ = try Activity.request(attributes: attributes, content: content, pushType: nil)
        } catch {
            // best-effort: 실패해도 알림 재예약은 별도로 진행된다.
        }
    }

    /// 특정 알람의 스누즈 Activity 종료(스누즈 알림 발사/탭, 재스누즈, 알람 삭제 시).
    func end(reminderID: UUID) {
        for activity in Activity<SnoozeActivityAttributes>.activities
        where activity.attributes.reminderID == reminderID {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    /// fireDate가 지난 스누즈 Activity 정리(앱이 다시 활성화될 때 호출). 0:00 잔존 방지의 마지막 그물.
    func endExpired() {
        let now = Date()
        for activity in Activity<SnoozeActivityAttributes>.activities
        where activity.content.state.fireDate <= now {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
