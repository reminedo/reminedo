//
//  ReminderEditSheet.swift
//  reminedo
//
//  추가·수정 공용 바텀 시트(§3.3). 좌상단 X(취소)·우상단 ✓(저장, 유효 전 비활성).
//  Phase 2는 메모·URL 콘텐츠 — 사진 세그먼트만 비활성("곧", Phase 3). 세그먼트 전환 시 입력 보존(§3.3).
//  저장은 단일 경로: 모델 mutate → save() → notificationService.reschedule(§4.2).
//

import SwiftUI
import SwiftData
import PhotosUI

struct ReminderEditSheet: View {
    enum Mode {
        case add
        case edit(Reminder)
    }

    let mode: Mode

    /// 공유 진입 프리필 URL(§2.3/§4.10). nil이면 기존 추가/수정 동작 그대로.
    /// 설정 시 .url 세그먼트 선택 + urlText 채움 → 기존 Phase 2 미리보기 fetch·제목 자동채움이 트리거된다.
    private let prefillURL: String?
    private let prefillImageImportFileName: String?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(NotificationService.self) private var notificationService
    @Environment(DeletionManager.self) private var deletionManager
    @Environment(ImageStore.self) private var imageStore
    @Environment(SnoozeActivityController.self) private var snoozeActivity

    // 편집 가능한 로컬 상태(저장 시에만 모델에 반영 — 취소 폐기 가드를 단순화).
    @State private var selectedType: ContentType
    @State private var title: String
    @State private var memo: String
    // URL 드래프트는 memo와 별개로 보관해 세그먼트 전환 시 입력이 보존되도록 한다(§3.3).
    @State private var urlText: String
    // 이미지 드래프트도 memo/url과 별개로 보관(세그먼트 전환 시 보존, §3.3).
    //  pickedImage = 이번에 새로 고른 이미지(아직 미저장), imageFileName = 편집 모드의 기존 저장본.
    @State private var pickedImage: UIImage?
    @State private var imageFileName: String?
    /// UIKit PhotoPicker(PHPickerViewController 래퍼)를 .sheet로 띄우기 위한 플래그.
    @State private var showPhotoPicker = false
    /// 제목 TextField 포커스(first responder) 명시 관리. PHPicker 해제 후에도 탭으로 키보드가
    /// 정상 진입하도록 SwiftUI 포커스를 일원화한다(PhotoPicker의 key window 복원과 함께 동작).
    @FocusState private var titleFocused: Bool
    /// 미리보기 캐시(이슈4): currentImage computed를 대체. body 재평가마다 디스크 I/O·UIImage 재생성을 막아
    /// 제목 TextField 포커스(First Responder) 안정화. pickedImage/imageFileName 변경 시 한 번만 로드.
    @State private var loadedPreviewImage: UIImage?
    @State private var time: Date

    // URL 미리보기는 시트 로컬(전역 주입 아님) — 시트 수명과 함께 산다(§4.9).
    @State private var previewService = LinkPreviewService()
    @State private var repeatRule: RepeatRule
    @State private var weekdaysMask: Int
    @State private var soundType: SoundType
    @State private var snoozeEnabled: Bool
    @State private var snoozeMinutes: Int

    // 폐기 가드 비교용 원본 스냅샷.
    private let original: Snapshot

    @State private var showDiscardConfirm = false
    @State private var showDeleteConfirm = false

