import AVFoundation
import AVFAudio
import CoreAudio
import Foundation

// MARK: - AudioDevice

struct AudioDevice: Equatable {
    let id: AudioDeviceID
    let name: String
    let hasInput: Bool

    static func allInputDevices() -> [AudioDevice] {
        var propAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propAddress, 0, nil, &dataSize) == noErr else { return [] }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propAddress, 0, nil, &dataSize, &deviceIDs) == noErr else { return [] }

        return deviceIDs.compactMap { deviceID -> AudioDevice? in
            // Check if device has input channels
            var inputAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            var inputSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(deviceID, &inputAddress, 0, nil, &inputSize) == noErr else { return nil }

            let bufferListPtr = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(inputSize))
            defer { bufferListPtr.deallocate() }
            guard AudioObjectGetPropertyData(deviceID, &inputAddress, 0, nil, &inputSize, bufferListPtr) == noErr else { return nil }

            let bufferList = UnsafeMutableAudioBufferListPointer(bufferListPtr)
            let inputChannels = bufferList.reduce(0) { $0 + Int($1.mNumberChannels) }
            guard inputChannels > 0 else { return nil }

            // Get device name
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceNameCFString,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var nameSize: UInt32 = UInt32(MemoryLayout<Unmanaged<CFString>>.size)
            var nameRef: Unmanaged<CFString>?
            guard AudioObjectGetPropertyData(deviceID, &nameAddress, 0, nil, &nameSize, &nameRef) == noErr,
                  let cfName = nameRef?.takeUnretainedValue() else { return nil }

            return AudioDevice(id: deviceID, name: cfName as String, hasInput: true)
        }
    }

    /// The system default input device
    static func defaultInput() -> AudioDevice? {
        var propAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propAddress, 0, nil, &size, &deviceID) == noErr else { return nil }

        let devices = allInputDevices()
        return devices.first { $0.id == deviceID }
    }
}

// MARK: - AudioRecorder

class AudioRecorder {
    private var engine = AVAudioEngine()
    private var buffers: [AVAudioPCMBuffer] = []
    private let sampleRate: Double = 16000
    private let channels: AVAudioChannelCount = 1
    private var targetFormat: AVAudioFormat?
    private var isRecording = false
    private var engineReady = false
    private var selectedDeviceID: AudioDeviceID?

    var onLevels: (([Float]) -> Void)?
    var onAudioBuffer: ((AVAudioPCMBuffer) -> Void)?
    private var levelHistory: [Float] = Array(repeating: 0, count: 24)

    /// Call once at app launch to request mic permission and pre-warm engine
    func prepare() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            warmUp()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                if granted {
                    DispatchQueue.main.async { self?.warmUp() }
                }
            }
        default:
            print("Microphone permission denied")
        }
    }

    func setInputDevice(_ deviceID: AudioDeviceID?) {
        selectedDeviceID = deviceID
        // Re-warm with new device
        if engineReady {
            engine.stop()
            engineReady = false
            warmUp()
        }
    }

    private func applyInputDevice() {
        guard let deviceID = selectedDeviceID else { return }
        let inputNode = engine.inputNode
        let audioUnit = inputNode.audioUnit!
        var devID = deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &devID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        if status != noErr {
            try? "applyInputDevice: failed to set device \(deviceID), status=\(status)\n".appendToFile("/tmp/voiceinput-debug.log")
        } else {
            try? "applyInputDevice: set device \(deviceID)\n".appendToFile("/tmp/voiceinput-debug.log")
        }
    }

    private func warmUp() {
        // Create a fresh engine to ensure we get the real microphone
        // (if engine was created before mic permission, inputNode is a dummy)
        engine.stop()
        engine = AVAudioEngine()

        // Set input device before accessing inputNode format
        applyInputDevice()

        targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: false
        )

        let inputFormat = engine.inputNode.outputFormat(forBus: 0)
        try? "warmUp: inputFormat=\(inputFormat)\n".appendToFile("/tmp/voiceinput-debug.log")

        do {
            try engine.start()
            engineReady = true
        } catch {
            print("AudioRecorder warmUp error: \(error)")
        }
    }

    func start() {
        buffers.removeAll()
        levelHistory = Array(repeating: 0, count: 24)
        isRecording = true

        // If engine not ready yet (e.g. permission just granted), warm up now
        if !engineReady {
            if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized {
                warmUp()
            } else {
                print("Microphone not authorized")
                return
            }
        }

        guard let targetFormat = targetFormat else { return }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        try? "start: inputFormat=\(inputFormat), sampleRate=\(inputFormat.sampleRate), channels=\(inputFormat.channelCount)\n".appendToFile("/tmp/voiceinput-debug.log")

        // Fresh converter each time (it has internal state)
        guard let freshConverter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            try? "start: failed to create converter\n".appendToFile("/tmp/voiceinput-debug.log")
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self, self.isRecording else { return }

            let level = self.rmsLevel(buffer: buffer)

            let frameCount = AVAudioFrameCount(
                Double(buffer.frameLength) * self.sampleRate / inputFormat.sampleRate
            )
            guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount) else { return }

            var error: NSError?
            freshConverter.convert(to: converted, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            if error == nil && converted.frameLength > 0 {
                self.buffers.append(converted)
                self.onAudioBuffer?(converted)
            }

            DispatchQueue.main.async {
                self.pushLevel(level)
                self.onLevels?(self.levelHistory)
            }
        }

        if !engine.isRunning {
            do { try engine.start() } catch { print("ERROR: \(error)") }
        }
    }

    func stop() -> Data? {
        isRecording = false
        engine.inputNode.removeTap(onBus: 0)
        guard !buffers.isEmpty else { return nil }
        return buildWAV()
    }

    private func rmsLevel(buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<count { sum += data[i] * data[i] }
        return min(1.0, sqrt(sum / Float(count)) * 4.0)
    }

    private func pushLevel(_ level: Float) {
        levelHistory.removeFirst()
        levelHistory.append(level)
    }

    private func buildWAV() -> Data {
        var samples: [Float] = []
        for buf in buffers {
            guard let channelData = buf.floatChannelData?[0] else { continue }
            let count = Int(buf.frameLength)
            samples.append(contentsOf: UnsafeBufferPointer(start: channelData, count: count))
        }

        let int16Samples = samples.map { sample -> Int16 in
            Int16(max(-1.0, min(1.0, sample)) * Float(Int16.max))
        }

        let dataSize = int16Samples.count * 2
        var data = Data()
        data.reserveCapacity(44 + dataSize)

        func u32(_ v: UInt32) { var v = v; data.append(Data(bytes: &v, count: 4)) }
        func u16(_ v: UInt16) { var v = v; data.append(Data(bytes: &v, count: 2)) }

        data.append(contentsOf: "RIFF".utf8); u32(UInt32(36 + dataSize))
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8); u32(16); u16(1); u16(UInt16(channels))
        u32(UInt32(sampleRate)); u32(UInt32(sampleRate) * UInt32(channels) * 2)
        u16(UInt16(channels) * 2); u16(16)
        data.append(contentsOf: "data".utf8); u32(UInt32(dataSize))

        int16Samples.withUnsafeBufferPointer { ptr in
            data.append(UnsafeBufferPointer(
                start: UnsafeRawPointer(ptr.baseAddress!).assumingMemoryBound(to: UInt8.self),
                count: dataSize
            ))
        }
        return data
    }
}
