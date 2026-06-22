//
//  DeletionManager.swift
//  reminedo
//
//  삭제 Undo의 지연 삭제 상태(§4.3). 삭제 즉시 pending 알림만 취소하고 레코드는 SwiftData에
//  남겨둔 채 이 매니저에 ID를 등록한다 — 목록은 등록된 ID를 숨기고, 스낵바 만료/앱 종료 시
//  실제 delete를 커밋한다. Undo = 등록 해제 + reschedule(레코드가 그대로라 복구).
//
//  환경 주입 @Observable. 실제 커밋(modelContext.delete + 이미지명 enqueue)은 List 루트가 수행한다.
//

import SwiftUI

@Observable
final class DeletionManager {
    /// 지연 삭제 대기 중인 reminder ID(목록에서 숨김 대상).
    private(set) var pendingDeletionIDs: Set<UUID> = []

    /// 현재 스낵바에 표시 중인 단건(Undo 대상). 자동 만료 타이머가 만료하면 커밋된다.
    private(set) var snackbarReminderID: UUID?

    /// 삭제 등록 — pending 알림 취소는 호출부가 이미 수행했다고 가정(§4.3 순서).
    func enqueue(_ id: UUID) {
        pendingDeletionIDs.insert(id)
        snackbarReminderID = id
    }

    /// 목록 필터용: 이 ID가 지연 삭제 대기 중인지.
    func isPendingDeletion(_ id: UUID) -> Bool {
        pendingDeletionIDs.contains(id)
    }

    /// Undo — 등록 해제(복구). 실제 reschedule은 호출부가 수행한다.
    func undo(_ id: UUID) {
        pendingDeletionIDs.remove(id)
        if snackbarReminderID == id { snackbarReminderID = nil }
    }

    /// 커밋 완료/스낵바 닫힘 — 등록 해제(실제 delete는 호출부가 수행 후 호출).
    func clear(_ id: UUID) {
        pendingDeletionIDs.remove(id)
        if snackbarReminderID == id { snackbarReminderID = nil }
    }
}
