import XCTest
import AVFoundation
@testable import Pluck

final class PluckTests: XCTestCase {
    
    // MARK: - Ring Buffer Tests
    
    func testAudioRingBufferWriteAndRead() {
        let ringBuffer = AudioRingBuffer(capacity: 1024)
        let count = 256
        let inputSamples: [Float] = (0..<count).map { Float($0) * 0.1 }
        
        let written = inputSamples.withUnsafeBufferPointer { ptr in
            ringBuffer.write(from: ptr.baseAddress!, count: count)
        }
        XCTAssertEqual(written, count, "All samples should be written into ring buffer.")
        XCTAssertEqual(ringBuffer.availableToRead(), count)
        
        var outputSamples = [Float](repeating: 0.0, count: count)
        outputSamples.withUnsafeMutableBufferPointer { ptr in
            ringBuffer.read(into: ptr.baseAddress!, count: count)
        }
        
        XCTAssertEqual(ringBuffer.availableToRead(), 0)
        for i in 0..<count {
            XCTAssertEqual(outputSamples[i], inputSamples[i], accuracy: 0.0001, "Sample at index \(i) must match")
        }
    }
    
    func testAudioRingBufferReadZeroPaddingOnUnderrun() {
        let ringBuffer = AudioRingBuffer(capacity: 512)
        let inputSamples: [Float] = [1.0, 2.0, 3.0, 4.0]
        
        inputSamples.withUnsafeBufferPointer { ptr in
            ringBuffer.write(from: ptr.baseAddress!, count: inputSamples.count)
        }
        
        let readCount = 8
        var outputSamples = [Float](repeating: -99.0, count: readCount)
        outputSamples.withUnsafeMutableBufferPointer { ptr in
            ringBuffer.read(into: ptr.baseAddress!, count: readCount)
        }
        
        // First 4 samples should match input; remaining 4 must be zero-padded
        XCTAssertEqual(outputSamples[0], 1.0)
        XCTAssertEqual(outputSamples[1], 2.0)
        XCTAssertEqual(outputSamples[2], 3.0)
        XCTAssertEqual(outputSamples[3], 4.0)
        XCTAssertEqual(outputSamples[4], 0.0)
        XCTAssertEqual(outputSamples[5], 0.0)
        XCTAssertEqual(outputSamples[6], 0.0)
        XCTAssertEqual(outputSamples[7], 0.0)
    }
    
    func testAudioRingBufferWraparound() {
        // Power-of-2 capacity: 64
        let ringBuffer = AudioRingBuffer(capacity: 64)
        let firstBatch: [Float] = (0..<40).map { Float($0) }
        firstBatch.withUnsafeBufferPointer { ptr in
            _ = ringBuffer.write(from: ptr.baseAddress!, count: 40)
        }
        
        var readBuf = [Float](repeating: 0.0, count: 40)
        readBuf.withUnsafeMutableBufferPointer { ptr in
            ringBuffer.read(into: ptr.baseAddress!, count: 40)
        }
        
        // Now write 40 more, which must wrap around index 64 -> 0
        let secondBatch: [Float] = (100..<140).map { Float($0) }
        secondBatch.withUnsafeBufferPointer { ptr in
            let written = ringBuffer.write(from: ptr.baseAddress!, count: 40)
            XCTAssertEqual(written, 40)
        }
        
        var secondRead = [Float](repeating: 0.0, count: 40)
        secondRead.withUnsafeMutableBufferPointer { ptr in
            ringBuffer.read(into: ptr.baseAddress!, count: 40)
        }
        
        for i in 0..<40 {
            XCTAssertEqual(secondRead[i], secondBatch[i])
        }
    }
    
    func testAudioRingBufferOverflowProtection() {
        let ringBuffer = AudioRingBuffer(capacity: 64)
        let fillBatch = [Float](repeating: 1.0, count: 64)
        fillBatch.withUnsafeBufferPointer { ptr in
            let written = ringBuffer.write(from: ptr.baseAddress!, count: 64)
            XCTAssertEqual(written, 64)
        }
        
        // Attempt to write beyond capacity
        let overflowBatch = [Float](repeating: 99.0, count: 10)
        let overflowWritten = overflowBatch.withUnsafeBufferPointer { ptr in
            ringBuffer.write(from: ptr.baseAddress!, count: 10)
        }
        XCTAssertEqual(overflowWritten, 0, "Writing to a full ring buffer should safely return 0 without corrupting buffer.")
        
        // Verify original content is intact
        var readBuf = [Float](repeating: 0.0, count: 64)
        readBuf.withUnsafeMutableBufferPointer { ptr in
            ringBuffer.read(into: ptr.baseAddress!, count: 64)
        }
        for sample in readBuf {
            XCTAssertEqual(sample, 1.0)
        }
    }
    
