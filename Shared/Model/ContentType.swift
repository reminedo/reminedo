//
//  ContentType.swift
//  reminedo
//
//  알람이 담는 콘텐츠 종류. 모든 알람은 메모/URL/이미지 중 하나를 반드시 가진다(§1).
//  Shared 레이어 — Foundation만 import(위젯/공유 확장과 공유 예정).
//

import Foundation

enum ContentType: String, Codable, CaseIterable, Sendable {
    case memo
    case url
    case image
}
