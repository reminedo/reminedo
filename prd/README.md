# 리마인두 (Reminedo) PRD

## 1. 제품 개요

리마인두는 특정 시간에 **메모·이미지·링크(YouTube/Instagram/Safari)** 를 연결한 알람을 설정하고, 알람이 울렸을 때 **바로 행동으로 이어지게** 하는 iOS 로컬 알람 앱이다.

> **핵심 가치 — 알림에서 끝나지 않고, 행동까지 이어지게 한다.**

서버 없이 동작하며, 알람 데이터와 이미지는 모두 기기 내부에 저장한다. 모든 알람은 **메모·URL·이미지 중 하나의 콘텐츠를 반드시 가진다**(콘텐츠 없는 순수 알람은 MVP 범위 외 — 차별점 유지).

> **용어:** "알림 탭"·"알림 목록"은 화면 이름이다. 개별 항목은 "**알람**"(데이터 모델 `Reminder`). iOS 시스템 통지는 "**로컬 알림**". 화면명 "알림"과 통지 "알림"은 문맥으로 구분한다.

### 기술 스택 (확정)
- **플랫폼:** iOS **17.0+** (SwiftUI, 다크 전용, 한국어 단일 로케일)
- **번들 ID:** `com.geniusjun.reminedo` · **App Group:** `group.com.geniusjun.reminedo` · **URL scheme:** `reminedo`
- **데이터:** SwiftData(알람) · Documents(이미지) · UserDefaults(설정·플래그)
- **알림:** UserNotifications(로컬), 시각=**현지 시각 고정**
- **링크 미리보기:** LinkPresentation · **공유:** Share Extension + App Group + URL scheme

### MVP 알림 한계 & 신뢰 정책
- 표준 로컬 알림은 잠금화면/배너에 **알림 카드**로 표시(시계 앱식 풀스크린 점유 불가 — iOS 26 AlarmKit 전용).
- 액션은 자동으로 다 보이지 않음 — 길게 누르거나 스와이프, **collapsed 최대 2개**.
- **무음 스위치/집중 모드에서 소리가 안 날 수 있음** → 사용자 명시 고지(§13). Time Sensitive는 Phase 5.
- 프라이버시: 알림에는 **제목만** 노출.
- **"저장됨 ≠ 울림" 원칙**(§13).
- **백그라운드 복구 한계(수용):** 권한 재활성화·64한도 자리 복구·예약 재시도는 `scenePhase==.active`(앱 진입) 시 수행됨. 앱을 한 번도 안 열면 복구되지 않는다 — MVP 수용 한계로 명시(BGTaskScheduler는 Phase 5 후보).

### MVP 범위 외
- 순수(콘텐츠 없는) 알람, 다국어, 정식 접근성, 분석/트래킹, 라이트 모드, iCloud, Apple Watch.
- 홈 화면 위젯은 MVP 범위 외지만 **차기 계획(Phase 6, §14)** 으로 사양화됨 — 위젯이 강제하는 스토어 위치 선결정은 §9 Phase 0에 반영.

---

## 2. 핵심 시나리오

### 2.1 다른 앱 사용 중 알람 (배너) — `unlock.png`
1. 등록 시간에 상단 **알림 배너**.
2. collapsed엔 **2개(지금 보기/닫기)**, 길게 누르면 **다시 알림**까지. (액션 등록 순서는 시안 무관 [지금 보기, 닫기, 다시 알림] 고정)
3. **지금 보기(O):** 이미지=앱 내 풀스크린 / URL=외부 열기 / 메모=앱 내 메모 화면.
4. **닫기(X):** 이번 회차 종료(삭제 아님, 반복 유지). **다시 알림:** 스누즈 시간 후 1회 재예약.

### 2.2 잠금화면 알람 — `lock.png`
1. 잠금 상태에서 **표준 잠금화면 알림 카드**. (`lock.png` 풀스크린은 AlarmKit 전용 향후 비주얼 — 시안 재정렬 필요, §3.8)
2. 길게 눌러 액션 노출 → **지금 보기(O):** 시스템 인증 후 앱 진입 → 행동 화면. 카드 본문 탭 = O.

### 2.3 외부 앱 공유로 알람 생성 (URL scheme 딥링크)
1. 공유 시트 → 리마인두 → Extension이 URL 수신.
2. Extension이 URL을 **App Group에 기록** + **`reminedo://add`(파라미터 없는 트리거)로 메인 앱 호출**.
3. 메인 앱 `onOpenURL`이 App Group URL을 읽고(소비·삭제) **추가 시트**를 연다.
4. 시트 오픈 즉시 미리보기 fetch → **제목 자동 채움**(사용자 미입력일 때만, §13).

