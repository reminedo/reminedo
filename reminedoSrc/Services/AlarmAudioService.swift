//
//  AlarmAudioService.swift
//  reminedo
//
//  백그라운드 오디오 알람(§오디오 알람, 알라미 방식). 무음 루프로 앱을 백그라운드에 살려두고
//  (UIBackgroundModes: audio), 알람 시각에 AVAudioSession.playback 풀볼륨으로 재생해 무음모드·
//  잠금화면을 관통한다. 정확한 발사 자체는 UNNotification(OS 보장)이 책임지고, 이 서비스는
//  "살아있을 때 큰 소리"를 더하는 best-effort 강화 레이어다(타이머 정확도·생존은 보장 못 함).
//
//  ※ shared 싱글톤: 백그라운드 DispatchSourceTimer·인터럽션 관찰자가 SwiftUI environment
//    밖에서도 닿아야 하므로(글로벌 오디오 매니저). 뷰는 .environment로 받는다.
//  ※ 한계(문서화): 앱 강제종료·jetsam 시 죽음 → UN 백스톱만. 타이머는 백그라운드 throttling으로
//    수 시간 뒤 ±오차 가능. 무음 keep-alive는 회색지대. 시뮬레이터로 검증 불가(실기기 필수).
//  ※ Live Activity는 안 씀(백그라운드 오디오 앱은 LA 백그라운드 업데이트 금지 — SessionKit 제약).
//

import AVFoundation
import Foundation
import SwiftData

@MainActor
@Observable
final class AlarmAudioService {
    static let shared = AlarmAudioService()

    private let modelContext = SharedModelContainer.shared.mainContext

    private var silencePlayer: AVAudioPlayer?
    private var alarmPlayer: AVAudioPlayer?
    private var fireTimer: DispatchSourceTimer?
    private var autoStopWork: DispatchWorkItem?

    /// 타이머가 무엇을 위해 걸렸는지(발사 시 어느 알람/스누즈인지 식별).
    private var scheduledFire: (id: UUID, date: Date, isSnooze: Bool)?
    /// 진행 중 스누즈 발사 예정(Reminder 모델 밖의 1회성). keep-alive가 nextAcrossAll과 함께 고려.
    private var pendingSnooze: (id: UUID, date: Date)?

    private(set) var isRinging = false
    private var ringingReminderID: UUID?

    /// 사용자가 앱을 안 열면 무한 재생되는 것 방지(분 단위).
    private let autoStopAfter: TimeInterval = 5 * 60

