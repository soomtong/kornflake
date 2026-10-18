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

    func testScaleUpDown() {
        func plan(descending: Bool = false, seamless: Bool = false) -> [Int] {
            AuditionBuilder.makePlan(
                mode: .scale,
                rootPitchClass: 0,
                octave: 4,
                scale: ScaleType.all[0],
                chord: ChordType.all[0],
                descending: descending,
                twoOctaves: false,
                upDown: true,
                seamless: seamless
            ).midiNotes
        }
        XCTAssertEqual(plan(), [60, 62, 64, 65, 67, 69, 71, 72, 71, 69, 67, 65, 64, 62, 60])
        XCTAssertEqual(plan(seamless: true), [60, 62, 64, 65, 67, 69, 71, 72, 71, 69, 67, 65, 64, 62])
        XCTAssertEqual(plan(descending: true), [72, 71, 69, 67, 65, 64, 62, 60, 62, 64, 65, 67, 69, 71, 72])
    }

    func testChordExtension() {
        func plan(up: Int, down: Int, descending: Bool = false) -> [Int] {
            AuditionBuilder.makePlan(
                mode: .chord,
                rootPitchClass: 0,
                octave: 4,
                scale: ScaleType.all[0],
                chord: ChordType.all[0],
                descending: descending,
                twoOctaves: false,
                extendUp: up,
                extendDown: down
            ).midiNotes
        }
        XCTAssertEqual(plan(up: 0, down: 0), [60, 64, 67])
        XCTAssertEqual(plan(up: 2, down: 0), [60, 64, 67, 72, 76])
        XCTAssertEqual(plan(up: 0, down: 1), [55, 60, 64, 67])
        XCTAssertEqual(plan(up: 1, down: 4), [43, 48, 52, 55, 60, 64, 67, 72])
        XCTAssertEqual(plan(up: 1, down: 1, descending: true), [72, 67, 64, 60, 55])
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

import CoreMIDI

final class MIDIOutputTests: XCTestCase {
    /// Subscribes to the "Kornflake" virtual source and checks the notes that arrive.
    func testVirtualPortDeliversNotes() throws {
        let output = MIDIOutput()

        var client = MIDIClientRef()
        XCTAssertEqual(MIDIClientCreate("test" as CFString, nil, nil, &client), noErr)
        let lock = NSLock()
        var received: [UInt32] = []
        var port = MIDIPortRef()
        let status = MIDIInputPortCreateWithProtocol(client, "in" as CFString, ._1_0, &port) { list, _ in
            var packet = list.pointee.packet
            for _ in 0..<list.pointee.numPackets {
                let count = Int(packet.wordCount)
                let words = withUnsafePointer(to: &packet.words) {
                    $0.withMemoryRebound(to: UInt32.self, capacity: 64) { Array(UnsafeBufferPointer(start: $0, count: count)) }
                }
                lock.lock(); received += words; lock.unlock()
                packet = MIDIEventPacketNext(&packet).pointee
            }
        }
        XCTAssertEqual(status, noErr)

        var endpoint = MIDIObjectRef()
        var type = MIDIObjectType.other
        XCTAssertEqual(MIDIObjectFindByUniqueID(output.sourceUniqueID, &endpoint, &type), noErr)
        XCTAssertEqual(MIDIPortConnectSource(port, endpoint, nil), noErr)

        let target = MIDITarget(channel: 2, destinationID: nil)
        output.noteOn(60, velocity: 100, target: target)
        output.noteOff(60, target: target)
        Thread.sleep(forTimeInterval: 0.3)

        lock.lock(); let words = received; lock.unlock()
        XCTAssertEqual(words, [0x2092_3C64, 0x2082_3C00])
        MIDIPortDispose(port)
        MIDIClientDispose(client)
    }
}

import Compression

/// Synthetic inputs that exercise the parser's defences against corrupt or hostile files.
final class K2RobustnessTests: XCTestCase {
    private func temporaryFile(_ bytes: [UInt8]) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kornflake-\(UUID().uuidString).nki")
        try Data(bytes).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func littleEndian(_ value: UInt32) -> [UInt8] {
        (0..<4).map { UInt8((value >> (8 * UInt32($0))) & 0xFF) }
    }

    func testMonolithIndexRejectsOverflowingWallpaperLength() throws {
        // 170-byte K2 header, then a wallpaper block whose length would overflow UInt64.
        var bytes = [UInt8](repeating: 0, count: 170)
        bytes += littleEndian(0x2AE9_05FA)
        bytes += [UInt8](repeating: 0, count: 10)
        bytes += [UInt8](repeating: 0xFF, count: 8)
        let url = try temporaryFile(bytes)
        XCTAssertThrowsError(try K2MonolithIndex.read(url: url))
    }

    func testMonolithIndexSkipsSampleBlockPastEndOfFile() throws {
        // A sample block that claims 4 GB of audio in a file a few hundred bytes long.
        var bytes = [UInt8](repeating: 0, count: 170)
        bytes += littleEndian(0x16CC_F80A)
        var header = [UInt8](repeating: 0, count: 27)
        header.replaceSubrange(15..<19, with: littleEndian(0xFFFF_FFFF))
        bytes += header
        bytes += [UInt8](repeating: 0, count: 64)
        let url = try temporaryFile(bytes)
        let index = try K2MonolithIndex.read(url: url)
        XCTAssertTrue(index.extentsByName.isEmpty)
    }

    func testInflateRoundTrip() throws {
        let text = String(repeating: "<V name=\"lowKey\" value=\"36\"/>", count: 2_000)
        let plain = Data(text.utf8)
        var compressed = [UInt8](repeating: 0, count: plain.count + 1024)
        let written = plain.withUnsafeBytes { src in
            compression_encode_buffer(
                &compressed, compressed.count,
                src.bindMemory(to: UInt8.self).baseAddress!, plain.count,
                nil, COMPRESSION_ZLIB
            )
        }
        XCTAssertGreaterThan(written, 0)
        // K2 stores a zlib stream: a 2-byte header in front of the raw DEFLATE data.
        let stream = Data([0x78, 0x9C]) + Data(compressed.prefix(written)) + Data("trailing bytes".utf8)
        XCTAssertEqual(try K2Compression.inflate(stream), plain)
    }

    func testInflateRejectsNonZlibData() {
        XCTAssertThrowsError(try K2Compression.inflate(Data(repeating: 0x78, count: 4096)))
        XCTAssertThrowsError(try K2Compression.inflate(Data([0x78, 0x9C, 0x00])))
    }
}
