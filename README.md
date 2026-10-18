# Kornflake

Kontakt 라이브러리의 **실제 샘플**을 Kontakt Player 없이 들어보는 macOS 도구입니다.
악기를 고르고, 근음·스케일·코드를 선택한 뒤, 순차 또는 동시에 재생할 수 있습니다.

```
/Volumes/Ultra Touch/Pile/+Kontakt   ← 기본 스캔 경로
```

---

## 1. 먼저 확인한 사실

이 컬렉션의 `.nki` 파일을 전수 조사한 결과는 다음과 같습니다.

| 구분 | 수량 | Kontakt Player 없이 재생 |
|---|---:|---|
| 전체 `.nki` | 6,882 | — |
| Kontakt 2/3 (비암호화, zlib XML) | 5,406 | **가능** |
| Kontakt 4.2 (FastLZ 바이너리) | 1 | 미지원 |
| Kontakt 5+ (`hsin` 컨테이너, 암호화) | 1,475 | 불가능 |

Kontakt 5+ 파일은 내부 프리셋이 `SUBTREE` + `ENCRYPT` 청크로 암호화되어 있습니다.
예: Alicia's Keys, Noire, Play Series, Session Guitarist, Symphony Essentials 등.
이 도구는 **암호화를 해제하지 않습니다.** 해당 악기는 목록에 표시하되
`K5 · protected`로 표시하고 재생을 비활성화합니다.

반면 Kontakt 2/3 세대의 DRM-free 악기는 프리셋이 zlib 압축 XML로 저장되어 있어
샘플 매핑(키 범위, 벨로시티, 루트키, 샘플 경로)을 직접 읽을 수 있습니다.

### 실제로 샘플까지 찾아지는 악기

| 라이브러리 | DRM-free 악기 수 | 샘플 형태 |
|---|---:|---|
| E-mu Pack | 3,304 | 외부 WAV |
| Ensoniq ASR | 808 | 외부 WAV |
| Vintage Pro | 505 | 외부 WAV |
| Yamaha Motif ES | 402 | `.nki` 모놀리스 내장 WAV |
| Virtuoso | 256 | 외부 WAV |
| **합계** | **5,275** | |

이 중 **5,269개**는 첫 샘플 경로까지 확인되었습니다.
Yamaha Motif ES의 나머지 6개는 모놀리스 헤더만 있고 XML 매핑이 없는 복사본입니다.

K2 파일 5,406개 중 137개는 XML 매핑을 찾지 못했습니다(일부는 K5 스타일이거나
샘플 폴더가 없는 복사본). 앱은 매핑이 확인된 K2만 DRM-free로 표시하고,
나머지는 `K2 · no mapping`으로 표시합니다. 일부 모놀리스는 헤더만으로
판정하므로 선택 시 오류가 날 수 있습니다.

> 요약: **Kontakt Player 없이 실제 음색을 재생하려면 DRM-free K2 계열만 가능**합니다.
> 보호된 K5 라이브러리는 정식 Kontakt/Kontakt Player가 필요합니다.

---

## 2. 동작 방식

Kontakt 엔진이나 별도 샘플러를 새로 만들지 않습니다.

1. `.nki` 헤더를 읽어 Kontakt 2/3 / 4.2 / 5+ 형식을 구분합니다.
2. K2 파일의 zlib 스트림을 풀어 `K2_Container` XML을 파싱합니다.
3. 그룹·존에서 키 범위, 벨로시티, 루트키, 튜닝, 볼륨/팬, 샘플 시작/끝, 루프 정보를 읽습니다.
4. NI 경로 인코딩(`@bd016...F00000019000...wav`)을 실제 경로로 디코딩합니다.
5. 모놀리스 `.nki`는 내부 WAV 블록을 캐시로 추출합니다.
6. `AVAudioEngine` + `AVAudioUnitVarispeed`로 샘플을 재생합니다.
   - 44.1 kHz / stereo로 리샘플링
   - 존의 sampleStart/sampleEnd 적용
   - 짧은 fade in/out
   - 24개 보이스 풀

즉, **샘플러 엔진을 새로 설계하지 않고** macOS 기본 오디오 스택 위에
“존 선택 + 샘플 재생 + 피치 변속”만 구현했습니다.

### 스케일 / 코드

- 스케일: Major, Natural/Harmonic/Melodic Minor, Dorian, Phrygian, Lydian,
  Mixolydian, Locrian, Major/Minor Pentatonic, Blues, Diminished (W–H / H–W),
  Whole Tone, Chromatic
- 코드: Major, Minor, Dim, Aug, Sus2, Sus4, Maj7, m7, 7, dim7, ø7, mMaj7,
  6, m6, add9, 9, m9, 7sus4
- 근음 + 옥타브 선택
- Sequential(순차) / Together(동시)
- 내림차순, 2옥타브, 반복 재생
- Note length: 1/16, 1/8, 1/4, 1/2, 1, 2, 3, 4 (BPM 40–240)
- Pedal hold: 음 길이로 자르지 않고 샘플의 자연 감쇠까지 재생

---

## 3. 빌드 및 실행

요구 사항: macOS 14 이상, Swift 6 툴체인(Xcode 또는 Command Line Tools).

```bash
cd /Users/dp/Repository/kornflake

# .app 번들 생성 후 실행 (GUI/TCC 권한 때문에 번들 실행을 권장)
./scripts/build-app.sh
open Kornflake.app
```

