//
//  ReminedoApp.swift
//  reminedo
//
//  앱 진입점. App Group 공유 SwiftData 컨테이너 주입(§7·§14.2), AppState 환경 주입,
//  알림 카테고리 등록(§4.5), 딥링크 라우팅 골격(§4.11). 다크 강제는 Info.plist + 여기 모두.
//

import SwiftUI
import SwiftData
import UserNotifications

@main
struct ReminedoApp: App {
    @Environment(\.scenePhase) private var scenePhase

    @State private var appState = AppState()

    /// 앱 전역 단일 NotificationService(§refactor). delegate가 스누즈를 이걸로 걸고, 화면들이
    /// 권한 상태를 관찰하며, 공유 SwiftData 컨텍스트로 알람을 조회/영속한다.
    @State private var notificationService = NotificationService()

    /// 삭제 Undo의 지연 삭제 상태(§4.3) — 환경 주입.
    @State private var deletionManager = DeletionManager()

    /// 이미지 영속 단일 서비스(§4.7) — NotificationService와 동류로 환경 주입.
    @State private var imageStore = ImageStore()

    /// 스누즈 카운트다운 Live Activity 관리(§4.6 확장) — lock 화면이 주입받아 시작, delegate가 종료.
    @State private var snoozeActivity = SnoozeActivityController()

    /// 백그라운드 오디오 알람(§오디오 알람) — keep-alive + 풀볼륨 + 인터럽션 복구. shared(백그라운드 타이머 접근).
    @State private var alarmAudio = AlarmAudioService.shared

    /// UN delegate는 콜드스타트 탭을 놓치지 않도록 UI보다 먼저 등록·보존한다(§4.11).
    private let notificationDelegate: NotificationDelegate

    init() {
        NotificationCategories.register()
        // 의존 순서(§refactor): appState → notificationService → activity → delegate → UNUC delegate.
        let appState = AppState()
        _appState = State(initialValue: appState)
        let notificationService = NotificationService()
        _notificationService = State(initialValue: notificationService)
        let snoozeActivity = SnoozeActivityController()
        _snoozeActivity = State(initialValue: snoozeActivity)
        let alarmAudio = AlarmAudioService.shared
        _alarmAudio = State(initialValue: alarmAudio)
        let delegate = NotificationDelegate(
            appState: appState,
            notificationService: notificationService,
            snoozeActivity: snoozeActivity,
            alarmAudio: alarmAudio
        )
        notificationDelegate = delegate
        UNUserNotificationCenter.current().delegate = delegate
        // BGTask 백그라운드 복구(§9 Phase 5 후보). 핸들러 등록은 finishLaunching 이전(여기)에 1회.
        BackgroundRefreshManager.register(notificationService: notificationService)
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(appState)
                .environment(notificationService)
                .environment(deletionManager)
                .environment(imageStore)
                .environment(snoozeActivity)
                .environment(alarmAudio)
                .preferredColorScheme(.dark)
                .onOpenURL { handleURL($0) }
                .task { processPendingImageDeletes() }
        }
        .modelContainer(SharedModelContainer.shared)
        // 백그라운드 진입 시: BGAppRefreshTask 예약 + 오디오 keep-alive 시작.
        // 활성화 시: 만료 스누즈 LA 정리 + 발사된 일회성 알람 정리 + 오디오 keep-alive 종료(포그라운드는 인앱 UI가 처리).
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                BackgroundRefreshManager.schedule()
                WatchdogScheduler.reschedule()
                alarmAudio.startKeepAlive()
            case .active:
                WatchdogScheduler.cancel()
                snoozeActivity.endExpired()
                notificationService.disableFiredOneShots()
                alarmAudio.stop()
            default: break
            }
        }
    }

    /// reminedo://edit/{uuid} → .edit(위젯·Phase 6) / reminedo://add → 공유(Phase 4).
    private func handleURL(_ url: URL) {
        guard url.scheme == SharedConstants.urlScheme else { return }
        switch url.host {
        case "act":
            // 스누즈 카운트다운 Live Activity 탭 → 알림 본문 탭과 동일하게 인앱 lock 화면(.act)으로.
            // lock 화면에서 "다시 알림"을 누르면 다시 스누즈가 걸리고 새 카운트다운이 떠 반복 가능하다.
            if let last = url.pathComponents.last, let uuid = UUID(uuidString: last) {
                appState.pendingRoute = .act(uuid)
            }
        case "edit":
            if let last = url.pathComponents.last, let uuid = UUID(uuidString: last) {
                appState.pendingRoute = .edit(uuid)
            }
        case "add":
            // 공유 확장에서 가져온 URL/사진을 메인 앱의 알림 추가 시트로 넘긴다.
            // 실제 저장, 검증, 예약은 앱의 기존 생성 흐름을 그대로 사용한다.
            if let payload = SharePayload.consume() {
                appState.pendingAddURL = payload.url
                appState.pendingAddImageImportFileName = payload.imageFileName
            }
            appState.pendingAddRequested = true
        default:
            break
        }
    }

    /// 앱 시작 시 지연 삭제 큐(UserDefaults `pendingImageDeletes`)를 정리한다(§4.3/§4.7).
    /// 삭제 커밋 시 적재된 이미지 파일명을 실제 파일에서 지우고 큐를 비운다(best-effort).
    private func processPendingImageDeletes() {
        let key = SharedConstants.UserDefaultsKey.pendingImageDeletes
        let queue = UserDefaults.standard.stringArray(forKey: key) ?? []
        guard !queue.isEmpty else { return }
        imageStore.deleteAll(in: queue)
        UserDefaults.standard.removeObject(forKey: key)
    }
}