    func testAudioRingBufferDriftProtection() {
        let ringBuffer = AudioRingBuffer(capacity: 4096)
        let bigBatch = [Float](repeating: 0.5, count: 2500)
        bigBatch.withUnsafeBufferPointer { ptr in
            _ = ringBuffer.write(from: ptr.baseAddress!, count: 2500)
        }
        
        // Read with bufferSize 128 (maxLatency = 2048, targetLatency = 512)
        var readBuf = [Float](repeating: 0.0, count: 128)
        readBuf.withUnsafeMutableBufferPointer { ptr in
            ringBuffer.read(into: ptr.baseAddress!, count: 128, bufferSize: 128)
        }
        
        // After reading 128 from 2500 with drift adjustment, remaining should be targetLatency - 128
        let remaining = ringBuffer.availableToRead()
        XCTAssertLessThanOrEqual(remaining, 512, "Drift protection should bound available samples to target latency.")
    }
    
    func testAudioRingBufferConcurrentStress() {
        let ringBuffer = AudioRingBuffer(capacity: 4096)
        let totalSamples = 50_000
        let group = DispatchGroup()
        
        // Producer
        DispatchQueue.global(qos: .userInitiated).async(group: group) {
            var sampleVal: Float = 1.0
            var written = 0
            let temp = UnsafeMutablePointer<Float>.allocate(capacity: 128)
            defer { temp.deallocate() }
            
            while written < totalSamples {
                let chunkSize = min(128, totalSamples - written)
                for i in 0..<chunkSize {
                    temp[i] = sampleVal
                    sampleVal += 1.0
                }
                let n = ringBuffer.write(from: temp, count: chunkSize)
                written += n
                if n == 0 { usleep(100) }
            }
        }
        
        // Consumer
        DispatchQueue.global(qos: .userInitiated).async(group: group) {
            var readCount = 0
            let temp = UnsafeMutablePointer<Float>.allocate(capacity: 128)
            defer { temp.deallocate() }
            
            while readCount < totalSamples {
                let avail = ringBuffer.availableToRead()
                if avail > 0 {
                    let toRead = min(avail, 128)
                    ringBuffer.read(into: temp, count: toRead)
                    readCount += toRead
                } else {
                    usleep(100)
                }
            }
        }
        
        let result = group.wait(timeout: .now() + 5.0)
        XCTAssertEqual(result, .success, "Concurrent read/write stress test timed out or deadlocked.")
    }
    
    // MARK: - Output Channel Mapping Tests
    
    func testOutputChannelMapping() {
        // Stereo
        let stereoMap = CoreAudioHelper.createOutputChannelMap(totalChannels: 2, isMultiOutput: false)
        XCTAssertEqual(stereoMap, [0, 1])
        
        // Mono
        let monoMap = CoreAudioHelper.createOutputChannelMap(totalChannels: 1, isMultiOutput: false)
        XCTAssertEqual(monoMap, [0])
        
        // 4 Channels standard (e.g. Quad interface)
        let fourChanMap = CoreAudioHelper.createOutputChannelMap(totalChannels: 4, isMultiOutput: false)
        XCTAssertEqual(fourChanMap, [0, 1, -1, -1])
        
        // 4 Channels Multi-Output (mirroring stereo)
        let multiOutput4 = CoreAudioHelper.createOutputChannelMap(totalChannels: 4, isMultiOutput: true)
        XCTAssertEqual(multiOutput4, [0, 1, 0, 1])
        
        // 6 Channels Multi-Output
        let multiOutput6 = CoreAudioHelper.createOutputChannelMap(totalChannels: 6, isMultiOutput: true)
        XCTAssertEqual(multiOutput6, [0, 1, 0, 1, 0, 1])
    }
    
    // MARK: - Manager Lifecycle Tests
    
