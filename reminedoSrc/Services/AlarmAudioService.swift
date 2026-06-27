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
import AudioToolbox
import Foundation
import MediaPlayer
import SwiftData
import UIKit

@MainActor
@Observable
final class AlarmAudioService {
    static let shared = AlarmAudioService()

    private let modelContext = SharedModelContainer.shared.mainContext

    private var silencePlayer: AVAudioPlayer?
    private var alarmPlayer: AVAudioPlayer?
    private var fireTimer: DispatchSourceTimer?
    private var autoStopWork: DispatchWorkItem?
    /// 이슈7: 알람 울리는 동안 반복 진동 타이머.
    private var vibrationTimer: DispatchSourceTimer?
    /// 이슈9: 백그라운드 동안 watchdog를 주기 재예약하는 타이머(앱 사망 시 미예약 → 발화).
    private var watchdogTimer: DispatchSourceTimer?

    /// 타이머가 무엇을 위해 걸렸는지(발사 시 어느 알람/스누즈인지 식별).
    private var scheduledFire: (id: UUID, date: Date, isSnooze: Bool)?
    /// 진행 중 스누즈 발사 예정(Reminder 모델 밖의 1회성). keep-alive가 nextAcrossAll과 함께 고려.
    private var pendingSnooze: (id: UUID, date: Date)?

    private(set) var isRinging = false
    private var ringingReminderID: UUID?

    /// 사용자가 앱을 안 열면 무한 재생되는 것 방지(분 단위).
    private let autoStopAfter: TimeInterval = 5 * 60

    // MARK: - 볼륨 부스트(알라미 방식)
    // 무음 스위치는 .playback 세션이 이미 뚫지만, 사용자가 미디어 볼륨을 낮춰뒀으면 작게 난다.
    // 발사 시 시스템 미디어 볼륨을 최대로 끌어올리고(부스트), 종료 시 원래 값으로 복원한다.
    // 시스템 볼륨 쓰기는 MPVolumeView의 내부 슬라이더가 유일한 공개 경로(슬라이더는 윈도 계층에 있어야 동작).
    // ※ 한계: 백그라운드 윈도 비활성 시 슬라이더 쓰기가 무동작일 수 있음(실기기 검증 필요, best-effort).
    // ※ force-quit 안전: 부스트 직전 원래 볼륨을 UserDefaults에도 저장 → 복원 못 하고 죽어도
    //   다음 실행(.active → stop → restoreSystemVolume)에서 잔존 값으로 복구한다.

    /// 화면 밖·투명으로 부착하는 볼륨 제어용 뷰. subview의 UISlider로 시스템 미디어 볼륨을 조작한다.
    /// (@Observable 매크로는 lazy 저장 프로퍼티를 추적할 수 없어 관찰 대상에서 제외.)
    @ObservationIgnored private lazy var volumeView: MPVolumeView = {
        let view = MPVolumeView(frame: CGRect(x: -2000, y: -2000, width: 1, height: 1))
        view.alpha = 0.001
        view.isUserInteractionEnabled = false
        return view
    }()
    /// 부스트 직전 시스템 볼륨(복원용). 부스트 중에만 값을 보유한다.
    private var savedSystemVolume: Float?
    /// 페이드인: 플레이어 상대 볼륨을 이 값에서 1.0까지 fadeInDuration 동안 끌어올린다.
    private let fadeInStartVolume: Float = 0.1
    private let fadeInDuration: TimeInterval = 5

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

    /// 런치 시 호출: 이전 세션이 부스트 중 강제종료돼 사용자 볼륨이 최대로 잔존하면 원래 값으로 복구.
    /// (.active onChange는 cold launch 초기값엔 안 fire될 수 있어 별도 진입점이 필요하다.)
    func recoverBoostedVolumeIfNeeded() {
        guard savedSystemVolume == nil, persistedBoostVolume() != nil else { return }
        // 사용자가 force-quit 후 직접 볼륨을 바꿨거나(현재값이 부스트값에서 벗어남), 부스트가 애초에
        // 시스템 볼륨을 못 올렸으면 강제 되돌릴 필요가 없다 → persisted만 정리하고 종료.
        let live = AVAudioSession.sharedInstance().outputVolume
        guard live >= 0.95 else { clearPersistedBoostVolume(); return }
        retryRecovery(attemptsLeft: 5)   // cold launch 직후 슬라이더 미준비 대비 짧은 재시도.
    }

