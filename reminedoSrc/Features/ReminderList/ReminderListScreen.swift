//
//  ReminderListScreen.swift
//  reminedo
//
//  알림 목록 화면(§3.2). @Query로 알람을 읽어 시·분 오름차순(동시각 tie-break createdAt)으로
//  정렬해 표시한다. Off 알람도 같은 순서·흐림 처리. 우상단 +로 추가 시트, 셀 탭→편집 시트.
//  Phase 1b: 권한 배너(§3.2)·삭제 Undo 스낵바(§4.3)·예약 실패 한도 안내(§4.12)·
//  scenePhase==.active 권한 재조회/재시도(§4.12) 책임을 List 루트가 가진다.
//

import SwiftUI
import SwiftData

struct ReminderListScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppState.self) private var appState
    @Environment(NotificationService.self) private var notificationService
    @Environment(DeletionManager.self) private var deletionManager
    @Environment(SnoozeActivityController.self) private var snoozeActivity
    @Query private var reminders: [Reminder]

    @State private var editTarget: Reminder?
    @State private var showingAdd = false
    @State private var showLimitAlert = false
    @State private var snackbarTask: Task<Void, Never>?

    /// 첫 알람 저장 후 1회 잠금화면 사용법 안내(§13.8). hasSeenLockHint로 게이팅.
    @AppStorage(SharedConstants.UserDefaultsKey.hasSeenLockHint) private var hasSeenLockHint = false
    @State private var showLockHint = false

    /// 공유 진입 시 추가 시트에 넣을 프리필 URL(§2.3/§4.10). showingAdd와 함께 소비된다.
    @State private var addPrefillURL: String?

    /// 정렬은 §3.2 시·분 기준(nextFireDate 아님). 지연 삭제 대기 알람은 목록에서 숨긴다(§4.3).
    private var sortedReminders: [Reminder] {
        let calendar = Calendar.current
        return reminders
            .filter { !deletionManager.isPendingDeletion($0.id) }
            .sorted { lhs, rhs in
                let l = calendar.dateComponents([.hour, .minute], from: lhs.scheduledAt)
                let r = calendar.dateComponents([.hour, .minute], from: rhs.scheduledAt)
                if l.hour != r.hour { return (l.hour ?? 0) < (r.hour ?? 0) }
                if l.minute != r.minute { return (l.minute ?? 0) < (r.minute ?? 0) }
                return lhs.createdAt < rhs.createdAt
            }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Tokens.Palette.background.ignoresSafeArea()
                mainContent
                snackbarOverlay
                lockHintOverlay
            }
            // 커스텀 헤더(home.png: "알림"+"+" 동일선상)를 쓰므로 네비바는 숨긴다.
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingAdd, onDismiss: consumePendingAfterSheetClose) {
                ReminderEditSheet(mode: .add, prefillURL: addPrefillURL)
            }
            .sheet(item: $editTarget, onDismiss: consumePendingAfterSheetClose) { reminder in
                ReminderEditSheet(mode: .edit(reminder))
            }
            // (Phase 5) 권한 요청은 온보딩(§3.7)에서만 — 여기 임시 .task 요청은 이중 프롬프트 방지를 위해 제거됨.
            // scenePhase==.active: 권한 재조회 + 실패 알람 자동 재시도(§4.12).
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { handleSceneActive() }
            }
            // 첫 알람 저장(빈 목록→비어있지 않음) 시 1회 잠금화면 힌트(§13.8).
            .onChange(of: sortedReminders.isEmpty) { wasEmpty, isEmpty in
                if wasEmpty && !isEmpty && !hasSeenLockHint { presentLockHint() }
            }
            // onOpenURL이 앱 활성 중 도착하면 scenePhase 전이가 없을 수 있어 별도로 소비한다(§4.10).
            .onChange(of: appState.pendingAddRequested) { _, requested in
                if requested { consumePendingAddIfNeeded() }
            }
            // 위젯 딥링크 .edit(§14.5/§4.11) → 편집 시트. 활성 중 onOpenURL이 도착하면 scenePhase
            // 전이가 없을 수 있어 pendingRoute 변경도 별도로 관찰해 소비한다.
            .onChange(of: appState.pendingRoute) { _, _ in
                if scenePhase == .active { consumePendingEditIfNeeded() }
            }
            .onChange(of: deletionManager.snackbarReminderID) { _, id in
                if id != nil { scheduleSnackbarExpiry(for: id!) }
            }
            .onAppear { handleSceneActive() }
            .alert(Strings.Scheduling.limitTitle, isPresented: $showLimitAlert) {
                Button(Strings.Scheduling.limitConfirm, role: .cancel) {}
            } message: {
                Text(Strings.Scheduling.limitMessage)
            }
            // 알림 O / 딥링크 라우팅 소비(§4.11).
            .overlay { ActionRouterView() }
        }
    }

    // MARK: - 콘텐츠

    /// 헤더는 항상 최상위에 렌더(빈 상태에서도 "알림"·+ 유지) → 그 아래에서만 빈/리스트 분기.
    private var mainContent: some View {
        VStack(spacing: 0) {
            header
            if !notificationService.isAuthorized {
                PermissionBanner(onOpenSettings: openSettings)
                    .padding(.horizontal, Tokens.Spacing.gutter)
                    .padding(.top, Tokens.Spacing.row)
            }
            if sortedReminders.isEmpty {
                emptyState
                    .frame(maxHeight: .infinity)
            } else {
                list
            }
        }
    }

    /// home.png 헤더: 좌측 "알림"(라지·볼드) + 우측 + 버튼이 같은 baseline.
    private var header: some View {
        HStack {
            Text(Strings.List.title)
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(Tokens.Palette.textPrimary)
            Spacer()
            Button {
                showingAdd = true
            } label: {
                Image(systemName: "plus")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Tokens.Palette.accent)
            }
            .accessibilityLabel(Strings.List.add)
        }
        .padding(.horizontal, Tokens.Spacing.gutter)
        .padding(.top, Tokens.Spacing.row)
        .padding(.bottom, 4)
    }

    private var list: some View {
        List {
            ForEach(sortedReminders) { reminder in
                ReminderCell(
                    reminder: reminder,
                    onTap: { editTarget = reminder },
                    onWarningTap: { showLimitAlert = true }
                )
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: Tokens.Spacing.gutter, bottom: 6, trailing: Tokens.Spacing.gutter))
                .listRowBackground(Color.clear)
                // 스와이프 삭제(이슈3): trailing 스와이프 → 기존 삭제/Undo 파이프라인 재사용(§4.3).
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        swipeDelete(reminder)
                    } label: {
                        Label(Strings.Edit.delete, systemImage: "trash")
                    }
                    .tint(.red)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Tokens.Palette.background)
        // 마지막 셀이 탭 바에 가리지 않도록 여백 확보(§3.1).
        .scrollDismissesKeyboard(.immediately)
    }

    /// 스와이프 삭제(이슈3): pending 취소 + 스누즈 LA 종료 + 지연 삭제 큐 등록.
    /// 기존 스낵바·commit 파이프라인(scheduleSnackbarExpiry/commitDelete)이 deletionManager
    /// snackbarReminderID onChange로 자동 연동된다(§4.3). Undo = reschedule로 복구.
    private func swipeDelete(_ reminder: Reminder) {
        notificationService.cancel(reminder)
        snoozeActivity.end(reminderID: reminder.id)
        deletionManager.enqueue(reminder.id)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: Tokens.Symbols.tabReminders)
                .font(.system(size: 44))
                .foregroundStyle(Tokens.Palette.accent)
            Text(Strings.Empty.title)
                .font(.headline)
                .foregroundStyle(Tokens.Palette.textPrimary)
            Text(Strings.Empty.message)
                .font(.subheadline)
                .foregroundStyle(Tokens.Palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    // MARK: - 스낵바 / 토스트

    @ViewBuilder
    private var snackbarOverlay: some View {
        if let id = deletionManager.snackbarReminderID {
            VStack {
                Spacer()
                UndoSnackbar(onUndo: { undoDelete(id) })
                    .padding(.bottom, 90)
            }
        }
    }

    /// 첫 알람 저장 후 1회 노출되는 잠금화면 사용법 토스트(§13.8). 탭/자동만료로 닫힌다.
    @ViewBuilder
    private var lockHintOverlay: some View {
        if showLockHint {
            VStack {
                HStack(spacing: 8) {
                    Image(systemName: "hand.tap")
                    Text(Strings.LockHint.message)
                        .font(.subheadline.weight(.medium))
                }
                .foregroundStyle(Tokens.Palette.textPrimary)
                .padding(.horizontal, Tokens.Spacing.gutter)
                .padding(.vertical, Tokens.Spacing.row)
                .frame(maxWidth: .infinity)
                .background(Tokens.Palette.card)
                .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous)
                        .strokeBorder(Tokens.Palette.accent.opacity(0.5), lineWidth: 1)
                )
                .padding(.horizontal, Tokens.Spacing.gutter)
                .padding(.top, Tokens.Spacing.row)
                .onTapGesture { dismissLockHint() }
                .transition(.move(edge: .top).combined(with: .opacity))
                Spacer()
            }
        }
    }

    // MARK: - 동작

    /// 잠금화면 힌트 표시 + 플래그 set(1회). ~4초 후 자동 만료(§13.8).
    private func presentLockHint() {
        hasSeenLockHint = true
        withAnimation { showLockHint = true }
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            dismissLockHint()
        }
    }

    private func dismissLockHint() {
        withAnimation { showLockHint = false }
    }

    private func handleSceneActive() {
        Task { await notificationService.refreshAuthorization() }
        notificationService.retryFailedScheduling()
        consumePendingAddIfNeeded()
        consumePendingEditIfNeeded()
    }

    /// 위젯 딥링크 .edit(§14.5)를 1회 소비해 편집 시트를 연다(reminedo://edit/{uuid}).
    /// 폐기 가드(§3.3/§4.11): 편집/추가 시트가 이미 떠 있으면(=작성 중) 강제 dismiss하지 않고
    /// 라우트를 보류한다. 사용자가 현재 시트를 닫는 시점(onDismiss)에서 다시 호출돼 그때 소비한다 —
    /// 이로써 "변경 사항을 버릴까요?" 가드가 현재 시트에 그대로 적용된다(실수 복구 §13.5).
    /// 삭제된 reminder면 무시(consume-once).
    private func consumePendingEditIfNeeded() {
        guard case .edit(let id)? = appState.pendingRoute else { return }
        // 시트 작성 중이면 보류(route 유지) — 닫힐 때 onDismiss에서 재호출된다.
        guard !showingAdd, editTarget == nil else { return }
        appState.pendingRoute = nil   // consume-once
        guard let reminder = fetch(id: id) else { return }   // 삭제됐으면 무시
        editTarget = reminder
    }

    /// 시트가 닫힌 직후 보류된 트리거(공유 추가 / 위젯 편집)를 그때 소비한다(폐기 가드 후속 처리).
    /// 한 시트가 닫히자마자 다른 시트를 같은 런루프에 띄우면 SwiftUI가 표시를 놓칠 수 있어
    /// add는 즉시, edit은 다음 틱으로 흘려 충돌을 피한다.
    private func consumePendingAfterSheetClose() {
        consumePendingAddIfNeeded()
        DispatchQueue.main.async { consumePendingEditIfNeeded() }
    }

    /// 공유 추가 트리거(§2.3/§4.10)를 1회 소비해 프리필 추가 시트를 연다.
    /// 폐기 가드(§3.3/§4.10): 추가/수정 시트가 이미 떠 있으면(=작성 중) 기존 시트를 강제로
    /// 덮어쓰지 않고 트리거를 보류한다. 시트를 사용자가 닫는 시점(onDismiss)에서 다시 이 함수가
    /// 호출되어 보류된 트리거를 그때 소비한다. 이로써 §3.3 "변경 사항을 버릴까요?" 가드가
    /// 현재 시트에 그대로 적용되고(취소 흐름은 ReminderEditSheet가 담당), 공유 프리필은
    /// 안전하게 큐잉되어 사용자 입력을 잃지 않는다.
    private func consumePendingAddIfNeeded() {
        guard appState.pendingAddRequested else { return }
        // 시트 작성 중이면 보류(트리거 플래그 유지) — 닫힐 때 onDismiss에서 재호출된다.
        guard !showingAdd, editTarget == nil else { return }
        addPrefillURL = appState.pendingAddURL
        appState.pendingAddURL = nil
        appState.pendingAddRequested = false
        showingAdd = true
    }

    /// 스낵바 ~4초 자동 만료 → 실제 삭제 커밋(§4.3).
    private func scheduleSnackbarExpiry(for id: UUID) {
        snackbarTask?.cancel()
        snackbarTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            commitDelete(id)
        }
    }

    /// Undo(§4.3): 등록 해제 + reschedule(레코드가 그대로라 복구).
    private func undoDelete(_ id: UUID) {
        snackbarTask?.cancel()
        deletionManager.undo(id)
        if let reminder = fetch(id: id) {
            notificationService.reschedule(reminder)
        }
    }

    /// 실제 삭제 커밋: modelContext.delete + 이미지명 enqueue(Phase 3 정리) + 자동 재시도.
    private func commitDelete(_ id: UUID) {
        guard let reminder = fetch(id: id) else {
            deletionManager.clear(id)
            return
        }
        // 이미지·링크 썸네일 파일명을 모두 지연 삭제 큐에 적재(§4.3/§4.7).
        enqueueImageForCleanup(reminder.imageFileName)
        enqueueImageForCleanup(reminder.linkThumbnailFileName)
        modelContext.delete(reminder)
        try? modelContext.save()
        deletionManager.clear(id)
        // 삭제 즉시 위젯 reload(§14.2 ②) — 삭제는 reschedule 경로를 안 타므로 여기서 명시 호출.
        WidgetReloader.reload()
        // 삭제 → pending 감소 → 실패 알람 재시도(§4.12).
        notificationService.retryFailedScheduling()
    }

    /// 이미지 파일명을 지연 삭제 큐(UserDefaults)에 적재(§4.3). 실제 파일 삭제는 앱 시작 시
    /// ReminedoApp.processPendingImageDeletes()가 ImageStore로 수행한다(§4.7).
    private func enqueueImageForCleanup(_ fileName: String?) {
        guard let fileName, !fileName.isEmpty else { return }
        let key = SharedConstants.UserDefaultsKey.pendingImageDeletes
        var queue = UserDefaults.standard.stringArray(forKey: key) ?? []
        queue.append(fileName)
        UserDefaults.standard.set(queue, forKey: key)
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func fetch(id: UUID) -> Reminder? {
        let descriptor = FetchDescriptor<Reminder>(predicate: #Predicate { $0.id == id })
        return try? modelContext.fetch(descriptor).first
    }
}

private struct SwipeDeleteRow<Content: View>: View {
    let onDelete: () -> Void
    let content: () -> Content

    @State private var offset: CGFloat = 0

    private let actionWidth: CGFloat = 92

    init(onDelete: @escaping () -> Void, @ViewBuilder content: @escaping () -> Content) {
        self.onDelete = onDelete
        self.content = content
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(action: delete) {
                Image(systemName: "trash.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: actionWidth)
                    .frame(maxHeight: .infinity)
                    .background(Color.red)
                    .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous))
            }
            .buttonStyle(.plain)

            content()
                .offset(x: offset)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 12)
                        .onChanged { value in
                            let proposed = min(0, value.translation.width)
                            offset = max(-actionWidth, proposed)
                        }
                        .onEnded { value in
                            if value.translation.width < -actionWidth * 1.3 {
                                delete()
                            } else {
                                withAnimation(.snappy) {
                                    offset = value.translation.width < -actionWidth * 0.45 ? -actionWidth : 0
                                }
                            }
                        }
                )
        }
    }

    private func delete() {
        withAnimation(.snappy) { offset = 0 }
        onDelete()
    }
}

#Preview {
    ReminderListScreen()
        .modelContainer(for: Reminder.self, inMemory: true)
        .environment(AppState())
        .environment(NotificationService())
        .environment(DeletionManager())
        .environment(ImageStore())
        .environment(SnoozeActivityController())
        .preferredColorScheme(.dark)
}
