//
//  ReminedoWidget.swift
//  ReminedoWidget
//
//  홈 화면 알람 요약 위젯(§14). App Group 공유 SwiftData 스토어를 읽기 전용으로 fetch해
//  오늘의 알람을 시·분 오름차순(동시각 tie-break createdAt)으로 흘끗 보여준다(§14.3).
//  단일 엔트리 + 데이터 변경 기반 reload(앱이 WidgetCenter.reloadAllTimelines 호출, §14.2/§14.4).
//
//  이 타깃은 앱 타깃 코드(Tokens/Strings/ReminderToggle/ContentType+UI)를 보지 못하므로
//  색·심볼·시간 포맷은 여기서 자급한다(§Conventions). Shared 타입(Reminder/enum/
//  SharedModelContainer/SharedConstants)만 공유한다.
//

import WidgetKit
import SwiftUI
import SwiftData

// MARK: - 위젯 로컬 디자인 상수(자급 — 앱 토큰 미접근)

private enum WidgetTokens {
    /// 그린 액센트 #00C853(§11).
    static let accent = Color(red: 0x00 / 255, green: 0xC8 / 255, blue: 0x53 / 255)
    /// 카드 #1C1C1E(§11).
    static let card = Color(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255)
    static let background = Color.black
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.6)
    static let toggleOff = Color.white.opacity(0.25)
    /// Off 알람 흐림 정도(§14.3/§14.6).
    static let dimmedOpacity = 0.4
}

private enum WidgetSymbols {
    static let header = "alarm"
    static let memo = "text.bubble"
    static let url = "link"
    static let image = "photo"
    static let empty = "alarm"

    static func icon(for type: ContentType) -> String {
        switch type {
        case .memo: return memo
        case .url: return url
        case .image: return image
        }
    }
}

// MARK: - 행 수 정책(§14.3)

private enum RowPolicy {
    static func maxRows(for family: WidgetFamily) -> Int {
        switch family {
        case .systemLarge: return 5
        case .systemMedium: return 2
        case .systemSmall: return 1
        default: return 2
        }
    }
}

// MARK: - 엔트리 모델(SwiftData 모델을 직접 넘기지 않고 값 타입으로 스냅샷)

struct ReminderItem: Identifiable {
    let id: UUID
    let title: String
    let scheduledAt: Date
    let contentType: ContentType
    let isEnabled: Bool
    let schedulingFailed: Bool
}

struct ReminedoEntry: TimelineEntry {
    let date: Date
    let items: [ReminderItem]
    /// 전체 알람 개수(표시 행 초과분을 "+N개 더"로 계산하기 위해 별도 보관).
    let totalCount: Int
    /// 더미(placeholder/snapshot) 여부 — 회색 행 렌더 분기에 쓴다.
    let isPlaceholder: Bool
}

// MARK: - Provider

struct ReminedoProvider: TimelineProvider {
    /// 컨테이너는 1회만 만든다(static). getTimeline마다 새 ModelContext로 fetch(§14.2 stale-fetch 회피).
    private static let container: ModelContainer = SharedModelContainer.makeContainer()

    func placeholder(in context: Context) -> ReminedoEntry {
        // 레이아웃 유지용 더미 회색 행(§14.4).
        ReminedoEntry(date: .now, items: dummyItems(), totalCount: dummyItems().count, isPlaceholder: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (ReminedoEntry) -> Void) {
        // 위젯 갤러리 대표 더미(§14.4).
        let items = dummyItems()
        completion(ReminedoEntry(date: .now, items: items, totalCount: items.count, isPlaceholder: true))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ReminedoEntry>) -> Void) {
        let items = fetchItems()
        let entry = ReminedoEntry(date: .now, items: items, totalCount: items.count, isPlaceholder: false)
        // 단일 엔트리 + 데이터 변경 기반 reload(§14.4) — 자정/시각 타이머 불필요.
        completion(Timeline(entries: [entry], policy: .never))
    }

