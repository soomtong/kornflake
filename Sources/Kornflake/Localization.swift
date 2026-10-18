import Foundation
import KornflakeCore

enum AppLanguage: String, CaseIterable, Identifiable {
    case ko
    case en

    var id: String { rawValue }

    /// Korean for Korean system locales, English otherwise.
    static var systemDefault: AppLanguage {
        Locale.preferredLanguages.first?.hasPrefix("ko") == true ? .ko : .en
    }
}

extension AppModel {
    /// Picks the string for the current UI language.
    func tr(_ en: String, _ ko: String) -> String {
        language == .ko ? ko : en
    }

    func toggleLanguage() {
        language = language == .ko ? .en : .ko
    }

    func scaleName(_ scale: ScaleType) -> String {
        guard language == .ko else { return scale.name }
        return Self.koreanScaleNames[scale.id] ?? scale.name
    }

    func chordName(_ chord: ChordType) -> String {
        guard language == .ko else { return chord.name }
        return Self.koreanChordNames[chord.id] ?? chord.name
    }

    func modeName(_ mode: AuditionMode) -> String {
        switch mode {
        case .scale: return tr("Scale", "스케일")
        case .chord: return tr("Chord", "코드")
        }
    }

    private static let koreanScaleNames: [String: String] = [
        "major": "메이저 (이오니안)",
        "minor": "내추럴 마이너 (에올리안)",
        "harmonicMinor": "하모닉 마이너",
        "melodicMinor": "멜로딕 마이너",
        "dorian": "도리안",
        "phrygian": "프리지안",
        "lydian": "리디안",
        "mixolydian": "믹솔리디안",
        "locrian": "로크리안",
        "majorPentatonic": "메이저 펜타토닉",
        "minorPentatonic": "마이너 펜타토닉",
        "blues": "블루스",
        "diminishedWH": "디미니시드 (온–반)",
        "diminishedHW": "디미니시드 (반–온)",
        "wholeTone": "온음음계",
        "chromatic": "반음계"
    ]

    private static let koreanChordNames: [String: String] = [
        "major": "메이저",
        "minor": "마이너",
        "dim": "디미니시드",
        "aug": "어규먼트",
        "sus2": "Sus2",
        "sus4": "Sus4",
        "maj7": "메이저 7",
        "min7": "마이너 7",
        "dom7": "도미넌트 7",
        "dim7": "디미니시드 7",
        "halfDim7": "하프 디미니시드 7",
        "minMaj7": "마이너–메이저 7",
        "six": "메이저 6",
        "min6": "마이너 6",
        "add9": "Add 9",
        "nine": "도미넌트 9",
        "min9": "마이너 9",
        "sevenSus4": "7 Sus4"
    ]
}

/// Display data for a category folder such as "01 Acoustic Piano".
struct CategoryStyle {
    let number: String?
    let englishName: String
    let koreanName: String
    let symbol: String

    func name(in language: AppLanguage) -> String {
        language == .ko ? koreanName : englishName
    }

    func matches(_ query: String) -> Bool {
        englishName.localizedCaseInsensitiveContains(query)
            || koreanName.localizedCaseInsensitiveContains(query)
    }

    init(folderName: String) {
        let (number, name) = PatchNaming.split(folderName)
        self.number = number
        self.englishName = name
        let key = name.lowercased()
        self.koreanName = Self.koreanNames[key] ?? name
        self.symbol = Self.symbol(for: key)
    }

    private static let koreanNames: [String: String] = [
        "acoustic piano": "어쿠스틱 피아노",
        "electric piano": "일렉트릭 피아노",
        "keyboards": "키보드",
        "electric organ": "일렉트릭 오르간",
        "pipe organ": "파이프 오르간",
        "acoustic guitar": "어쿠스틱 기타",
        "electric guitar": "일렉트릭 기타",
        "overdriven guitar": "오버드라이브 기타",
        "plucked": "발현악기",
        "bells": "벨",
        "mallets": "말렛",
        "acoustic bass": "어쿠스틱 베이스",
        "synth bass": "신스 베이스",
        "soft lead": "소프트 리드",
        "hard lead": "하드 리드",
        "dance lead": "댄스 리드",
        "orchestral strings": "오케스트라 스트링",
        "ensemble strings": "앙상블 스트링",
        "synth strings": "신스 스트링",
        "flutes": "플루트",
        "choir": "합창",
        "acoustic brass": "어쿠스틱 브라스",
        "synth brass": "신스 브라스",
        "pads": "패드",
        "synth fx": "신스 FX",
        "hits&stabs": "히트 & 스탭",
        "sound effects": "효과음",
        "percussions": "퍼커션",
        "percussions kits": "퍼커션 키트",
        "drum kits": "드럼 키트"
    ]

    private static func symbol(for key: String) -> String {
        let rules: [(String, String)] = [
            ("piano", "pianokeys"), ("keyboard", "pianokeys"),
            ("organ", "music.note.list"),
            ("guitar", "guitars"),
            ("plucked", "music.note"),
            ("bell", "bell"),
            ("mallet", "hammer"),
            ("bass", "waveform.path"),
            ("lead", "waveform"),
            ("string", "music.quarternote.3"),
            ("flute", "wind"),
            ("choir", "music.mic"),
            ("brass", "speaker.wave.3"),
            ("pad", "square.stack.3d.up"),
            ("fx", "sparkles"), ("effect", "sparkles"),
            ("hit", "bolt"),
            ("percussion", "circle.grid.3x3"), ("drum", "circle.grid.3x3")
        ]
        return rules.first { key.contains($0.0) }?.1 ?? "folder"
    }
}

enum PatchNaming {
    /// Splits a leading order number off a file or folder name: "01 FullGrand" -> ("01", "FullGrand").
    static func split(_ name: String) -> (number: String?, title: String) {
        let digits = name.prefix { $0.isNumber }
        let rest = name.dropFirst(digits.count)
        guard !digits.isEmpty, rest.first == " " else { return (nil, name) }
        return (String(digits), String(rest.dropFirst()))
    }
}
