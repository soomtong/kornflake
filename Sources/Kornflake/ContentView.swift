import SwiftUI
import KornflakeCore

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
                sidebar
                    .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 340)
            } content: {
                instrumentList
                    .background(Color(nsColor: .textBackgroundColor).ignoresSafeArea(edges: .top))
                    .navigationSplitViewColumnWidth(min: 320, ideal: 420, max: 620)
            } detail: {
                detail
                    .background(Color(nsColor: .textBackgroundColor).ignoresSafeArea(edges: .top))
                    .navigationSplitViewColumnWidth(min: 430, ideal: 520)
            }
            .toolbarBackground(.hidden, for: .windowToolbar)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Toggle(isOn: $model.drmFreeOnly) {
                        Label("DRM-free only", systemImage: "checkmark.shield")
                    }
                    .help("Show only unencrypted Kontakt 2/3 instruments that Kornflake can play")

                    Button {
                        model.chooseRoot()
                    } label: {
                        Label("Choose Folder", systemImage: "folder")
                    }
                    .help("Choose the folder that contains your Kontakt libraries")

                    Button {
                        model.scan()
                    } label: {
                        Label("Rescan", systemImage: "arrow.clockwise")
                    }
                    .disabled(model.isScanning)
                }
            }
            .onChange(of: model.selectedInstrumentID) { _, newValue in
                model.selectInstrument(newValue)
            }

            Divider()
            statusBar
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $model.selectedLibraryID) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("All Instruments")
                        Text("\(model.totalVisibleInstrumentCount) total")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .tag(Optional<String>.none)

                ForEach(model.visibleLibraries) { library in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(library.name)
                                .lineLimit(1)
                            Text("\(library.playableCount) DRM-free · \(library.protectedCount) protected")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .tag(Optional(library.id))
                }
            }
            .contentMargins(.bottom, 8, for: .scrollContent)
            .overlay {
                if model.libraries.isEmpty && !model.isScanning {
                    ContentUnavailableView(
                        "No instruments",
                        systemImage: "pianokeys",
                        description: Text("Choose a folder that contains Kontakt libraries.")
                    )
                }
            }
        }
        .navigationTitle("Libraries")
    }

    private var instrumentList: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Search instruments", text: $model.searchText)
                    .textFieldStyle(.roundedBorder)
                Text("\(model.visibleInstruments.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(10)

            List(selection: $model.selectedInstrumentID) {
                ForEach(model.visibleInstruments) { instrument in
                    InstrumentRow(instrument: instrument)
                        .tag(Optional(instrument.id))
                }
            }
            .contentMargins(.bottom, 8, for: .scrollContent)
            .overlay {
                if model.visibleInstruments.isEmpty {
                    ContentUnavailableView(
                        "Nothing to show",
                        systemImage: "magnifyingglass",
                        description: Text(model.drmFreeOnly
                            ? "No DRM-free instruments match this search."
                            : "No instruments match this search.")
                    )
                }
            }
        }
        .navigationTitle(model.selectedLibrary?.name ?? "Instruments")
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
                            Text("Reading mapping…")
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
            Text("\(instrument.library) · \(ByteCountFormatter.string(fromByteCount: instrument.size, countStyle: .file))")
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
                    Label("\(parsed.zones.count) zones", systemImage: "square.stack.3d.up")
                    Label("\(parsed.groups.count) groups", systemImage: "rectangle.3.group")
                    if parsed.isMonolith {
                        Label("embedded samples", systemImage: "shippingbox")
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
            GroupBox("Sound") {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Articulation", selection: $model.selectedGroupIndex) {
                        Text("Auto").tag(Optional<Int>.none)
                        ForEach(model.availableGroups) { group in
                            Text(group.name).tag(Optional(group.index))
                        }
                    }
                    .pickerStyle(.menu)

                    HStack(spacing: 10) {
                        Button {
                            model.testTone()
                        } label: {
                            Label("Play C4", systemImage: "play.circle")
                        }
                        .disabled(model.isPlaying)

                        Text("Audition the raw tone before building a scale or chord.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(6)
            }

            GroupBox("Scale & Chord") {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Mode", selection: $model.mode) {
                        ForEach(AuditionMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack(spacing: 12) {
                        Picker("Root", selection: $model.rootPitchClass) {
                            ForEach(0..<12, id: \.self) { pitchClass in
                                Text(NoteNaming.sharpNames[pitchClass]).tag(pitchClass)
                            }
                        }
                        .frame(maxWidth: 150)

                        Picker("Octave", selection: $model.octave) {
                            ForEach(1..<7, id: \.self) { octave in
                                Text("\(octave)").tag(octave)
                            }
                        }
                        .frame(maxWidth: 110)

                        Spacer()
                    }

                    if model.mode == .scale {
                        Picker("Scale", selection: $model.scale) {
                            ForEach(ScaleType.all) { scale in
                                Text(scale.name).tag(scale)
                            }
                        }
                        HStack {
                            Toggle("Descending", isOn: $model.descending)
                            Toggle("Two octaves", isOn: $model.twoOctaves)
                        }
                    } else {
                        Picker("Chord", selection: $model.chord) {
                            ForEach(ChordType.all) { chord in
                                Text(chord.name).tag(chord)
                            }
                        }
                    }
                }
                .padding(6)
            }

            GroupBox("Playback") {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Order", selection: $model.sequential) {
                        Text("Sequential").tag(true)
                        Text("Together").tag(false)
                    }
                    .pickerStyle(.segmented)

                    HStack(spacing: 10) {
                        Picker("Note length", selection: $model.noteLength) {
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

                    Toggle("Pedal hold (natural decay)", isOn: $model.pedalHold)
                        .help("Let each note ring until the sample's own decay instead of cutting it at the note length.")

                    HStack(spacing: 12) {
                        Toggle("Loop", isOn: $model.loop)
                        Spacer()
                        Button {
                            model.isPlaying ? model.stop() : model.play()
                        } label: {
                            Label(
                                model.isPlaying ? "Stop" : "Play",
                                systemImage: model.isPlaying ? "stop.fill" : "play.fill"
                            )
                            .frame(minWidth: 80)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(6)
            }

            GroupBox("Notes") {
                VStack(alignment: .leading, spacing: 10) {
                    let notes = model.isPlaying ? model.currentNoteNames : model.plannedPlan.names
                    if notes.isEmpty {
                        Text("No notes")
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

    private var welcome: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Kornflake")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                Text("Audition the actual samples inside DRM-free Kontakt libraries — without Kontakt Player.")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Label("Kontakt 2/3 instruments are parsed directly from their mapping and samples.", systemImage: "waveform.path")
                    Label("Protected Kontakt 5+ containers are listed but never decrypted.", systemImage: "lock.shield")
                    Label("Pick a root, choose a scale or chord, then play.", systemImage: "pianokeys")
                }

                if !model.libraries.isEmpty {
                    HStack(spacing: 18) {
                        StatPill(title: "Libraries", value: "\(model.libraries.count)")
                        StatPill(title: "Instruments", value: "\(model.instrumentByID.count)")
                        StatPill(title: "DRM-free", value: "\(model.instrumentByID.values.filter { $0.isPlayable }.count)")
                    }
                    .padding(.top, 6)
                }

                Text("Tip: use the DRM-free filter in the toolbar to hide protected instruments.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(32)
            .frame(maxWidth: 720, alignment: .leading)
        }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            if model.isScanning {
                ProgressView()
                    .controlSize(.small)
            }
            Text(model.scanMessage.isEmpty ? "Ready" : model.scanMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if model.isPlaying {
                Label("Playing", systemImage: "speaker.wave.2.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }
}

private struct InstrumentRow: View {
    let instrument: InstrumentRef

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .foregroundStyle(instrument.isPlayable ? .green : .secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(instrument.name)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            FormatBadge(format: instrument.format, hasMapping: instrument.hasMapping)
        }
        .padding(.vertical, 2)
    }

    private var iconName: String {
        if instrument.isPlayable { return "waveform" }
        if instrument.format == .k2 { return "exclamationmark.triangle" }
        return "lock"
    }

    private var subtitle: String {
        let size = ByteCountFormatter.string(fromByteCount: instrument.size, countStyle: .file)
        return "\(instrument.library) · \(size)"
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