    /// 매 호출 새 ModelContext로 전체 Reminder fetch → 시·분 오름차순(tie-break createdAt) 정렬(§14.3).
    /// 읽기 전용 — NO 쓰기(§14.2).
    private func fetchItems() -> [ReminderItem] {
        let context = ModelContext(Self.container)
        let descriptor = FetchDescriptor<Reminder>()
        guard let reminders = try? context.fetch(descriptor) else { return [] }
        let calendar = Calendar.current
        let sorted = reminders.sorted { lhs, rhs in
            let l = calendar.dateComponents([.hour, .minute], from: lhs.scheduledAt)
            let r = calendar.dateComponents([.hour, .minute], from: rhs.scheduledAt)
            if l.hour != r.hour { return (l.hour ?? 0) < (r.hour ?? 0) }
            if l.minute != r.minute { return (l.minute ?? 0) < (r.minute ?? 0) }
            return lhs.createdAt < rhs.createdAt
        }
        return sorted.map {
            ReminderItem(
                id: $0.id,
                title: $0.title,
                scheduledAt: $0.scheduledAt,
                contentType: $0.contentType,
                isEnabled: $0.isEnabled,
                schedulingFailed: $0.schedulingFailed
            )
        }
    }

    private func dummyItems() -> [ReminderItem] {
        let now = Date.now
        return [
            ReminderItem(id: UUID(), title: "오전 운동", scheduledAt: now, contentType: .memo, isEnabled: true, schedulingFailed: false),
            ReminderItem(id: UUID(), title: "강의 링크 보기", scheduledAt: now, contentType: .url, isEnabled: true, schedulingFailed: false),
            ReminderItem(id: UUID(), title: "사진 정리", scheduledAt: now, contentType: .image, isEnabled: false, schedulingFailed: false),
        ]
    }
}

// MARK: - 시간 포맷(로컬 헬퍼 — 앱 DateFormatting 미의존, §C)

private enum WidgetTime {
    /// "H:MM"(widget.png 큰 시간 텍스트).
    static func clockString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "h:mm"
        return formatter.string(from: date)
    }
    /// "오전/오후"(widget.png 시간 아래 작은 표시).
    static func ampmString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "a"
        return formatter.string(from: date)
    }
    /// "오전/오후 H:MM"(레거시 통합 — 빈 상태 등에서 사용).
    static func string(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "a h:mm"
        return formatter.string(from: date)
    }
}

// MARK: - 딥링크 URL

private enum WidgetLinks {
    /// 행 탭 → 편집 시트(§14.5). 앱 onOpenURL이 reminedo://edit/{uuid}를 .edit로 라우팅.
    static func edit(_ id: UUID) -> URL {
        URL(string: "\(SharedConstants.urlScheme)://edit/\(id.uuidString)")!
    }
    /// 헤더/빈 영역/"+N개 더" 탭 → 앱 알림 목록(§14.5).
    static let list = URL(string: "\(SharedConstants.urlScheme)://list")!
}

// MARK: - Widget

