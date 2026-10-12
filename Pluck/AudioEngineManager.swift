import Foundation
import AVFoundation
import CoreAudio
import AudioToolbox
import Combine
import Accelerate

// Lock-free single-producer single-consumer ring buffer for low-latency audio streaming
final class AudioRingBuffer {
    let capacity: Int
    private let mask: Int64
    private let buffer: UnsafeMutablePointer<Float>
    private let wPtr: UnsafeMutablePointer<Int64>
    private let rPtr: UnsafeMutablePointer<Int64>
    
    init(capacity: Int = 16384) {
        var cap = 2
        while cap < capacity { cap *= 2 }
        self.capacity = cap
        self.mask = Int64(cap - 1)
        self.buffer = UnsafeMutablePointer<Float>.allocate(capacity: cap)
        self.buffer.initialize(repeating: 0, count: cap)
        self.wPtr = UnsafeMutablePointer<Int64>.allocate(capacity: 1)
        self.rPtr = UnsafeMutablePointer<Int64>.allocate(capacity: 1)
        self.wPtr.initialize(to: 0)
        self.rPtr.initialize(to: 0)
    }
    
    deinit {
        buffer.deallocate()
        wPtr.deallocate()
        rPtr.deallocate()
    }
    
    private func getW() -> Int64 {
        return OSAtomicAdd64Barrier(0, wPtr)
    }
    
    private func getR() -> Int64 {
        return OSAtomicAdd64Barrier(0, rPtr)
    }
    
    func reset() {
        while true {
            let curW = getW()
            if OSAtomicCompareAndSwap64Barrier(curW, 0, wPtr) { break }
        }
        while true {
            let curR = getR()
            if OSAtomicCompareAndSwap64Barrier(curR, 0, rPtr) { break }
        }
        buffer.initialize(repeating: 0, count: capacity)
    }
    
    func availableToRead() -> Int {
        let diff = getW() - getR()
        return max(0, min(capacity, Int(diff)))
    }
    
    @discardableResult
    func write(from ptr: UnsafePointer<Float>, count: Int) -> Int {
        let w = getW()
        let r = getR()
        let freeSpace = capacity - Int(w - r)
        guard freeSpace > 0 else { return 0 }
        
        let toWrite = min(count, freeSpace)
        for i in 0..<toWrite {
            let idx = Int((w + Int64(i)) & mask)
            buffer[idx] = ptr[i]
        }
        OSAtomicAdd64Barrier(Int64(toWrite), wPtr)
        return toWrite
    }
    
    func read(into ptr: UnsafeMutablePointer<Float>, count: Int, bufferSize: UInt32 = 128) {
        var r = getR()
        let w = getW()
        let avail = Int(w - r)
        
        // Dynamic clock drift protection:
        // Bound latency between targetLatency and maxLatency based on buffer frame size
        let targetLatency = max(512, Int(bufferSize) * 2)
        let maxLatency = max(2048, Int(bufferSize) * 4)
        
        if avail > maxLatency {
            let newR = w - Int64(targetLatency)
            while true {
                let curR = getR()
                if OSAtomicCompareAndSwap64Barrier(curR, newR, rPtr) { break }
            }
            r = newR
        }
        
        let validAvail = max(0, Int(w - r))
        let toRead = min(validAvail, count)
        
        for i in 0..<toRead {
            let idx = Int((r + Int64(i)) & mask)
            ptr[i] = buffer[idx]
        }
        
        if toRead > 0 {
            OSAtomicAdd64Barrier(Int64(toRead), rPtr)
        }
        
        if toRead < count {
            for i in toRead..<count {
                ptr[i] = 0.0
            }
        }
    }
}

// Dedicated CoreAudio HAL input capturer running on its own independent stream
final class AudioInputCapturer {
    private var unit: AudioUnit?
    private let ringBuffer: AudioRingBuffer
    private let onRMSUpdate: ((Float) -> Void)?
    
    private var bufferList: AudioBufferList
    private let sampleBuffer: UnsafeMutablePointer<Float>
    private let maxFrames: UInt32 = 4096
    
    init(
        deviceID: AudioDeviceID,
        inputChannel: Int,
        sampleRate: Float64,
        bufferSize: UInt32,
        ringBuffer: AudioRingBuffer,
        onRMSUpdate: ((Float) -> Void)?
    ) throws {
        self.ringBuffer = ringBuffer
        self.onRMSUpdate = onRMSUpdate
        
        self.sampleBuffer = UnsafeMutablePointer<Float>.allocate(capacity: Int(maxFrames))
        self.bufferList = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(
                mNumberChannels: 1,
                mDataByteSize: maxFrames * UInt32(MemoryLayout<Float>.size),
                mData: sampleBuffer
            )
        )
        
