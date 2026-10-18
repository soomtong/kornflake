import AppKit
import KornflakeCore
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        NavigationSplitView {
            LibrarySidebar(model: model)
                .navigationSplitViewColumnWidth(min: 260, ideal: 310, max: 400)
        } detail: {
            AuditionDetail(model: model)
        }
        .frame(minWidth: 1_000, minHeight: 700)
        .onChange(of: model.request) { _, _ in
            if model.isPlaying {
                model.stop()
            }
        }
        .onDisappear {
            model.stop()
        }
    }
}

private struct LibrarySidebar: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Library")
                        .font(.title2.bold())
                    Spacer()
                    if model.isScanning {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                Text(model.libraryRoot.lastPathComponent)
                    .font(.headline)
                    .lineLimit(1)
                Text(model.libraryRoot.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack {
                    Button("폴더 선택…") {
                        model.chooseLibrary()
                    }
                    .controlSize(.small)

                    Button {
                        model.loadLibrary()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .controlSize(.small)
                    .help("라이브러리 새로고침")
                }

                TextField("악기/스냅샷 검색", text: $model.searchText)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(16)

            Divider()

            List(selection: $model.selectedItemID) {
                Section {
                    if model.filteredInstruments.isEmpty {
                        Text(model.isScanning ? "스캔 중…" : "표시할 악기가 없습니다")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.filteredInstruments) { item in
                        LibraryRow(item: item)
                            .tag(item.id)
                            .onTapGesture(count: 2) {
                                model.openInKontakt(item)
                            }
                            .contextMenu {
                                Button("Kontakt에서 열기") { model.openInKontakt(item) }
                                Button("Finder에서 보기") { model.reveal(item) }
                                Button("경로 복사") { model.copyPath(item) }
                            }
                    }
                } header: {
                    HStack {
                        Text("Instruments")
                        Spacer()
                        Text("\(model.filteredInstruments.count)")
                            .monospacedDigit()
                    }
                }

                Section {
                    if model.filteredSnapshots.isEmpty {
                        Text("스냅샷이 없습니다")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.filteredSnapshots) { item in
                        LibraryRow(item: item)
                            .tag(item.id)
                            .onTapGesture(count: 2) {
                                model.reveal(item)
                            }
                            .contextMenu {
                                Button("Finder에서 보기") { model.reveal(item) }
                                Button("경로 복사") { model.copyPath(item) }
                            }
                    }
                } header: {
                    HStack {
                        Text("Snapshots")
                        Spacer()
                        Text("\(model.filteredSnapshots.count)")
                            .monospacedDigit()
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }
}

private struct AuditionDetail: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if let item = model.selectedItem {
                    selectedItemCard(item)
                }
                SoundSection(model: model)
                PlaybackSection(model: model)
                NotesSection(model: model)
                MIDISection(model: model)
                footer
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Kornflake")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                Text("Kontakt 라이브러리를 위한 스케일·코드 청취 MIDI 컨트롤러")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 6) {
                Circle()
                    .fill(model.isPlaying ? Color.green : Color.secondary)
                    .frame(width: 8, height: 8)
                Text(model.isPlaying ? "재생 중" : "대기")
                    .font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.secondary.opacity(0.12), in: Capsule())
        }
    }

    private func selectedItemCard(_ item: LibraryItem) -> some View {
        GroupBox("선택한 항목") {
            HStack(spacing: 12) {
                Image(systemName: iconName(for: item.kind))
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.headline)
                    Text(item.relativePath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                if item.kind == .snapshot {
                    Text("Kontakt 스냅샷 브라우저에서 선택")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Finder에서 보기") {
                        model.reveal(item)
                    }
                } else {
                    Button("Kontakt에서 열기") {
                        model.openInKontakt(item)
                    }
                }
                Button("경로 복사") {
                    model.copyPath(item)
                }
            }
            .padding(4)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(model.midiReady ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
            Text(model.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
            Text("MIDI only · 샘플/DRM 미접근")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func iconName(for kind: LibraryItem.Kind) -> String {
        switch kind {
        case .instrument: "pianokeys"
        case .multi: "square.stack.3d.up"
        case .snapshot: "camera"
        }
    }
}

private struct SoundSection: View {
    @ObservedObject var model: AppModel

    private let pitchClassNames = [
        "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B",
    ]

    var body: some View {
        GroupBox("스케일 / 코드") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 16) {
                    Picker("근음", selection: $model.rootPitchClass) {
                        ForEach(0..<12, id: \.self) { index in
                            Text(pitchClassNames[index]).tag(index)
                        }
                    }
                    .frame(width: 130)

                    Stepper(value: $model.octave, in: 1...7) {
                        Text("옥타브 \(model.octave)")
                    }
                    .frame(width: 150)

                    Text("MIDI \(model.request.rootMIDINote)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                Picker("종류", selection: $model.soundKind) {
                    ForEach(SoundKind.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 200), spacing: 8)],
                    spacing: 8
                ) {
                    if model.soundKind == .scale {
                        ForEach(Scale.allCases) { scale in
                            SelectableChip(
                                title: scale.displayName,
                                isSelected: model.scale == scale
                            ) {
                                model.scale = scale
                            }
                        }
                    } else {
                        ForEach(Chord.allCases) { chord in
                            SelectableChip(
                                title: chord.displayName,
                                isSelected: model.chord == chord
                            ) {
                                model.chord = chord
                            }
                        }
                    }
                }
            }
            .padding(6)
        }
    }
}

