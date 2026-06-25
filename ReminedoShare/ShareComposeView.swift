//
//  ShareComposeView.swift
//  ReminedoShare
//
//  공유 확장 입력 폼. 제목·시간(+링크 또는 사진)만 받아 저장한다(나머지 설정은 앱에서 수정).
//  저장 시 호스트(ShareViewController)가 알림을 직접 예약하고 App Group에 페이로드를 기록한다.
//

import SwiftUI

struct ShareComposeView: View {
    enum Kind {
        case url      // 링크 입력 필드 노출
        case image    // 사진 첨부(필드 없음, 안내만)
    }

    let kind: Kind
    let onSave: (_ title: String, _ urlText: String, _ date: Date) -> Void
    let onCancel: () -> Void

    @State private var title: String
    @State private var urlText: String
    @State private var date: Date

    init(
        kind: Kind,
        initialURL: String = "",
        onSave: @escaping (_ title: String, _ urlText: String, _ date: Date) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.kind = kind
        self.onSave = onSave
        self.onCancel = onCancel
        _title = State(initialValue: "")
        _urlText = State(initialValue: initialURL)
        // 기본 시각: 현재로부터 1시간 뒤(분/초 버림으로 깔끔하게).
        let base = Date().addingTimeInterval(3600)
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour], from: base)
        _date = State(initialValue: Calendar.current.date(from: comps) ?? base)
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("제목") {
                    TextField("알림 제목", text: $title)
                }
                switch kind {
                case .url:
                    Section("링크") {
                        TextField("https://", text: $urlText)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                    }
                case .image:
                    Section("사진") {
                        Label("사진 1장이 첨부됩니다", systemImage: "photo")
                            .foregroundStyle(.secondary)
                    }
                }
                Section("시간") {
                    DatePicker("알림 시각", selection: $date)
                        .datePickerStyle(.compact)
                }
            }
            .navigationTitle("리마인두에 추가")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        onSave(title.trimmingCharacters(in: .whitespacesAndNewlines), urlText, date)
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
}