        var desc = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        
        guard let comp = AudioComponentFindNext(nil, &desc) else {
            throw NSError(domain: "AudioInputCapturer", code: -1, userInfo: [NSLocalizedDescriptionKey: "HALOutput component not found"])
        }
        
        var unit: AudioUnit?
        var status = AudioComponentInstanceNew(comp, &unit)
        guard let unit = unit, status == noErr else {
            throw NSError(domain: "AudioInputCapturer", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Failed to create AudioComponentInstance (\(status))"])
        }
        self.unit = unit
        
        // 1. Enable input (bus 1)
        var enableIO: UInt32 = 1
        status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &enableIO, UInt32(MemoryLayout<UInt32>.size))
        guard status == noErr else { throw NSError(domain: "AudioInputCapturer", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Failed to enable input IO"]) }
        
        // 2. Disable output (bus 0)
        enableIO = 0
        status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &enableIO, UInt32(MemoryLayout<UInt32>.size))
        guard status == noErr else { throw NSError(domain: "AudioInputCapturer", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Failed to disable output IO"]) }
        
        // 3. Set device
        var devID = deviceID
        status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &devID, UInt32(MemoryLayout<AudioDeviceID>.size))
        guard status == noErr else { throw NSError(domain: "AudioInputCapturer", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Failed to set input device (\(status))"]) }
        
        // 4. Set stream format (bus 1 output scope)
        var streamDesc = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 32,
            mReserved: 0
        )
        status = AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &streamDesc, UInt32(MemoryLayout<AudioStreamBasicDescription>.size))
        guard status == noErr else { throw NSError(domain: "AudioInputCapturer", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Failed to set stream format (\(status))"]) }
        
        // 5. Set channel map
        var channelMap = [Int32(inputChannel)]
        let channelMapSize = UInt32(MemoryLayout<Int32>.size * channelMap.count)
        status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_ChannelMap, kAudioUnitScope_Output, 1, &channelMap, channelMapSize)
        guard status == noErr else { throw NSError(domain: "AudioInputCapturer", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Failed to set input channel map (\(status))"]) }
        
        // 6. Set buffer size
        var bufSize = bufferSize
        _ = AudioUnitSetProperty(unit, kAudioDevicePropertyBufferFrameSize, kAudioUnitScope_Global, 0, &bufSize, UInt32(MemoryLayout<UInt32>.size))
        
        // 7. Set input callback
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        var callbackStruct = AURenderCallbackStruct(
            inputProc: { (inRefCon, ioActionFlags, inTimeStamp, inBusNumber, inNumberFrames, ioData) -> OSStatus in
                let capturer = Unmanaged<AudioInputCapturer>.fromOpaque(inRefCon).takeUnretainedValue()
                return capturer.renderCallback(ioActionFlags: ioActionFlags, inTimeStamp: inTimeStamp, inNumberFrames: inNumberFrames)
            },
            inputProcRefCon: selfPtr
        )
        status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0, &callbackStruct, UInt32(MemoryLayout<AURenderCallbackStruct>.size))
        guard status == noErr else { throw NSError(domain: "AudioInputCapturer", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Failed to set input callback (\(status))"]) }
        
        // 8. Initialize
        status = AudioUnitInitialize(unit)
        guard status == noErr else { throw NSError(domain: "AudioInputCapturer", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Failed to initialize AudioUnit (\(status))"]) }
    }
    
    deinit {
        stop()
        if let u = unit {
            AudioUnitUninitialize(u)
            AudioComponentInstanceDispose(u)
        }
        sampleBuffer.deallocate()
    }
    
    func start() throws {
        guard let u = unit else { return }
        let status = AudioOutputUnitStart(u)
        guard status == noErr else {
            throw NSError(domain: "AudioInputCapturer", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "AudioOutputUnitStart failed (\(status))"])
        }
    }
    
    func stop() {
        guard let u = unit else { return }
        AudioOutputUnitStop(u)
    }
    
    private func renderCallback(
        ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
        inTimeStamp: UnsafePointer<AudioTimeStamp>,
        inNumberFrames: UInt32
    ) -> OSStatus {
        guard let u = unit else { return noErr }
        let framesToRender = min(inNumberFrames, maxFrames)
        bufferList.mBuffers.mDataByteSize = framesToRender * UInt32(MemoryLayout<Float>.size)
        
        let err = AudioUnitRender(u, ioActionFlags, inTimeStamp, 1, framesToRender, &bufferList)
        guard err == noErr else { return err }
        
        ringBuffer.write(from: sampleBuffer, count: Int(framesToRender))
        
        var rms: Float = 0.0
        vDSP_rmsqv(sampleBuffer, 1, &rms, vDSP_Length(framesToRender))
        onRMSUpdate?(rms)
        
        return noErr
    }
}

public class AudioEngineManager: ObservableObject {
    @Published public var isRunning = false
    @Published public var inputLevel: Float = 0.0
    @Published public var outputLevel: Float = 0.0
    @Published public var helixUnit: AVAudioUnit? = nil
    
    // Status text to show in the UI for debugging and state updates
    @Published public var statusMessage: String = "Initializing..."
    @Published public var availableDevices: [AudioDevice] = []
    @Published public var isHelixAvailable = true
    @Published public var micPermissionDenied = false
    
    private var isInitialized = false
    
    @Published public var selectedInputDevice: AudioDevice? = nil {
        didSet {
            guard isInitialized else { return }
            log("Selected Input Device changed: \(selectedInputDevice?.name ?? "None")")
            if let dev = selectedInputDevice {
                UserDefaults.standard.set(dev.uid, forKey: "pluck.selectedInputUID")
                if selectedInputChannel >= dev.inputChannels {
                    selectedInputChannel = max(0, dev.inputChannels - 1)
                }
            }
            if isActivated {
                triggerReconfiguration()
            }
        }
    }
    @Published public var selectedOutputDevice: AudioDevice? = nil {
        didSet {
            guard isInitialized else { return }
            log("Selected Output Device changed: \(selectedOutputDevice?.name ?? "None")")
            if let dev = selectedOutputDevice {
                UserDefaults.standard.set(dev.uid, forKey: "pluck.selectedOutputUID")
            }
            if isActivated {
                triggerReconfiguration()
            }
        }
    }
    @Published public var selectedInputChannel: Int = 0 {
        didSet {
            guard isInitialized else { return }
            UserDefaults.standard.set(selectedInputChannel, forKey: "pluck.selectedInputChannel")
            log("Selected Input Channel changed: \(selectedInputChannel + 1)")
            if isActivated {
                triggerReconfiguration()
            }
        }
    }
    @Published public var selectedBufferSize: UInt32 = 128 {
        didSet {
            guard isInitialized else { return }
            UserDefaults.standard.set(selectedBufferSize, forKey: "pluck.selectedBufferSize")
            log("Selected Buffer Size changed: \(selectedBufferSize)")
            let input = selectedInputDevice
            let output = selectedOutputDevice
            let size = selectedBufferSize
            audioQueue.async { [weak self] in
                guard let self = self else { return }
                self.updateDeviceBufferSize(input: input, output: output, targetOutputDeviceID: self.privateAggregateDeviceID, size: size)
            }
        }
    }
    @Published public var isBypassed = false {
        didSet {
            log("Bypass toggled: \(isBypassed)")
            helixUnit?.auAudioUnit.shouldBypassEffect = isBypassed
        }
    }
    
    private var engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private var inputCapturer: AudioInputCapturer?
    private let ringBuffer = AudioRingBuffer(capacity: 16384)
    private var privateAggregateDeviceID: AudioDeviceID? = nil
    
    private var isConfiguring = false
    private var shouldStartAfterConfig = false
    private var configVersion = 0
    private var activityToken: NSObjectProtocol? = nil
    private var devicesListenerBlock: AudioObjectPropertyListenerBlock?
    private var engineConfigObserver: NSObjectProtocol?
    
    private let audioQueue = DispatchQueue(label: "pl.tepper.pluck.audioQueue", qos: .userInitiated)
    private var meterTimer: Timer?
    private var rawInputBits: Int32 = 0
    private var rawOutputBits: Int32 = 0
    
    public static let availableBufferSizes: [UInt32] = [32, 64, 128, 256, 512]
    
    private static let logFormatter = ISO8601DateFormatter()
    
    private func log(_ message: String) {
        let timestamp = Self.logFormatter.string(from: Date())
        print("[\(timestamp)] [AudioEngineManager] \(message)")
        fflush(stdout)
    }
    
    private var isActivated = false
    
    public init(autoActivate: Bool = false) {
        log("Initializing AudioEngineManager...")
        
        CoreAudioHelper.destroyAllOrphanedAggregateDevices()
        
        availableDevices = CoreAudioHelper.getAllDevices()
        log("Available audio devices: \(availableDevices.map { "\($0.name) (I:\($0.inputChannels), O:\($0.outputChannels))" })")
        
        let savedInUID = UserDefaults.standard.string(forKey: "pluck.selectedInputUID")
        let savedOutUID = UserDefaults.standard.string(forKey: "pluck.selectedOutputUID")
        let savedChannel = UserDefaults.standard.object(forKey: "pluck.selectedInputChannel") as? Int
        let savedBufferSize = UserDefaults.standard.object(forKey: "pluck.selectedBufferSize") as? UInt32
        
        let defaultInID = CoreAudioHelper.getDefaultDeviceID(isInput: true)
        let defaultOutID = CoreAudioHelper.getDefaultDeviceID(isInput: false)
        
        selectedInputDevice = availableDevices.first(where: { $0.uid == savedInUID })
            ?? availableDevices.first(where: { $0.deviceID == defaultInID })
            ?? availableDevices.first(where: { $0.inputChannels > 0 })
            
        selectedOutputDevice = availableDevices.first(where: { $0.uid == savedOutUID })
            ?? availableDevices.first(where: { $0.deviceID == defaultOutID })
            ?? availableDevices.first(where: { $0.outputChannels > 0 })
            
        if let ch = savedChannel, let dev = selectedInputDevice, ch < dev.inputChannels {
            selectedInputChannel = ch
        }
        if let buf = savedBufferSize, buf > 0 {
            selectedBufferSize = buf
        }
        
        log("Initial Input Device: \(selectedInputDevice?.name ?? "None") (Channel \(selectedInputChannel + 1))")
        log("Initial Output Device: \(selectedOutputDevice?.name ?? "None") (Buffer \(selectedBufferSize))")
        
        // Listen for hardware device topology changes (hotplug/unplug)
        devicesListenerBlock = CoreAudioHelper.addDevicesListener { [weak self] in
            guard let self = self else { return }
            self.log("Hardware device configuration changed. Updating device list...")
            self.availableDevices = CoreAudioHelper.getAllDevices()
            self.validateAndReconfigureDevices()
        }
        
        engineConfigObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            self.log("AVAudioEngineConfigurationChange Notification received.")
            self.availableDevices = CoreAudioHelper.getAllDevices()
            self.validateAndReconfigureDevices()
        }
        
        self.statusMessage = "Ready. Select devices and Start Engine."
        isInitialized = true
        if autoActivate {
            activate()
        }
    }
    
    public var pluginStateURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let pluckDir = appSupport.appendingPathComponent("Pluck", isDirectory: true)
        if !FileManager.default.fileExists(atPath: pluckDir.path) {
            try? FileManager.default.createDirectory(at: pluckDir, withIntermediateDirectories: true)
        }
        return pluckDir.appendingPathComponent("preset.plist")
    }
    
    public func savePluginState() {
        guard let au = helixUnit?.auAudioUnit else { return }
        if let state = au.fullState {
            let url = pluginStateURL
            (state as NSDictionary).write(to: url, atomically: true)
            log("Saved plugin preset state to \(url.path)")
        }
    }
    
    public func restorePluginState(to unit: AVAudioUnit) {
        let url = pluginStateURL
        if FileManager.default.fileExists(atPath: url.path),
           let state = NSDictionary(contentsOf: url) as? [String: Any] {
            unit.auAudioUnit.fullState = state
            log("Restored plugin preset state from \(url.path)")
        }
    }
    
    public func activate() {
        guard !isActivated else { return }
        isActivated = true
        log("Activating AudioEngineManager and configuring graph...")
        triggerReconfiguration()
    }
    
    deinit {
        savePluginState()
        stopEngine()
        meterTimer?.invalidate()
        if let aggID = privateAggregateDeviceID {
            CoreAudioHelper.destroyAggregateDevice(aggID)
            privateAggregateDeviceID = nil
        }
        if let block = devicesListenerBlock {
            CoreAudioHelper.removeDevicesListener(block)
        }
        if let observer = engineConfigObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    private func validateAndReconfigureDevices() {
        guard !isConfiguring else { return }
        let devices = availableDevices
        
        if let selectedInput = selectedInputDevice {
            let stillExists = devices.contains(where: { $0.deviceID == selectedInput.deviceID })
            if !stillExists {
                log("Selected input device is no longer available. Reconfiguring...")
                selectedInputDevice = devices.first(where: { $0.inputChannels > 0 })
                return
            }
        }
        
        if let selectedOutput = selectedOutputDevice {
            let stillExists = devices.contains(where: { $0.deviceID == selectedOutput.deviceID })
            if !stillExists {
                log("Selected output device is no longer available. Reconfiguring...")
                selectedOutputDevice = devices.first(where: { $0.outputChannels > 0 })
                return
            }
        }
    }
    
    public func checkAndRequestMicrophoneAccess(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    self.micPermissionDenied = !granted
                    completion(granted)
                }
            }
        case .denied, .restricted:
            DispatchQueue.main.async {
                self.micPermissionDenied = true
                self.statusMessage = "Microphone access denied in System Settings."
                completion(false)
            }
        @unknown default:
            completion(false)
        }
    }
    
    public func startEngine() {
        log("startEngine() called. current status: isRunning=\(isRunning)")
        guard !isRunning else { return }
        
        checkAndRequestMicrophoneAccess { [weak self] granted in
            guard let self = self else { return }
            guard granted else {
                self.log("Cannot start engine: Microphone permission denied.")
                return
            }
            
            self.isActivated = true
            self.shouldStartAfterConfig = true
            self.triggerReconfiguration()
        }
    }
    
    public func stopEngine() {
        log("stopEngine() called.")
        savePluginState()
        shouldStartAfterConfig = false
        configVersion += 1
        
        isRunning = false
        statusMessage = "Engine stopped."
        stopMeterTimer()
        
        if let token = activityToken {
            ProcessInfo.processInfo.endActivity(token)
            activityToken = nil
        }
        
        audioQueue.async { [weak self] in
            guard let self = self else { return }
            self.log("Stopping hardware engine on audioQueue...")
            self.engine.stop()
            self.inputCapturer?.stop()
            if let aggID = self.privateAggregateDeviceID {
                self.log("Destroying private aggregate device \(aggID)...")
                CoreAudioHelper.destroyAggregateDevice(aggID)
                self.privateAggregateDeviceID = nil
            }
        }
    }
    
    public func toggleBypass() {
        isBypassed.toggle()
    }
    
    private func triggerReconfiguration() {
        configVersion += 1
        let currentVersion = configVersion
        log("triggerReconfiguration() triggered. New Version ID: \(currentVersion)")
        
        isConfiguring = true
        let wasRunning = isRunning
        if wasRunning {
            log("Engine was running, updating state on main thread before stopping...")
            isRunning = false
            statusMessage = "Stopping engine..."
            stopMeterTimer()
            if let token = activityToken {
                ProcessInfo.processInfo.endActivity(token)
                activityToken = nil
            }
            shouldStartAfterConfig = true
        }
        
        statusMessage = "Configuring Audio Devices..."
        
        let input = selectedInputDevice
        let output = selectedOutputDevice
        let inputChannel = selectedInputChannel
        let bufferSize = selectedBufferSize
        let existingUnit = helixUnit
        
        audioQueue.async { [weak self] in
            guard let self = self else { return }
            
            if wasRunning {
                self.log("Stopping hardware engine in background...")
                self.engine.stop()
                self.inputCapturer?.stop()
                self.engine.reset()
            }
            
            if let aggID = self.privateAggregateDeviceID {
                self.log("Destroying previous private aggregate device \(aggID)...")
                CoreAudioHelper.destroyAggregateDevice(aggID)
                self.privateAggregateDeviceID = nil
            }
            
            self.inputCapturer = nil
            
            self.setupAudioGraphAsync(
                version: currentVersion,
                input: input,
                output: output,
                inputChannel: inputChannel,
                bufferSize: bufferSize,
                existingUnit: existingUnit
            )
        }
    }
    
    private func updateDeviceBufferSize(input: AudioDevice?, output: AudioDevice?, targetOutputDeviceID: AudioDeviceID?, size: UInt32) {
        log("Updating device buffer sizes to \(size)...")
        if let device = output {
            if device.isMultiOutput {
                let subUIDs = CoreAudioHelper.getSubDeviceUIDs(for: device.deviceID)
                for subUID in subUIDs {
                    if let subDevID = CoreAudioHelper.getDeviceID(for: subUID) {
                        let success = CoreAudioHelper.setBufferSize(deviceID: subDevID, size: size)
                        log("Set subdevice \(subUID) buffer size success: \(success)")
                    }
                }
                if let aggID = targetOutputDeviceID {
                    let success = CoreAudioHelper.setBufferSize(deviceID: aggID, size: size)
                    log("Set aggregate output device \(aggID) buffer size success: \(success)")
                }
            } else {
                let success = CoreAudioHelper.setBufferSize(deviceID: device.deviceID, size: size)
                log("Set output device \(device.name) buffer size success: \(success)")
            }
        }
        if let device = input {
            let success = CoreAudioHelper.setBufferSize(deviceID: device.deviceID, size: size)
            log("Set input device \(device.name) buffer size success: \(success)")
        }
        
        // Sync back active hardware buffer size in case hardware clamped to its supported range
        if let device = output {
            let actual = CoreAudioHelper.getBufferSize(deviceID: targetOutputDeviceID ?? device.deviceID)
            if actual > 0 && actual != size {
                log("Hardware clamped buffer size from requested \(size) to actual \(actual)")
                DispatchQueue.main.async {
                    self.selectedBufferSize = actual
                }
            }
        }
    }
    
    private func setupAudioGraphAsync(
        version: Int,
        input: AudioDevice?,
        output: AudioDevice?,
        inputChannel: Int,
        bufferSize: UInt32,
        existingUnit: AVAudioUnit?
    ) {
        log("setupAudioGraphAsync() started for Version: \(version)")
        engine = AVAudioEngine()
        ringBuffer.reset()
        
        guard let input = input, let output = output else {
            log("Setup aborted: Input or Output device is nil.")
            DispatchQueue.main.async {
                self.statusMessage = "Error: Input/Output device not selected."
                self.isConfiguring = false
            }
            return
        }
        
        log("Configuring routing: Input=\(input.name) (ID \(input.deviceID)), Output=\(output.name) (ID \(output.deviceID))")
        
        var targetDeviceID = output.deviceID
        if output.isMultiOutput {
            log("Output device is Multi-Output (\(output.name)). Creating private aggregate device to bypass AVFAudio stacked output deadlock...")
            if let aggID = CoreAudioHelper.createMultiOutputAggregate(for: output.deviceID) {
                targetDeviceID = aggID
                self.privateAggregateDeviceID = aggID
                log("Created private aggregate device ID \(aggID) for Multi-Output device.")
            } else {
                log("Failed to create private aggregate device for Multi-Output. Falling back to direct device ID.")
            }
        }
        
        let totalOutputChannels = CoreAudioHelper.getChannelCount(deviceID: targetDeviceID, isInput: false)
        
        if let outputUnit = engine.outputNode.audioUnit {
            var deviceID = targetDeviceID
            let deviceSize = UInt32(MemoryLayout<AudioDeviceID>.size)
            log("Setting current device ID \(deviceID) on outputNode HAL AudioUnit...")
            let status = AudioUnitSetProperty(
                outputUnit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &deviceID,
                deviceSize
            )
            log("AudioUnitSetProperty CurrentDevice status code: \(status)")
            
            if totalOutputChannels > 0 {
                var channelMap = CoreAudioHelper.createOutputChannelMap(
                    totalChannels: totalOutputChannels,
                    isMultiOutput: output.isMultiOutput
                )
                let channelMapSize = UInt32(MemoryLayout<Int32>.size * channelMap.count)
                let mapStatus = AudioUnitSetProperty(
                    outputUnit,
                    kAudioOutputUnitProperty_ChannelMap,
                    kAudioUnitScope_Output,
                    0,
                    &channelMap,
                    channelMapSize
                )
                log("AudioUnitSetProperty ChannelMap (outputNode) status code: \(mapStatus), map: \(channelMap)")
            }
        } else {
            log("Error: engine.outputNode.audioUnit is nil, cannot set hardware device ID.")
        }
        
        updateDeviceBufferSize(input: input, output: output, targetOutputDeviceID: targetDeviceID, size: bufferSize)
        
        let nominalOutRate = CoreAudioHelper.getNominalSampleRate(deviceID: targetDeviceID)
        let nominalInRate = CoreAudioHelper.getNominalSampleRate(deviceID: input.deviceID)
        let sampleRate: Float64 = (nominalOutRate > 0) ? nominalOutRate : ((output.sampleRate > 0) ? output.sampleRate : 48000.0)
        
        // Ensure input device sample rate aligns with output device to prevent AUHAL configuration failures or pitch shifts
        if nominalInRate > 0 && abs(nominalInRate - sampleRate) > 1.0 {
            log("Input nominal sample rate (\(nominalInRate) Hz) differs from output (\(sampleRate) Hz). Aligning input device rate...")
            _ = CoreAudioHelper.setNominalSampleRate(deviceID: input.deviceID, sampleRate: sampleRate)
        }
        
        do {
            self.inputCapturer = try AudioInputCapturer(
                deviceID: input.deviceID,
                inputChannel: inputChannel,
                sampleRate: sampleRate,
                bufferSize: bufferSize,
                ringBuffer: self.ringBuffer,
                onRMSUpdate: { [weak self] rms in
                    self?.updateRawInputLevel(rms)
                }
            )
            log("AudioInputCapturer initialized successfully.")
        } catch {
            log("Failed to initialize AudioInputCapturer: \(error)")
            DispatchQueue.main.async {
                self.statusMessage = "Input init failed: \(error.localizedDescription)"
                self.isConfiguring = false
            }
            return
        }
        
        func configureAndStartEngine(with au: AVAudioUnit) {
            self.log("Attaching Audio Unit to AVAudioEngine...")
            if let oldEngine = au.engine, oldEngine !== self.engine {
                oldEngine.detach(au)
            }
            if au.engine !== self.engine {
                self.engine.attach(au)
            }
            
            self.log("Querying AVAudioEngine hardware formats...")
            let hardwareOutputFormat = self.engine.outputNode.outputFormat(forBus: 0)
            self.log("Hardware output format: \(hardwareOutputFormat)")
            
            guard let monoFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sampleRate,
                channels: 1,
                interleaved: false
            ),
            let stereoFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sampleRate,
                channels: 2,
                interleaved: false
            ) else {
                self.log("Error: Failed to create audio formats.")
                DispatchQueue.main.async {
                    self.statusMessage = "Error: Invalid audio format."
                    self.isConfiguring = false
                }
                return
            }
            
            let curBufSize = self.selectedBufferSize
            let sourceNode = AVAudioSourceNode(format: monoFormat) { [weak ringBuffer = self.ringBuffer] _, _, frameCount, audioBufferList -> OSStatus in
                guard let ringBuffer = ringBuffer else { return noErr }
                let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
                if let buffer = abl.first, let ptr = buffer.mData?.assumingMemoryBound(to: Float.self) {
                    ringBuffer.read(into: ptr, count: Int(frameCount), bufferSize: curBufSize)
                }
                return noErr
            }
            self.sourceNode = sourceNode
            self.engine.attach(sourceNode)
            
            self.log("Connecting nodes: sourceNode -> AudioUnit...")
            self.engine.connect(sourceNode, to: au, format: monoFormat)
            
            self.log("Connecting nodes: AudioUnit -> engine.mainMixerNode...")
            self.engine.connect(au, to: self.engine.mainMixerNode, format: stereoFormat)
            
            self.log("Connecting nodes: engine.mainMixerNode -> engine.outputNode...")
            // AUHAL receives standard stereo from mainMixerNode and routes to physical channels via channelMap
            self.engine.connect(self.engine.mainMixerNode, to: self.engine.outputNode, format: stereoFormat)
            
            self.log("Installing real-time VU meter taps...")
            self.installMeterTaps()
            
            self.log("Preparing AVAudioEngine...")
            self.engine.prepare()
            
            // Re-assert channel map after prepare()
            if let outputUnit = self.engine.outputNode.audioUnit, totalOutputChannels > 0 {
                var channelMap = CoreAudioHelper.createOutputChannelMap(
                    totalChannels: totalOutputChannels,
                    isMultiOutput: output.isMultiOutput
                )
                let mapSize = UInt32(MemoryLayout<Int32>.size * channelMap.count)
                _ = AudioUnitSetProperty(outputUnit, kAudioOutputUnitProperty_ChannelMap, kAudioUnitScope_Output, 0, &channelMap, mapSize)
                _ = AudioUnitSetProperty(outputUnit, kAudioOutputUnitProperty_ChannelMap, kAudioUnitScope_Global, 0, &channelMap, mapSize)
                self.log("Post-prepare channelMap asserted: \(channelMap)")
            }
            
            var startedSuccessfully = false
            var startErrorMsg: String? = nil
            
            if self.shouldStartAfterConfig && self.configVersion == version {
                self.log("Start engine flag is active. Starting engine now...")
                do {
                    try self.engine.start()
                    do {
                        try self.inputCapturer?.start()
                        startedSuccessfully = true
                        self.log("AVAudioEngine and InputCapturer started successfully.")
                    } catch {
                        self.log("InputCapturer failed to start: \(error). Rolling back engine...")
                        self.engine.stop()
                        throw error
                    }
                } catch {
                    startErrorMsg = error.localizedDescription
                    self.log("Failed to start audio engine: \(error)")
                }
            }
            
            DispatchQueue.main.async {
                self.isConfiguring = false
                if self.shouldStartAfterConfig {
                    if startedSuccessfully {
                        self.isRunning = true
                        self.statusMessage = "Engine active."
                        self.startMeterTimer()
                        self.activityToken = ProcessInfo.processInfo.beginActivity(
                            options: [.userInitiated, .idleSystemSleepDisabled],
                            reason: "Live Audio Hosting"
                        )
                    } else {
                        self.statusMessage = "Start failed: \(startErrorMsg ?? "Unknown error")"
                        self.isRunning = false
                    }
                    self.shouldStartAfterConfig = false
                } else {
                    self.statusMessage = "Audio Unit loaded."
                }
                self.log("Configuring setup completed.")
            }
        }
        
        if let existingUnit = existingUnit {
            self.log("Reusing already instantiated Audio Unit.")
            configureAndStartEngine(with: existingUnit)
            return
        }
        
        var desc = AudioComponentDescription(
            componentType: kAudioUnitType_MusicEffect, // aumf
            componentSubType: 0x36485041,              // '6HPA' (Helix Native)
            componentManufacturer: 0x4c534958,         // 'LSIX' (Line 6)
            componentFlags: 0,
            componentFlagsMask: 0
        )
        
        let component = AudioComponentFindNext(nil, &desc)
        if component == nil {
            log("Helix Native component was not found in system scan.")
            DispatchQueue.main.async {
                self.statusMessage = "Helix Native not installed."
                self.isHelixAvailable = false
                self.isConfiguring = false
            }
            return
        } else {
            log("Line 6 Helix Native component found successfully.")
            DispatchQueue.main.async {
                self.isHelixAvailable = true
            }
        }
        
        DispatchQueue.main.async {
            self.statusMessage = "Loading Audio Unit..."
        }
        log("Calling AVAudioUnit.instantiate asynchronously...")
        
        AVAudioUnit.instantiate(with: desc, options: []) { [weak self] (audioUnit, error) in
            guard let self = self else { return }
            self.audioQueue.async {
                self.log("AVAudioUnit.instantiate completion block called for Version \(version). Current Version: \(self.configVersion)")
                
                guard self.configVersion == version else {
                    self.log("Discarding instantiated Audio Unit because Version ID changed (\(version) != \(self.configVersion)).")
                    return
                }
                
                guard let au = audioUnit else {
                    let errMsg = error?.localizedDescription ?? "Unknown error"
                    self.log("Failed to instantiate Audio Unit: \(errMsg)")
                    DispatchQueue.main.async {
                        self.statusMessage = "Load failed: \(errMsg)"
                        self.isConfiguring = false
                    }
                    return
                }
                
                self.log("Audio Unit instantiated successfully.")
                self.restorePluginState(to: au)
                DispatchQueue.main.async {
                    self.helixUnit = au
                }
                configureAndStartEngine(with: au)
            }
        }
    }
    