### 2.4 이미지 알람 생성
1. 추가 → `이미지` → PhotosPicker(권한 불필요) → 앱 내부 JPEG 복사, 파일명만 저장.
2. O를 누르면 앱 내부 풀스크린.

---

## 3. 화면 구조 (다크 전용, 그린 액센트)

### 3.1 내비게이션
- 하단 탭: `알림` · `설정`. 추가/수정은 바텀 시트(좌상단 X, 우상단 ✓). 반복·사운드·다시 알림 시간은 시트 내 푸시.
- **탭 바:** 표준 SwiftUI `TabView` 하단 바. 활성 탭 = 그린(`#00C853`) 채움 아이콘+라벨, 비활성 = 회색. 아이콘: 알림 `bell.fill`, 설정 `gearshape`.
- 추가/수정 **시트**(§3.3)와 O 액션 **풀스크린**(§3.5)은 탭 바 **위 모달**로 덮어 탭 바를 가린다.
- 알림 목록은 마지막 셀이 탭 바에 가리지 않도록 **safe-area inset** 확보.
- 시트 작성 중 다른 탭으로 전환 시 §3.3 "변경 사항을 버릴까요?" 폐기 가드 적용.

### 3.2 알림 탭 — `home.png`
- 타이틀 `알림`, 우상단 `+`.
- 셀: [타입 아이콘] · 알림 시간 · 제목 · 부제(메모→텍스트, URL→`linkTitle`/도메인, 이미지→없음) · On/Off 토글. (사운드/반복/날짜 미표시 — home.png 최소 유지, 배지/검색은 차기)
- **정렬: 시·분 오름차순**(아이폰 기본 알람 방식). Off 알람도 같은 순서에 두되 **충분히 흐림** 처리. 예약 실패 알람은 제자리 + 경고 배지(상단 고정 안 함).
- > **시안 주의:** `home.png`의 셀 시각 순서·Off 흐림 미적용은 더미 시안이다. 실제 구현은 위 규칙(시·분 오름차순, Off 흐림)을 따른다.
- **권한 없음:** ① 상단 경고 배너 + [iOS 설정에서 알림 켜기] ② **각 셀 토글 회색/비활성 + 음소거 아이콘**(거짓 신호 방지).
- **빈 상태:** 그린 벨 + "아직 알람이 없어요" + "메모·링크·사진을 시간 알람에 붙여보세요" + CTA.
- 셀 탭 → 수정 시트.

### 3.3 추가/수정 시트 — `add/*`, `edit/*`
- 세그먼트: `메모` / `URL` / `사진`.
- 공통: 제목, 알림 시간, 반복, 사운드(기본/무음), 다시 알림(토글)+시간.
- 타입별: 메모(최대 500자, `0/500`, 초과 하드 차단) · URL(입력+미리보기 4상태) · 사진(JPG/PNG, 최대 10MB).
- **필수값: 제목 + 시간 + 해당 타입 콘텐츠(메모/유효 URL/이미지). 비면 ✓ 비활성.**
- placeholder 역할 구분(제목="알림에 표시될 제목", 메모="알람 시 펼쳐볼 내용") + 하단 안내 "알림엔 제목만 표시돼요. 내용은 '지금 보기'로 확인할 수 있어요".
- **저장된 콘텐츠 다시보기:** 수정 시트의 이미지 썸네일/메모 영역을 탭하면 fullScreenCover로 읽기전용 풀스크린 표시(편집 상태 보존하며 복귀). URL은 외부 열림.
- **새 알람 기본값:** 시각=현재 시각(분 올림), 타입=메모, 반복=안 함, 사운드=기본, 다시 알림=On, 시간=5분, 활성=On.
- **과거 시각 안내:** none·과거면 "오늘 ○○는 지나서 내일 ○○에 울려요".
- **권한 꺼짐 저장:** "지금은 알림이 꺼져 있어 이 알람은 울리지 않아요 [설정 열기]".
- **세그먼트 전환 시 입력 보존**, 저장 시 현재 타입 값만 영속화. 수정 시트도 타입 변경 허용.
- 다시 알림 Off → 시간 행 숨김.
- **저장:** ✓ 애니메이션(~0.8s) 후 닫힘 + 새 셀 하이라이트.
- **수정 취소:** 변경 있으면 "변경 사항을 버릴까요?" [버리기 / 계속 편집].
- 수정 하단 "알림 삭제"(빨강) → "이 알람을 삭제할까요?" [삭제 / 취소] → "삭제됨 [실행 취소]" 스낵바.

### 3.4 반복 선택 — `repeat.png`
- 주기(택1): **안 함** / 매일 / 매주. 매주 시 요일 칩(월~일) 다중 선택.