    /// 잔존 볼륨 복구를 슬라이더가 준비될 때까지 짧게 재시도(0.3s 간격). 성공하면 persisted가 비워져 중단.
    private func retryRecovery(attemptsLeft: Int) {
        guard persistedBoostVolume() != nil, attemptsLeft > 0 else { return }
        restoreSystemVolume()
        guard persistedBoostVolume() != nil else { return }   // 복구 성공 → 종료.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            MainActor.assumeIsolated { AlarmAudioService.shared.retryRecovery(attemptsLeft: attemptsLeft - 1) }
        }
    }

    /// 백그라운드 진입 시: 미래 발사가 있으면 무음 루프 시작 + 다음 발사 타이머. 없으면 정지.
    func startKeepAlive() {
        guard nearestFire() != nil else { stop(); return }
        startSilence()
        ensureVolumeViewInHierarchy()   // 발사 전 미리 부착해 백그라운드 발사 시 슬라이더가 준비되도록.
        scheduleNextFire()
        startWatchdog()   // 이슈9: 백그라운드 동안 watchdog 주기 재예약.
    }

    /// 포그라운드 진입/알람 없음: 전부 정지 + 세션 비활성. pendingSnooze(in-memory)는 유지.
    func stop() {
        fireTimer?.cancel(); fireTimer = nil
        scheduledFire = nil
        autoStopWork?.cancel(); autoStopWork = nil
        stopVibration()   // 이슈7
        stopWatchdog()    // 이슈9: 백그라운드 주기 타이머 정지.
        // 이슈9: 포그라운드(=살아있음)에선 watchdog가 발화하면 안 된다 — pending도 함께 제거.
        // (clearDelivered는 전환 직전 이미 도달한 것 정리; cancel은 남은 예약 제거.)
        WatchdogScheduler.cancel()
        WatchdogScheduler.clearDelivered()
        restoreSystemVolume()   // 부스트했었다면 원래 시스템 볼륨으로 복원.
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
        stopVibration()   // 이슈7
        restoreSystemVolume()   // 부스트 복원.
        isRinging = false
        ringingReminderID = nil
        autoStopWork?.cancel(); autoStopWork = nil
        if silencePlayer != nil { scheduleNextFire() }   // keep-alive 중일 때만 타이머 운용
    }

    /// 다시 알림: 풀볼륨 정지 + minutes 뒤 재발사 등록(오디오). UN 재예약·LA 갱신은 호출부가 처리.
    func snooze(reminderID: UUID, minutes: Int) {
        alarmPlayer?.stop(); alarmPlayer = nil
        stopVibration()   // 이슈7
        restoreSystemVolume()   // 부스트 복원(다음 발사 때 다시 부스트).
        isRinging = false
        autoStopWork?.cancel(); autoStopWork = nil
        ringingReminderID = nil
        pendingSnooze = (reminderID, Date().addingTimeInterval(TimeInterval(max(1, minutes) * 60)))
        // 이슈5(a): 일회성 알람이 fireAlarm(:122)에서 isEnabled=false로 꺼졌어도, 스누즈 대기 중엔
        // 홈이 켜짐으로 표시되도록 재활성화. (스누즈 종료 후엔 disableFiredOneShots가 다시 정리.)
        if let reminder = fetch(id: reminderID), !reminder.isEnabled {
            reminder.isEnabled = true
            try? modelContext.save()
        }
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
            startVibration()   // 이슈7: 소리와 함께 반복 진동.
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
        boostSystemVolume()   // 시스템 미디어 볼륨 최대로(원래 값 저장). 재생 확정 후에만 부스트.
        player.numberOfLoops = -1
        player.volume = fadeInStartVolume   // 페이드인 시작점(작게 시작).
        player.prepareToPlay()
        player.play()
        player.setVolume(1.0, fadeDuration: fadeInDuration)   // fadeInDuration 동안 풀볼륨까지 부드럽게 상승.
        alarmPlayer = player
    }

    // MARK: - 내부: 볼륨 부스트/복원

    /// 시스템 미디어 볼륨을 최대로 올린다. 원래 값은 savedSystemVolume + UserDefaults에 1회만 저장(복원용).
    private func boostSystemVolume() {
        ensureVolumeViewInHierarchy()
        if savedSystemVolume == nil {
            // 이전 세션의 미복구 잔존이 있으면 그 값이 진짜 원래 볼륨이다(현재값은 잔존 1.0일 수 있어 신뢰 불가).
            // → persisted를 우선 채택해, 복구 실패 후 재부스트로 진짜 원래값이 손실되는 것을 막는다.
            let original = persistedBoostVolume() ?? AVAudioSession.sharedInstance().outputVolume
            savedSystemVolume = original
            persistBoostVolume(original)   // force-quit 복구용 영구 저장.
        }
        setSystemVolume(1.0)
    }

    /// 원래 시스템 볼륨으로 복원. 인메모리 값 우선, 없으면 UserDefaults 잔존값(force-quit 후 다음 실행).
    /// 슬라이더가 아직 준비 안 돼 실제 적용에 실패하면 잔존값을 남겨 다음 .active에서 재시도한다.
    private func restoreSystemVolume() {
        guard let target = savedSystemVolume ?? persistedBoostVolume() else { return }
        ensureVolumeViewInHierarchy()
        guard setSystemVolume(target) else { return }   // 적용 실패(슬라이더 미준비) 시 잔존값 보존 → 재시도.
        savedSystemVolume = nil
        clearPersistedBoostVolume()
    }

    private func persistBoostVolume(_ value: Float) {
        UserDefaults.standard.set(Double(value), forKey: SharedConstants.UserDefaultsKey.boostedSystemVolume)
    }

    private func persistedBoostVolume() -> Float? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: SharedConstants.UserDefaultsKey.boostedSystemVolume) != nil else { return nil }
        return Float(defaults.double(forKey: SharedConstants.UserDefaultsKey.boostedSystemVolume))
    }

    private func clearPersistedBoostVolume() {
        UserDefaults.standard.removeObject(forKey: SharedConstants.UserDefaultsKey.boostedSystemVolume)
    }

    /// 시스템 볼륨 적용. 슬라이더가 없으면(미부착/레이아웃 전) false 반환(호출부가 재시도 판단).
    @discardableResult
    private func setSystemVolume(_ value: Float) -> Bool {
        guard let slider = volumeSlider else { return false }
        slider.value = max(0, min(1, value))
        return true
    }

    private var volumeSlider: UISlider? {
        volumeView.subviews.compactMap { $0 as? UISlider }.first
    }

    /// MPVolumeView는 윈도 계층에 부착돼야 내부 슬라이더가 동작한다. 화면 밖·투명으로 1회 부착.
    private func ensureVolumeViewInHierarchy() {
        guard volumeView.superview == nil, let window = activeWindow() else { return }
        window.addSubview(volumeView)
        volumeView.layoutIfNeeded()   // 슬라이더 subview 즉시 생성 유도.
    }

    private func activeWindow() -> UIWindow? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        return windows.first { $0.isKeyWindow } ?? windows.first
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

    // MARK: - 진동(이슈7)

    /// 알람 울리는 동안 ~1.5s 간격 반복 진동. 무음모드에서도 진동으로 알람 인지.
    private func startVibration() {
        vibrationTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: 1.5)
        timer.setEventHandler {
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
        timer.resume()
        vibrationTimer = timer
    }

    private func stopVibration() {
        vibrationTimer?.cancel(); vibrationTimer = nil
    }

    // MARK: - watchdog(이슈9, dead-man's switch)

    /// 백그라운드 동안 watchdog 알림을 주기 재예약. 앱이 죽으면 이 타이머가 멈추고,
    /// 마지막으로 예약한 watchdog가 ~N분 뒤 발화("앱을 다시 켜주세요").
    private func startWatchdog() {
        watchdogTimer?.cancel()
        WatchdogScheduler.reschedule()   // 즉시 1회 밀어두기.
        let timer = DispatchSource.makeTimerSource(queue: .main)
        // 만료(intervalMinutes*60=300s)까지 큰 안전마진을 두려고 만료 창과 무관하게 60초마다 재예약.
        // 마진 = 300 - 60 = 240초 → 백그라운드 throttle/짧은 인터럽트에도 오발화 방지.
        let period: TimeInterval = 60
        timer.schedule(deadline: .now() + period, repeating: period)
        timer.setEventHandler {
            WatchdogScheduler.reschedule()
        }
        timer.resume()
        watchdogTimer = timer
    }

    private func stopWatchdog() {
        watchdogTimer?.cancel(); watchdogTimer = nil
    }

    // MARK: - 내부: 인터럽션/리셋 복구

    private func handleInterruption(typeRaw: UInt) {
        guard let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else { return }
        guard type == .ended else { return }
        // .shouldResume 권고와 무관하게 항상 복구 시도(놓치면 watchdog 오발화).
        try? AVAudioSession.sharedInstance().setActive(true)
        if isRinging {
            alarmPlayer?.play()
        } else if silencePlayer != nil {
            silencePlayer?.play()
        } else if UIApplication.shared.applicationState == .background, nearestFire() != nil {
            // 백그라운드에서 인터럽트로 무음/타이머/watchdog가 죽었으면 keep-alive 전체를 재구성(원인 B 복구).
            // 포그라운드는 인앱 UI/scenePhase(.active→stop)가 담당하므로 여기서 keep-alive를 켜지 않는다.
            startKeepAlive()
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
