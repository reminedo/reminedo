//
//  Weekday.swift
//  reminedo
//
//  요일 비트마스크 ↔ iOS weekday ↔ UI(월~일) 순서를 잇는 단일 변환 헬퍼(§4.5).
//  세 좌표계를 한 곳에 모아 NotificationService(예약)·편집 시트(칩 UI)가 같은 규약을 쓰게 한다.
//  Shared 레이어이므로 Foundation만 import한다(위젯/공유 확장과 공유).
//
//  좌표계 정의
//    · 저장 비트(bit): bit0=일, bit1=월, bit2=화, …, bit6=토. repeatWeekdaysMask에 OR로 누적.
//    · iOS weekday : 1=일, 2=월, …, 7=토 (Calendar/UNCalendarNotificationTrigger 규약) → iosWeekday = bit + 1.
//    · UI 순서     : 월~일(0=월, …, 6=일). repeat.png 요일 칩 배치(§3.4/§11).
//
//  정식 단위 테스트 타깃은 미존재(pbxproj 수술 회피) — 대신 순수 함수 + #if DEBUG 자체검증으로 대신한다(Phase 5에서 테스트 타깃 도입 시 이관).
//

import Foundation

enum Weekday {
    /// 저장 비트 인덱스(0=일 … 6=토)를 iOS weekday(1=일 … 7=토)로.
    static func iosWeekday(forBit bit: Int) -> Int { bit + 1 }

    /// 비트마스크에 켜진 비트들을 iOS weekday 배열로 전개(오름차순: 일→토).
    static func iosWeekdays(fromMask mask: Int) -> [Int] {
        (0..<7).compactMap { bit in
            (mask & (1 << bit)) != 0 ? iosWeekday(forBit: bit) : nil
        }
    }

    /// 마스크에 선택된 요일이 하나라도 있는지(weekly 유효성, §3.4 — ≥1 요일 필수).
    static func hasAnyWeekday(_ mask: Int) -> Bool { mask != 0 }

    // MARK: - UI(월~일) ↔ 저장 비트

    /// UI 인덱스(0=월 … 6=일)를 저장 비트 인덱스(0=일 … 6=토)로.
    /// 월(UI 0) → 비트1, … 토(UI 5) → 비트6, 일(UI 6) → 비트0.
    static func bit(forUIIndex uiIndex: Int) -> Int {
        uiIndex == 6 ? 0 : uiIndex + 1
    }

    /// 마스크에서 UI 인덱스(0=월 … 6=일)가 선택돼 있는지.
    static func isSelected(uiIndex: Int, in mask: Int) -> Bool {
        (mask & (1 << bit(forUIIndex: uiIndex))) != 0
    }

    /// 마스크에서 UI 인덱스 비트를 토글한 새 마스크.
    static func toggling(uiIndex: Int, in mask: Int) -> Int {
        mask ^ (1 << bit(forUIIndex: uiIndex))
    }
}

#if DEBUG
/// 좌표계 매핑 자체검증(테스트 타깃 부재의 임시 대체). 앱 시작 시 1회 평가된다.
private let _weekdayMappingSelfCheck: Void = {
    // bit ↔ iOS weekday
    assert(Weekday.iosWeekday(forBit: 0) == 1, "일=비트0→iOS1")
    assert(Weekday.iosWeekday(forBit: 6) == 7, "토=비트6→iOS7")
    // UI(월~일) → 비트
    assert(Weekday.bit(forUIIndex: 0) == 1, "월(UI0)→비트1")
    assert(Weekday.bit(forUIIndex: 5) == 6, "토(UI5)→비트6")
    assert(Weekday.bit(forUIIndex: 6) == 0, "일(UI6)→비트0")
    // 마스크 전개: 월(비트1)+일(비트0) = 0b11 → iOS [1(일), 2(월)]
    let mask = (1 << Weekday.bit(forUIIndex: 0)) | (1 << Weekday.bit(forUIIndex: 6))
    assert(Weekday.iosWeekdays(fromMask: mask) == [1, 2], "월+일 마스크→iOS [일, 월]")
    assert(Weekday.hasAnyWeekday(0) == false)
    assert(Weekday.isSelected(uiIndex: 0, in: mask), "월 선택됨")
    assert(Weekday.toggling(uiIndex: 0, in: mask) & (1 << 1) == 0, "월 토글 시 해제")
}()
#endif