> `swift run`으로도 프로세스는 뜨지만, 번들 Info.plist가 없어
> 일반 앱처럼 전면 활성화되지 않을 수 있습니다. 위 스크립트를 사용하세요.

첫 실행 시 이동식 볼륨 접근 권한을 요청합니다. **Allow**를 선택하세요.
(스캔은 외장 볼륨의 `.nki`를 읽기 위해 필요합니다.)

권한을 거부했다면 **시스템 설정 → 개인정보 보호 및 보안 → 파일 및 폴더**에서
Kornflake의 이동식 볼륨 접근을 허용한 뒤 `⌘R`로 다시 스캔하세요.

---

## 4. 사용법

1. 왼쪽에서 라이브러리를 고릅니다.
2. 툴바의 **DRM-free only**가 켜져 있으면 재생 가능한 악기만 보입니다.
   보호된 K5 악기까지 보려면 끄면 됩니다.
3. 가운데 목록에서 악기를 선택합니다.
4. 필요하면 **Articulation**에서 그룹(연주법)을 고릅니다.
5. **Play C4**로 음색을 먼저 확인합니다.
6. **Scale & Chord**에서 모드·근음·스케일/코드를 정합니다.
7. **Sequential / Together**, **Loop**, **Note length**를 조정합니다.
8. **Play**(또는 Audition 메뉴)로 재생합니다.

단축키:

- `⌘T` — C4 테스트
- `Space` — 재생
- `⌘.` — 정지
- `⌘R` — 다시 스캔
- `⇧⌘O` — Kontakt 폴더 선택

---

## 5. 지원 범위와 한계

### 지원

- Kontakt 2/3 비암호화 `.nki`
- 외부 WAV/AIFF 샘플
- K2 모놀리스 `.nki` 내장 WAV
- 다중 그룹/존, 키·벨로시티 범위, 루트키, 튜닝, 볼륨/팬
- sampleStart / sampleEnd

### 미지원

- Kontakt 5+ 암호화 프리셋 (`hsin` + `ENCRYPT`) — 복호화하지 않음
- Kontakt 4.2 (FastLZ) — Scarbee Funk Guitarist 1개
- Kontakt 스크립트, 이펙트, 필터, 엔벨로프, 라운드 로빈/키스위치
- NCW 디코딩 — 이 컬렉션의 K2 악기에는 NCW가 없어 포함하지 않았습니다.
- 지속음 루프 재생 — 미리보기에서는 음을 Note length 또는 Pedal hold에 따라 처리합니다.
  Pedal hold도 샘플 버퍼의 12초 상한 안에서 동작합니다.
- 벨로시티 레이어는 고정 벨로시티(100)에 가장 가까운 존 하나만 사용합니다.

### 알아둘 점

- K5 악기를 선택하면 “Kontakt 5+ encrypted container” 안내가 나옵니다.
  이는 버그가 아니라 DRM을 우회하지 않기 위한 의도된 동작입니다.
- K2라도 XML이 없거나 샘플 폴더가 빠진 복사본은 재생되지 않습니다.
- 라이브러리 라이선스는 사용자가 보유한 것이어야 합니다.

---

## 6. 테스트

```bash
swift test
```

테스트는 실제 볼륨이 있을 때만 해당 케이스를 실행합니다.

- Virtuoso `Piccolo 2.nki` 파싱 + 외부 WAV 로드
- Yamaha Motif ES `03 Mtrance.nki` 모놀리스 파싱 + 내장 WAV 추출
- NI 경로 디코딩
- 스케일/코드 노트 생성
- 스캐너가 K2/K5를 모두 찾는지
- `PreviewPlayer`가 오디오 엔진을 시작하고 버퍼를 스케줄하는지

---

## 7. 프로젝트 구조

```
Sources/KornflakeCore/
  Models.swift            데이터 모델, 스케일/코드 정의
  KontaktScanner.swift    폴더 스캔 및 형식 감지
  K2Parser.swift          K2 헤더/zlib/XML/경로 디코딩
  K2Monolith.swift        모놀리스 내장 샘플 인덱스/추출
  SampleResolver.swift    샘플 경로 해석 + basename fallback
  AudioSampleLoader.swift WAV/AIFF 로드, 44.1k stereo 변환, 트림/fade
  PreviewPlayer.swift     24-voice 미리보기 플레이어
  Audition.swift          스케일/코드 노트 생성
Sources/Kornflake/
  KornflakeApp.swift      SwiftUI 앱 진입점
  AppModel.swift          스캔/파싱/재생 상태 머신
  ContentView.swift       3-column UI
scripts/build-app.sh      .app 번들 생성
scripts/make-icon.sh      AppIcon.icns 재생성
scripts/make-icon.swift   아이콘 드로잉 소스
assets/AppIcon.icns       macOS 앱 아이콘
assets/AppIcon-1024.png   아이콘 원본
```

---

## 8. 참고

- ConvertWithMoss (Jürgen Moßgraber, LGPLv3) — K2/K5 NKI 구조와 모놀리스 포맷 조사에 참고
- monomadic/ncw (MIT/Apache-2.0) — NCW 포맷 조사 (이 앱에는 미포함)
- Apple AVFoundation — 오디오 로딩/리샘플링/재생

Kontakt, Kontakt Player, Native Instruments는 Native Instruments GmbH의 상표입니다.
이 프로젝트는 Native Instruments와 무관하며, DRM 우회 기능을 제공하지 않습니다.