### 3.5 행동(O 액션) 화면 (시안 없음 — 사양)
- **이미지:** 순수 Black 풀스크린, 핀치/더블탭 확대, 아래 스와이프 또는 항상 보이는 닫기 X, "쓸어내려 닫기" 힌트 1회. 파일 없으면 "이미지를 불러올 수 없어요"(+셀 썸네일 깨짐 표시).
- **URL:** 외부 앱/Safari(§4.8). 인앱 화면 없음.
- **메모:** 앱 배경 풀스크린, 제목+본문(스크롤), 상단 닫기.

### 3.6 설정 탭 (groupedList)
1. 알림 권한 상태 + [iOS 설정에서 알림 켜기]
2. 기본 사운드(기본/무음) ※ 볼륨 제어 불가
3. 알림 동작 안내 "무음/집중 모드에선 소리가 안 날 수 있어요"
4. 앱 정보(버전)
5. **데이터 삭제:** 확인 다이얼로그 → **알람 레코드 + 이미지 파일 + 사운드 설정만 삭제**, `hasOnboarded` 등 온보딩 플래그 유지, 빈 알림 목록 복귀.

### 3.7 온보딩 (시안 없음)
- `hasOnboarded==false`일 때 **1회만**: 앱 아이콘 + 소개 "메모·링크·사진을 시간 알람에 붙여, 알림에서 바로 행동까지" + [알림 허용] / [건너뛰기]. 둘 중 무엇으로든 종료 후 플래그 set, 이후 미노출(권한 거부해도 진행).

### 3.8 알림 표시 매핑
| 시안 | MVP | 비고 |
|------|------|------|
| `lock.png` 풀스크린 | 표준 잠금화면 카드 | 풀스크린은 AlarmKit(iOS 26+) 향후, 시안 재정렬 필요 |
| `save.png` 체크 | 저장 성공(~0.8s) | 후 닫힘 + 새 셀 하이라이트 |

---

## 4. 기능 요구사항

### 4.1 생성
- 저장 시 로컬 알림 예약, 기본 활성. UUID는 시트 진입 시 즉시 발급.
- 시각=현지 시각 고정. none·과거면 다음 발생(내일 시·분)으로 이월(+안내). 반복은 시·분/요일만. DST 경계는 iOS 기본 동작 수용.

### 4.2 수정 — 재예약 단일 경로(원자성)
- 순서: ① SwiftData 저장(진실원) ② 해당 알람 **모든 pending 취소**(식별자 prefix, `#snooze` 포함 — 수정 시 진행 중 스누즈도 취소: 의도) ③ 재예약(best-effort). 실패해도 DB 유지 + 셀 경고. add/edit/on-off/snooze 모두 단일 `reschedule(reminder)`.

### 4.3 삭제 + Undo
- 삭제 즉시: **pending 알림만 취소** + 스낵바 표시. 레코드/이미지는 **지연 삭제 큐**(이미지 파일명은 UserDefaults `pendingImageDeletes`에 영속, 앱 시작 시 정리). 스낵바 만료/앱 종료 시 실제 삭제 커밋. **Undo = reschedule 재호출**(레코드 그대로라 복구).

### 4.4 On/Off
- Off→pending 취소(데이터 유지), On→재예약 + **결과 피드백**(성공=햅틱, 실패=즉시 셀 경고 배지). 조용한 실패 금지.

### 4.5 로컬 알림 — 식별자/카테고리/페이로드
- 카테고리: 단일 `REMINDER_CATEGORY`(앱 시작 1회). 액션: `OPEN`("지금 보기",`.foreground`)/`DISMISS`("닫기",`.destructive`)/`SNOOZE`("다시 알림"). **정적 라벨**(`lock.png` "5분 후" 표기는 "다시 알림"으로 시안 수정). **Phase 단계: 1a는 카테고리에 `OPEN`/`DISMISS` 2액션만 등록, `SNOOZE` 액션·핸들러는 1b에서 추가**(§2 시나리오의 "다시 알림"은 1b 기준 서술 — 1a 단독 구간엔 조용한 실패 방지를 위해 미노출).
- 식별자: none/daily=`"{id}"`, weekly=`"{id}#wd{weekday}"`(1=일…7=토), snooze=`"{id}#snooze"`. id는 UUID라 prefix 매칭 충돌 없음(테스트).
- 콘텐츠: `title`=제목, `body`=비움, `sound`=기본/nil, `userInfo`=`["reminderId":uuid,"isSnooze":false]`, `threadIdentifier`=`"{HHmm}"`(동시각 그룹핑), `categoryIdentifier`=REMINDER_CATEGORY.
- 트리거: none→`repeats:false`(다음 발생 components), daily→`repeats:true`, weekly→요일별 `repeats:true`.
- 요일 비트: 저장 비트마스크(bit0=일…bit6=토), iOS weekday=bit+1, UI 월~일. 단일 변환 헬퍼+단위테스트.
- 반복 X: 현재 회차만 종료, 다음 회차 자동 유지. 동시각 다중은 제목으로 구분(고유 제목 권장).
- **`nextFireDate(reminder, now)` 헬퍼**(과거안내·트리거 공유)는 정의하되, **목록 정렬에는 사용하지 않음**(정렬은 §3.2 시·분 기준).

