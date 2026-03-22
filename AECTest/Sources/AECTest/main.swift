import AVFoundation
import ScreenCaptureKit
import CSpeexDSP
import Foundation

// ─────────────────────────────────────────────
// AEC Verification Tool
//
// Records 8 seconds of:
//   1. Mic input (raw)
//   2. System audio (reference)
//   3. AEC output (mic - echo)
//
// Usage: swift run AECTest
// Output: /tmp/aec-mic.wav, /tmp/aec-ref.wav, /tmp/aec-out.wav
// ─────────────────────────────────────────────

let sampleRate: Int = 16000
let frameSize: Int = 160  // 10ms at 16kHz
let filterLength: Int = sampleRate / 2  // 500ms tail (8000 samples)
let duration: TimeInterval = 8

// MARK: - Ring Buffer

class RingBuffer {
    private var buffer: [Int16]
    private var writePos = 0
    private var readPos = 0
    private var count = 0
    private let capacity: Int
    private let lock = NSLock()

    init(capacity: Int) {
        self.capacity = capacity
        self.buffer = [Int16](repeating: 0, count: capacity)
    }

    func write(_ samples: [Int16]) {
        lock.lock()
        defer { lock.unlock() }
        for s in samples {
            buffer[writePos % capacity] = s
            writePos += 1
        }
        count += samples.count
    }

    func read(_ count: Int) -> [Int16]? {
        lock.lock()
        defer { lock.unlock() }
        guard self.count >= count else { return nil }
        var out = [Int16](repeating: 0, count: count)
        for i in 0..<count {
            out[i] = buffer[(readPos + i) % capacity]
        }
        readPos += count
        self.count -= count
        return out
    }

    var available: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}

// MARK: - WAV Writer

func writeWAV(samples: [Int16], sampleRate: Int, to path: String) throws {
    var data = Data()
    let dataSize = UInt32(samples.count * 2)
    let fileSize = 36 + dataSize
    let sr = UInt32(sampleRate)

    data.append(contentsOf: "RIFF".utf8)
    data.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian) { Array($0) })
    data.append(contentsOf: "WAVE".utf8)
    data.append(contentsOf: "fmt ".utf8)
    data.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })
    data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })
    data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })
    data.append(contentsOf: withUnsafeBytes(of: sr.littleEndian) { Array($0) })
    data.append(contentsOf: withUnsafeBytes(of: (sr * 2).littleEndian) { Array($0) })
    data.append(contentsOf: withUnsafeBytes(of: UInt16(2).littleEndian) { Array($0) })
    data.append(contentsOf: withUnsafeBytes(of: UInt16(16).littleEndian) { Array($0) })
    data.append(contentsOf: "data".utf8)
    data.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })

    samples.withUnsafeBufferPointer { ptr in
        data.append(UnsafeBufferPointer(start: UnsafeRawPointer(ptr.baseAddress!)
            .assumingMemoryBound(to: UInt8.self), count: samples.count * 2))
    }
    try data.write(to: URL(fileURLWithPath: path))
}

// MARK: - Resample helper

func resampleToInt16(buffer: AVAudioPCMBuffer, targetRate: Double) -> [Int16] {
    let srcRate = buffer.format.sampleRate
    let srcFrames = Int(buffer.frameLength)
    guard srcFrames > 0 else { return [] }

    // Get float samples from channel 0
    guard let floatData = buffer.floatChannelData else { return [] }
    let srcPtr = floatData[0]

    let ratio = targetRate / srcRate
    let dstFrames = Int(Double(srcFrames) * ratio)
    var result = [Int16](repeating: 0, count: dstFrames)

    for i in 0..<dstFrames {
        let srcIdx = Double(i) / ratio
        let idx = Int(srcIdx)
        let frac = Float(srcIdx - Double(idx))
        let s0 = srcPtr[min(idx, srcFrames - 1)]
        let s1 = srcPtr[min(idx + 1, srcFrames - 1)]
        let sample = s0 + (s1 - s0) * frac
        let clamped = max(-1.0, min(1.0, sample))
        result[i] = Int16(clamped * 32767)
    }
    return result
}

// MARK: - System Audio Capture (ScreenCaptureKit)

class SystemAudioCapture: NSObject, SCStreamOutput {
    let ringBuffer: RingBuffer
    private var stream: SCStream?
    private let targetRate: Double

    init(ringBuffer: RingBuffer, targetRate: Double) {
        self.ringBuffer = ringBuffer
        self.targetRate = targetRate
    }

    func start() async throws {
        let content = try await SCShareableContent.current
        guard let display = content.displays.first else {
            throw NSError(domain: "AEC", code: 1, userInfo: [NSLocalizedDescriptionKey: "No display found"])
        }

        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = false
        config.sampleRate = 48000
        config.channelCount = 1

        // Don't capture video - minimize overhead
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1) // 1 fps

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: .global())
        try await stream.startCapture()
        self.stream = stream
        print("[Ref] System audio capture started")
    }

    func stop() async {
        try? await stream?.stopCapture()
        stream = nil
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        guard let pcm = sampleBuffer.toPCMBuffer() else { return }
        let samples = resampleToInt16(buffer: pcm, targetRate: targetRate)
        if !samples.isEmpty {
            ringBuffer.write(samples)
        }
    }
}

// MARK: - Mic Capture