    func testAudioEngineManagerInitializationAndStop() {
        let manager = AudioEngineManager()
        XCTAssertFalse(manager.isRunning, "Engine should not be running immediately upon initialization.")
        XCTAssertFalse(manager.isBypassed, "Engine should not be bypassed upon initialization.")
        
        // Test idempotent stop
        manager.stopEngine()
        XCTAssertFalse(manager.isRunning)
        XCTAssertEqual(manager.statusMessage, "Engine stopped.")
    }
    
    func testBypassToggle() {
        let manager = AudioEngineManager()
        XCTAssertFalse(manager.isBypassed)
        manager.toggleBypass()
        XCTAssertTrue(manager.isBypassed)
    }
    
    func testMultiOutputDetection() {
        let multiOutput = AudioDevice(
            deviceID: 999,
            name: "OBS Recorder",
            uid: "~:AMS2_StackedOutput:0",
            inputChannels: 0,
            outputChannels: 2,
            sampleRate: 48000
        )
        let standardDevice = AudioDevice(
            deviceID: 998,
            name: "BlackHole 2ch",
            uid: "BlackHole2ch_UID",
            inputChannels: 2,
            outputChannels: 2,
            sampleRate: 48000
        )
        XCTAssertTrue(multiOutput.isMultiOutput)
        XCTAssertFalse(standardDevice.isMultiOutput)
    }
    
    func testCoreAudioDeviceFetching() throws {
        let devices = CoreAudioHelper.getAllDevices()
        try XCTSkipIf(devices.isEmpty, "No audio devices found in current environment.")
        for dev in devices {
            XCTAssertFalse(dev.name.isEmpty, "Device must have a non-empty name.")
            XCTAssertFalse(dev.uid.isEmpty, "Device must have a non-empty UID.")
        }
    }
    
    func testBufferSizeHelpers() throws {
        let devices = CoreAudioHelper.getAllDevices()
        guard let testDevice = devices.first(where: { $0.outputChannels > 0 }) else {
            throw XCTSkip("No output devices available for buffer size testing.")
        }
        let currentSize = CoreAudioHelper.getBufferSize(deviceID: testDevice.deviceID)
        XCTAssertGreaterThan(currentSize, 0, "Buffer size should be greater than 0.")
    }
    
    func testMultiOutputAggregateCreationAndDestruction() throws {
        let devices = CoreAudioHelper.getAllDevices()
        guard let multiOutput = devices.first(where: { $0.isMultiOutput }) else {
            throw XCTSkip("No Multi-Output device found on this system.")
        }
        
        let subUIDs = CoreAudioHelper.getSubDeviceUIDs(for: multiOutput.deviceID)
        XCTAssertFalse(subUIDs.isEmpty, "Multi-Output device must contain at least one subdevice.")
        
        guard let aggID = CoreAudioHelper.createMultiOutputAggregate(for: multiOutput.deviceID) else {
            XCTFail("Failed to create private aggregate device for Multi-Output device.")
            return
        }
        
        XCTAssertGreaterThan(aggID, 0)
        let totalChannels = CoreAudioHelper.getChannelCount(deviceID: aggID, isInput: false)
        XCTAssertGreaterThan(totalChannels, 0, "Aggregate device should expose output channels.")
        
        let destroyed = CoreAudioHelper.destroyAggregateDevice(aggID)
        XCTAssertTrue(destroyed, "Aggregate device must be successfully destroyed.")
    }
    
    func testSubDeviceExtractionWithDriftCompensation() throws {
        let devices = CoreAudioHelper.getAllDevices()
        guard let multiOutput = devices.first(where: { $0.isMultiOutput }) else {
            throw XCTSkip("No Multi-Output device found on this system.")
        }
        
        let subDevices = CoreAudioHelper.getSubDevices(for: multiOutput.deviceID)
        XCTAssertFalse(subDevices.isEmpty, "Multi-Output device must contain at least one subdevice.")
        
        for sub in subDevices {
            XCTAssertFalse(sub.uid.isEmpty, "SubDevice UID must not be empty.")
        }
        
        // In any valid multi-output aggregate, exactly one subdevice is the clock master (drift = 0)
        let hasClockMaster = subDevices.contains { $0.driftCompensation == 0 }
        XCTAssertTrue(hasClockMaster, "Multi-Output device must specify at least one subdevice with driftCompensation = 0 as clock master.")
    }
}