### 4.6 스누즈
- 토글(기본 On) + 시간(5/10/15/30, 기본 5). `SNOOZE` 시 `UNTimeIntervalNotificationTrigger(repeats:false)`, 식별자 `#snooze`, `isSnooze=true`(`reminderId`로 reminder 조회해 분 결정), `add` 완료 후 completionHandler. 반복 원본 미변경. 포그라운드 스누즈 시 확인 피드백(잠금화면에선 노출 한계 수용, 대안은 차기).

### 4.7 이미지
- 항상 JPEG 재인코딩 → `/Documents/reminder-images/{id}.jpg`(덮어쓰기). 10MB 초과 다운스케일. 셀 썸네일 다운샘플 + `NSCache`. 앱 삭제 시 삭제.

### 4.8 URL
- 유효성 scheme∈{http,https}, 실패 "올바른 링크를 입력해주세요". 실행 `openURL` → 처리 앱 우선, 실패 시 Safari.

### 4.9 URL 미리보기
- **시트 오픈/입력 시점 fetch**(공유 자동채움). URL마다 새 `LPMetadataProvider`, 타임아웃, 메인 액터 갱신, 디바운스+취소. `linkTitle`/`linkThumbnailFileName` 영속화.
- 4상태: 빈/로딩(스피너)/성공(썸네일+제목, **자동 채움은 제목 미입력 시에만**)/실패("미리보기를 못 불러왔지만 링크는 저장돼요"+도메인).
- 제목 검증과 로딩 분리: 유효 URL이면 도메인을 임시 제목으로 저장 허용.

### 4.10 Share Extension
- 별도 Target + 동일 App Group entitlement. URL/Web URL 우선.
- 페이로드: App Group `UserDefaults(suiteName:)`에 `{url, sharedAt}` JSON 1건(다중 공유 시 첫 URL만 + "첫 번째 링크만 저장됐어요" 토스트) → `reminedo://add` → 메인 앱 소비(삭제). 시트 작성 중이면 §3.3 폐기 가드 후 재오픈. 미지원 → "URL을 리마인두에 저장할 수 없어요".

### 4.11 라우팅(알림·딥링크, 콜드스타트)
- **타입 있는 라우트:** `AppState.pendingRoute`는 단일 UUID가 아니라 목적지 타입을 가진다 — 알림 O는 **행동 화면**, 위젯 탭(§14)은 **편집 시트**로 가야 하므로 분리 필수.
  ```swift
  enum PendingRoute { case act(UUID)   // 알림 O → 행동(이미지/URL/메모) 화면
                      case edit(UUID) } // 위젯 탭 → 편집 시트
  @Observable final class AppState { var pendingRoute: PendingRoute? }
  ```
- delegate 앱 시작 시 등록. `didReceive`(+`UNNotificationDefaultActionIdentifier`=OPEN 동일)에서 `reminderId`로 `.act` 설정. `onOpenURL`의 `reminedo://edit/{uuid}`(위젯)는 `.edit` 설정.
- 소비: `scenePhase==.active` 1회 소비 후 nil. 삭제된 reminder면 무시.
- **시트/풀스크린 충돌:** `.act`(알림 O)는 다른 시트/풀스크린 떠 있으면 dismiss 후 라우팅. **`.edit`(위젯)는 편집 시트 작성 중이면 강제 dismiss 금지 — §3.3 "변경 사항을 버릴까요?" 폐기 가드 적용**(실수 복구 원칙 §13.5).