    private init() {
        // 관찰자는 .main 큐에서 실행된다 → MainActor.assumeIsolated로 동기 처리(self 캡처 없이 shared 참조).
        let nc = NotificationCenter.default
        nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { note in
            let raw = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) ?? 0
            MainActor.assumeIsolated { AlarmAudioService.shared.handleInterruption(typeRaw: raw) }
        }
        nc.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AlarmAudioService.shared.handleMediaReset() }
        }
    }

    // MARK: - keep-alive 생명주기 (scenePhase에서 호출)

    /// 백그라운드 진입 시: 미래 발사가 있으면 무음 루프 시작 + 다음 발사 타이머. 없으면 정지.
    func startKeepAlive() {
        guard nearestFire() != nil else { stop(); return }
        startSilence()
        scheduleNextFire()
    }

    /// 포그라운드 진입/알람 없음: 전부 정지 + 세션 비활성. pendingSnooze(in-memory)는 유지.
    func stop() {
        fireTimer?.cancel(); fireTimer = nil
        scheduledFire = nil
        autoStopWork?.cancel(); autoStopWork = nil
        alarmPlayer?.stop(); alarmPlayer = nil
        silencePlayer?.stop(); silencePlayer = nil
        isRinging = false
        ringingReminderID = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - 정지/스누즈 (커맨드 버스/인앱에서 호출)

    /// 풀볼륨 정지(취소·지금보기·autoStop). 무음 keep-alive는 유지하고 다음 알람을 다시 건다.
    func stopRinging() {
        alarmPlayer?.stop(); alarmPlayer = nil
        isRinging = false
        ringingReminderID = nil
        autoStopWork?.cancel(); autoStopWork = nil
        if silencePlayer != nil { scheduleNextFire() }   // keep-alive 중일 때만 타이머 운용
    }

    /// 다시 알림: 풀볼륨 정지 + minutes 뒤 재발사 등록(오디오). UN 재예약·LA 갱신은 호출부가 처리.
    func snooze(reminderID: UUID, minutes: Int) {
        alarmPlayer?.stop(); alarmPlayer = nil
        isRinging = false
        autoStopWork?.cancel(); autoStopWork = nil
        ringingReminderID = nil
        pendingSnooze = (reminderID, Date().addingTimeInterval(TimeInterval(max(1, minutes) * 60)))
        if silencePlayer != nil { scheduleNextFire() }   // keep-alive 중이면 즉시, 아니면 다음 startKeepAlive가 픽업
    }

    /// 현재 울리는 알람을 그 알람의 snoozeMinutes로 스누즈(네이티브 알림 SNOOZE 액션용).
    func snoozeCurrent() {
        guard let id = ringingReminderID, let reminder = fetch(id: id) else { return }
        snooze(reminderID: id, minutes: reminder.snoozeMinutes)
    }

    // MARK: - 발사

    private func fireAlarm() {
        guard let fire = scheduledFire else { return }
        scheduledFire = nil
        if fire.isSnooze { pendingSnooze = nil }

        let reminder = fetch(id: fire.id)

        // .silent 알람은 풀볼륨 미재생(UN이 무음 처리). 기본음 알람만 큰 소리로 울린다.
        if reminder?.soundType == .defaultSound {
            playAlarm()
            isRinging = true
            ringingReminderID = fire.id
            scheduleAutoStop()
        }

        // 일회성(.none)은 발사 후 비활성화 — 매일 재발사 버그 방지. UN-only 발사는 .active reconciliation이 보강.
        if !fire.isSnooze, let reminder, reminder.repeatRule == .none {
            reminder.isEnabled = false
            try? modelContext.save()
        }
        // 다음 알람 대비 재예약(방금 발사한 알람 제외 → 동시각/일회성 재발사 방지).
        scheduleNextFire(excludingReminder: fire.isSnooze ? nil : fire.id)
    }

    // MARK: - 내부: 세션/플레이어

    private func configureSession(solo: Bool) {
        let session = AVAudioSession.sharedInstance()
        let options: AVAudioSession.CategoryOptions = solo ? [] : [.mixWithOthers]
        try? session.setCategory(.playback, mode: .default, options: options)
        try? session.setActive(true)
    }

    private func startSilence() {
        guard silencePlayer == nil else { return }
        configureSession(solo: false)   // 사용자 음악 안 끊음
        guard let url = Bundle.main.url(forResource: "silence", withExtension: "caf"),
              let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.numberOfLoops = -1
        player.volume = 1.0
        player.prepareToPlay()
        player.play()
        silencePlayer = player
    }

    private func playAlarm() {
        configureSession(solo: true)   // 무음모드·잠금 관통, 단독 점유
        guard let url = Bundle.main.url(forResource: "alarm", withExtension: "caf"),
              let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.numberOfLoops = -1
        player.volume = 1.0
        player.prepareToPlay()
        player.play()
        alarmPlayer = player
    }

    // MARK: - 내부: 타이머/발사 시각

    /// nextAcrossAll(전체 활성 알람)과 pendingSnooze 중 가장 가까운 미래 발사.
    private func nearestFire(excludingReminder: UUID? = nil) -> (id: UUID, date: Date, isSnooze: Bool)? {
        var best: (id: UUID, date: Date, isSnooze: Bool)?
        if let r = NextFireDate.nextAcrossAll(in: modelContext, excluding: excludingReminder) {
            best = (r.id, r.date, false)
        }
        if let s = pendingSnooze, best == nil || s.date < best!.date {
            best = (s.id, s.date, true)
        }
        return best
    }

    private func scheduleNextFire(excludingReminder: UUID? = nil) {
        fireTimer?.cancel(); fireTimer = nil
        guard let fire = nearestFire(excludingReminder: excludingReminder) else {
            scheduledFire = nil
            return
        }
        scheduledFire = fire
        let delay = max(0, fire.date.timeIntervalSinceNow)
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + delay, leeway: .seconds(1))
        timer.setEventHandler { [weak self] in
            Task { @MainActor in self?.fireAlarm() }
        }
        timer.resume()
        fireTimer = timer
    }

    private func scheduleAutoStop() {
        autoStopWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.stopRinging() }
        }
        autoStopWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + autoStopAfter, execute: work)
    }

    // MARK: - 내부: 인터럽션/리셋 복구

    private func handleInterruption(typeRaw: UInt) {
        guard let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else { return }
        if type == .ended {
            try? AVAudioSession.sharedInstance().setActive(true)
            if isRinging { alarmPlayer?.play() } else { silencePlayer?.play() }
        }
    }

    private func handleMediaReset() {
        // 오디오 데몬 재시작 → 모든 플레이어 무효화. 현재 상태대로 재생성.
        let wasRinging = isRinging
        silencePlayer = nil
        startSilence()
        if wasRinging { playAlarm() }
    }

    private func fetch(id: UUID) -> Reminder? {
        let descriptor = FetchDescriptor<Reminder>(predicate: #Predicate { $0.id == id })
        return try? modelContext.fetch(descriptor).first
    }
}
