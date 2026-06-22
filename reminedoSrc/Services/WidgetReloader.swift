//
//  WidgetReloader.swift
//  reminedo
//
//  위젯 타임라인 reload 트리거를 한 곳에 모은 얇은 헬퍼(§14.2). 위젯은 읽기 전용이고
//  단일 엔트리 + 데이터 변경 기반 reload이므로, 앱이 위젯이 보여주는 데이터를 바꾼 직후마다
//  여기로 reload를 호출한다 — ① reschedule 성공/실패 ② 삭제 즉시 ③ 삭제 Undo(reschedule 경유)
//  ④ 64한도 자동 재시도 결과 ⑤ 권한 재활성 전체 재예약 완료 후. "reschedule 직후"만으로는
//  삭제 경로가 누락되므로 삭제 커밋 지점도 명시 호출한다.
//

import WidgetKit

enum WidgetReloader {
    /// 모든 위젯 타임라인을 reload. 위젯 타깃이 없어도(아직 미설치) no-op에 가깝다.
    static func reload() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