### 4.12 권한·예약 상태 (Phase 1b)
- `scenePhase==.active`마다 `getNotificationSettings()` 재조회 → 배너·셀 토글 갱신. 권한 새로 켜지면 활성 알람 전체 재예약.
- **64개 한도:** 예약 직전 `pending+신규>64`(임계 60) 검사. **weekly는 all-or-nothing**(요일 칸 전부 못 넣으면 실패 유지). 저장은 허용 + `schedulingFailed=true` + 셀 상시 경고 배지. 배지 탭 → "기기 알림 한도예요. 매주 여러 요일 알람은 요일마다 한 칸을 써요. 다른 알람을 꺼서 자리를 비워주세요."
- **자동 재시도:** pending 감소를 유발하는 모든 mutation(삭제/Off/만료) 후 + `scenePhase==.active` 시, `schedulingFailed` 알람을 **다음 발생 시각이 가까운 순(`nextFireDate`)** 으로 재시도. (이는 목록 표시 정렬과 별개 — 목록 정렬은 §3.2 시·분 기준이고, 재시도 우선순위에만 `nextFireDate` 사용.) 앱 미실행 시 미동작(수용 한계).

---

## 5. 데이터 모델 (SwiftData, v1 초기 스키마 = 마이그레이션 없음)

```swift
@Model
final class Reminder {
    @Attribute(.unique) var id: UUID
    var title: String
    var scheduledAt: Date            // 시·분 항상, 날짜는 none일 때만
    var repeatRule: RepeatRule       // default .none
    var repeatWeekdaysMask: Int      // bit0=일 … bit6=토 (weekly만)
    var isEnabled: Bool              // default true
    var contentType: ContentType     // memo/url/image (콘텐츠 필수)
    var memo: String?
    var imageFileName: String?
    var targetURL: String?
    var linkTitle: String?
    var linkThumbnailFileName: String?
    var snoozeEnabled: Bool          // default true
    var snoozeMinutes: Int           // 5/10/15/30, default 5
    var soundType: SoundType         // default .defaultSound
    var schedulingFailed: Bool       // default false
    var createdAt: Date
    var updatedAt: Date
}

enum ContentType: String, Codable { case memo, url, image }
enum RepeatRule: String, Codable { case none, daily, weekly }
enum SoundType: String, Codable { case defaultSound, silent }
```
> 신규 프로젝트라 위 전 필드를 v1에 포함, 마이그레이션 불필요. ModelContext `@MainActor`, 알림은 별도 `@MainActor NotificationService`.

---

## 6. 저장·유지 정책
- 알람: SwiftData / 이미지: Documents / 설정·플래그: UserDefaults. 종료·재부팅·업데이트 후 유지, 앱 삭제 시 삭제, 기기 변경 복구 없음.

---

## 7. 권한 · 엔타이틀먼트 · 플래그
- 알림: 온보딩 요청(alert/sound/badge). 거부 시 §3.2/§3.3 신뢰 처리.
- 사진: `PhotosPicker`만 → 권한·usage description 불필요.
- App Group `group.com.geniusjun.reminedo`(메인 + Share Extension + Widget Extension 3곳). **SwiftData 스토어를 이 App Group 컨테이너에 두며 Phase 0에서 확정**(위젯 대비, §9·§14.2). URL scheme `reminedo`(`CFBundleURLTypes`). 다크 강제: `UIUserInterfaceStyle=Dark`.
- **UserDefaults 1회성 플래그:** `hasOnboarded`, `hasSeenLockHint`(잠금화면 사용법 1회 안내), `pendingImageDeletes`(지연 삭제 큐).

---

## 8. 엣지 케이스 / 마이크로카피
| 상황 | 처리/문구 |
|------|------|
| 권한 없음 | 배너 "알림 권한이 꺼져 있어 알람이 울리지 않아요." + 셀 토글 비활성 |
| 권한 꺼짐 저장 | "지금은 알림이 꺼져 있어 이 알람은 울리지 않아요 [설정 열기]" |
| 무음/집중모드 | 설정·온보딩 고지 |
| 과거 시각 | "오늘 ○○는 지나서 내일 ○○에 울려요" |
| 알람 0개 | 빈 상태 + 기능 소개 + CTA |
| 삭제 | "이 알람을 삭제할까요?" → "삭제됨 [실행 취소]" |
| 64 한도 | 셀 경고 배지 + 한도 안내 |
| 이미지 없음/깨짐 | "이미지를 불러올 수 없어요." (셀 썸네일도) |
| 미리보기 실패 | "미리보기를 못 불러왔지만 링크는 저장돼요." |
| 잘못된 URL | "올바른 링크를 입력해주세요." |
| 다중 공유 | "첫 번째 링크만 저장됐어요." |
| 미지원 공유 | "URL을 리마인두에 저장할 수 없어요." |

> 톤: 안내문 해요체, 버튼 명사형, 파괴 액션 빨강.

---

