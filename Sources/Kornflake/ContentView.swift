import SwiftUI
import KornflakeCore

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @FocusState private var searchFocused: Bool
    /// Categories folded by the user; a search or a selection inside one opens it again.
    @State private var collapsedCategories: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
                patchList
                    .navigationSplitViewColumnWidth(min: 240, ideal: 300, max: 420)
            } detail: {
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.background.ignoresSafeArea())
                    .navigationSplitViewColumnWidth(min: 430, ideal: 520)
                    .navigationTitle("")
            }
            .toolbarBackground(.hidden, for: .windowToolbar)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    DAWToggle(title: model.tr("MIDI Out", "MIDI 출력"), isOn: $model.midiEnabled)
                        .help(model.tr("Send played notes to MIDI (⌥M)", "재생하는 음을 MIDI로 출력 (⌥M)"))

                    DAWSegmented(selection: $model.language, options: [
                        (value: AppLanguage.ko, label: "한국어"),
                        (value: AppLanguage.en, label: "EN")
                    ])
                    .frame(width: 118)
                    .help(model.tr("Switch between Korean and English (⇧⌘L)", "한국어/영어 전환 (⇧⌘L)"))

                    Button {
                        model.chooseRoot()
                    } label: {
                        Label(model.tr("Choose Folder", "폴더 선택"), systemImage: "folder")
                            .labelStyle(.iconOnly)
                            .frame(width: 14)
                    }
                    .buttonStyle(DAWButtonStyle())
                    .help(model.tr("Choose the Kontakt instrument folder to load", "불러올 Kontakt 악기 폴더 선택"))

                    Button {
                        model.scan()
                    } label: {
                        Label(model.tr("Rescan", "다시 검색"), systemImage: "arrow.clockwise")
                            .labelStyle(.iconOnly)
                            .frame(width: 14)
                    }
                    .buttonStyle(DAWButtonStyle())
                    .help(model.tr("Rescan the instrument folder (⌘R)", "악기 폴더 다시 검색 (⌘R)"))
                    .disabled(model.isScanning || model.rootURL == nil)
                }
            }
            .onChange(of: model.selectedInstrumentID) { _, newValue in
                model.selectInstrument(newValue)
            }

            Rectangle().fill(Theme.stroke).frame(height: 1)
            statusBar
        }
        .background(Theme.background)
        .tint(Theme.accent)
    }

    /// Patches of the loaded instrument, grouped by category folder.
    private var patchList: some View {
        let categories = model.visibleCategories
        return ScrollViewReader { proxy in
            List(selection: $model.selectedInstrumentID) {
                ForEach(categories) { category in
                    let isCollapsed = collapsedCategories.contains(category.id) && model.searchText.isEmpty
                    CategoryHeader(
                        style: CategoryStyle(folderName: category.name),
                        count: category.instruments.count,
                        language: model.language,
                        isCollapsed: isCollapsed
                    ) {
                        if collapsedCategories.contains(category.id) {
                            collapsedCategories.remove(category.id)
                        } else {
                            collapsedCategories.insert(category.id)
                        }
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Theme.sidebar)
                    .listRowInsets(EdgeInsets())

                    if !isCollapsed {
                        ForEach(category.instruments) { patch in
                            PatchRow(instrument: patch)
                                .tag(Optional(patch.id))
                                .listRowSeparator(.hidden)
                                .listRowBackground(
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(model.selectedInstrumentID == patch.id ? Theme.accent.opacity(0.16) : .clear)
                                        .padding(.horizontal, 6)
                                )
                                .simultaneousGesture(TapGesture().onEnded {
                                    // Leave the search field so Space plays instead of typing.
                                    searchFocused = false
                                    NSApp.keyWindow?.makeFirstResponder(nil)
                                })
                        }
                    }
                }
            }
            .onChange(of: model.selectedInstrumentID) { _, id in
                guard let id else { return }
                if let library = model.instrumentByID[id]?.library,
                   let category = categories.first(where: { $0.name == library }) {
                    collapsedCategories.remove(category.id)
                }
                proxy.scrollTo(id)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.sidebar)
        .contentMargins(.bottom, 8, for: .scrollContent)
        .safeAreaInset(edge: .top, spacing: 0) {
            TextField(model.tr("Search patches or categories", "패치·카테고리 검색"), text: $model.searchText)
                .textFieldStyle(DAWSearchFieldStyle())
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
            VStack(spacing: 0) {
                instrumentHeader(instrument)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.panel)
                Rectangle()
                    .fill(model.isPlaying ? Theme.ledGreen.opacity(0.7) : Theme.stroke)
                    .frame(height: 1)

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if let message = model.parseMessage {
                            messageCard(message)
                        }
                        if model.isParsing {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text(model.tr("Reading mapping…", "매핑을 읽는 중…"))
                                    .foregroundStyle(Theme.textDim)
                            }
                        }
                        if let parsed = model.parsedInstrument {
                            auditionPanel(parsed: parsed)
                        }
                    }
                    .padding(22)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } else {
            welcome
        }
    }

    private func instrumentHeader(_ instrument: InstrumentRef) -> some View {
        HStack(alignment: .top, spacing: 16) {
            instrumentInfo(instrument)
            Spacer(minLength: 0)
            if model.parsedInstrument != nil {
                transport
            }
        }
    }

    /// Play controls pinned next to the patch name so they stay in reach while tweaking the panels below.
    private var transport: some View {
        HStack(spacing: 8) {
            Button {
                model.testTone()
            } label: {
                Label(model.tr("C4", "C4"), systemImage: "speaker.wave.2.fill")
            }
            .buttonStyle(DAWButtonStyle())
            .disabled(model.isPlaying)
            .help(model.tr(
                "Play C4 to audition the raw tone before building a scale or chord (⌘T)",
                "스케일이나 코드를 만들기 전에 C4 원음을 먼저 들어 봅니다 (⌘T)"
            ))

            DAWToggle(title: model.tr("Loop", "반복"), isOn: $model.loop)
                .help(model.tr("Repeat playback (⌥L)", "반복 재생 (⌥L)"))

            Button {
                model.isPlaying ? model.stop() : model.play()
            } label: {
                Label(
                    model.isPlaying ? model.tr("Stop", "정지") : model.tr("Play", "재생"),
                    systemImage: model.isPlaying ? "stop.fill" : "play.fill"
                )
                .font(.system(size: 14, weight: .bold))
                .frame(minWidth: 88, minHeight: 28)
            }
            .buttonStyle(DAWButtonStyle(kind: model.isPlaying ? .stop : .primary))
            .help(model.tr("Play / Stop (Space)", "재생 / 정지 (Space)"))
        }
        .fixedSize()
    }

    private func instrumentInfo(_ instrument: InstrumentRef) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(instrument.name)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                FormatBadge(format: instrument.format, hasMapping: instrument.hasMapping)
            }
            Text("\(CategoryStyle(folderName: instrument.library).name(in: model.language)) · \(ByteCountFormatter.string(fromByteCount: instrument.size, countStyle: .file))")
                .foregroundStyle(Theme.textDim)
            Text(instrument.url.path)
                .font(.caption.monospaced())
                .foregroundStyle(Theme.textFaint)
                .lineLimit(1)
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
                .foregroundStyle(Theme.textDim)

                HStack(spacing: 8) {
                    ParamLabel(model.tr("Layer", "레이어"))
                    DAWSelect(selection: $model.selectedGroupIndex, options: layerOptions, width: 230)
                }
                .padding(.top, 4)
                .help(model.tr(
                    "A patch is built from layers (Kontakt groups), usually velocity layers. Auto picks the best match per note; choosing one plays only that layer.",
                    "패치는 레이어(Kontakt 그룹)로 구성되며 대개 벨로시티 레이어입니다. 자동은 음마다 가장 알맞은 레이어를 고르고, 하나를 선택하면 그 레이어만 재생합니다."
                ))
            }
        }
    }

    private func messageCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(Theme.accent)
            Text(message)
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.accent.opacity(0.3)))
    }

    private func auditionPanel(parsed: ParsedInstrument) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            scalePanel
            playbackPanel
            notesPanel
            midiPanel
        }
    }

    private var layerOptions: [(value: Int?, label: String)] {
        var options: [(value: Int?, label: String)] = [(nil, model.tr("Auto (best match)", "자동 (가장 알맞은 레이어)"))]
        for (position, group) in model.availableGroups.enumerated() {
            options.append((Optional(group.index), model.layerLabel(group, position: position + 1)))
        }
        return options
    }

    private var midiPanel: some View {
        DAWPanel(model.tr("MIDI control", "MIDI 컨트롤")) {
            DAWToggle(title: model.tr("MIDI Out", "MIDI 출력"), isOn: $model.midiEnabled)
        } content: {
            midiControl
        }
    }

    private var scalePanel: some View {
        DAWPanel(model.tr("Scale & Chord", "스케일 & 코드")) {
            VStack(alignment: .leading, spacing: 14) {
                DAWSegmented(
                    selection: $model.mode,
                    options: AuditionMode.allCases.map { (value: $0, label: model.modeName($0)) }
                )

                HStack(alignment: .top, spacing: 12) {
                    Param(model.tr("Root", "근음")) {
                        DAWSelect(
                            selection: $model.rootPitchClass,
                            options: (0..<12).map { (value: $0, label: NoteNaming.sharpNames[$0]) },
                            width: 84
                        )
                    }
                    Param(model.tr("Octave", "옥타브")) {
                        DAWSelect(
                            selection: $model.octave,
                            options: (1..<7).map { (value: $0, label: "\($0)") },
                            width: 72
                        )
                    }
                    if model.mode == .scale {
                        Param(model.tr("Scale", "스케일")) {
                            DAWSelect(
                                selection: $model.scale,
                                options: ScaleType.all.map { (value: $0, label: model.scaleName($0)) }
                            )
                        }
                    } else {
                        Param(model.tr("Chord", "코드")) {
                            DAWSelect(
                                selection: $model.chord,
                                options: ChordType.all.map { (value: $0, label: model.chordName($0)) }
                            )
                        }
                    }
                }

                if model.mode == .scale {
                    FlowLayout(spacing: 8) {
                        DAWToggle(title: model.tr("Descending", "내림차순"), isOn: $model.descending)
                        DAWToggle(title: model.tr("Two octaves", "2옥타브"), isOn: $model.twoOctaves)
                        DAWToggle(title: model.tr("Up & down", "오르내리기"), isOn: $model.upDown)
                            .help(model.tr(
                                "Play the scale up and back down in one pass. With Descending it goes down first. With Loop it repeats seamlessly.",
                                "스케일을 올라갔다가 다시 내려오는 한 사이클로 재생합니다. 내림차순과 함께 쓰면 내려가는 것부터 시작하고, 반복을 켜면 끊김 없이 이어집니다."
                            ))
                    }
                } else {
                    HStack(alignment: .top, spacing: 20) {
                        Param(model.tr("Extend up", "위로 확장")) {
                            DAWStepper(value: $model.extendUp, range: 0...AppModel.maxExtension, display: "+\(model.extendUp)", minWidth: 44)
                        }
                        Param(model.tr("Extend down", "아래로 확장")) {
                            DAWStepper(value: $model.extendDown, range: 0...AppModel.maxExtension, display: "−\(model.extendDown)", minWidth: 44)
                        }
                    }
                    .help(model.tr(
                        "Adds notes above or below the chord by continuing its pattern, for a fuller, wider voicing.",
                        "코드의 패턴을 이어서 위나 아래에 음을 추가해 더 넓고 풍성한 사운드를 만듭니다."
                    ))
                }
            }
        }
    }

    private var playbackPanel: some View {
        DAWPanel(model.tr("Playback", "재생")) {
            VStack(alignment: .leading, spacing: 14) {
                DAWSegmented(
                    selection: $model.sequential,
                    options: [(value: true, label: model.tr("Sequential", "순차")), (value: false, label: model.tr("Together", "동시"))]
                )

                HStack(alignment: .top, spacing: 12) {
                    Param(model.tr("Note length", "음 길이")) {
                        DAWSelect(
                            selection: $model.noteLength,
                            options: NoteLength.allCases.map { (value: $0, label: $0.rawValue) },
                            width: 110
                        )
                    }
                    Param(model.tr("Duration", "길이")) {
                        LCDReadout(text: "\(Int(model.noteDuration * 1000)) ms", minWidth: 70)
                    }
                    Spacer()
                    Param(model.tr("Tempo", "템포")) {
                        DAWStepper(
                            value: Binding(get: { Int(model.tempo) }, set: { model.tempo = Double($0) }),
                            range: 40...240,
                            step: 5,
                            display: "\(Int(model.tempo)) BPM",
                            minWidth: 80
                        )
                    }
                }

                FlowLayout(spacing: 8) {
                    DAWToggle(title: model.tr("Pedal hold (natural decay)", "페달 홀드 (자연 감쇠)"), isOn: $model.pedalHold)
                        .help(model.tr("Let each note ring until the sample's own decay instead of cutting it at the note length.", "음 길이에서 자르지 않고 샘플 고유의 감쇠가 끝날 때까지 울리게 합니다."))
                    DAWToggle(title: model.tr("Auto replay on change", "변경 시 자동 재생"), isOn: $model.autoPlayback)
                        .help(model.tr(
                            "While playing, changing a control (chord, pattern, tempo, patch…) restarts playback so you hear it right away.",
                            "재생 중에 코드, 패턴, 템포, 패치 등을 바꾸면 곧바로 다시 시작해 바뀐 소리를 바로 들려줍니다."
                        ))
                }
            }
        }
    }

    private var notesPanel: some View {
        DAWPanel(model.tr("Notes", "음")) {
            LED(isOn: model.isPlaying, color: Theme.ledGreen)
        } content: {
            VStack(alignment: .leading, spacing: 10) {
                let notes = model.isPlaying ? model.currentNoteNames : model.plannedPlan.names
                if notes.isEmpty {
                    Text(model.tr("No notes", "음 없음"))
                        .foregroundStyle(Theme.textDim)
                } else {
                    FlowLayout(spacing: 6) {
                        ForEach(Array(notes.enumerated()), id: \.offset) { _, name in
                            Text(name)
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundStyle(Theme.lcd)
                                .padding(.horizontal, 9)
                                .frame(minHeight: 24)
                                .background(Theme.well, in: RoundedRectangle(cornerRadius: 4))
                                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.stroke))
                        }
                    }
                }
                if !model.playbackMessage.isEmpty {
                    Text(model.playbackMessage)
                        .font(.caption)
                        .foregroundStyle(Theme.textDim)
                }
            }
        }
    }

    private var midiControl: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .bottom, spacing: 12) {
                Param(model.tr("Port", "포트")) {
                    DAWSelect(
                        selection: $model.midiDestinationID,
                        options: [(value: Int32?.none, label: model.tr("Kornflake (virtual)", "Kornflake (가상)"))]
                            + model.midiDestinations.map { (value: Optional($0.id), label: $0.name) }
                    )
                }

                Param(model.tr("Channel", "채널")) {
                    DAWSelect(
                        selection: $model.midiChannel,
                        options: (1...16).map { (value: $0, label: "\($0)") },
                        width: 72
                    )
                }

                DAWToggle(title: model.tr("Also play built-in sound", "내장 음색도 함께 재생"), isOn: $model.internalSound)
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
            .foregroundStyle(Theme.textDim)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var welcome: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                welcomeHero
                Text("Yamaha Motif Player")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(Theme.text)
                Text(model.tr("Audition the patches of a single Kontakt instrument — without Kontakt Player.", "Kontakt Player 없이 Kontakt 악기 하나의 패치를 들어 봅니다."))
                    .font(.title3)
                    .foregroundStyle(Theme.textDim)

                Rectangle().fill(Theme.stroke).frame(height: 1)

                if model.rootURL == nil {
                    Button {
                        model.chooseRoot()
                    } label: {
                        Label(model.tr("Choose Instrument Folder…", "악기 폴더 선택…"), systemImage: "folder")
                    }
                    .buttonStyle(DAWButtonStyle(kind: .primary))
                } else {
                    HStack(spacing: 18) {
                        StatPill(title: model.tr("Categories", "카테고리"), value: "\(model.categories.count)")
                        StatPill(title: model.tr("Patches", "패치"), value: "\(model.patchCount)")
                    }
                    Text(model.tr("Pick a patch from the side panel.", "사이드 패널에서 패치를 선택하세요."))
                        .foregroundStyle(Theme.textDim)
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
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.textDim)
            Spacer()
            LED(isOn: model.isPlaying, color: Theme.ledGreen)
            Text(model.isPlaying ? model.tr("Playing", "재생 중") : model.tr("Idle", "대기"))
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(1)
                .textCase(.uppercase)
                .foregroundStyle(model.isPlaying ? Theme.ledGreen : Theme.textFaint)
        }
        .padding(.horizontal, 12)
        .frame(height: 26)
        .background(Theme.panelHeader)
    }
}

