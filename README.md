# Kornflake

Kontakt 라이브러리의 음색을 스케일과 코드로 빠르게 들어보는 macOS용 MIDI 컨트롤러.

Kornflake는 오디오를 직접 만들지 않는다. Kontakt(또는 Kontakt Player)가 샘플을 재생하고, Kornflake는 선택한 근음·스케일·코드에 해당하는 MIDI 노트를 순차 또는 동시에 보낸다. `.nki`, `.nkm`, `.nkx`, `.nicnt` 파일을 읽거나 복호화하지 않는다.

## 먼저 확인한 사실

| 항목 | 결과 |
|---|---|
| `Play Series - Stacks` 구성 | `Instruments/Stacks.nki`, `Samples/*.nkx` 466.7MB, `*.nicnt`(RAS3), `Snapshots/Stacks/*.nksn` |
| 샘플 원본 | 폴더에 WAV 없음. `.nkx`는 Kontakt용 암호화/압축 컨테이너 |
| Kontakt Player 미설치 재생 | 불가능. `.nkx`와 `.nicnt`를 해석하려면 Kontakt 호환 엔진과 DRM 우회가 필요 |
| Play Series 호환성 | Native Instruments 매뉴얼 기준 Kontakt 또는 Kontakt Player에서 동작 |
| 이 폴더의 라이선스 | EULA 3.1: 리버스 엔지니어링·디컴파일 금지. 3.7: 샘플을 샘플러/사운드 라이브러리로 재패키징 금지 |

따라서 "Kontakt Player를 설치하지 않고 실제 음색 재생"과 "DRM 우회"는 구현하지 않았다. Kontakt Player는 무료이며, Native Access로 라이브러리를 등록하면 이 폴더의 음색을 정상적으로 재생할 수 있다. Kornflake는 그 위에서 스케일·코드 청취를 자동화한다.

## 요구사항 대응

| 요구사항 | 구현 |
|---|---|
| Kontakt 라이브러리 실제 음색 | Kontakt가 재생, Kornflake는 MIDI만 전송 |
| Kontakt Player 미설치 | 충족하지 않음. 무료 Kontakt Player 필요 |
| 악기 선택 후 즉시 재생 | 라이브러리 폴더의 `.nki`/`.nkm` 목록, 더블클릭 또는 "Kontakt에서 열기" |
| 스케일·코드·근음 선택 | 15개 스케일, 16개 코드, 12 피치 클래스 × 옥타브 1~7 |
| 순차/동시 재생 | `순차 재생`, `동시 재생` |
| 재생·정지·반복 | Play/Stop, Loop, Panic(All Sound Off) |
| macOS | macOS 14+, SwiftUI, CoreMIDI |

## 설치와 실행

1. Native Access를 설치하고 Native ID로 로그인한다.
2. Kontakt Player(무료)를 설치한다.
3. Native Access에서 `Play Series - Stacks`를 등록하거나, 이미 설치된 라이브러리 경로를 지정한다.
4. Kontakt Player를 실행하고 `Instruments/Stacks.nki`를 연다.
5. 이 저장소에서 앱을 빌드한다.

```sh
make test
make app
make run
```

Kontakt에서 톤을 고르는 방법:

- Kontakt의 악기 브라우저에서 `Stacks.nki`를 연다.
- Kontakt 상단의 스냅샷 브라우저에서 원하는 프리셋을 선택한다. `Snapshots/Stacks/` 아래의 프리셋은 악기 안에서 선택한다.
- Kornflake 사이드바는 `.nksn` 파일 목록을 보여주고 Finder에서 위치를 열어준다. MIDI로 스냅샷을 직접 바꾸는 표준 방식은 없으므로 Kontakt UI에서 선택한다.

## MIDI 라우팅

Kornflake는 두 가지 방법을 지원한다.

### 1. 가상 소스

앱이 `Kornflake`라는 CoreMIDI 가상 소스를 만든다. Kontakt의 MIDI 입력 설정에서 `Kornflake`를 활성화하면 된다. 별도 설치가 필요 없다.