## 9. 구현 우선순위
- **Phase 0 — 셋업:** 배포 타깃 26.5→17.0 · `UIUserInterfaceStyle=Dark` · **App Group entitlement `group.com.geniusjun.reminedo` + SwiftData 스토어를 App Group 컨테이너에 생성**(`ModelConfiguration(groupContainer: .identifier("group.com.geniusjun.reminedo"))`) · 알림 권한 요청(1a 검증용 임시, 정식 온보딩은 Phase 5). **1a 최소 셋업은 여기까지.** URL scheme `reminedo` · `SNOOZE` 포함 카테고리 · Share/Widget Extension **타깃 멤버십**은 해당 Phase(1b/2/4/6) 직전에 구성.
  - > **선행조건(중요):** 스토어 위치(App Group)는 **반드시 Phase 0에서** 잡는다. 앱 샌드박스 기본 위치로 시작 후 Phase 6(위젯)에서 App Group으로 옮기면 기존 데이터 마이그레이션이 필요해져 §5 "마이그레이션 없음" 원칙과 충돌한다(데이터 증발=신뢰붕괴). 현 코드가 SwiftData 미구현 상태라 지금 잡으면 비용 0.
- **Phase 1a — 빨리 울려보기:** 알림 목록/시·분 정렬/빈상태 · 추가·수정 시트(메모) · 단순 삭제 · On/Off · 예약(none/daily·식별자) · O/X · 라우팅 · 메모 화면 · 다크.
- **Phase 1b — 신뢰·반복:** weekly+요일 · 64한도+자동 재시도 · 삭제 Undo · 권한/예약 실패 신뢰 처리(배너·셀 토글·배지) · 스누즈.
- **Phase 2 — URL:** 입력/검증 · 미리보기(4상태·자동채움) · O 외부 열기+fallback.
- **Phase 3 — 이미지:** PhotosPicker · JPEG 저장/썸네일 · O 풀스크린 뷰어 · 다시보기.
- **Phase 4 — Share Extension:** Target+App Group+딥링크 · 페이로드 · 추가 시트.
- **Phase 5 — 마무리/확장:** 설정·온보딩·데이터 삭제 · Time Sensitive · BGTask 복구 · (확장) AlarmKit 풀스크린(iOS 26+) · 셀 정보 배지/검색 · 접근성/다국어.
- **Phase 6 — 홈 화면 위젯(우선순위 낮음, §14):** **6a 읽기 전용**(Widget Extension·App Group 공유 스토어 읽기·Medium/Large·`reminedo://edit` 딥링크·토글=상태표시) → **6b 인터랙티브 토글**(AppIntent 앱 프로세스 라우팅 재예약).

---

## 10. 변경 이력 (info.md → 본 PRD)
| 항목 | info.md | 본 PRD | 근거 |
|------|---------|--------|------|
| 콘텐츠 | 이미지/링크 | 메모/URL/이미지 (콘텐츠 필수) | 모순 해소 + 결정 |
| 탭/추가 | 알람·설정 탭 | 알림·설정 탭, 추가는 바텀 시트 | home.png + 결정 |
| 탭/타이틀 | 홈 | 알림 (탭 바 명시) | home.png 개정(2026-06) |
| 반복 | 5종 | none/daily/weekly+요일 | repeat.png + 결정 |
| 잠금화면 | 풀스크린 | 표준 카드(MVP), AlarmKit 향후 | UN 제약 |
| 셀 표시 | 사운드/반복 | 미표시(home.png 최소) | 결정 |
| 정렬 | 미정 | 시·분 오름차순 | 결정(아이폰 기본 알람) |
| 사진 권한 | 전체 접근 | PhotosPicker(불필요) | PHPicker |
| 사운드 | "크기" | 기본/무음 | 볼륨 제어 불가 |
| 스누즈 | Phase 5 | MVP(1b), 5/10/15/30, 기본 On | 결정 |
| URL 미리보기 | 미언급 | MVP, 오픈 시 fetch+자동채움 | 결정 |
| Share | App Group | 딥링크+App Group | 직접 오픈 불가 |
| 배포 타깃 | 미정 | iOS 17.0 (26.5→하향) | 결정 |
| 알림 노출 | 미정 | 제목만 | 결정 |
| 시간대 | 미정 | 현지 시각 고정 | 결정 |
| 백그라운드 복구 | 미정 | scenePhase 의존, 미실행 시 복구불가(수용) | 결정 |
| 위젯 | (범위 외) | Phase 6 (읽기전용→인터랙티브) | widget.png 추가(2026-06) |
| 스토어 위치 | 미정 | Phase 0부터 App Group 컨테이너 | 위젯 선행조건 |

---