    init(mode: Mode, prefillURL: String? = nil, prefillImageImportFileName: String? = nil) {
        self.mode = mode
        self.prefillURL = prefillURL
        self.prefillImageImportFileName = prefillImageImportFileName

        switch mode {
        case .add:
            // 새 알람 기본값(§3.3): 시각=현재 시각 분 올림, 타입=메모, 반복=안 함, 사운드=기본,
            //   다시 알림=On·5분. 단, 공유 프리필 URL이 있으면 타입=.url + urlText 프리필(§2.3/§4.10).
            let defaultTime = Self.roundedUpToMinute(.now)
            let importedImage = Self.loadSharedImportImage(named: prefillImageImportFileName)
            let prefilledType: ContentType = (importedImage != nil) ? .image : ((prefillURL != nil) ? .url : .memo)
            let prefilledURLText = prefillURL ?? ""
            // 신규 알람 기본 사운드는 항상 기본음(§3.3). 저장값에 무관하게 .defaultSound로 초기화한다.
            let defaultSound = SoundType.defaultSound
            _selectedType = State(initialValue: prefilledType)
            _title = State(initialValue: "")
            _memo = State(initialValue: "")
            _urlText = State(initialValue: prefilledURLText)
            _pickedImage = State(initialValue: importedImage)
            _imageFileName = State(initialValue: nil)
            _time = State(initialValue: defaultTime)
            _repeatRule = State(initialValue: .none)
            _weekdaysMask = State(initialValue: 0)
            _soundType = State(initialValue: defaultSound)
            _snoozeEnabled = State(initialValue: true)
            _snoozeMinutes = State(initialValue: 5)
            original = Snapshot(selectedType: prefilledType, title: "", memo: "", urlText: prefilledURLText, imageFileName: nil,
                                time: defaultTime, repeatRule: .none, weekdaysMask: 0, soundType: defaultSound,
                                snoozeEnabled: true, snoozeMinutes: 5)
        case .edit(let reminder):
            let memo = reminder.memo ?? ""
            let urlText = reminder.targetURL ?? ""
            // 모든 타입(메모/URL/사진) 전환 허용(§3.3·§3.86).
            let initialType = reminder.contentType
            let imageFileName = reminder.imageFileName
            _selectedType = State(initialValue: initialType)
            _title = State(initialValue: reminder.title)
            _memo = State(initialValue: memo)
            _urlText = State(initialValue: urlText)
            _pickedImage = State(initialValue: nil)
            _imageFileName = State(initialValue: imageFileName)
            _time = State(initialValue: reminder.scheduledAt)
            _repeatRule = State(initialValue: reminder.repeatRule)
            _weekdaysMask = State(initialValue: reminder.repeatWeekdaysMask)
            _soundType = State(initialValue: reminder.soundType)
            _snoozeEnabled = State(initialValue: reminder.snoozeEnabled)
            _snoozeMinutes = State(initialValue: reminder.snoozeMinutes)
            original = Snapshot(selectedType: initialType, title: reminder.title, memo: memo, urlText: urlText,
                                imageFileName: imageFileName, time: reminder.scheduledAt, repeatRule: reminder.repeatRule,
                                weekdaysMask: reminder.repeatWeekdaysMask, soundType: reminder.soundType,
                                snoozeEnabled: reminder.snoozeEnabled, snoozeMinutes: reminder.snoozeMinutes)
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    /// ✓ 활성 조건(§3.3): 제목 + 선택 타입의 콘텐츠(메모면 비어있지 않음, URL이면 유효 http/https)
    ///   + (매주면 요일 ≥1, §3.4). 미리보기 실패는 저장을 막지 않는다(§4.9) — URL 유효성만 본다.
    private var isValid: Bool {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        switch selectedType {
        case .memo:
            guard !memo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        case .url:
            guard URLValidation.isValid(urlText) else { return false }
        case .image:
            // ✓ 활성: 새로 고른 이미지 또는 편집 모드의 기존 저장본이 있어야 한다(§3.3).
            guard pickedImage != nil || imageFileName != nil else { return false }
        }
        if repeatRule == .weekly { return Weekday.hasAnyWeekday(weekdaysMask) }
        return true
    }

    /// URL 입력이 있는데 유효하지 않을 때만 인라인 오류를 노출(§3.3).
    private var showsURLInvalid: Bool {
        selectedType == .url
            && !urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !URLValidation.isValid(urlText)
    }

    private var hasChanges: Bool {
        selectedType != original.selectedType || title != original.title ||
        memo != original.memo || urlText != original.urlText ||
        // 새 이미지를 골랐거나 기존 저장본이 바뀌었으면 변경으로 본다.
        pickedImage != nil || imageFileName != original.imageFileName ||
        time != original.time ||
        repeatRule != original.repeatRule || weekdaysMask != original.weekdaysMask ||
        soundType != original.soundType ||
        snoozeEnabled != original.snoozeEnabled || snoozeMinutes != original.snoozeMinutes
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Tokens.Palette.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: Tokens.Spacing.gutter) {
                        segmentedTypePicker
                        titleField
                        switch selectedType {
                        case .memo: memoField
                        case .url: urlSection
                        case .image: imageSection
                        }
                        settingsCard
                        if isEditing { deleteButton }
                    }
                    .padding(Tokens.Spacing.gutter)
                }
            }
            .navigationTitle(isEditing ? Strings.Edit.editTitle : Strings.Edit.addTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        attemptCancel()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(Tokens.Palette.textPrimary)
                    }
                    .accessibilityLabel(Strings.Edit.cancel)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: save) {
                        Image(systemName: "checkmark")
                            .foregroundStyle(isValid ? Tokens.Palette.accent : Tokens.Palette.disabled)
                    }
                    .disabled(!isValid)
                    .accessibilityLabel(Strings.Edit.save)
                }
            }
            .onAppear {
                // 시트 오픈 시점 fetch(§4.9): 기존 URL이 있으면(편집 모드) 즉시 미리보기 시작.
                if selectedType == .url, !urlText.isEmpty {
                    previewService.fetch(urlText)
                }
                // 이슈4: 편집 모드 기존 이미지 1회 로드(cachedPreview).
                reloadPreview()
            }
            .onChange(of: pickedImage) { _, _ in reloadPreview() }
            .onChange(of: imageFileName) { _, _ in reloadPreview() }
            // 사진 선택기: 중첩 .sheet 대신 보이지 않는 host에서 UIKit present로 PHPicker를 띄운다
            // (중첩 시트 해제 시 시트 전체 터치가 죽던 버그 회피). PhotoPicker.swift 참고.
            //  showPhotoPicker == true일 때만 렌더링해 평상시 잔여 host/hit-test 레이어를 남기지 않는다.
            .background {
                if showPhotoPicker {
                    PhotoPicker(isPresented: $showPhotoPicker) { image in
                        pickedImage = image
                    }
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)
                }
            }
            .confirmationDialog(Strings.Edit.discardTitle, isPresented: $showDiscardConfirm, titleVisibility: .visible) {
                Button(Strings.Edit.discardConfirm, role: .destructive) { dismiss() }
                Button(Strings.Edit.discardCancel, role: .cancel) {}
            }
            .confirmationDialog(Strings.Edit.deleteConfirmTitle, isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button(Strings.Edit.deleteConfirm, role: .destructive) { deleteReminder() }
                Button(Strings.Edit.deleteCancel, role: .cancel) {}
            }
        }
    }

    // MARK: - 구성 요소

    /// 메모/URL/사진 세그먼트. 세 타입 모두 활성(§3.3).
    /// 세그먼트 전환은 selectedType만 바꾸고 입력(memo/urlText/이미지)은 보존한다(§3.3).
    private var segmentedTypePicker: some View {
        HStack(spacing: 8) {
            segment(.memo, label: Strings.Edit.segmentMemo, enabled: true)
            segment(.url, label: Strings.Edit.segmentURL, enabled: true)
            segment(.image, label: Strings.Edit.segmentImage, enabled: true)
        }
    }

    private func segment(_ type: ContentType, label: String, enabled: Bool) -> some View {
        let selected = (type == selectedType)
        return Button {
            guard enabled else { return }
            selectedType = type
        } label: {
            HStack(spacing: 6) {
                Image(systemName: type.symbolName)
                Text(label)
                if !enabled {
                    Text(Strings.Edit.comingSoon)
                        .font(.caption2)
                        .foregroundStyle(Tokens.Palette.textSecondary)
                }
            }
            .font(.subheadline.weight(.medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(selected ? Tokens.Palette.accent.opacity(0.22) : Tokens.Palette.card)
            .foregroundStyle(enabled ? (selected ? Tokens.Palette.accent : Tokens.Palette.textPrimary) : Tokens.Palette.disabled)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .opacity(enabled ? 1 : 0.6)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Strings.Edit.titleLabel)
                .font(.footnote)
                .foregroundStyle(Tokens.Palette.textSecondary)
            TextField(Strings.Edit.titlePlaceholder, text: $title)
                .focused($titleFocused)
                .textFieldStyle(.plain)
                .padding(Tokens.Spacing.row)
                .background(Tokens.Palette.card)
                .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous))
                .foregroundStyle(Tokens.Palette.textPrimary)
                // 엔터/완료 시 포커스를 명시적으로 해제(stale FocusState 방지).
                // ⚠️ TextField에 .onTapGesture를 붙이면 네이티브 탭→편집 진입 제스처를 가로채
                //    제목 입력이 아예 막힌다(추가/편집 공통). 그래서 탭 핸들러는 두지 않고,
                //    탭→포커스는 네이티브에 맡긴다. PHPicker 해제 후 key window는
                //    PhotoPicker(topVC present + makeKey)가 복원하므로 별도 핵이 필요 없다.
                .submitLabel(.done)
                .onSubmit { titleFocused = false }
        }
    }

    private var memoField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Strings.Edit.memoLabel)
                .font(.footnote)
                .foregroundStyle(Tokens.Palette.textSecondary)
            ZStack(alignment: .topLeading) {
                if memo.isEmpty {
                    Text(Strings.Edit.memoPlaceholder)
                        .foregroundStyle(Tokens.Palette.textSecondary)
                        .padding(.horizontal, Tokens.Spacing.row + 4)
                        .padding(.vertical, Tokens.Spacing.row + 8)
                }
                TextEditor(text: $memo)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 120)
                    .padding(Tokens.Spacing.row)
                    .foregroundStyle(Tokens.Palette.textPrimary)
                    .onChange(of: memo) { _, newValue in
                        // 500자 하드 차단(§3.3).
                        if newValue.count > Strings.Edit.memoLimit {
                            memo = String(newValue.prefix(Strings.Edit.memoLimit))
                        }
                    }
            }
            .background(Tokens.Palette.card)
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous))
            HStack {
                Spacer()
                Text("\(memo.count)/\(Strings.Edit.memoLimit)")
                    .font(.caption)
                    .foregroundStyle(Tokens.Palette.textSecondary)
            }
        }
    }

    /// URL 입력 + 4상태 미리보기(§4.9). 입력 onChange → 디바운스 fetch. 외부 열림은 미리보기 탭.
    private var urlSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Strings.Edit.urlLabel)
                .font(.footnote)
                .foregroundStyle(Tokens.Palette.textSecondary)
            TextField(Strings.Edit.urlPlaceholder, text: $urlText)
                .textFieldStyle(.plain)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .padding(Tokens.Spacing.row)
                .background(Tokens.Palette.card)
                .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous))
                .foregroundStyle(Tokens.Palette.textPrimary)
                .onChange(of: urlText) { _, newValue in
                    previewService.fetch(newValue)
                }
            if showsURLInvalid {
                Text(Strings.Edit.urlInvalid)
                    .font(.footnote)
                    .foregroundStyle(Tokens.Palette.destructive)
                    .padding(.horizontal, 4)
            }
            urlPreview
                .onChange(of: previewService.state) { _, state in
                    // 자동 채움(§4.9/§13.7): 미리보기 성공 + 제목 미입력일 때만.
                    if case .success(let previewTitle, _) = state,
                       title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        title = previewTitle
                    }
                }
        }
    }

    /// 미리보기 4상태(§4.9): 빈/로딩/성공(썸네일+제목, 탭→외부 열림)/실패(문구+도메인).
    @ViewBuilder
    private var urlPreview: some View {
        switch previewService.state {
        case .empty:
            Text(Strings.Edit.urlPreviewHint)
                .font(.footnote)
                .foregroundStyle(Tokens.Palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Tokens.Spacing.row)
        case .loading:
            HStack {
                ProgressView()
                    .tint(Tokens.Palette.textSecondary)
                Spacer()
            }
            .padding(Tokens.Spacing.row)
            .frame(maxWidth: .infinity)
            .background(Tokens.Palette.card)
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous))
        case .success(let previewTitle, let image):
            Button {
                URLActionHandler.open(urlText)
            } label: {
                HStack(spacing: Tokens.Spacing.row) {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    } else {
                        Image(systemName: ContentType.url.symbolName)
                            .font(.title3)
                            .foregroundStyle(ContentType.url.tint)
                            .frame(width: 56, height: 56)
                            .background(Tokens.Palette.background)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    Text(previewTitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Tokens.Palette.textPrimary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "arrow.up.right.square")
                        .foregroundStyle(Tokens.Palette.textSecondary)
                }
                .padding(Tokens.Spacing.row)
                .background(Tokens.Palette.card)
                .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous))
            }
            .buttonStyle(.plain)
        case .failure(let domain):
            VStack(alignment: .leading, spacing: 4) {
                Text(Strings.Edit.urlPreviewFailure)
                    .font(.footnote)
                    .foregroundStyle(Tokens.Palette.textPrimary)
                Text(domain)
                    .font(.caption)
                    .foregroundStyle(Tokens.Palette.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Tokens.Spacing.row)
            .background(Tokens.Palette.card)
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous))
        }
    }

    /// 사진 콘텐츠(§3.3/§4.7): PhotosPicker로 선택, 선택/기존 이미지 미리보기.
    ///  미리보기 탭 → 읽기전용 풀스크린(§3.3/§13.6, 편집 상태 보존하며 복귀).
    private var imageSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Strings.Edit.imageLabel)
                .font(.footnote)
                .foregroundStyle(Tokens.Palette.textSecondary)

            if let preview = loadedPreviewImage {
                // 선택/기존 이미지 미리보기(읽기전용). 풀스크린 없이 미리보기만 노출한다 —
                // 탭 타깃을 없애 제목 입력 탭이 풀스크린으로 새는 문제를 차단한다.
                Image(uiImage: preview)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous))
                    .clipped()
            } else {
                Text(Strings.Edit.imagePickHint)
                    .font(.footnote)
                    .foregroundStyle(Tokens.Palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Tokens.Spacing.row)
            }

            // 사진 선택은 루트 .background의 PhotoPicker(UIKit present)로 띄운다
            // (권한·usage description 불필요, §7).
            Button {
                showPhotoPicker = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: Tokens.Symbols.image)
                    Text(loadedPreviewImage == nil ? Strings.Edit.imagePick : Strings.Edit.imageChange)
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Tokens.Palette.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Tokens.Spacing.row)
                .background(Tokens.Palette.card)
                .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    /// 미리보기 이미지 갱신(이슈4): pickedImage 우선, 없으면 imageFileName(편집 모드)을 디스크에서 1회 로드해
    /// @State에 캐싱. body 재평가마다 disk I/O/UIImage 재생성하던 currentImage computed를 대체해
    /// 미리보기 뷰 identity 교란 → 제목 TextField 포커스 상실을 막는다.
    private func reloadPreview() {
        if let pickedImage {
            loadedPreviewImage = pickedImage
        } else if let imageFileName {
            loadedPreviewImage = imageStore.loadImage(named: imageFileName)
        } else {
            loadedPreviewImage = nil
        }
    }

    private var settingsCard: some View {
        VStack(spacing: Tokens.Spacing.row) {
            VStack(alignment: .leading, spacing: 8) {
                Text(Strings.Edit.timeLabel)
                    .font(.footnote)
                    .foregroundStyle(Tokens.Palette.textSecondary)
                DatePicker("", selection: $time, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    // 휠은 디바이스 로케일을 따라 AM/PM이 나오므로 한국어(오전/오후)로 고정.
                    .environment(\.locale, Locale(identifier: "ko_KR"))
            }

            Divider().overlay(Tokens.Palette.textSecondary.opacity(0.3))

            HStack {
                Text(Strings.Edit.repeatLabel)
                    .foregroundStyle(Tokens.Palette.textPrimary)
                Spacer()
                Picker("", selection: $repeatRule) {
                    Text(Strings.Edit.repeatNone).tag(RepeatRule.none)
                    Text(Strings.Edit.repeatDaily).tag(RepeatRule.daily)
                    Text(Strings.Edit.repeatWeekly).tag(RepeatRule.weekly)
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }

            // 매주 선택 시 요일 칩(월~일, 다중 선택, 원형 칩 §11/§3.4).
            if repeatRule == .weekly {
                weekdayChips
            }

            Divider().overlay(Tokens.Palette.textSecondary.opacity(0.3))

            HStack {
                Text(Strings.Edit.soundLabel)
                    .foregroundStyle(Tokens.Palette.textPrimary)
                Spacer()
                Picker("", selection: $soundType) {
                    Text(Strings.Edit.soundDefault).tag(SoundType.defaultSound)
                    Text(Strings.Edit.soundSilent).tag(SoundType.silent)
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
            }

            Divider().overlay(Tokens.Palette.textSecondary.opacity(0.3))

            // 다시 알림(스누즈, §3.3/§4.6): 토글 On일 때만 시간 행 노출.
            HStack {
                Text(Strings.Edit.snoozeLabel)
                    .foregroundStyle(Tokens.Palette.textPrimary)
                Spacer()
                Toggle("", isOn: $snoozeEnabled)
                    .labelsHidden()
                    .tint(Tokens.Palette.accent)
            }

            if snoozeEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    Text(Strings.Edit.snoozeTimeLabel)
                        .font(.footnote)
                        .foregroundStyle(Tokens.Palette.textSecondary)
                    // 1분 단위 스크롤(1~60분). snoozeMinutes는 Int 그대로 저장.
                    Picker("", selection: $snoozeMinutes) {
                        ForEach(1...60, id: \.self) { minutes in
                            Text(Strings.Edit.snoozeMinutesText(minutes)).tag(minutes)
                        }
                    }
                    .pickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
                }
            }
        }
        .padding(Tokens.Spacing.gutter)
        .background(Tokens.Palette.card)
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous))
    }

    /// 요일 칩 행(월~일). 원형 칩, 선택 시 그린 채움(§11).
    private var weekdayChips: some View {
        HStack(spacing: 8) {
            ForEach(Array(Strings.Edit.weekdayLabels.enumerated()), id: \.offset) { index, label in
                let selected = Weekday.isSelected(uiIndex: index, in: weekdaysMask)
                Button {
                    weekdaysMask = Weekday.toggling(uiIndex: index, in: weekdaysMask)
                } label: {
                    Text(label)
                        .font(.footnote.weight(.semibold))
                        .frame(width: 36, height: 36)
                        .background(selected ? Tokens.Palette.accent : Tokens.Palette.background)
                        .foregroundStyle(selected ? Tokens.Palette.background : Tokens.Palette.textPrimary)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(selected ? .clear : Tokens.Palette.textSecondary.opacity(0.4), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var deleteButton: some View {
        Button {
            showDeleteConfirm = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "trash")
                Text(Strings.Edit.delete)
            }
            .font(.body.weight(.medium))
            .foregroundStyle(Tokens.Palette.destructive)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Tokens.Spacing.row)
        }
    }

    // MARK: - 동작

    private func attemptCancel() {
        if hasChanges {
            showDiscardConfirm = true
        } else {
            dismiss()
        }
    }

    private func save() {
        guard isValid else { return }
        let reminder: Reminder
        switch mode {
        case .add:
            // UUID는 시트 진입 시(=Reminder init) 발급(§4.1).
            reminder = Reminder()
            modelContext.insert(reminder)
        case .edit(let existing):
            reminder = existing
        }
        reminder.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        reminder.contentType = selectedType
        // 선택된 타입의 콘텐츠만 영속(§3.3): 전환된 다른 타입의 잔여 값은 비운다.
        switch selectedType {
        case .memo:
            reminder.memo = memo
            reminder.targetURL = nil
            reminder.linkTitle = nil
        case .url:
            reminder.targetURL = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
            // 미리보기 성공 시 제목을 linkTitle로 저장(셀 부제). 실패면 도메인을 폴백 제목으로.
            if case .success(let previewTitle, let previewImage) = previewService.state {
                reminder.linkTitle = previewTitle
                // 미리보기 썸네일을 ImageStore에 영속(§4.9). best-effort — 실패해도 저장은 계속.
                if let previewImage,
                   let name = imageStore.saveLinkThumbnail(previewImage, for: reminder.id) {
                    reminder.linkThumbnailFileName = name
                }
            } else {
                reminder.linkTitle = URLValidation.normalizedURL(from: urlText)?.host
            }
            reminder.memo = nil
            reminder.imageFileName = nil
        case .image:
            // 새로 고른 이미지가 있으면 항상 JPEG 재인코딩 후 "{id}.jpg"에 저장(§4.7).
            //  기존 저장본만 있고 변경이 없으면 imageFileName을 그대로 유지한다.
            if let pickedImage {
                if let name = try? imageStore.save(pickedImage, for: reminder.id) {
                    reminder.imageFileName = name
                }
            } else if let imageFileName {
                reminder.imageFileName = imageFileName
            }
            reminder.memo = nil
            reminder.targetURL = nil
            reminder.linkTitle = nil
        }
        reminder.isEnabled = true
        reminder.scheduledAt = time
        reminder.repeatRule = repeatRule
        // weekly가 아니면 마스크를 0으로 정규화(stale 비트 방지).
        reminder.repeatWeekdaysMask = (repeatRule == .weekly) ? weekdaysMask : 0
        reminder.soundType = soundType
        reminder.snoozeEnabled = snoozeEnabled
        reminder.snoozeMinutes = snoozeMinutes
        reminder.updatedAt = .now

        try? modelContext.save()
        notificationService.reschedule(reminder)
        dismiss()
    }

    /// 삭제(§4.3): pending 알림만 취소 + 지연 삭제 큐 등록 → 시트 닫힘. 스낵바·실제 커밋은 List 루트.
    /// 레코드는 그대로 남아 Undo = reschedule로 복구된다.
    private func deleteReminder() {
        guard case .edit(let reminder) = mode else { return }
        notificationService.cancel(reminder)          // #snooze 포함 prefix 일괄 취소
        snoozeActivity.end(reminderID: reminder.id)   // 진행 중 스누즈 Live Activity도 종료(#6)
        deletionManager.enqueue(reminder.id)
        dismiss()
    }

    // MARK: - 헬퍼

    private static func roundedUpToMinute(_ date: Date) -> Date {
        let calendar = Calendar.current
        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        var rounded = comps
        rounded.second = 0
        if (comps.second ?? 0) > 0 {
            rounded.minute = (comps.minute ?? 0) + 1
        }
        return calendar.date(from: rounded) ?? date
    }

    /// 폐기 가드 비교용 스냅샷.
    private static func loadSharedImportImage(named fileName: String?) -> UIImage? {
        guard let fileName, !fileName.isEmpty,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedConstants.appGroupID)
        else { return nil }
        let url = container
            .appendingPathComponent("shared-imports", isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
        let image = UIImage(contentsOfFile: url.path)
        if image != nil {
            try? FileManager.default.removeItem(at: url)
        }
        return image
    }

    private struct Snapshot {
        let selectedType: ContentType
        let title: String
        let memo: String
        let urlText: String
        let imageFileName: String?
        let time: Date
        let repeatRule: RepeatRule
        let weekdaysMask: Int
        let soundType: SoundType
        let snoozeEnabled: Bool
        let snoozeMinutes: Int
    }
}
