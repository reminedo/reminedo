//
//  ReminderCell.swift
//  reminedo
//
//  ReminderRow(순수 표현)를 감싸는 앱 셀. 알람을 소유해 부제를 만들고, 탭→편집 시트,
//  토글 변경→isEnabled 저장 후 단일 reschedule 경로 호출(§4.2/§4.4)까지 side-effect를 담당한다.
//

import SwiftUI
import SwiftData

struct ReminderCell: View {
    @Bindable var reminder: Reminder
    var onTap: () -> Void
    /// 예약 실패 배지 탭 → 한도 안내 알림(§4.12). List 루트가 처리.
    var onWarningTap: () -> Void = {}

    @Environment(\.modelContext) private var modelContext
    @Environment(NotificationService.self) private var notificationService
    @Environment(ImageStore.self) private var imageStore

    var body: some View {
        Button(action: onTap) {
            ReminderRow(
                time: reminder.scheduledAt,
                type: reminder.contentType,
                title: reminder.title,
                thumbnail: thumbnail,
                thumbnailBroken: thumbnailBroken,
                isOn: $reminder.isEnabled,
                // 권한 꺼짐이면 토글 비활성+음소거(거짓신호 방지, §3.2/§13.1).
                isEnabled: notificationService.isAuthorized,
                dimmed: !reminder.isEnabled,
                showWarning: reminder.schedulingFailed,
                interactive: true,
                onToggle: handleToggle,
                onWarningTap: onWarningTap
            )
        }
        .buttonStyle(.plain)
    }

    /// 이미지 알람 셀 썸네일(§3.2/§4.7): ImageStore의 다운샘플 캐시에서 해소. 풀 이미지 미로드.
    private var thumbnail: UIImage? {
        guard reminder.contentType == .image,
              let fileName = reminder.imageFileName, !fileName.isEmpty else { return nil }
        return imageStore.thumbnail(named: fileName)
    }

    /// 이미지 알람인데 파일명이 있으나 썸네일을 못 만든(파일 없음/깨짐) 상태(§8).
    private var thumbnailBroken: Bool {
        guard reminder.contentType == .image,
              let fileName = reminder.imageFileName, !fileName.isEmpty else { return false }
        return imageStore.thumbnail(named: fileName) == nil
    }

    /// On/Off(§4.4): 저장 → reschedule → 성공 햅틱. 실패는 schedulingFailed 플래그로 행에 표시.
    /// Off는 pending을 줄이므로(§4.12) 자동 재시도를 켜 다른 실패 알람의 자리 복구를 시도한다.
    private func handleToggle(_ isOn: Bool) {
        reminder.isEnabled = isOn
        reminder.updatedAt = .now
        try? modelContext.save()
        notificationService.reschedule(reminder)
        if isOn {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } else {
            // Off → pending 감소 → 실패 알람 재시도(§4.12).
            notificationService.retryFailedScheduling()
        }
    }
}