## 11. 디자인 토큰 (잠정)
- 그린 `#00C853` 계열, 배경 `#000000`, 카드 `#1C1C1E` 계열.
- SF Symbols: 메모 `text.bubble`, URL `link`, 이미지 `photo`, 경고 `exclamationmark.triangle.fill`, 음소거 `bell.slash`. 탭 바: 알림 `bell.fill`, 설정 `gearshape`.
- 탭 바: 활성 그린 `#00C853`(채움 아이콘+라벨), 비활성 회색.
- 시간 인라인 휠, 세그먼트 아이콘+텍스트 커스텀, 카드 ~14pt, 칩 원형.
- 시안 없는 화면(사양 구현): 빈상태·설정·온보딩·사운드선택·미리보기 4상태·이미지/메모 뷰어·권한 배너·다이얼로그·스낵바·예약실패 배지.

---

## 12. MVP 정의
리마인두 MVP는 아이폰 기본 알람 앱과 유사한 로컬 알람 앱이다. 사용자는 알람을 만들고 메모·이미지·URL 중 하나를 연결한다. 시간이 되면 iOS 로컬 알림(제목만)이 배너/잠금화면 카드로 뜨고, 지금 보기(O)·닫기(X)·다시 알림 중 선택한다. O를 누르면 이미지는 앱 내부 풀스크린, URL은 외부 링크, 메모는 앱 내부 메모 화면으로 이어진다. 외부 앱 공유로도 URL 알람을 만들 수 있다(딥링크). 서버 없이 동작하고 모든 데이터는 기기 내부에 저장된다. 시각은 현지 시각 고정이며, 풀스크린 잠금화면 알람·Time Sensitive는 향후 확장으로 둔다.

---

## 13. 사용자 신뢰 & UX 원칙
1. **저장 ≠ 울림:** 권한 꺼짐/예약 실패를 저장 시점·셀·배너에서 노출. 권한 꺼지면 셀 토글을 켜진 것처럼 두지 않는다.
2. **조용한 실패 금지:** On 재예약·64한도 실패를 시각/햅틱 피드백. `schedulingFailed`는 셀 상시 배지 + 조치 안내, 자동 재시도(§4.12).
3. **솔직한 한계 고지:** 무음/집중모드 미발신, 백그라운드 미복구를 온보딩·설정에 명시.
4. **예측 가능성:** 과거 시각 이월·외부 링크 이동·"닫기는 삭제 아님" 안내. 스누즈 후 다음 알림 인지.
5. **실수 복구:** 삭제 Undo 스낵바 + 이미지 지연 삭제.
6. **다시보기 경로:** 저장 이미지/메모를 수정 시트 콘텐츠 영역 탭으로 읽기전용 풀스크린.
7. **공유 마찰 최소화:** 오픈 즉시 미리보기 fetch로 제목 자동 채움(미입력 시에만), 로딩이 저장을 막지 않음.
8. **첫 경험 유도:** 첫 알람 저장 후 "잠금화면에선 알림을 길게 눌러 버튼을 여세요" 1회 안내(`hasSeenLockHint`).

---

## 14. 홈 화면 위젯 (Phase 6 · 우선순위 낮음 — 핵심 기능 이후) — `widget.png`

> 핵심 기능(Phase 0~5) 완료 후 추가. 단 **스토어 위치(App Group)는 Phase 0에서 선결정**된다(§9 선행조건). 6a(읽기 전용)를 먼저, 6b(인터랙티브 토글)를 차기로 단계화한다.

### 14.1 개요
- WidgetKit 홈 화면 위젯. 패밀리 **systemMedium + systemLarge**(위젯 타깃 배포 타깃도 iOS 17.0).
- 구성: 헤더(앱 아이콘 + "리마인두") + 알람 행(시각 AM/PM · 타입 아이콘 · 제목 1줄 · On/Off 토글).
- 위젯은 `home.png` 목록의 축약본 — 흘끗 보고 오늘 알람을 확인하는 glanceable 표면.

### 14.2 데이터 공유 & 갱신
- **App Group 공유 SwiftData 스토어**(Phase 0에서 확정, §9·§7). `Reminder` 스키마·`ModelContainer` 팩토리는 앱+위젯 **공유 코드**(shared framework 또는 양 타깃 멤버십).
- 위젯은 **읽기 전용**. `getTimeline`마다 **새 `ModelContext`로 fetch**(iOS 17 stale-fetch 회피). 앱↔위젯 **양방향 쓰기 금지**.
- **스냅샷 JSON 방식 비채택** — 이중 진실원이 되어 동기화 누락 시 위젯이 "저장≠표시" 거짓신호를 내고 §13.1과 충돌.
- **reload 트리거:** 앱은 `save()` 후 `WidgetCenter.shared.reloadAllTimelines()`를 다음 시점마다 호출 — ① `reschedule` 성공/실패 ② **삭제 즉시** ③ 삭제 Undo(reschedule 경유) ④ 64한도 자동 재시도 결과 ⑤ 권한 재활성 전체 재예약 **완료 후 1회(배치)**. ("reschedule 직후"만으로는 삭제 경로가 누락되므로 위 지점을 명시 트리거로 둔다.)