private struct PlaybackSection: View {
    @ObservedObject var model: AppModel

    var body: some View {
        GroupBox("재생") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Button {
                        model.togglePlay()
                    } label: {
                        Label(
                            model.isPlaying ? "정지" : "재생",
                            systemImage: model.isPlaying ? "stop.fill" : "play.fill"
                        )
                        .frame(minWidth: 100)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(model.isPlaying ? .red : .accentColor)

                    Toggle("반복", isOn: $model.loop)
                        .toggleStyle(.switch)

                    Spacer()

                    Button("Panic") {
                        model.panic()
                    }
                    .help("모든 소리를 즉시 끕니다 (MIDI CC 120/123)")
                }

                Picker("재생 방식", selection: $model.auditionMode) {
                    ForEach(AuditionMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 260)

                HStack {
                    Text("BPM")
                        .frame(width: 40, alignment: .leading)
                    Slider(value: $model.bpm, in: 40...240, step: 1)
                    Text("\(Int(model.bpm))")
                        .monospacedDigit()
                        .frame(width: 34, alignment: .trailing)
                }

                HStack {
                    Text("Gate")
                        .frame(width: 40, alignment: .leading)
                    Slider(value: $model.gate, in: 0.1...0.95)
                    Text("\(Int(model.gate * 100))%")
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
            }
            .padding(6)
        }
    }
}

private struct NotesSection: View {
    @ObservedObject var model: AppModel

    var body: some View {
        GroupBox("재생 음") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(model.noteNames(model.currentNotes))
                        .font(.system(.body, design: .monospaced))
                    Spacer()
                    Text("\(model.currentNotes.count) notes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 6) {
                    ForEach(model.currentNotes, id: \.self) { note in
                        NoteChip(
                            name: model.noteName(note),
                            isActive: model.activeNotes.contains(note)
                        )
                    }
                }
            }
            .padding(6)
        }
    }
}

private struct MIDISection: View {
    @ObservedObject var model: AppModel

    var body: some View {
        GroupBox("MIDI 출력") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Picker("대상", selection: $model.destinationID) {
                        Text("Kornflake 가상 소스").tag(Int32?.none)
                        ForEach(model.destinations) { destination in
                            Text(destination.name).tag(Optional(destination.id))
                        }
                    }

                    Button {
                        model.refreshMIDI()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("MIDI 대상 새로고침")

                    Spacer()

                    Picker("채널", selection: $model.midiChannel) {
                        ForEach(1...16, id: \.self) { channel in
                            Text("\(channel)").tag(channel)
                        }
                    }
                    .frame(width: 110)

                    Button("테스트음") {
                        model.testMIDI()
                    }
                }

                Text("Kontakt의 MIDI 입력에서 'Kornflake'를 선택하거나, Audio MIDI Setup의 IAC 버스를 앱과 Kontakt 양쪽에서 선택하세요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(6)
        }
    }
}

private struct LibraryRow: View {
    let item: LibraryItem

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .frame(width: 16)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .lineLimit(1)
                Text(item.relativePath)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.vertical, 2)
    }

    private var icon: String {
        switch item.kind {
        case .instrument: "pianokeys"
        case .multi: "square.stack.3d.up"
        case .snapshot: "camera"
        }
    }
}

private struct SelectableChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            isSelected ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
        }
    }
}

private struct NoteChip: View {
    let name: String
    let isActive: Bool

    var body: some View {
        Text(name)
            .font(.system(.caption, design: .monospaced).weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(isActive ? Color.white : Color.primary)
            .background(
                isActive ? Color.accentColor : Color.secondary.opacity(0.12),
                in: Capsule()
            )
    }
}
