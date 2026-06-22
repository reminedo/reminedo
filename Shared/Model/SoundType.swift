//
//  SoundType.swift
//  reminedo
//
//  알림 사운드(기본/무음). 볼륨 제어는 불가(§3.6).
//

import Foundation

enum SoundType: String, Codable, Sendable {
    case defaultSound
    case silent
}
