import AppKit
import AVFoundation
import Foundation

class AudioStreamer {
    private var audioEngine: AVAudioEngine
    private var isStreaming = false
    private var isPrepared = false
    private var resetWorkItem: DispatchWorkItem?
    var onAudioData: ((Data) -> Void)?

    init() {
        audioEngine = AVAudioEngine()
        observeAudioConfigChanges()
    }

    /// Pre-allocate audio resources so start() is fast.
    /// Call once during app setup (after microphone permission is granted).
    func prepare() {
        guard !isPrepared else { return }
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        Log.info("Audio input format: \(inputFormat)")

        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        )!

        let converter = AVAudioConverter(from: inputFormat, to: targetFormat)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self, self.isStreaming, let converter = converter else { return }

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

        audioEngine.prepare()
        isPrepared = true
        Log.info("Audio engine prepared")
    }

    func start() throws {
        guard !isStreaming else { return }
        if !isPrepared { prepare() }
        try audioEngine.start()
        isStreaming = true
    }

    func stop() {
        guard isStreaming else { return }
        isStreaming = false
        audioEngine.pause()
    }

    /// Reset the audio engine after config changes (device switch, sleep/wake).
    /// Next call to start() will re-prepare with the new device config.
    private func resetEngine() {
        let wasStreaming = isStreaming
        if isStreaming {
            isStreaming = false
        }
        // Remove old observers before creating a new engine
        NotificationCenter.default.removeObserver(self, name: .AVAudioEngineConfigurationChange, object: audioEngine)
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        isPrepared = false
        audioEngine = AVAudioEngine()
        // Re-observe on the new engine instance only
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleConfigChange),
            name: .AVAudioEngineConfigurationChange,
            object: audioEngine
        )
        Log.info("Audio engine reset (wasStreaming=\(wasStreaming))")
    }

    private func observeAudioConfigChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleConfigChange),
            name: .AVAudioEngineConfigurationChange,
            object: audioEngine
        )
        // Also reset after system wake — AVAudioEngine often goes stale
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc private func handleConfigChange(_ notification: Notification) {
        Log.info("Audio config changed — resetting engine")
        resetEngine()
    }

    @objc private func handleWake(_ notification: Notification) {
        // Debounce: multiple wake notifications can fire in rapid succession
        resetWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Log.info("System wake — resetting audio engine")
            self?.resetEngine()
        }
        resetWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
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

    deinit {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}
