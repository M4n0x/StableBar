import CoreAudio
import Darwin
import Foundation
import IOKit.ps

struct NetworkCounters: Sendable {
    let received: UInt64
    let sent: UInt64

    func rates(since previous: NetworkCounters, elapsed: Double) -> (download: Double, upload: Double) {
        let received = received >= previous.received ? received - previous.received : 0
        let sent = sent >= previous.sent ? sent - previous.sent : 0
        return (Double(received) / elapsed, Double(sent) / elapsed)
    }
}

struct CPUTicks: Sendable {
    let user: UInt32
    let system: UInt32
    let idle: UInt32
    let nice: UInt32

    func usage(since previous: CPUTicks) -> Double {
        let busy = UInt64(user &- previous.user) + UInt64(system &- previous.system) + UInt64(nice &- previous.nice)
        let total = busy + UInt64(idle &- previous.idle)
        return total == 0 ? 0 : Double(busy) / Double(total)
    }
}

func networkCounters(_ data: Data) -> [UInt16: NetworkCounters] {
    var counters: [UInt16: NetworkCounters] = [:]
    data.withUnsafeBytes { bytes in
        var offset = 0
        while offset < bytes.count {
            let length = bytes.loadUnaligned(fromByteOffset: offset, as: UInt16.self)
            let type = bytes.load(fromByteOffset: offset + 3, as: UInt8.self)
            if type == RTM_IFINFO2 {
                let interface = bytes.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                if interface.ifm_flags & IFF_UP != 0 {
                    counters[interface.ifm_index] = NetworkCounters(received: interface.ifm_data.ifi_ibytes,
                                                                  sent: interface.ifm_data.ifi_obytes)
                }
            }
            offset += Int(length)
        }
    }
    return counters
}

final class NativeMetrics {
    private var cpu: CPUTicks?
    private var network: [String: NetworkCounters] = [:]
    private var networkTime: ContinuousClock.Instant?

    func sample(_ type: ProviderType) throws -> ScriptOutput {
        switch type {
        case .battery: return try battery()
        case .network: return try networkRates()
        case .system: return try system()
        case .audio: return try audio()
        case .command, .stream: preconditionFailure("Command providers do not use native metrics.")
        }
    }

