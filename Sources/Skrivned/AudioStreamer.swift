import AVFoundation
import Foundation

class AudioStreamer {
    private var audioEngine: AVAudioEngine?
    private var isStreaming = false
    var onAudioData: ((Data) -> Void)?

    func start() throws {
        guard !isStreaming else { return }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        )!

        let converter = AVAudioConverter(from: inputFormat, to: targetFormat)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self, let converter = converter else { return }

            let ratio = 16000.0 / inputFormat.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
            guard capacity > 0 else { return }

            guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

            var error: NSError?
            converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            if error == nil && convertedBuffer.frameLength > 0 {
                let pcmData = self.float32ToInt16(convertedBuffer)
                self.onAudioData?(pcmData)
            }
        }

        engine.prepare()
        try engine.start()

        audioEngine = engine
        isStreaming = true
    }

    func stop() {
        guard isStreaming else { return }
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        isStreaming = false
    }

    private func float32ToInt16(_ buffer: AVAudioPCMBuffer) -> Data {
        guard let floatData = buffer.floatChannelData else { return Data() }
        let frameCount = Int(buffer.frameLength)
        var int16Data = Data(count: frameCount * 2)

        int16Data.withUnsafeMutableBytes { rawBuffer in
            let int16Buffer = rawBuffer.bindMemory(to: Int16.self)
            for i in 0..<frameCount {
                let sample = max(-1.0, min(1.0, floatData[0][i]))
                int16Buffer[i] = Int16(sample * 32767)
            }
        }

        return int16Data
    }
}