struct ReminedoWidget: Widget {
    private let kind = "ReminedoWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ReminedoProvider()) { entry in
            ReminedoWidgetView(entry: entry)
                .containerBackground(WidgetTokens.background, for: .widget)
        }
        .configurationDisplayName("리마인두")
        .description("오늘의 알람을 흘끗 확인해요.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Views

struct ReminedoWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ReminedoEntry

    private var maxRows: Int { RowPolicy.maxRows(for: family) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if entry.items.isEmpty {
                emptyState
            } else {
                rows
            }
        }
        // 헤더/빈 영역 탭 → 앱 목록(§14.5). 개별 행은 Link로 덮어 우선한다.
        .widgetURL(WidgetLinks.list)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: WidgetSymbols.header)
                .foregroundStyle(WidgetTokens.textPrimary)
            Text("알람 목록")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WidgetTokens.accent)
            Spacer()
        }
    }

    @ViewBuilder
    private var rows: some View {
        // 표시 행: 초과 시 마지막 한 칸을 "+N개 더"로 대체(§14.3). 다만 systemSmall(maxRows=1)은
        // 칸이 1개뿐이라 overflow가 유일한 행을 잠식하므로, Small은 항상 첫 알람 1개를 보여준다.
        let overflow = entry.totalCount > maxRows && maxRows > 1
        let visibleCount = overflow ? maxRows - 1 : min(entry.items.count, maxRows)
        let visible = Array(entry.items.prefix(max(visibleCount, 0)))

        VStack(spacing: 6) {
            ForEach(visible) { item in
                rowView(item)
            }
            if overflow {
                moreRow(count: entry.totalCount - visible.count)
            }
        }
    }

    @ViewBuilder
    private func rowView(_ item: ReminderItem) -> some View {
        let content = RowContent(item: item, isPlaceholder: entry.isPlaceholder)
        if entry.isPlaceholder {
            content
        } else {
            // 행 탭 → 편집 시트 딥링크(§14.5).
            Link(destination: WidgetLinks.edit(item.id)) { content }
        }
    }

    private func moreRow(count: Int) -> some View {
        // "+N개 더" → 앱 목록(widgetURL이 이미 list로 가므로 별도 Link 불필요).
        HStack {
            Text("+\(count)개 더")
                .font(.footnote.weight(.medium))
                .foregroundStyle(WidgetTokens.accent)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            Image(systemName: WidgetSymbols.empty)
                .foregroundStyle(WidgetTokens.accent)
            Text("알람이 없어요")
                .font(.footnote)
                .foregroundStyle(WidgetTokens.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 행 콘텐츠(시각 · 타입 아이콘 · 제목 · 비인터랙티브 토글)

private struct RowContent: View {
    let item: ReminderItem
    let isPlaceholder: Bool

    var body: some View {
        HStack(spacing: 10) {
            // widget.png: 큰 초록 시간 + 그 아래 작은 AM/PM.
            VStack(alignment: .leading, spacing: 0) {
                Text(isPlaceholder ? "0:00" : WidgetTime.clockString(from: item.scheduledAt))
                    .font(.system(size: 20, weight: .semibold).monospacedDigit())
                    .foregroundStyle(WidgetTokens.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(isPlaceholder ? "오전" : WidgetTime.ampmString(from: item.scheduledAt))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(WidgetTokens.accent.opacity(0.85))
            }

            Image(systemName: WidgetSymbols.icon(for: item.contentType))
                .font(.subheadline)
                .foregroundStyle(WidgetTokens.textPrimary)

            Text(item.title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(WidgetTokens.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 4)

            // 예약 실패 경고(§14.3) — 거짓신호 방지.
            if item.schedulingFailed && item.isEnabled {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
            }

            // 비인터랙티브 상태 표시 토글(§14.6a) — 탭 컨트롤 아님. 6b에서 AppIntent로 인터랙티브화.
            DisplayToggle(isOn: item.isEnabled)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(WidgetTokens.card)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        // Off 알람은 충분히 흐림(§14.3/§14.6).
        .opacity(isPlaceholder ? 0.5 : (item.isEnabled ? 1.0 : WidgetTokens.dimmedOpacity))
        .redacted(reason: isPlaceholder ? .placeholder : [])
    }
}

/// 앱 토글 외형을 본뜬 비인터랙티브 캡슐+원(§14.6a). 켜짐=그린, 꺼짐=흐린 회색. 탭 불가.
private struct DisplayToggle: View {
    let isOn: Bool

    var body: some View {
        Capsule()
            .fill(isOn ? WidgetTokens.accent : WidgetTokens.toggleOff)
            .frame(width: 34, height: 20)
            .overlay(
                Circle()
                    .fill(Color.white)
                    .padding(2)
                    .frame(width: 20, height: 20)
                    .offset(x: isOn ? 7 : -7)
            )
            .allowsHitTesting(false)   // 6a: 표시 전용, 탭 컨트롤 아님.
    }
}

// MARK: - Preview

#Preview(as: .systemLarge) {
    ReminedoWidget()
} timeline: {
    ReminedoEntry(
        date: .now,
        items: [
            ReminderItem(id: UUID(), title: "오전 운동", scheduledAt: .now, contentType: .memo, isEnabled: true, schedulingFailed: false),
            ReminderItem(id: UUID(), title: "강의 보기", scheduledAt: .now, contentType: .url, isEnabled: false, schedulingFailed: false),
        ],
        totalCount: 2,
        isPlaceholder: false
    )
}