    private func battery() throws -> ScriptOutput {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            throw CommandFailure(message: "Could not read power sources.")
        }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? Double,
                  let maximum = description[kIOPSMaxCapacityKey] as? Double, maximum > 0 else { continue }
            let percent = current / maximum
            let charging = description[kIOPSIsChargingKey] as? Bool == true
            let onAC = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            let minutes = description[charging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey] as? Int
            let state = charging ? "charging" : (onAC ? "charged" : "battery")
            var fields = ["state": state, "present": "true", "percent": String(Int(percent * 100))]
            if let minutes, minutes >= 0 { fields["timeRemaining"] = String(minutes) }
            return ScriptOutput(text: "\(Int(percent * 100))%", icon: charging ? "battery.100percent.bolt" : "battery.100percent",
                                value: percent, fields: fields, values: ["percent": percent])
        }
        return ScriptOutput(text: "AC", icon: "powerplug", fields: ["state": "ac", "present": "false"])
    }

    private func system() throws -> ScriptOutput {
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        var load = host_cpu_load_info()
        var loadCount = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let cpuStatus = withUnsafeMutablePointer(to: &load) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(loadCount)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &loadCount)
            }
        }
        guard cpuStatus == KERN_SUCCESS else { throw CommandFailure(message: "Could not read CPU statistics (\(cpuStatus)).") }
        let ticks = CPUTicks(user: load.cpu_ticks.0, system: load.cpu_ticks.1, idle: load.cpu_ticks.2, nice: load.cpu_ticks.3)
        let usage = cpu.map { ticks.usage(since: $0) } ?? 0
        cpu = ticks
        var memory = vm_statistics64()
        var memoryCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let memoryStatus = withUnsafeMutablePointer(to: &memory) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(memoryCount)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &memoryCount)
            }
        }
        guard memoryStatus == KERN_SUCCESS else { throw CommandFailure(message: "Could not read memory statistics (\(memoryStatus)).") }
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        let used = (Double(memory.internal_page_count) + Double(memory.wire_count)
                    + Double(memory.compressor_page_count) - Double(memory.purgeable_count))
            * Double(getpagesize())
        return ScriptOutput(text: "\(Int(usage * 100))%", icon: "cpu", value: usage,
                            fields: ["cpu": String(Int(usage * 100)), "memory": String(Int(used / total * 100))],
                            values: ["cpu": usage, "memory": used / total, "memoryUsed": used, "memoryTotal": total])
    }

    private func networkRates() throws -> ScriptOutput {
        var query: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var size = 0
        guard sysctl(&query, UInt32(query.count), nil, &size, nil, 0) == 0 else {
            throw CommandFailure(message: "Could not read network interfaces: \(String(cString: strerror(errno))).")
        }
        var data = Data(count: size)
        let status = data.withUnsafeMutableBytes { sysctl(&query, UInt32(query.count), $0.baseAddress, &size, nil, 0) }
        guard status == 0 else { throw CommandFailure(message: "Could not read network counters: \(String(cString: strerror(errno))).") }
        var current: [String: NetworkCounters] = [:]
        for (index, counters) in networkCounters(data.prefix(size)) {
            var name = [CChar](repeating: 0, count: Int(IFNAMSIZ))
            if if_indextoname(UInt32(index), &name) != nil {
                let name = name.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
                if name.hasPrefix("en") { current[name] = counters }
            }
        }
        let now = ContinuousClock.now
        let elapsed = networkTime.map { Double($0.duration(to: now).components.seconds) + Double($0.duration(to: now).components.attoseconds) / 1e18 }
        var download = 0.0
        var upload = 0.0
        var interfaces: [[String: String]] = []
        for name in current.keys.sorted() {
            var rates = (download: 0.0, upload: 0.0)
            if let previous = network[name], let elapsed, elapsed > 0 {
                rates = current[name]!.rates(since: previous, elapsed: elapsed)
            }
            download += rates.download
            upload += rates.upload
            interfaces.append(["name": name, "download": String(Int(rates.download)), "upload": String(Int(rates.upload))])
        }
        network = current
        networkTime = now
        return ScriptOutput(text: "↓\(Int(download / 1024)) ↑\(Int(upload / 1024)) KiB/s", icon: "network",
                            fields: ["interface": current.keys.sorted().joined(separator: ", ")], lists: ["interfaces": interfaces],
                            values: ["download": download, "upload": upload])
    }

    private func audio() throws -> ScriptOutput {
        var defaultAddress = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                        mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(0)
        var deviceSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &defaultAddress, 0, nil, &deviceSize, &device)
        guard status == noErr else { throw CommandFailure(message: "Could not read the audio output device (\(status)).") }
        guard device != kAudioObjectUnknown else {
            return ScriptOutput(text: "No output", icon: "speaker.slash", fields: ["volumeAvailable": "false"], lists: ["devices": []])
        }
        let name = try audioName(device)
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
                            value: volume, fields: fields, lists: ["devices": try audioDevices()], values: volume.map { ["volume": $0] })
    }

    private func audioName(_ device: AudioDeviceID) throws -> String {
        var address = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                                mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name)
        guard status == noErr, let name else { throw CommandFailure(message: "Could not read audio device name (\(status)).") }
        return name.takeRetainedValue() as String
    }

    private func audioDevices() throws -> [[String: String]] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size)
        guard status == noErr else { throw CommandFailure(message: "Could not list audio devices (\(status)).") }
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        let readStatus = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices)
        guard readStatus == noErr else { throw CommandFailure(message: "Could not read audio devices (\(readStatus)).") }
        return try devices.compactMap { device in
            var streams = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                                    mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
            var streamSize: UInt32 = 0
            let status = AudioObjectGetPropertyDataSize(device, &streams, 0, nil, &streamSize)
            if status != noErr || streamSize == 0 { return nil }
            return ["id": String(device), "name": try audioName(device)]
        }
    }
}
