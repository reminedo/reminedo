//
//  SettingsScreen.swift
//  reminedo
//
//  설정 탭(§3.6). grouped List · 다크. 권한 상태/동작 안내/앱 정보/데이터 삭제.
//  서비스(NotificationService·ImageStore)는 환경 주입을 그대로 쓰고(thin view, fat service),
//  사운드 기본값·플래그는 UserDefaults(@AppStorage)로 둔다. 온보딩 플래그는 데이터 삭제에서 유지한다.
//

import SwiftUI
import SwiftData

struct SettingsScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(NotificationService.self) private var notificationService
    @Environment(ImageStore.self) private var imageStore

    /// 신규 알람 기본 사운드(§3.6). SoundType.rawValue 저장. ReminderEditSheet 추가 모드가 읽는다.
    @AppStorage(SharedConstants.UserDefaultsKey.defaultSound) private var defaultSoundRaw = SoundType.defaultSound.rawValue

    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationStack {
            List {
                permissionSection
                behaviorSection
                infoSection
                dataSection
            }
            .scrollContentBackground(.hidden)
            .background(Tokens.Palette.background)
            .navigationTitle(Strings.Settings.title)
            .confirmationDialog(
                Strings.Settings.deleteAllConfirmTitle,
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button(Strings.Settings.deleteAllConfirm, role: .destructive) { deleteAllData() }
                Button(Strings.Settings.deleteAllCancel, role: .cancel) {}
            } message: {
                Text(Strings.Settings.deleteAllMessage)
            }
        }
    }

    // MARK: - 1. 알림 권한

    private var permissionSection: some View {
        Section(Strings.Settings.permissionSection) {
            HStack {
                Image(systemName: notificationService.isAuthorized ? "bell.fill" : Tokens.Symbols.muted)
                    .foregroundStyle(notificationService.isAuthorized ? Tokens.Palette.accent : Tokens.Palette.textSecondary)
                Text(permissionStatusText)
                    .foregroundStyle(Tokens.Palette.textPrimary)
            }
            Button(Strings.Settings.openSystemSettings, action: openSystemSettings)
                .foregroundStyle(Tokens.Palette.accent)
        }
        .listRowBackground(Tokens.Palette.card)
    }

    private var permissionStatusText: String {
        switch notificationService.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return Strings.Settings.permissionOn
        case .denied: return Strings.Settings.permissionOff
        default: return Strings.Settings.permissionUndetermined
        }
    }

    // MARK: - 2. 알림 동작 안내

    private var behaviorSection: some View {
        Section(Strings.Settings.behaviorSection) {
            HStack(spacing: Tokens.Spacing.row) {
                Image(systemName: "moon.fill")
                    .foregroundStyle(Tokens.Palette.textSecondary)
                Text(Strings.Settings.behaviorInfo)
                    .font(.subheadline)
                    .foregroundStyle(Tokens.Palette.textSecondary)
            }
        }
        .listRowBackground(Tokens.Palette.card)
    }

    // MARK: - 3. 앱 정보

    private var infoSection: some View {
        Section(Strings.Settings.infoSection) {
            HStack {
                Text(Strings.Settings.versionLabel)
                    .foregroundStyle(Tokens.Palette.textPrimary)
                Spacer()
                Text(Strings.Settings.versionText(appVersion, build: appBuild))
                    .foregroundStyle(Tokens.Palette.textSecondary)
            }
        }
        .listRowBackground(Tokens.Palette.card)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private var appBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    // MARK: - 4. 데이터 삭제

    private var dataSection: some View {
        Section(Strings.Settings.dataSection) {
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "trash")
                    Text(Strings.Settings.deleteAll)
                }
                .foregroundStyle(Tokens.Palette.destructive)
            }
        }
        .listRowBackground(Tokens.Palette.card)
    }

    // MARK: - 동작

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// 모든 데이터 삭제(§3.6): 알람 레코드 + 이미지 파일 + 사운드 설정만 삭제하고
    /// 온보딩 플래그(hasOnboarded·hasSeenLockHint)는 유지한다.
    private func deleteAllData() {
        // 1) 모든 pending 로컬 알림 취소.
        notificationService.cancelAll()
        // 2) 모든 Reminder 레코드 삭제.
        if let all = try? modelContext.fetch(FetchDescriptor<Reminder>()) {
            for reminder in all { modelContext.delete(reminder) }
            try? modelContext.save()
        }
        // 3) 모든 이미지 파일 삭제(메인·링크 썸네일 포함, reminder-images 디렉터리 통째로).
        imageStore.deleteAllImages()
        // 4) 지연 삭제 큐도 비운다(더 이상 가리킬 파일 없음).
        UserDefaults.standard.removeObject(forKey: SharedConstants.UserDefaultsKey.pendingImageDeletes)
        // 5) 사운드 설정만 초기화(온보딩 플래그는 유지 — §3.6).
        UserDefaults.standard.removeObject(forKey: SharedConstants.UserDefaultsKey.defaultSound)
        defaultSoundRaw = SoundType.defaultSound.rawValue
    }
}

#Preview {
    SettingsScreen()
        .modelContainer(for: Reminder.self, inMemory: true)
        .environment(NotificationService())
        .environment(ImageStore())
        .preferredColorScheme(.dark)
}
