import XCTest
@testable import KornflakeCore

final class KornflakeCoreTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/Volumes/Ultra Touch/Pile/+Kontakt", isDirectory: true)

    func testPathDecoder() throws {
        let encoded = "@bd016Virtuoso Samplesd038Orchestral  Winds, Brass, & PercussionF00000019000PiccolomfS1B3.L.wav"
        let decoded = try K2PathDecoder.decode(encoded)
        XCTAssertEqual(decoded, "../Virtuoso Samples/Orchestral  Winds, Brass, & Percussion/PiccolomfS1B3.L.wav")
    }

    func testPlainPath() throws {
        XCTAssertEqual(try K2PathDecoder.decode("Samples/foo.wav"), "Samples/foo.wav")
        XCTAssertEqual(try K2PathDecoder.decode("C:\\Samples\\foo.wav"), "C:/Samples/foo.wav")
        XCTAssertEqual(K2PathDecoder.decodePercentEscapes("Cafe%20Au%%Lait"), "Cafe Au%Lait")
    }

    func testAuditionBuilder() {
        let scale = AuditionBuilder.makePlan(
            mode: .scale,
            rootPitchClass: 0,
            octave: 4,
            scale: ScaleType.all[0],
            chord: ChordType.all[0],
            descending: false,
            twoOctaves: false
        )
        XCTAssertEqual(scale.midiNotes, [60, 62, 64, 65, 67, 69, 71, 72])

        let chord = AuditionBuilder.makePlan(
            mode: .chord,
            rootPitchClass: 0,
            octave: 4,
            scale: ScaleType.all[0],
            chord: ChordType.all[0],
            descending: false,
            twoOctaves: false
        )
        XCTAssertEqual(chord.midiNotes, [60, 64, 67])
    }

    func testNoteLengths() {
        XCTAssertEqual(NoteLength.sixteenth.seconds(at: 120), 0.125, accuracy: 0.0001)
        XCTAssertEqual(NoteLength.eighth.seconds(at: 120), 0.25, accuracy: 0.0001)
        XCTAssertEqual(NoteLength.quarter.seconds(at: 120), 0.5, accuracy: 0.0001)
        XCTAssertEqual(NoteLength.half.seconds(at: 120), 1.0, accuracy: 0.0001)
        XCTAssertEqual(NoteLength.whole.seconds(at: 120), 2.0, accuracy: 0.0001)
        XCTAssertEqual(NoteLength.fourWhole.seconds(at: 120), 8.0, accuracy: 0.0001)
        XCTAssertEqual(NoteLength.quarter.seconds(at: 60), 1.0, accuracy: 0.0001)
    }

    func testParseVirtuoso() throws {
        let url = root.appendingPathComponent("Virtuoso/Orchestral  Winds, Brass, & Percussion/Piccolo 2.nki")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: url.path))

        let inspection = KontaktScanner.inspect(url: url)
        XCTAssertEqual(inspection.format, .k2)
        XCTAssertTrue(inspection.hasMapping)

        let parsed = try K2Parser.parse(url: url)
        XCTAssertEqual(parsed.programName, "Piccolo 2")
        XCTAssertGreaterThan(parsed.zones.count, 10)
        XCTAssertFalse(parsed.zones[0].sampleName.isEmpty)

        let resolver = SampleResolver(rootURL: root, libraryName: "Virtuoso")
        let sample = try resolver.resolve(zone: parsed.zones[0], in: parsed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sample.path))

        let buffer = try AudioSampleLoader.shared.load(
            url: sample,
            startFrame: parsed.zones[0].sampleStart,
            endFrame: parsed.zones[0].sampleEnd
        )
        XCTAssertGreaterThan(buffer.frameLength, 0)
        if let channel = buffer.floatChannelData?[0] {
            let peak = (0..<Int(buffer.frameLength)).map { abs(channel[$0]) }.max() ?? 0
            XCTAssertGreaterThan(peak, 0.0001)
        }
    }

    func testParseMonolith() throws {
        let url = root.appendingPathComponent("Yamaha Motif ES/16 Dance Lead/03 Mtrance.nki")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: url.path))

        let parsed = try K2Parser.parse(url: url)
        XCTAssertTrue(parsed.isMonolith)
        XCTAssertNotNil(parsed.monolith)
        XCTAssertGreaterThan(parsed.zones.count, 0)

        let sample = try XCTUnwrap(parsed.monolith).sampleURL(named: parsed.zones[0].sampleName)
        let data = try Data(contentsOf: sample, options: .mappedIfSafe).prefix(4)
        XCTAssertEqual(Data(data), Data("RIFF".utf8))

        let buffer = try AudioSampleLoader.shared.load(
            url: sample,
            startFrame: parsed.zones[0].sampleStart,
            endFrame: parsed.zones[0].sampleEnd
        )
        XCTAssertGreaterThan(buffer.frameLength, 0)
    }

    func testPreviewPlayerStartsAndSchedules() throws {
        let url = root.appendingPathComponent("Virtuoso/Orchestral  Winds, Brass, & Percussion/Piccolo 2.nki")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: url.path))
        let parsed = try K2Parser.parse(url: url)
        let resolver = SampleResolver(rootURL: root, libraryName: "Virtuoso")
        let sample = try resolver.resolve(zone: parsed.zones[0], in: parsed)
        let buffer = try AudioSampleLoader.shared.load(
            url: sample,
            startFrame: parsed.zones[0].sampleStart,
            endFrame: parsed.zones[0].sampleEnd
        )

        let player = PreviewPlayer()
        try player.prepare()
        XCTAssertTrue(player.isRunning)
        player.play(buffer: buffer, rate: 1, gain: 0.05, pan: 0, duration: 0.2)
        player.play(buffer: buffer, rate: 1, gain: 0.05, pan: 0, duration: 0.2, hold: true)
        Thread.sleep(forTimeInterval: 0.35)
        player.stopAll()
    }

    func testSeveralMonolithInstruments() throws {
        let folder = root.appendingPathComponent("Yamaha Motif ES/16 Dance Lead")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: folder.path))
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "nki" }
            .prefix(5)

        for url in files {
            let parsed = try K2Parser.parse(url: url)
            XCTAssertTrue(parsed.isMonolith, url.lastPathComponent)
            let sample = try XCTUnwrap(parsed.monolith).sampleURL(named: parsed.zones[0].sampleName)
            let header = try Data(contentsOf: sample, options: .mappedIfSafe).prefix(4)
            XCTAssertEqual(Data(header), Data("RIFF".utf8), url.lastPathComponent)
        }
    }

    func testSeveralEmuInstruments() throws {
        let folder = root.appendingPathComponent("E-mu Pack/Proteus 2000/Proteus 2000 Bank 3")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: folder.path))
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "nki" }
            .prefix(5)

        let resolver = SampleResolver(rootURL: root, libraryName: "E-mu Pack")
        for (index, url) in files.enumerated() {
            let parsed = try K2Parser.parse(url: url)
            XCTAssertFalse(parsed.zones.isEmpty, url.lastPathComponent)
            XCTAssertFalse(parsed.programName.isEmpty, url.lastPathComponent)
            if index == 0 {
                let sample = try resolver.resolve(zone: parsed.zones[0], in: parsed)
                XCTAssertTrue(FileManager.default.fileExists(atPath: sample.path))
            }
        }
    }

    func testSeveralVintageProInstruments() throws {
        let folder = root.appendingPathComponent("Vintage Pro/Vintage Pro Bank 3")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: folder.path))
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "nki" }
            .prefix(5)

        for url in files {
            let parsed = try K2Parser.parse(url: url)
            XCTAssertFalse(parsed.zones.isEmpty, url.lastPathComponent)
        }
    }

    func testSeveralEnsoniqInstruments() throws {
        let folder = root.appendingPathComponent("Ensoniq ASR/Bass")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: folder.path))
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "nki" }
            .prefix(5)

        let resolver = SampleResolver(rootURL: root, libraryName: "Ensoniq ASR")
        for (index, url) in files.enumerated() {
            let parsed = try K2Parser.parse(url: url)
            XCTAssertFalse(parsed.zones.isEmpty, url.lastPathComponent)
            if index == 0 {
                let sample = try resolver.resolve(zone: parsed.zones[0], in: parsed)
                XCTAssertTrue(FileManager.default.fileExists(atPath: sample.path))
            }
        }
    }

    func testKnownUnsupportedK2WithoutXML() throws {
        let url = root.appendingPathComponent("Abbey Road 60s Drums Library/Instruments/Abbey Road - Late 60s Kit Essential.nki")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: url.path))
        let inspection = KontaktScanner.inspect(url: url)
        XCTAssertEqual(inspection.format, .k2)
        XCTAssertFalse(inspection.hasMapping)

        XCTAssertThrowsError(try K2Parser.parse(url: url)) { error in
            guard case K2Error.missingXML = error else {
                return XCTFail("Expected missingXML, got \(error)")
            }
        }
    }

    func testScannerSeesBothFormats() throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: root.path))
        let libraries = try KontaktScanner.scan(rootURL: root)
        let all = libraries.flatMap(\.instruments)
        XCTAssertGreaterThan(all.count, 1000)
        print("playable:", all.filter(\.isPlayable).count, "k2:", all.filter { $0.format == .k2 }.count)
        XCTAssertGreaterThan(all.filter(\.isPlayable).count, 5_000)
        XCTAssertTrue(all.contains { $0.format == .k2 })
        XCTAssertTrue(all.contains { $0.format == .k5 })
    }
}