class MicCapture: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    let ringBuffer: RingBuffer
    private var session: AVCaptureSession?
    private let targetRate: Double
    private let queue = DispatchQueue(label: "mic-capture")

    init(ringBuffer: RingBuffer, targetRate: Double) {
        self.ringBuffer = ringBuffer
        self.targetRate = targetRate
    }

    func start() throws {
        let session = AVCaptureSession()
        guard let device = AVCaptureDevice.default(for: .audio) else {
            throw NSError(domain: "AEC", code: 2, userInfo: [NSLocalizedDescriptionKey: "No mic"])
        }
        let input = try AVCaptureDeviceInput(device: device)
        session.addInput(input)
        let output = AVCaptureAudioDataOutput()
        output.setSampleBufferDelegate(self, queue: queue)
        session.addOutput(output)
        session.startRunning()
        self.session = session
        print("[Mic] Capture started: \(device.localizedName)")
    }

    func stop() {
        session?.stopRunning()
        session = nil
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pcm = sampleBuffer.toPCMBuffer() else { return }
        let samples = resampleToInt16(buffer: pcm, targetRate: targetRate)
        if !samples.isEmpty {
            ringBuffer.write(samples)
        }
    }
}

// MARK: - CMSampleBuffer → AVAudioPCMBuffer

extension CMSampleBuffer {
    func toPCMBuffer() -> AVAudioPCMBuffer? {
        guard let formatDesc = CMSampleBufferGetFormatDescription(self),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)
        else { return nil }
        guard let avFormat = AVAudioFormat(streamDescription: asbd) else { return nil }
        let frameCount = CMSampleBufferGetNumSamples(self)
        guard frameCount > 0,
              let pcm = AVAudioPCMBuffer(pcmFormat: avFormat, frameCapacity: AVAudioFrameCount(frameCount))
        else { return nil }
        pcm.frameLength = AVAudioFrameCount(frameCount)
        guard let block = CMSampleBufferGetDataBuffer(self) else { return nil }
        let length = CMBlockBufferGetDataLength(block)

        if let floatData = pcm.floatChannelData {
            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: floatData[0])
        } else if let int16Data = pcm.int16ChannelData {
            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: int16Data[0])
        }
        return pcm
    }
}

// MARK: - Main

print("=== AEC Verification Tool ===")
print("Play music from speakers, then speak into the mic.")
print("Recording \(Int(duration)) seconds...\n")

let micRing = RingBuffer(capacity: sampleRate * 20)
let refRing = RingBuffer(capacity: sampleRate * 20)

let micCapture = MicCapture(ringBuffer: micRing, targetRate: Double(sampleRate))
let sysCapture = SystemAudioCapture(ringBuffer: refRing, targetRate: Double(sampleRate))

// Start captures
try micCapture.start()
try await sysCapture.start()

// Wait for both to warm up
try await Task.sleep(for: .milliseconds(500))
print("[AEC] Recording started - speak now!\n")

// Let it record
try await Task.sleep(for: .seconds(duration))

// Stop captures
micCapture.stop()
await sysCapture.stop()

print("\n[AEC] Recording stopped. Processing...")
print("[Mic] buffer: \(micRing.available) samples")
print("[Ref] buffer: \(refRing.available) samples")

// Process with SpeexDSP
let echoState = speex_echo_state_init(Int32(frameSize), Int32(filterLength))
let ppState = speex_preprocess_state_init(Int32(frameSize), Int32(sampleRate))
var echoPtr: UnsafeMutableRawPointer? = UnsafeMutableRawPointer(echoState)
speex_preprocess_ctl(ppState, SPEEX_PREPROCESS_SET_ECHO_STATE, &echoPtr)

var micAll = [Int16]()
var refAll = [Int16]()
var outAll = [Int16]()
var framesProcessed = 0

while true {
    guard let micFrame = micRing.read(frameSize) else { break }
    micAll.append(contentsOf: micFrame)

    // Get reference frame, or silence if not available
    let refFrame: [Int16]
    if let ref = refRing.read(frameSize) {
        refFrame = ref
        refAll.append(contentsOf: ref)
    } else {
        refFrame = [Int16](repeating: 0, count: frameSize)
        refAll.append(contentsOf: refFrame)
    }

    var outFrame = [Int16](repeating: 0, count: frameSize)
    micFrame.withUnsafeBufferPointer { micPtr in
        refFrame.withUnsafeBufferPointer { refPtr in
            outFrame.withUnsafeMutableBufferPointer { outPtr in
                speex_echo_cancellation(echoState, micPtr.baseAddress, refPtr.baseAddress, outPtr.baseAddress)
            }
        }
    }
    speex_preprocess_run(ppState, &outFrame)
    outAll.append(contentsOf: outFrame)
    framesProcessed += 1
}

speex_echo_state_destroy(echoState)
speex_preprocess_state_destroy(ppState)

print("[AEC] Processed \(framesProcessed) frames (\(String(format: "%.1f", Double(framesProcessed * frameSize) / Double(sampleRate)))s)")

// Write WAV files
try writeWAV(samples: micAll, sampleRate: sampleRate, to: "/tmp/aec-mic.wav")
try writeWAV(samples: refAll, sampleRate: sampleRate, to: "/tmp/aec-ref.wav")
try writeWAV(samples: outAll, sampleRate: sampleRate, to: "/tmp/aec-out.wav")

print("\nDone! Compare:")
print("  /tmp/aec-mic.wav  - Raw mic (with echo)")
print("  /tmp/aec-ref.wav  - System audio (reference)")
print("  /tmp/aec-out.wav  - AEC output (echo removed)")
print("\nPlay with: afplay /tmp/aec-out.wav")
