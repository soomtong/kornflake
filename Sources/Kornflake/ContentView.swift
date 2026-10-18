import SwiftUI
import KornflakeCore

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
                patchList
                    .navigationSplitViewColumnWidth(min: 240, ideal: 300, max: 420)
            } detail: {
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .textBackgroundColor).ignoresSafeArea())
                    .navigationSplitViewColumnWidth(min: 430, ideal: 520)
                    .navigationTitle("")
            }
            .toolbarBackground(.hidden, for: .windowToolbar)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Toggle(isOn: $model.midiEnabled) {
                        Label(model.tr("MIDI Out", "MIDI 출력"), systemImage: "cable.connector")
                    }
                    .toggleStyle(.button)
                    .help(model.tr("Send played notes to MIDI (⌥M)", "재생하는 음을 MIDI로 출력 (⌥M)"))

                    Picker(model.tr("Language", "언어"), selection: $model.language) {
                        Text("한국어").tag(AppLanguage.ko)
                        Text("EN").tag(AppLanguage.en)
                    }
                    .pickerStyle(.segmented)
                    .help(model.tr("Switch between Korean and English (⇧⌘L)", "한국어/영어 전환 (⇧⌘L)"))

                    Button {
                        model.chooseRoot()
                    } label: {
                        Label(model.tr("Choose Folder", "폴더 선택"), systemImage: "folder")
                    }
                    .help(model.tr("Choose the Kontakt instrument folder to load", "불러올 Kontakt 악기 폴더 선택"))

                    Button {
                        model.scan()
                    } label: {
                        Label(model.tr("Rescan", "다시 검색"), systemImage: "arrow.clockwise")
                    }
                    .disabled(model.isScanning || model.rootURL == nil)
                }
            }
            .onChange(of: model.selectedInstrumentID) { _, newValue in
                model.selectInstrument(newValue)
            }

            Divider()
            statusBar
        }
    }

    /// Patches of the loaded instrument, grouped by category folder.
    private var patchList: some View {
        let categories = model.visibleCategories
        return ScrollViewReader { proxy in
            List(selection: $model.selectedInstrumentID) {
                ForEach(categories) { category in
                    Section {
                        ForEach(category.instruments) { patch in
                            PatchRow(instrument: patch)
                                .tag(Optional(patch.id))
                                .simultaneousGesture(TapGesture().onEnded {
                                    // Leave the search field so Space plays instead of typing.
                                    searchFocused = false
                                    NSApp.keyWindow?.makeFirstResponder(nil)
                                })
                        }
                    } header: {
                        CategoryHeader(
                            style: CategoryStyle(folderName: category.name),
                            count: category.instruments.count,
                            language: model.language
                        )
                    }
                }
            }
            .onChange(of: model.selectedInstrumentID) { _, id in
                if let id { proxy.scrollTo(id) }
            }
        }
        .listStyle(.sidebar)
        .contentMargins(.bottom, 8, for: .scrollContent)
        .safeAreaInset(edge: .top, spacing: 0) {
            TextField(model.tr("Search patches or categories", "패치·카테고리 검색"), text: $model.searchText)
                .textFieldStyle(.roundedBorder)
                .padding(10)
                .focused($searchFocused)
                .onSubmit {
                    model.selectFirstVisiblePatch()
                    searchFocused = false
                }
                .onKeyPress(.downArrow) {
                    model.selectAdjacentPatch(1)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    model.selectAdjacentPatch(-1)
                    return .handled
                }
                .onExitCommand { searchFocused = false }
                .onChange(of: searchFocused) { _, focused in
                    model.isSearchFocused = focused
                }
                .onChange(of: model.searchFocusRequest) { _, _ in
                    searchFocused = true
                }
        }
        .overlay {
            if model.rootURL == nil {
                ContentUnavailableView(
                    model.tr("No instrument loaded", "불러온 악기 없음"),
                    systemImage: "pianokeys",
                    description: Text(model.tr(
                        "Choose the instrument folder to load its patches.",
                        "악기 폴더를 선택하면 패치 목록을 불러옵니다."
                    ))
                )
            } else if categories.isEmpty && !model.isScanning {
                ContentUnavailableView(
                    model.tr("No patches", "패치 없음"),
                    systemImage: "magnifyingglass",
                    description: Text(model.searchText.isEmpty
                        ? model.tr("No playable .nki patches were found in this folder.", "이 폴더에서 재생 가능한 .nki 패치를 찾지 못했습니다.")
                        : model.tr("No patches match this search.", "검색과 일치하는 패치가 없습니다."))
                )
            }
        }
        .navigationTitle(model.instrumentName)
        .navigationSubtitle(model.patchCount > 0 ? model.tr("\(model.patchCount) patches", "패치 \(model.patchCount)개") : "")
    }

    @ViewBuilder
    private var detail: some View {
        if let instrument = model.selectedInstrument {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    instrumentHeader(instrument)
                    if let message = model.parseMessage {
                        messageCard(message)
                    }
                    if model.isParsing {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text(model.tr("Reading mapping…", "매핑을 읽는 중…"))
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let parsed = model.parsedInstrument {
                        auditionPanel(parsed: parsed)
                    }
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            welcome
        }
    }

    private func instrumentHeader(_ instrument: InstrumentRef) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(instrument.name)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                FormatBadge(format: instrument.format, hasMapping: instrument.hasMapping)
                Spacer()
            }
            Text("\(CategoryStyle(folderName: instrument.library).name(in: model.language)) · \(ByteCountFormatter.string(fromByteCount: instrument.size, countStyle: .file))")
                .foregroundStyle(.secondary)
            Text(instrument.url.path)
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
            if let parsed = model.parsedInstrument {
                HStack(spacing: 12) {
                    Label(parsed.programName, systemImage: "waveform")
                    Label(model.tr("\(parsed.zones.count) zones", "존 \(parsed.zones.count)개"), systemImage: "square.stack.3d.up")
                    Label(model.tr("\(model.availableGroups.count) layers", "레이어 \(model.availableGroups.count)개"), systemImage: "rectangle.3.group")
                    if parsed.isMonolith {
                        Label(model.tr("embedded samples", "내장 샘플"), systemImage: "shippingbox")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func messageCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
    }

    private func auditionPanel(parsed: ParsedInstrument) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox(model.tr("Sound", "사운드")) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(model.tr("Layer", "레이어"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Picker(model.tr("Layer", "레이어"), selection: $model.selectedGroupIndex) {
                            Text(model.tr("Auto (best match)", "자동 (가장 알맞은 레이어)")).tag(Optional<Int>.none)
                            ForEach(Array(model.availableGroups.enumerated()), id: \.element.id) { position, group in
                                Text(model.layerLabel(group, position: position + 1)).tag(Optional(group.index))
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .help(model.tr(
                            "A patch is built from layers (Kontakt groups), usually velocity layers. Auto picks the best match per note; choosing one plays only that layer.",
                            "패치는 레이어(Kontakt 그룹)로 구성되며 대개 벨로시티 레이어입니다. 자동은 음마다 가장 알맞은 레이어를 고르고, 하나를 선택하면 그 레이어만 재생합니다."
                        ))

                        Button {
                            model.testTone()
                        } label: {
                            Label(model.tr("Play C4", "C4 재생"), systemImage: "play.circle")
                        }
                        .disabled(model.isPlaying)

                        Text(model.tr("Audition the raw tone before building a scale or chord.", "스케일이나 코드를 만들기 전에 원음을 먼저 들어 보세요."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Divider()

                    midiControl
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(6)
            }

            GroupBox(model.tr("Scale & Chord", "스케일 & 코드")) {
                VStack(alignment: .leading, spacing: 14) {
                    Picker(model.tr("Mode", "모드"), selection: $model.mode) {
                        ForEach(AuditionMode.allCases) { mode in
                            Text(model.modeName(mode)).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack(spacing: 12) {
                        Picker(model.tr("Root", "근음"), selection: $model.rootPitchClass) {
                            ForEach(0..<12, id: \.self) { pitchClass in
                                Text(NoteNaming.sharpNames[pitchClass]).tag(pitchClass)
                            }
                        }
                        .frame(maxWidth: 150)

                        Picker(model.tr("Octave", "옥타브"), selection: $model.octave) {
                            ForEach(1..<7, id: \.self) { octave in
                                Text("\(octave)").tag(octave)
                            }
                        }
                        .frame(maxWidth: 110)

                        Spacer()
                    }

                    if model.mode == .scale {
                        Picker(model.tr("Scale", "스케일"), selection: $model.scale) {
                            ForEach(ScaleType.all) { scale in
                                Text(model.scaleName(scale)).tag(scale)
                            }
                        }
                        HStack {
                            Toggle(model.tr("Descending", "내림차순"), isOn: $model.descending)
                            Toggle(model.tr("Two octaves", "2옥타브"), isOn: $model.twoOctaves)
                            Toggle(model.tr("Up & down", "오르내리기"), isOn: $model.upDown)
                                .help(model.tr(
                                    "Play the scale up and back down in one pass. With Descending it goes down first. With Loop it repeats seamlessly.",
                                    "스케일을 올라갔다가 다시 내려오는 한 사이클로 재생합니다. 내림차순과 함께 쓰면 내려가는 것부터 시작하고, 반복을 켜면 끊김 없이 이어집니다."
                                ))
                        }
                    } else {
                        Picker(model.tr("Chord", "코드"), selection: $model.chord) {
                            ForEach(ChordType.all) { chord in
                                Text(model.chordName(chord)).tag(chord)
                            }
                        }
                        HStack(spacing: 16) {
                            Stepper(value: $model.extendUp, in: 0...AppModel.maxExtension) {
                                Text(model.tr("Extend up: \(model.extendUp)", "위로 확장: \(model.extendUp)"))
                                    .monospacedDigit()
                            }
                            Stepper(value: $model.extendDown, in: 0...AppModel.maxExtension) {
                                Text(model.tr("Extend down: \(model.extendDown)", "아래로 확장: \(model.extendDown)"))
                                    .monospacedDigit()
                            }
                        }
                        .help(model.tr(
                            "Adds notes above or below the chord by continuing its pattern, for a fuller, wider voicing.",
                            "코드의 패턴을 이어서 위나 아래에 음을 추가해 더 넓고 풍성한 사운드를 만듭니다."
                        ))
                    }
                }
                .padding(6)
            }

            GroupBox(model.tr("Playback", "재생")) {
                VStack(alignment: .leading, spacing: 14) {
                    Picker(model.tr("Order", "순서"), selection: $model.sequential) {
                        Text(model.tr("Sequential", "순차")).tag(true)
                        Text(model.tr("Together", "동시")).tag(false)
                    }
                    .pickerStyle(.segmented)

                    HStack(spacing: 10) {
                        Picker(model.tr("Note length", "음 길이"), selection: $model.noteLength) {
                            ForEach(NoteLength.allCases) { length in
                                Text(length.rawValue).tag(length)
                            }
                        }
                        .frame(maxWidth: 150)

                        Text("\(Int(model.noteDuration * 1000)) ms")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 64, alignment: .leading)

                        Spacer()

                        Stepper(value: $model.tempo, in: 40...240, step: 5) {
                            Text("\(Int(model.tempo)) BPM")
                                .font(.caption.monospacedDigit())
                        }
                        .fixedSize()
                    }

                    Toggle(model.tr("Pedal hold (natural decay)", "페달 홀드 (자연 감쇠)"), isOn: $model.pedalHold)
                        .help(model.tr("Let each note ring until the sample's own decay instead of cutting it at the note length.", "음 길이에서 자르지 않고 샘플 고유의 감쇠가 끝날 때까지 울리게 합니다."))

                    Toggle(model.tr("Auto replay on change", "변경 시 자동 재생"), isOn: $model.autoPlayback)
                        .help(model.tr(
                            "While playing, changing a control (chord, pattern, tempo, patch…) restarts playback so you hear it right away.",
                            "재생 중에 코드, 패턴, 템포, 패치 등을 바꾸면 곧바로 다시 시작해 바뀐 소리를 바로 들려줍니다."
                        ))

                    HStack(spacing: 12) {
                        Toggle(model.tr("Loop", "반복"), isOn: $model.loop)
                        Spacer()
                        Button {
                            model.isPlaying ? model.stop() : model.play()
                        } label: {
                            Label(
                                model.isPlaying ? model.tr("Stop", "정지") : model.tr("Play", "재생"),
                                systemImage: model.isPlaying ? "stop.fill" : "play.fill"
                            )
                            .frame(minWidth: 80)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(6)
            }

            GroupBox(model.tr("Notes", "음")) {
                VStack(alignment: .leading, spacing: 10) {
                    let notes = model.isPlaying ? model.currentNoteNames : model.plannedPlan.names
                    if notes.isEmpty {
                        Text(model.tr("No notes", "음 없음"))
                            .foregroundStyle(.secondary)
                    } else {
                        FlowLayout(spacing: 6) {
                            ForEach(Array(notes.enumerated()), id: \.offset) { _, name in
                                Text(name)
                                    .font(.system(.body, design: .rounded).weight(.medium))
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .background(.quaternary, in: Capsule())
                            }
                        }
                    }
                    if !model.playbackMessage.isEmpty {
                        Text(model.playbackMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var midiControl: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(model.tr("MIDI control", "MIDI 컨트롤"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle(model.tr("MIDI Out", "MIDI 출력"), isOn: $model.midiEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            Group {
                Picker(model.tr("Port", "포트"), selection: $model.midiDestinationID) {
                    Text(model.tr("Kornflake (virtual)", "Kornflake (가상)")).tag(Optional<Int32>.none)
                    ForEach(model.midiDestinations) { destination in
                        Text(destination.name).tag(Optional(destination.id))
                    }
                }

                Picker(model.tr("Channel", "채널"), selection: $model.midiChannel) {
                    ForEach(1...16, id: \.self) { channel in
                        Text("\(channel)").tag(channel)
                    }
                }

                Toggle(model.tr("Also play built-in sound", "내장 음색도 함께 재생"), isOn: $model.internalSound)
                    .help(model.tr(
                        "Keep the built-in samples sounding together with MIDI out. Turn off to hear only the external instrument.",
                        "MIDI 출력과 동시에 내장 샘플도 재생합니다. 끄면 외부 악기 소리만 들립니다."
                    ))
            }
            .disabled(!model.midiEnabled)

            Text(model.tr(
                "Other apps and DAWs can receive these notes from the “Kornflake” MIDI input port.",
                "다른 앱이나 DAW는 “Kornflake” MIDI 입력 포트로 이 음을 받을 수 있습니다."
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var welcome: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                welcomeHero
                Text("Yamaha Motif Player")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                Text(model.tr("Audition the patches of a single Kontakt instrument — without Kontakt Player.", "Kontakt Player 없이 Kontakt 악기 하나의 패치를 들어 봅니다."))
                    .font(.title3)
                    .foregroundStyle(.secondary)

                Divider()

                if model.rootURL == nil {
                    Button {
                        model.chooseRoot()
                    } label: {
                        Label(model.tr("Choose Instrument Folder…", "악기 폴더 선택…"), systemImage: "folder")
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    HStack(spacing: 18) {
                        StatPill(title: model.tr("Categories", "카테고리"), value: "\(model.categories.count)")
                        StatPill(title: model.tr("Patches", "패치"), value: "\(model.patchCount)")
                    }
                    Text(model.tr("Pick a patch from the side panel.", "사이드 패널에서 패치를 선택하세요."))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(32)
            .frame(maxWidth: 720, alignment: .leading)
        }
    }

    @ViewBuilder
    private var welcomeHero: some View {
        if let url = Bundle.module.url(forResource: "motif-hero", withExtension: "jpg", subdirectory: "Resources"),
           let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(height: 240)
                .frame(maxWidth: .infinity)
                .overlay(
                    LinearGradient(colors: [.clear, .black.opacity(0.35)], startPoint: .center, endPoint: .bottom)
                )
                .overlay(alignment: .bottomTrailing) {
                    Text("Yamaha Motif · Pixabay/hanmaili, CC0")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(10)
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
                .padding(.bottom, 6)
        }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            if model.isScanning {
                ProgressView()
                    .controlSize(.small)
            }
            Text(model.scanMessage.isEmpty ? model.tr("Ready", "준비됨") : model.scanMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if model.isPlaying {
                Label(model.tr("Playing", "재생 중"), systemImage: "speaker.wave.2.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }
}

private struct CategoryHeader: View {
    let style: CategoryStyle
    let count: Int
    let language: AppLanguage

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: style.symbol)
                .frame(width: 16)
            Text(style.name(in: language))
                .lineLimit(1)
            Spacer()
            Text("\(count)")
                .font(.caption2.monospacedDigit())
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(.quaternary, in: Capsule())
        }
        .font(.subheadline.weight(.semibold))
        .textCase(nil)
        .padding(.top, 4)
    }
}

private struct PatchRow: View {
    let instrument: InstrumentRef

    var body: some View {
        let (number, title) = PatchNaming.split(instrument.name)
        HStack(spacing: 8) {
            Text(number ?? "")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 22, alignment: .trailing)
            Text(title)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
    }
}

private struct FormatBadge: View {
    let format: KontaktFormat
    var hasMapping: Bool = true

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(foreground)
            .background(background, in: Capsule())
    }

    private var label: String {
        if format == .k2 && !hasMapping { return "K2 · no mapping" }
        return format.shortLabel
    }

    private var foreground: Color {
        if format == .k2 && !hasMapping { return .orange }
        switch format {
        case .k2: return .green
        case .k42: return .orange
        case .k5, .k5Monolith: return .secondary
        case .unknown: return .secondary
        }
    }

    private var background: Color {
        if format == .k2 && !hasMapping { return .orange.opacity(0.12) }
        switch format {
        case .k2: return .green.opacity(0.12)
        case .k42: return .orange.opacity(0.12)
        default: return .secondary.opacity(0.10)
        }
    }
}

private struct StatPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 24, weight: .semibold, design: .rounded).monospacedDigit())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// A tiny wrapping layout for note chips.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 400
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
