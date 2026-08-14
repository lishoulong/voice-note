import Foundation
import Speech
import AVFoundation
import SwiftUI

/// 本机实时听写引擎:SFSpeechRecognizer(zh-CN)+ AVAudioEngine。
/// 无权限 / 模拟器不可用时进入降级态(status),UI 退化为可直接打字。
@MainActor
@Observable
final class SpeechDictation {
    enum Status: Equatable { case idle, listening, denied, unavailable }

    var status: Status = .idle
    var transcript: String = ""
    var seconds: Int = 0
    var levels: [CGFloat] = Array(repeating: 0.06, count: 28)

    let maxSeconds = 60
    var isListening: Bool { status == .listening }

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var timer: Timer?
    private var running = false

    func start() async {
        guard !running else { return }
        guard await requestSpeech(), await requestMic() else { status = .denied; return }
        guard let recognizer, recognizer.isAvailable else { status = .unavailable; return }
        do {
            try beginAudio(recognizer)
            running = true
            status = .listening
            startTimer()
        } catch {
            status = .unavailable
        }
    }

    func stop() {
        running = false
        timer?.invalidate(); timer = nil
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if status == .listening { status = .idle }
    }

    // MARK: - internals

    private func beginAudio(_ recognizer: SFSpeechRecognizer) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request = req

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
            let level = SpeechDictation.rms(buffer)
            Task { @MainActor [weak self] in self?.pushLevel(level) }
        }
        engine.prepare()
        try engine.start()

        task = recognizer.recognitionTask(with: req) { [weak self] result, _ in
            guard let result else { return }
            let text = result.bestTranscription.formattedString
            Task { @MainActor [weak self] in self?.transcript = text }
        }
    }

    private func pushLevel(_ raw: Float) {
        let v = CGFloat(min(1, max(0.06, raw * 12)))
        levels.removeFirst()
        levels.append(v)
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.running else { return }
                self.seconds += 1
                if self.seconds >= self.maxSeconds { self.stop() }
            }
        }
    }

    private func requestSpeech() async -> Bool {
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0 == .authorized) }
        }
    }

    private func requestMic() async -> Bool {
        await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { cont.resume(returning: $0) }
        }
    }

    nonisolated static func rms(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let ch = buffer.floatChannelData?[0] else { return 0 }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<n {
            let s = ch[i]
            sum += s * s
        }
        return (sum / Float(n)).squareRoot()
    }
}