### 2. IAC 버스

Kontakt가 가상 소스를 보지 못하는 환경에서는 Audio MIDI Setup에서 IAC 버스를 만들고, Kornflake의 MIDI 대상에서 해당 버스를 선택한다. Kontakt의 MIDI 입력에서도 같은 IAC 버스를 선택한다.

MIDI 대상 콤보박스가 `Kornflake 가상 소스`이면 가상 소스로 보내고, 특정 대상이 선택되어 있으면 그 대상으로 보낸다. `테스트음`은 C4 한 음을 보내 라우팅을 확인한다.

## 사용

1. 라이브러리 폴더를 선택한다. 기본값은 `/Volumes/Ultra Touch/Play Series - Stacks`.
2. 근음과 옥타브를 고른다. C4는 MIDI 60이다.
3. `스케일` 또는 `코드`를 고른다.
4. `순차 재생` 또는 `동시 재생`을 고른다.
5. BPM과 Gate를 조절한다.
6. `재생`을 누르고 `반복`을 켜면 계속 듣는다. `정지`는 예약된 노트를 취소하고 노트 오프를 보낸다.
7. 소리가 멈추지 않으면 `Panic`을 누른다. CC 120, 123, 64와 피치 벤드 중앙을 보낸다.

스케일은 순차 재생에서 옥타브 음까지 포함한다. 동시 재생에서는 옥타브 중복을 생략한다. 코드는 항상 근음 위치의 보이싱을 사용한다.

## 지원하는 스케일과 코드

스케일: Major, Natural Minor, Harmonic Minor, Melodic Minor, Major/Minor Pentatonic, Blues, Dorian, Phrygian, Lydian, Mixolydian, Locrian, Whole Tone, Diminished Whole-Half, Diminished Half-Whole.

코드: Major, Minor, Diminished, Augmented, Sus2, Sus4, Power 5, Major 6, Minor 6, Major 7, Minor 7, Dominant 7, Diminished 7, Half-Diminished 7, Add 9, Dominant 9.

## 구조

```text
Sources/KornflakeCore/MusicTheory.swift   스케일/코드 정의, 노트 생성, 타이밍
Sources/Kornflake/MIDIOutput.swift        CoreMIDI 가상 소스/대상 출력
Sources/Kornflake/AuditionPlayer.swift    순차/동시/반복 스케줄러
Sources/Kornflake/LibraryScanner.swift    .nki/.nkm/.nksn 파일 인벤토리
Sources/Kornflake/AppModel.swift          상태, 설정 저장, 라이브러리 스캔
Sources/Kornflake/ContentView.swift       SwiftUI UI
Tests/KornflakeCoreTests/                 노트 생성 테스트
```

## 검증

```sh
swift test          # 8개 코어 테스트
make app            # release 빌드 + ad-hoc 서명 + dist/Kornflake.app
open dist/Kornflake.app
```

확인한 동작:

- `swift test`: 8개 테스트 통과.
- `make app`: 릴리스 빌드, `Info.plist` 검증, ad-hoc 코드 서명 성공.
- 앱 실행: 라이브러리에서 `Stacks.nki`와 스냅샷 100여 개를 스캔, UI 표시.
- CoreMIDI: 앱의 `Kornflake` 가상 소스가 시스템에 노출됨. 재생 중 외부 수신 프로세스에서 C major 스케일의 Note On/Off(예: D4, E4, F4, G4)와 All Notes Off(CC 123)를 수신함.

Kontakt 실음 재생은 이 머신에 Kontakt가 설치되어 있지 않아 직접 확인하지 못했다. 위 검증은 MIDI 경로와 노트 생성까지다.

## 범위 밖

- `.nki`/`.nkx`/`.nicnt` 파싱, 복호화, DRM 우회
- 샘플 추출, 재패키징, 독자 악기 포맷
- Kontakt 스냅샷을 MIDI로 강제 전환하는 UI 자동화
- 오디오 엔진, 샘플러, 플러그인 호스트
