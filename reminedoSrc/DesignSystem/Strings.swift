//
//  Strings.swift
//  reminedo
//
//  한국어 문자열의 단일 출처. 특히 "알림"(화면명/iOS 통지)과 "알람"(Reminder 엔티티)의
//  용어 구분(§1 용어 정의)을 코드에서도 일관되게 유지한다.
//

import Foundation

enum Strings {
    enum Tab {
        static let reminders = "알림"   // 화면명(알람 목록 탭)
        static let settings = "설정"
    }

    enum Empty {
        static let title = "아직 알람이 없어요"
        static let message = "메모·링크·사진을 시간 알람에 붙여보세요"
    }

    /// 설정 탭(§3.6). 그룹 List, 다크.
    enum Settings {
        static let placeholder = "설정은 곧 추가됩니다"   // (미사용) 구 플레이스홀더

        static let title = "설정"

        // 1. 알림 권한 상태
        static let permissionSection = "알림 권한"
        static let permissionOn = "알림 허용됨"
        static let permissionOff = "알림 꺼짐"
        static let permissionUndetermined = "아직 허용하지 않음"
        static let openSystemSettings = "iOS 설정에서 알림 켜기"

        // 2. 기본 사운드
        static let soundSection = "기본 사운드"
        static let soundFooter = "새 알람에 적용돼요. 알림 볼륨은 앱에서 제어할 수 없어요."

        // 3. 알림 동작 안내
        static let behaviorSection = "알림 동작"
        static let behaviorInfo = "무음/집중 모드에선 소리가 안 날 수 있어요"

        // 4. 앱 정보
        static let infoSection = "앱 정보"
        static let versionLabel = "버전"
        static func versionText(_ version: String, build: String) -> String { "\(version) (\(build))" }

        // 5. 데이터 삭제
        static let dataSection = "데이터"
        static let deleteAll = "모든 데이터 삭제"
        static let deleteAllConfirmTitle = "정말 모든 데이터를 삭제할까요?"
        static let deleteAllMessage = "모든 알람과 사진이 삭제돼요. 되돌릴 수 없어요."
        static let deleteAllConfirm = "삭제"
        static let deleteAllCancel = "취소"
    }

    /// 온보딩(§3.7). 1회 노출.
    enum Onboarding {
        static let title = "리마인두"
        static let intro = "메모·링크·사진을 시간 알람에 붙여, 알림에서 바로 행동까지"
        static let allow = "알림 허용"
        static let skip = "건너뛰기"
    }

    /// 첫 알람 저장 후 1회 잠금화면 사용법 안내(§13.8).
    enum LockHint {
        static let message = "잠금화면에선 알림을 길게 눌러 버튼을 여세요"
    }

    enum List {
        static let title = "알림"          // 알림 목록 화면 타이틀(§3.2)
        static let add = "추가"            // + 버튼 접근성 라벨
    }

    /// 권한·예약 신뢰 처리(§3.2/§4.12/§13.1).
    enum Permission {
        static let bannerOffMessage = "알림 권한이 꺼져 있어 알람이 울리지 않아요."
        static let openSettings = "iOS 설정에서 알림 켜기"
        static let grantedToast = "알림이 켜졌어요"
    }

    /// 예약 실패(64한도 등) 안내(§4.12/§8).
    enum Scheduling {
        static let limitTitle = "기기 알림 한도예요"
        static let limitMessage = "매주 여러 요일 알람은 요일마다 한 칸을 써요. 다른 알람을 꺼서 자리를 비워주세요."
        static let limitConfirm = "확인"
    }

    /// 삭제 Undo 스낵바(§4.3/§8).
    enum Snackbar {
        static let deleted = "삭제됨"
        static let undo = "실행 취소"
    }

    /// 추가/수정 시트(§3.3).
    enum Edit {
        static let addTitle = "새로운 알림"
        static let editTitle = "알림 편집"

        static let cancel = "취소"
        static let save = "저장"

        static let segmentMemo = "메모"
        static let segmentURL = "URL"
        static let segmentImage = "사진"
        static let comingSoon = "곧"        // 비활성 표시(현재 미사용 — 메모/URL/사진 모두 활성)

