import CoreMIDI
import Foundation

struct MIDIDestination: Identifiable, Hashable {
    let id: Int32
    let name: String
    let endpoint: MIDIEndpointRef

    static func == (lhs: MIDIDestination, rhs: MIDIDestination) -> Bool {
        lhs.id == rhs.id && lhs.endpoint == rhs.endpoint
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(endpoint)
    }
}

/// Sends MIDI 1.0 channel messages either to a selected destination or to the
/// app's virtual source. It never reads or decodes library files.
@MainActor
final class MIDIOutput {
    static let virtualSourceName = "Kornflake"

    private var client: MIDIClientRef = 0
    private var source: MIDIEndpointRef = 0
    private var port: MIDIPortRef = 0

    private(set) var destinations: [MIDIDestination] = []
    private(set) var isAvailable = false
    private(set) var errorMessage: String?

    init() {
        var newClient: MIDIClientRef = 0
        let clientStatus = MIDIClientCreate(Self.virtualSourceName as CFString, nil, nil, &newClient)
        guard clientStatus == noErr else {
            errorMessage = "MIDI 클라이언트 생성 실패 (OSStatus \(clientStatus))"
            return
        }
        client = newClient

        var newSource: MIDIEndpointRef = 0
        let sourceStatus = MIDISourceCreate(newClient, Self.virtualSourceName as CFString, &newSource)
        guard sourceStatus == noErr else {
            errorMessage = "가상 MIDI 소스 생성 실패 (OSStatus \(sourceStatus))"
            return
        }
        source = newSource

        var newPort: MIDIPortRef = 0
        let portStatus = MIDIOutputPortCreate(newClient, "Kornflake Out" as CFString, &newPort)
        guard portStatus == noErr else {
            errorMessage = "MIDI 출력 포트 생성 실패 (OSStatus \(portStatus))"
            return
        }
        port = newPort

        isAvailable = true
        refreshDestinations()
    }

    func refreshDestinations() {
        var found: [MIDIDestination] = []
        let count = MIDIGetNumberOfDestinations()
        for index in 0..<count {
            let endpoint = MIDIGetDestination(index)
            guard endpoint != 0 else { continue }
            var uniqueID: Int32 = 0
            guard MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &uniqueID) == noErr else {
                continue
            }
            found.append(
                MIDIDestination(
                    id: uniqueID,
                    name: Self.displayName(for: endpoint),
                    endpoint: endpoint
                )
            )
        }
        destinations = found.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    func noteOn(_ note: UInt8, velocity: UInt8 = 100, channel: UInt8 = 0) {
        send([0x90 | (channel & 0x0F), note & 0x7F, velocity & 0x7F])
    }

    func noteOff(_ note: UInt8, channel: UInt8 = 0) {
        send([0x80 | (channel & 0x0F), note & 0x7F, 0])
    }

    func allNotesOff(channel: UInt8 = 0) {
        send([0xB0 | (channel & 0x0F), 64, 0])   // sustain off
        send([0xB0 | (channel & 0x0F), 123, 0])  // all notes off
    }

    func panic(channel: UInt8 = 0) {
        send([0xB0 | (channel & 0x0F), 120, 0])  // all sound off
        send([0xB0 | (channel & 0x0F), 64, 0])
        send([0xB0 | (channel & 0x0F), 123, 0])
        send([0xE0 | (channel & 0x0F), 0, 64])   // pitch bend center
    }

    /// Sends a one-shot note for checking routing without starting the sequencer.
    func playTestNote(channel: UInt8) {
        noteOn(60, velocity: 100, channel: channel)
    }

    func stopTestNote(channel: UInt8) {
        noteOff(60, channel: channel)
    }

    private func send(_ bytes: [UInt8]) {
        guard isAvailable, !bytes.isEmpty else { return }
        if let selected = destinations.first(where: { $0.id == selectedDestinationID }) {
            send(bytes, to: selected.endpoint)
        } else {
            sendToVirtualSource(bytes)
        }
    }

    /// Set by the app model. Unknown IDs fall back to the virtual source.
    var selectedDestinationID: Int32?

    private func send(_ bytes: [UInt8], to endpoint: MIDIEndpointRef) {
        bytes.withUnsafeBufferPointer { buffer in
            var packetList = MIDIPacketList()
            let packet = MIDIPacketListInit(&packetList)
            guard let base = buffer.baseAddress else { return }
            _ = MIDIPacketListAdd(
                &packetList,
                MemoryLayout<MIDIPacketList>.size,
                packet,
                0,
                buffer.count,
                base
            )
            MIDISend(port, endpoint, &packetList)
        }
    }

    private func sendToVirtualSource(_ bytes: [UInt8]) {
        bytes.withUnsafeBufferPointer { buffer in
            var packetList = MIDIPacketList()
            let packet = MIDIPacketListInit(&packetList)
            guard let base = buffer.baseAddress else { return }
            _ = MIDIPacketListAdd(
                &packetList,
                MemoryLayout<MIDIPacketList>.size,
                packet,
                0,
                buffer.count,
                base
            )
            MIDIReceived(source, &packetList)
        }
    }

    private static func displayName(for endpoint: MIDIEndpointRef) -> String {
        var value: Unmanaged<CFString>?
        if MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &value) == noErr,
           let name = value?.takeUnretainedValue() {
            return name as String
        }
        return "MIDI Destination"
    }
}