    private func updateRawInputLevel(_ rms: Float) {
        let bits = Int32(bitPattern: rms.bitPattern)
        while true {
            let cur = OSAtomicAdd32Barrier(0, &rawInputBits)
            if OSAtomicCompareAndSwap32Barrier(cur, bits, &rawInputBits) { break }
        }
    }

    private func updateRawOutputLevel(_ rms: Float) {
        let bits = Int32(bitPattern: rms.bitPattern)
        while true {
            let cur = OSAtomicAdd32Barrier(0, &rawOutputBits)
            if OSAtomicCompareAndSwap32Barrier(cur, bits, &rawOutputBits) { break }
        }
    }
    
    private func startMeterTimer() {
        meterTimer?.invalidate()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isRunning else { return }
            let inBits = UInt32(bitPattern: OSAtomicAdd32Barrier(0, &self.rawInputBits))
            let outBits = UInt32(bitPattern: OSAtomicAdd32Barrier(0, &self.rawOutputBits))
            self.inputLevel = Float(bitPattern: inBits)
            self.outputLevel = Float(bitPattern: outBits)
        }
    }
    
    private func stopMeterTimer() {
        meterTimer?.invalidate()
        meterTimer = nil
        inputLevel = 0.0
        outputLevel = 0.0
        updateRawInputLevel(0.0)
        updateRawOutputLevel(0.0)
    }

    private func installMeterTaps() {
        let bufferSize: AVAudioFrameCount = 1024
        engine.mainMixerNode.removeTap(onBus: 0)
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: bufferSize, format: nil) { [weak self] (buffer, _) in
            guard let self = self else { return }
            let rms = self.calculateRMS(buffer: buffer)
            self.updateRawOutputLevel(rms)
        }
    }
    
    private func calculateRMS(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0.0 }
        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        guard channelCount > 0, frameLength > 0 else { return 0.0 }
        
        var maxRms: Float = 0.0
        for ch in 0..<channelCount {
            var rms: Float = 0.0
            vDSP_rmsqv(channelData[ch], 1, &rms, vDSP_Length(frameLength))
            if rms > maxRms {
                maxRms = rms
            }
        }
        return maxRms
    }
}
