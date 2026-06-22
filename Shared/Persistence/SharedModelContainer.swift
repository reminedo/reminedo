//
//  SharedModelContainer.swift
//  reminedo
//
//  앱·위젯·공유 확장이 공유하는 SwiftData 컨테이너 팩토리. 스토어를 App Group 컨테이너에
//  생성하는 것이 핵심 — Phase 6 위젯이 같은 스토어를 읽으려면 처음부터 여기 있어야 하며,
//  나중에 옮기면 마이그레이션이 필요해져 "마이그레이션 없음" 원칙과 충돌한다(§9 선행조건, §14.2).
//

import Foundation
import SwiftData

enum SharedModelContainer {
    static let shared: ModelContainer = {
        return makeContainer()
    }()

    /// App Group 컨테이너에 동일 스키마로 ModelContainer를 새로 만든다.
    /// 위젯의 TimelineProvider는 메인 액터 밖에서 돌 수 있으므로 `nonisolated`로 둬,
    /// 비-메인 코드가 호출해 자체 컨테이너를 만들 수 있게 한다(§14.2). 위젯은 이 팩토리로
    /// 컨테이너를 1회(static) 만들고, getTimeline마다 새 ModelContext로 fetch한다(iOS 17 stale-fetch 회피).
    nonisolated static func makeContainer() -> ModelContainer {
        let schema = Schema([Reminder.self])
        let configuration = ModelConfiguration(
            schema: schema,
            groupContainer: .identifier(SharedConstants.appGroupID)
        )
        do {
            return try ModelContainer(for: schema, configurations: configuration)
        } catch {
            fatalError("SwiftData ModelContainer 생성 실패: \(error)")
        }
    }
}