### 14.3 표시 · 정렬
- **정렬: §3.2와 동일 시·분 오름차순**(앱 목록과 일치 — 화면 간 순서 일관, §13.4). Off 알람 포함(흐림). 동시각 tie-break = `createdAt`.
- **행 수:** systemLarge 최대 5행(초과 시 6번째 행을 "+N개 더"로 대체), systemMedium 최대 2행(+ "+N개 더"). "+N개 더" 탭 = 앱 알림 목록 딥링크.
- 위젯 행은 **부제 생략**(공간), 타입 아이콘만(`text.bubble`/`link`/`photo`).
- **이미지 썸네일 미표시(의도적):** 이미지는 앱 샌드박스 `Documents`에 있어 위젯이 직접 읽을 수 없다 → 타입 아이콘만. 향후 위젯 썸네일을 원하면 이미지 저장 위치도 App Group으로 옮겨야 함(스토어 위치와 동류의 선행 제약).
- 권한 꺼짐/예약 실패(`schedulingFailed`)는 헤더·셀 경고로 표시해 거짓신호 방지(정교화는 6b).
- 빈 상태: "알람이 없어요"(탭 → 앱).

### 14.4 타임라인 · 위젯 상태
- 시각은 **고정 텍스트**(카운트다운 아님) → **단일 엔트리 + 데이터 변경 기반 reload**(자정/시각 타이머 불필요 → 배터리·예산 유리).
- `placeholder(in:)` = 더미 회색 행으로 레이아웃 유지. 위젯 갤러리 `snapshot` = 대표 더미 데이터.
- **잠금화면/StandBy 위젯은 범위 외** — 홈 화면 systemMedium/Large만(잠금화면 redacted 제목 정책 회피).

### 14.5 탭 · 딥링크
- systemMedium/Large는 각 행을 `Link(reminedo://edit/{uuid})`로 감쌈. 헤더/빈 영역 탭 = 앱 목록 열기.
- §4.11 라우팅 **재사용** — `onOpenURL`이 `reminedo://edit/{uuid}`를 받아 `PendingRoute.edit(uuid)` 설정 → 편집 시트. 위젯 딥링크는 기존 라우팅 인프라의 **`.edit` 타입 신규 추가**일 뿐 별도 메커니즘 아님. 편집 시트 작성 중 도착 시 §3.3 폐기 가드 적용(강제 dismiss 금지).

### 14.6 토글 단계
- **Phase 6a — 읽기 전용(먼저):** 토글은 현재 `isEnabled`를 **표시만 하는 비인터랙티브** 요소로 그린다. `widget.png`의 인터랙티브 스위치 외형은 **6b 최종 비주얼**이며, 6a는 약하게/상태 아이콘으로 그려 "탭 컨트롤이 아님"을 신호한다(Off 흐림과 결합). 토글/행 탭 → 앱 편집 시트 딥링크로 사용자가 끄고 켠다. **거짓신호 0.**
- **Phase 6b — 인터랙티브 토글(차기):** `AppIntent`를 앱+위젯 양 타깃 + `ForegroundContinuableIntent`로 **앱 프로세스에서 실행** → `isEnabled` 토글 + 기존 `reschedule(reminder)` 단일 경로 + `save()` + reload. 재예약 실패(권한 꺼짐/64한도/백그라운드 깨우기 실패) 시 **변경 미적용 + 셀 경고**로 거짓신호 차단.
- **채택 금지:** ⓐ 위젯 익스텐션이 `UNUserNotificationCenter`로 **직접 재예약**(샌드박스 제약, Apple 미보장) — 토글만 켜지고 알림은 안 걸리는 거짓신호. ⓑ 토글만 바꾸고 **재예약은 앱 다음 활성화 때**(즉시 안 울림 = §13.1 위반).

### 14.7 신규 타깃 · 엔타이틀먼트 · 공유 코드
- **Widget Extension 타깃**(WidgetKit + SwiftUI, 배포 타깃 17.0).
- **엔타이틀먼트:** App Group `group.com.geniusjun.reminedo`(메인 + Share + Widget 3곳). 위젯 타깃은 알림 권한 요청 안 함.
- **공유 코드:** `Reminder` 스키마·enum, `ModelContainer` 팩토리(`groupContainer:` 설정). 6b 시 토글 `AppIntent`를 앱+위젯 양 타깃 멤버십.
