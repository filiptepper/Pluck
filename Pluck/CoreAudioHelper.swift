import CoreAudio
import Foundation

public struct AudioDevice: Identifiable, Hashable {
    public var id: AudioDeviceID { deviceID }
    public let deviceID: AudioDeviceID
    public let name: String
    public let uid: String
    public let inputChannels: Int
    public let outputChannels: Int
    public let sampleRate: Double
    public var isMultiOutput: Bool {
        uid.hasPrefix("~:AMS2_StackedOutput")
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(deviceID)
    }
    
    public static func == (lhs: AudioDevice, rhs: AudioDevice) -> Bool {
        return lhs.deviceID == rhs.deviceID
    }
}

public class CoreAudioHelper {
    public static func getAllDevices() -> [AudioDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: 0
        )
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size)
        guard status == noErr else { return [] }
        
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceIDs)
        guard status == noErr else { return [] }
        
        var devices: [AudioDevice] = []
        for deviceID in deviceIDs {
            // 1. Get Name
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceNameCFString,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var nameCF: Unmanaged<CFString>?
            var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            status = AudioObjectGetPropertyData(deviceID, &nameAddress, 0, nil, &nameSize, &nameCF)
            let name = (status == noErr && nameCF != nil) ? (nameCF!.takeRetainedValue() as String) : "Unknown Device"
            
            // 2. Get UID
            var uidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var uidCF: Unmanaged<CFString>?
            var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            status = AudioObjectGetPropertyData(deviceID, &uidAddress, 0, nil, &uidSize, &uidCF)
            let uid = (status == noErr && uidCF != nil) ? (uidCF!.takeRetainedValue() as String) : ""
            
            // 3. Channels Count
            let inputChannels = getChannelCount(deviceID: deviceID, isInput: true)
            let outputChannels = getChannelCount(deviceID: deviceID, isInput: false)
            
            // 4. Sample Rate
            var rateAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyNominalSampleRate,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var sampleRate: Double = 0.0
            var rateSize = UInt32(MemoryLayout<Double>.size)
            status = AudioObjectGetPropertyData(deviceID, &rateAddress, 0, nil, &rateSize, &sampleRate)
            
            devices.append(AudioDevice(
                deviceID: deviceID,
                name: name,
                uid: uid,
                inputChannels: inputChannels,
                outputChannels: outputChannels,
                sampleRate: sampleRate
            ))
        }
        return devices
    }
    
    public static func getChannelCount(deviceID: AudioDeviceID, isInput: Bool) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: isInput ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput,
            mElement: 0
        )
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size)
        guard status == noErr && size > 0 else { return 0 }
        
        let rawPtr = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { rawPtr.deallocate() }
        let bufferList = rawPtr.bindMemory(to: AudioBufferList.self, capacity: 1)
        
        status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, bufferList)
        guard status == noErr else { return 0 }
        
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        var channelCount = 0
        for buffer in buffers {
            channelCount += Int(buffer.mNumberChannels)
        }
        return channelCount
    }
    
    public static func getBufferSize(deviceID: AudioDeviceID) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyBufferFrameSize,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: 0
        )
        var bufferSize: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &bufferSize)
        return status == noErr ? bufferSize : 0
    }
    
    public static func getBufferSizeRange(deviceID: AudioDeviceID) -> ClosedRange<UInt32>? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyBufferFrameSizeRange,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: 0
        )
        var range = AudioValueRange()
        var size = UInt32(MemoryLayout<AudioValueRange>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &range)
        guard status == noErr, range.mMinimum > 0, range.mMaximum >= range.mMinimum else { return nil }
        return UInt32(range.mMinimum)...UInt32(range.mMaximum)
    }
    
    public static func setBufferSize(deviceID: AudioDeviceID, size: UInt32) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyBufferFrameSize,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: 0
        )
        var targetSize = size
        if let range = getBufferSizeRange(deviceID: deviceID) {
            targetSize = min(max(size, range.lowerBound), range.upperBound)
        }
        let dataSize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, dataSize, &targetSize)
        return status == noErr
    }
    
    public static func destroyAllOrphanedAggregateDevices() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: 0
        )
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size)
        guard status == noErr else { return }
        
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceIDs)
        guard status == noErr else { return }
        
        for deviceID in deviceIDs {
            var uidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var uidCF: Unmanaged<CFString>?
            var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            status = AudioObjectGetPropertyData(deviceID, &uidAddress, 0, nil, &uidSize, &uidCF)
            
            if status == noErr, let uid = uidCF?.takeRetainedValue() as String? {
                if uid.hasPrefix("pl.tepper.pluck.multiout") {
                    print("[CoreAudioHelper] Found orphaned aggregate device: \(uid) (ID: \(deviceID)), destroying...")
                    _ = AudioHardwareDestroyAggregateDevice(deviceID)
                }
            }
        }
    }
    
    public static func getDeviceID(for uid: String) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size)
        guard status == noErr else { return nil }
        
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceIDs)
        guard status == noErr else { return nil }
        
        for deviceID in deviceIDs {
            var uidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var uidCF: Unmanaged<CFString>?
            var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            if AudioObjectGetPropertyData(deviceID, &uidAddress, 0, nil, &uidSize, &uidCF) == noErr,
               let uidVal = uidCF?.takeRetainedValue() as String? {
                if uidVal == uid {
                    return deviceID
                }
            }
        }
        return nil
    }
    
    public struct SubDeviceInfo: Equatable {
        public let uid: String
        public let driftCompensation: UInt32
        
        public init(uid: String, driftCompensation: UInt32) {
            self.uid = uid
            self.driftCompensation = driftCompensation
        }
    }
    
    public static func getSubDevices(for multiOutputDeviceID: AudioDeviceID) -> [SubDeviceInfo] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyOwnedObjects,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(multiOutputDeviceID, &addr, 0, nil, &size)
        guard status == noErr && size > 0 else { return [] }
        
        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var objectIDs = [AudioObjectID](repeating: 0, count: count)
        let err = AudioObjectGetPropertyData(multiOutputDeviceID, &addr, 0, nil, &size, &objectIDs)
        guard err == noErr else { return [] }
        
        var subDevices: [SubDeviceInfo] = []
        for objID in objectIDs {
            var classID: AudioClassID = 0
            var classSize = UInt32(MemoryLayout<AudioClassID>.size)
            var classAddr = AudioObjectPropertyAddress(
                mSelector: kAudioObjectPropertyClass,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            if AudioObjectGetPropertyData(objID, &classAddr, 0, nil, &classSize, &classID) == noErr {
                // 'asub' = 0x61737562 (kAudioSubDeviceClassID)
                if classID == 0x61737562 {
                    var uidAddr = AudioObjectPropertyAddress(
                        mSelector: kAudioDevicePropertyDeviceUID,
                        mScope: kAudioObjectPropertyScopeGlobal,
                        mElement: kAudioObjectPropertyElementMain
                    )
                    var cfStr: Unmanaged<CFString>?
                    var strSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
                    if AudioObjectGetPropertyData(objID, &uidAddr, 0, nil, &strSize, &cfStr) == noErr,
                       let uid = cfStr?.takeRetainedValue() as String? {
                        var driftAddr = AudioObjectPropertyAddress(
                            mSelector: kAudioSubDevicePropertyDriftCompensation,
                            mScope: kAudioObjectPropertyScopeGlobal,
                            mElement: kAudioObjectPropertyElementMain
                        )
                        var drift: UInt32 = (subDevices.isEmpty ? 0 : 1)
                        var driftSize = UInt32(MemoryLayout<UInt32>.size)
                        _ = AudioObjectGetPropertyData(objID, &driftAddr, 0, nil, &driftSize, &drift)
                        subDevices.append(SubDeviceInfo(uid: uid, driftCompensation: drift))
                    }
                }
            }
        }
        return subDevices
    }
    
    public static func getSubDeviceUIDs(for multiOutputDeviceID: AudioDeviceID) -> [String] {
        return getSubDevices(for: multiOutputDeviceID).map { $0.uid }
    }
    
    public static func createMultiOutputAggregate(for multiOutputDeviceID: AudioDeviceID) -> AudioDeviceID? {
        let subDevices = getSubDevices(for: multiOutputDeviceID)
        guard !subDevices.isEmpty else { return nil }
        
        var subDeviceDicts: [[String: Any]] = []
        let hasMasterClock = subDevices.contains { $0.driftCompensation == 0 }
        
        for (index, sub) in subDevices.enumerated() {
            let drift = hasMasterClock ? sub.driftCompensation : (index == 0 ? 0 : 1)
            subDeviceDicts.append([
                kAudioSubDeviceUIDKey: sub.uid,
                kAudioSubDeviceDriftCompensationKey: drift
            ])
        }
        
        let uniqueUID = "pl.tepper.pluck.multiout.\(UUID().uuidString)"
        let desc: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Pluck Output Aggregate",
            kAudioAggregateDeviceUIDKey: uniqueUID,
            kAudioAggregateDeviceSubDeviceListKey: subDeviceDicts,
            kAudioAggregateDeviceIsPrivateKey: true
        ]
        
        var aggID: AudioDeviceID = 0
        let status = AudioHardwareCreateAggregateDevice(desc as CFDictionary, &aggID)
        return status == noErr ? aggID : nil
    }
    
    @discardableResult
    public static func destroyAggregateDevice(_ deviceID: AudioDeviceID) -> Bool {
        let status = AudioHardwareDestroyAggregateDevice(deviceID)
        return status == noErr
    }
    
    public static func setNominalSampleRate(deviceID: AudioDeviceID, sampleRate: Double) -> Bool {
        var rateAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var rate = sampleRate
        let status = AudioObjectSetPropertyData(deviceID, &rateAddress, 0, nil, UInt32(MemoryLayout<Double>.size), &rate)
        return status == noErr
    }

    public static func getDefaultDeviceID(isInput: Bool) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: isInput ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        return status == noErr && deviceID != 0 ? deviceID : nil
    }

    public static func getNominalSampleRate(deviceID: AudioDeviceID) -> Double {
        var rateAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var sampleRate: Double = 0.0
        var rateSize = UInt32(MemoryLayout<Double>.size)
        let status = AudioObjectGetPropertyData(deviceID, &rateAddress, 0, nil, &rateSize, &sampleRate)
        return status == noErr ? sampleRate : 0.0
    }

    public static func createOutputChannelMap(totalChannels: Int, isMultiOutput: Bool) -> [Int32] {
        guard totalChannels > 0 else { return [] }
        var channelMap = [Int32](repeating: -1, count: totalChannels)
        if isMultiOutput {
            for ch in stride(from: 0, through: totalChannels - 2, by: 2) {
                channelMap[ch] = 0     // Left
                channelMap[ch + 1] = 1 // Right
            }
        } else {
            if totalChannels >= 2 {
                channelMap[0] = 0
                channelMap[1] = 1
            } else if totalChannels == 1 {
                channelMap[0] = 0
            }
        }
        return channelMap
    }

    public static func addDevicesListener(block: @escaping () -> Void) -> AudioObjectPropertyListenerBlock {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let listenerBlock: AudioObjectPropertyListenerBlock = { _, _ in
            DispatchQueue.main.async {
                block()
            }
        }
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.global(qos: .userInitiated),
            listenerBlock
        )
        return listenerBlock
    }

    public static func removeDevicesListener(_ listenerBlock: @escaping AudioObjectPropertyListenerBlock) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.global(qos: .userInitiated),
            listenerBlock
        )
    }
}
