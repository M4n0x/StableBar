import CoreAudio
import Foundation

/// The default output device's volume, mute state and name from CoreAudio. Its listeners follow the
/// default output device and the device list, and the default device's volume and mute state.
final class AudioMonitor: ChangeMonitor, @unchecked Sendable {
    /// The `temporary` field that holds the volume, such as `62%`, for a moment after it changes.
    static let changedVolumeField = "changedVolume"
    /// How long the volume shows after a change, in seconds.
    static let changedVolumeDuration = 1.5

    private let relay = MainQueueRelay()
    private let queue = DispatchQueue(label: "StableBar.AudioMonitor")
    /// The last output read, which the next read compares with. Only touched on the main actor, where
    /// reads happen.
    private var previous: ScriptOutput?
    // The listener state below is only touched on `queue`, where CoreAudio delivers the listeners.
    private var systemListener: AudioObjectPropertyListenerBlock?
    private var device = AudioObjectID(kAudioObjectUnknown)
    private var deviceListener: AudioObjectPropertyListenerBlock?
    private var deviceAddresses: [AudioObjectPropertyAddress] = []

    private static var systemAddresses: [AudioObjectPropertyAddress] {
        [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDevices].map {
            AudioObjectPropertyAddress(mSelector: $0, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        }
    }

    private static var volumeAddresses: [AudioObjectPropertyAddress] {
        [0, 1, 2].map {
            AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioDevicePropertyScopeOutput, mElement: $0)
        } + [AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput,
                                        mElement: kAudioObjectPropertyElementMain)]
    }

    func read() throws -> ScriptOutput {
        let output = Self.showingChange(to: try readDevice(), from: previous)
        previous = output
        return output
    }

    /// `output` with a `temporary` that shows its volume for a moment when its volume or mute state
    /// differs from `previous`'s, as `volumeChange` reports them. The volume is empty while muted or
    /// without a volume control. The first read shows nothing.
    static func showingChange(to output: ScriptOutput, from previous: ScriptOutput?) -> ScriptOutput {
        guard let previous, let change = BuiltInEvent.volumeChange.variables(from: previous, to: output) else { return output }
        var output = output
        let info = change["INFO"] ?? ""
        let volume = change["MUTED"] == "true" || info.isEmpty ? "" : "\(info)%"
        output.temporary = TemporaryOutput(fields: [changedVolumeField: volume], duration: changedVolumeDuration)
        return output
    }

    private func readDevice() throws -> ScriptOutput {
        let device = try Self.defaultDevice()
        guard device != kAudioObjectUnknown else {
            return ScriptOutput(text: "No output", icon: "speaker.slash", fields: ["volumeAvailable": "false"], lists: ["devices": []])
        }
        // A device that is being unplugged may not tell its name; the next change reads it again.
        let name = (try? Self.name(of: device)) ?? ""
        var volumes: [Float32] = []
        for channel: UInt32 in [0, 1, 2] {
            var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                                     mScope: kAudioDevicePropertyScopeOutput, mElement: channel)
            if AudioObjectHasProperty(device, &address) {
                var value: Float32 = 0
                var size = UInt32(MemoryLayout<Float32>.size)
                if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr {
                    volumes.append(value)
                    if channel == 0 { break }
                }
            }
        }
        let volume = volumes.isEmpty ? nil : Double(volumes.reduce(0, +) / Float32(volumes.count))
        var muteAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                                    mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var muted: UInt32 = 0
        var muteSize = UInt32(MemoryLayout<UInt32>.size)
        let muteStatus = AudioObjectGetPropertyData(device, &muteAddress, 0, nil, &muteSize, &muted)
        var fields = ["device": name, "deviceID": String(device), "volumeAvailable": String(volume != nil)]
        if muteStatus == noErr { fields["muted"] = String(muted != 0) }
        return ScriptOutput(text: volume.map { "\(Int(($0 * 100).rounded()))%" } ?? name, icon: muted != 0 ? "speaker.slash" : "speaker.wave.2",
                            value: volume, fields: fields, lists: ["devices": try Self.outputDevices()], values: volume.map { ["volume": $0] })
    }

    /// Calls `changed` on the main actor, so a change never runs between a refresh's read and its
    /// send. CoreAudio reports on `queue`, and `relay` hops to the main queue before it calls `changed`.
    func start(changed: @escaping @Sendable () -> Void) throws {
        try queue.sync {
            removeListeners()
            relay.start(changed)
            let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.systemChanged() }
            systemListener = listener
            for var address in Self.systemAddresses {
                let status = AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, listener)
                guard status == noErr else {
                    removeListeners()
                    relay.stop()
                    throw CommandFailure(message: "Could not watch audio devices (\(status)).")
                }
            }
            watchDefaultDevice()
        }
    }

    func stop() {
        relay.stop()
        queue.sync { removeListeners() }
    }

    /// On `queue`: the default device or the device list changed.
    private func systemChanged() {
        let current = (try? Self.defaultDevice()) ?? AudioObjectID(kAudioObjectUnknown)
        if !Self.covers(device: current, properties: Self.properties(of: current), watched: device, addresses: deviceAddresses) {
            watchDefaultDevice()
        }
        relay.notify()
    }

    /// Whether the volume and mute listener, on `watched` at `addresses`, already covers `device` and
    /// each of its `properties`. A device can publish a property late, such as a Bluetooth device's
    /// volume, and a listener can fail to register, so the next device-list change registers again.
    static func covers(device: AudioObjectID, properties: [AudioObjectPropertyAddress],
                       watched: AudioObjectID, addresses: [AudioObjectPropertyAddress]) -> Bool {
        device == watched && properties.allSatisfy { property in
            addresses.contains { $0.mSelector == property.mSelector && $0.mScope == property.mScope && $0.mElement == property.mElement }
        }
    }

    /// On `queue`: moves the volume and mute listener to the current default output device.
    private func watchDefaultDevice() {
        unwatchDevice()
        guard systemListener != nil, let device = try? Self.defaultDevice(), device != kAudioObjectUnknown else { return }
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.relay.notify() }
        var watched: [AudioObjectPropertyAddress] = []
        for var address in Self.properties(of: device) {
            if AudioObjectAddPropertyListenerBlock(device, &address, queue, listener) == noErr { watched.append(address) }
        }
        self.device = device
        deviceListener = listener
        deviceAddresses = watched
    }

    /// On `queue`.
    private func unwatchDevice() {
        if let deviceListener {
            for var address in deviceAddresses {
                AudioObjectRemovePropertyListenerBlock(device, &address, queue, deviceListener)
            }
        }
        device = AudioObjectID(kAudioObjectUnknown)
        deviceListener = nil
        deviceAddresses = []
    }

    /// On `queue`.
    private func removeListeners() {
        unwatchDevice()
        if let systemListener {
            for var address in Self.systemAddresses {
                AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, systemListener)
            }
        }
        systemListener = nil
    }

    private static func defaultDevice() throws -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        guard status == noErr else { throw CommandFailure(message: "Could not read the audio output device (\(status)).") }
        return device
    }

    /// The volume and mute properties that `device` has.
    private static func properties(of device: AudioDeviceID) -> [AudioObjectPropertyAddress] {
        guard device != kAudioObjectUnknown else { return [] }
        return volumeAddresses.filter { address in
            var address = address
            return AudioObjectHasProperty(device, &address)
        }
    }

    private static func name(of device: AudioDeviceID) throws -> String {
        var address = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                                mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name)
        guard status == noErr, let name else { throw CommandFailure(message: "Could not read audio device name (\(status)).") }
        return name.takeRetainedValue() as String
    }

    private static func outputDevices() throws -> [[String: String]] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size)
        guard status == noErr else { throw CommandFailure(message: "Could not list audio devices (\(status)).") }
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        let readStatus = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices)
        guard readStatus == noErr else { throw CommandFailure(message: "Could not read audio devices (\(readStatus)).") }
        return deviceRows(devices.filter(hasOutput), name: name(of:))
    }

    /// A row for each of `devices` whose name can be read. A device that is being unplugged may no
    /// longer tell its name, and the list leaves it out.
    static func deviceRows(_ devices: [AudioDeviceID], name: (AudioDeviceID) throws -> String) -> [[String: String]] {
        devices.compactMap { device in (try? name(device)).map { ["id": String(device), "name": $0] } }
    }

    private static func hasOutput(_ device: AudioDeviceID) -> Bool {
        var streams = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                                mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(device, &streams, 0, nil, &size) == noErr && size > 0
    }
}
