//
//  ReminedoWidgetBundle.swift
//  ReminedoWidget
//
//  위젯 익스텐션 진입점(§14). 홈 화면 알람 요약 위젯(systemMedium/Large) + 스누즈 카운트다운
//  Live Activity(§4.6 확장)를 담는다. 잠금화면/StandBy 위젯은 범위 외(§14.4).
//

import WidgetKit
import SwiftUI

@main
struct ReminedoWidgetBundle: WidgetBundle {
    var body: some Widget {
        ReminedoWidget()
        SnoozeLiveActivity()
    }
}
