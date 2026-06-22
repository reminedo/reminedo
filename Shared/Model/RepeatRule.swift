//
//  RepeatRule.swift
//  reminedo
//
//  알람 반복 주기(§3.4). weekly는 repeatWeekdaysMask와 함께 사용한다.
//

import Foundation

enum RepeatRule: String, Codable, Sendable {
    case none
    case daily
    case weekly
}
