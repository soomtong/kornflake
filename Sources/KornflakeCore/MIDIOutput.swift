import Foundation
import CoreMIDI

/// A MIDI destination (hardware port or another app's virtual input) that can receive notes.
public struct MIDIDestinationInfo: Identifiable, Hashable, Sendable {
    public let id: Int32
    public let name: String

    public init(id: Int32, name: String) {
        self.id = id
        self.name = name
    }
}

/// Where notes go: a channel (0...15) on either Kornflake's own virtual port or a destination.
public struct MIDITarget: Hashable, Sendable {
    public let channel: Int
    /// nil sends through the "Kornflake" virtual source that other apps can subscribe to.
    public let destinationID: Int32?

    public init(channel: Int, destinationID: Int32?) {
        self.channel = min(15, max(0, channel))
        self.destinationID = destinationID
    }
}

/// Sends note events over CoreMIDI. It publishes a virtual source named "Kornflake" so DAWs and
/// virtual instruments can listen to it, and can also address any destination directly.
public final class MIDIOutput: @unchecked Sendable {
    public static let virtualPortName = "Kornflake"

    private struct ActiveNote: Hashable {
        let note: Int
        let target: MIDITarget
    }

    private var client = MIDIClientRef()
    private var outputPort = MIDIPortRef()
    private var source = MIDIEndpointRef()
    private let lock = NSLock()
    private var activeNotes = Set<ActiveNote>()
    private var sustainTargets = Set<MIDITarget>()
    /// Destination endpoints resolved from their unique ID. Looking an endpoint up walks the
    /// whole MIDI device tree, so cache it and drop the cache when the setup changes.
    private var endpointsByID: [Int32: MIDIObjectRef] = [:]
    private var setupChangedHandler: (() -> Void)?

    /// Called on an arbitrary thread when ports appear or disappear.
    public var onSetupChanged: (() -> Void)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return setupChangedHandler
        }
        set {
            lock.lock()
            setupChangedHandler = newValue
            lock.unlock()
        }
    }

    public init() {
        MIDIClientCreateWithBlock(Self.virtualPortName as CFString, &client) { [weak self] notification in
            guard let self, notification.pointee.messageID == .msgSetupChanged else { return }
            self.lock.lock()
            self.endpointsByID.removeAll()
            let handler = self.setupChangedHandler
            self.lock.unlock()
            handler?()
        }
        MIDIOutputPortCreate(client, "Kornflake Out" as CFString, &outputPort)
        MIDISourceCreateWithProtocol(client, Self.virtualPortName as CFString, ._1_0, &source)
    }

    deinit {
        allNotesOff()
        if source != 0 { MIDIEndpointDispose(source) }
        if client != 0 { MIDIClientDispose(client) }
    }

    /// Unique ID of this instance's virtual source. Several Kornflake processes can each
    /// publish a source with the same name, so use this to tell them apart.
    public var sourceUniqueID: Int32 {
        var uniqueID: Int32 = 0
        MIDIObjectGetIntegerProperty(source, kMIDIPropertyUniqueID, &uniqueID)
        return uniqueID
    }

    public func destinations() -> [MIDIDestinationInfo] {
        (0..<MIDIGetNumberOfDestinations()).compactMap { index in
            let endpoint = MIDIGetDestination(index)
            guard endpoint != 0 else { return nil }
            var uniqueID: Int32 = 0
            MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &uniqueID)
            var name: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &name)
            let title = name?.takeRetainedValue() as String? ?? "MIDI \(index + 1)"
            return MIDIDestinationInfo(id: uniqueID, name: title)
        }
    }

    public func noteOn(_ note: Int, velocity: Int = 100, target: MIDITarget) {
        lock.lock()
        activeNotes.insert(ActiveNote(note: note, target: target))
        lock.unlock()
        send(status: 0x90, data1: note, data2: velocity, target: target)
    }

    public func noteOff(_ note: Int, target: MIDITarget) {
        lock.lock()
        let wasActive = activeNotes.remove(ActiveNote(note: note, target: target)) != nil
        lock.unlock()
        if wasActive {
            send(status: 0x80, data1: note, data2: 0, target: target)
        }
    }

    public func sustain(_ on: Bool, target: MIDITarget) {
        lock.lock()
        if on {
            sustainTargets.insert(target)
        } else {
            sustainTargets.remove(target)
        }
        lock.unlock()
        send(status: 0xB0, data1: 64, data2: on ? 127 : 0, target: target)
    }

    /// Releases the sustain pedal on every target that holds it.
    public func releaseSustain() {
        lock.lock()
        let targets = sustainTargets
        sustainTargets.removeAll()
        lock.unlock()
        for target in targets {
            send(status: 0xB0, data1: 64, data2: 0, target: target)
        }
    }

    /// Ends every note that is still sounding and releases the pedal.
    public func allNotesOff() {
        lock.lock()
        let notes = activeNotes
        activeNotes.removeAll()
        lock.unlock()
        for active in notes {
            send(status: 0x80, data1: active.note, data2: 0, target: active.target)
        }
        releaseSustain()
    }

    private func send(status: Int, data1: Int, data2: Int, target: MIDITarget) {
        // MIDI 1.0 channel voice message in a Universal MIDI Packet (type 2, group 0).
        let word = UInt32(0x2) << 28
            | UInt32(status | target.channel) << 16
            | UInt32(data1 & 0x7F) << 8
            | UInt32(data2 & 0x7F)

        // Keep the event list on the stack so sending a note does not allocate.
        let size = MemoryLayout<MIDIEventList>.size
        withUnsafeTemporaryAllocation(byteCount: size, alignment: MemoryLayout<MIDIEventList>.alignment) { raw in
            let list = raw.baseAddress!.bindMemory(to: MIDIEventList.self, capacity: 1)
            let packet = MIDIEventListInit(list, ._1_0)
            var words = word
            _ = MIDIEventListAdd(list, size, packet, 0, 1, &words)

            if let destinationID = target.destinationID {
                guard let endpoint = endpoint(forUniqueID: destinationID) else { return }
                MIDISendEventList(outputPort, endpoint, list)
            } else {
                MIDIReceivedEventList(source, list)
            }
        }
    }

    private func endpoint(forUniqueID uniqueID: Int32) -> MIDIObjectRef? {
        lock.lock()
        if let cached = endpointsByID[uniqueID] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        var object = MIDIObjectRef()
        var type = MIDIObjectType.other
        guard MIDIObjectFindByUniqueID(uniqueID, &object, &type) == noErr, object != 0 else { return nil }
        lock.lock()
        endpointsByID[uniqueID] = object
        lock.unlock()
        return object
    }
}