        // 이미지 콘텐츠(§3.3/§4.7)
        static let imageLabel = "사진"
        static let imagePick = "사진 선택"
        static let imageChange = "사진 변경"
        static let imagePickHint = "JPG·PNG 사진을 골라 알람에 붙여보세요"

        static let titleLabel = "제목"
        static let titlePlaceholder = "알림에 표시될 제목"

        static let memoLabel = "메모"
        static let memoPlaceholder = "알람 시 펼쳐볼 내용"
        static let memoLimit = 500

        // URL 콘텐츠(§3.3/§4.8/§4.9)
        static let urlLabel = "링크"
        static let urlPlaceholder = "https://"
        static let urlInvalid = "올바른 링크를 입력해주세요"
        static let urlPreviewHint = "링크를 입력하면 미리보기를 보여드려요"
        static let urlPreviewFailure = "미리보기를 못 불러왔지만 링크는 저장돼요"
        static let urlOpen = "다시 보기"

        static let timeLabel = "알림 시간"
        static let repeatLabel = "반복"
        static let repeatNone = "안 함"
        static let repeatDaily = "매일"
        static let repeatWeekly = "매주"

        /// 요일 칩 라벨(UI 순서 월~일, §3.4/§11).
        static let weekdayLabels = ["월", "화", "수", "목", "금", "토", "일"]

        static let soundLabel = "사운드"
        static let soundDefault = "기본"
        static let soundSilent = "무음"

        // 다시 알림(스누즈, §3.3/§4.6) — 시간은 1~60분 휠에서 1분 단위로 선택.
        static let snoozeLabel = "다시 알림"
        static let snoozeTimeLabel = "다시 알림 시간"
        static func snoozeMinutesText(_ minutes: Int) -> String { "\(minutes)분" }

        static let delete = "알림 삭제"
        static let deleteConfirmTitle = "이 알람을 삭제할까요?"
        static let deleteConfirm = "삭제"
        static let deleteCancel = "취소"

        static let discardTitle = "변경 사항을 버릴까요?"
        static let discardConfirm = "버리기"
        static let discardCancel = "계속 편집"
    }

    /// 외부 앱 공유(Share Extension, §2.3/§4.10/§8). 토스트·미지원 안내는 확장에서 노출되지만
    /// 카피는 단일 출처를 위해 여기 모은다(확장 타깃은 이 모듈을 공유하지 않아 값만 복제됨 — 동기 필수).
    enum Share {
        static let multipleToast = "첫 번째 링크만 저장됐어요."
        static let unsupported = "URL을 리마인두에 저장할 수 없어요."
    }

    /// 행동(O 액션) 화면(§3.5).
    enum Action {
        static let close = "닫기"
        static let imageLoadFailed = "이미지를 불러올 수 없어요"   // 파일 없음/깨짐(§8)
        static let swipeDownHint = "쓸어내려 닫기"                 // 이미지 뷰어 1회 힌트(§3.5)

        // 인앱 lock 화면(알림 탭 진입, lock.png 재현). 자물쇠 아이콘 없음.
        static let brand = "리마인두"
        // 이슈8: lock.png 시안 라벨("N분 후 다시 알림" / "알림 닫기" / "지금 보기").
        static func snoozeButton(_ minutes: Int) -> String { "\(minutes)분 후 다시 알림" }
        static let dismissButton = "알림 닫기"
        static let openButton = "지금 보기"

        // 이슈10: 포그라운드 커스텀 알림 배너(on_notice.png)의 짧은 버튼 라벨.
        static let snoozeShort = "다시 알림"
        static let cancelShort = "취소"
    }

    /// 이슈9: watchdog(dead-man's switch) 알림. 앱 강제종료 후 ~N분 뒤 발화.
    enum Watchdog {
        static let title = "앱이 꺼져 있어요"
        static let body = "리마인두가 켜져 있어야 알람이 울려요. 알람을 놓치지 않으려면 앱을 다시 켜주세요."
    }
}