private struct CategoryHeader: View {
    let style: CategoryStyle
    let count: Int
    let language: AppLanguage
    let isCollapsed: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: style.symbol)
                .frame(width: 16)
                .foregroundStyle(Theme.accent)
            Text(style.name(in: language))
                .lineLimit(1)
            Spacer()
            Text("\(count)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.lcd)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Theme.well, in: RoundedRectangle(cornerRadius: 3))
            // Fixed slot: the count never moves because the chevron is always there.
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Theme.textFaint)
                .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                .frame(width: 14)
        }
        .padding(.horizontal, 9)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
        .font(.system(size: 11, weight: .bold))
        .tracking(0.8)
        .foregroundStyle(Theme.textDim)
        .textCase(nil)
        .padding(.top, 6)
    }
}

private struct PatchRow: View {
    let instrument: InstrumentRef

    var body: some View {
        let (number, title) = PatchNaming.split(instrument.name)
        HStack(spacing: 8) {
            Text(number ?? "")
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Theme.textFaint)
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
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(foreground)
            .background(background, in: RoundedRectangle(cornerRadius: 3))
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(foreground.opacity(0.35)))
    }

    private var label: String {
        if format == .k2 && !hasMapping { return "K2 · no mapping" }
        return format.shortLabel
    }

    private var foreground: Color {
        if format == .k2 && !hasMapping { return Theme.accent }
        switch format {
        case .k2: return Theme.ledGreen
        case .k42: return Theme.accent
        case .k5, .k5Monolith: return Theme.textDim
        case .unknown: return Theme.textDim
        }
    }

    private var background: Color {
        if format == .k2 && !hasMapping { return Theme.accent.opacity(0.12) }
        switch format {
        case .k2: return Theme.ledGreen.opacity(0.12)
        case .k42: return Theme.accent.opacity(0.12)
        default: return Theme.textDim.opacity(0.10)
        }
    }
}

private struct StatPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 26, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.lcd)
                .shadow(color: Theme.lcd.opacity(0.35), radius: 4)
            ParamLabel(title)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.well, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.strokeStrong))
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
