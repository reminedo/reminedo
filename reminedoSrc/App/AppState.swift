//
//  AppState.swift
//  reminedo
//
//  앱 전역 라우팅 상태(§4.11). 알림 O는 행동 화면(.act), 위젯 탭은 편집 시트(.edit)로 가야
//  하므로 목적지 타입을 가진 라우트로 둔다. scenePhase==.active에서 1회 소비 후 nil 처리.
//

import SwiftUI

enum PendingRoute: Equatable {
    case act(UUID)         // 알림 본문 탭 → 인앱 lock 화면(다시알림/닫기/지금보기)
    case actContent(UUID)  // 네이티브 "지금 보기" 액션 → 콘텐츠 직행(lock 화면 생략)
    case edit(UUID)        // 위젯 탭 → 편집 시트
}

@Observable
final class AppState {
    var pendingRoute: PendingRoute?

    /// 공유로 들어온 추가 시트 프리필 URL(§2.3/§4.10). reminedo://add 수신 시 App Group
    /// 페이로드를 소비해 여기 담고, ReminderListScreen이 scenePhase==.active에서 1회 소비한다.
    /// nil이면 빈 추가 시트(graceful).
    var pendingAddURL: String?
    var pendingAddImageImportFileName: String?

    /// 공유 추가 트리거가 있었음을 표시. URL 없이 reminedo://add만 와도(페이로드 없음)
    /// 빈 추가 시트를 열기 위해 pendingAddURL(nil 가능)과 분리해 둔다.
    var pendingAddRequested: Bool = false

    /// 현재 울리는 알람(이슈10). 포그라운드 알람 발화 시 NotificationDelegate.willPresent가 세팅하고,
    /// 최상위 오버레이(RootTabView)가 on_notice.png 커스텀 배너를 띄운다. nil이면 배너 숨김.
    var ringingReminderID: UUID?
}
