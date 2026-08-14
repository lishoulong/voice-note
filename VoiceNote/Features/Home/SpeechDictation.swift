import Foundation
import Speech
import AVFoundation
import SwiftUI

/// 本机实时听写引擎:SFSpeechRecognizer(zh-CN)+ AVAudioEngine。
/// - 停顿后 SFSpeech 会结束当前段(final),这里把已 final 段累积到 committedText,
///   当前段拼在后面并重启识别继续听 → 1 分钟内连续衔接,不再丢前文。
/// - 无权限 / 模拟器 / iOS App on Mac 时进降级态(status),UI 退化为可直接打字。
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

    private var committedText = ""   // 已 final 的段落累积
    private var gen = 0              // 识别段代号,防旧任务的迟到回调污染

    func start() async {
        guard !running else { return }
        // 非真机环境(模拟器 / iOS App on Mac)音频栈不可靠,直接降级为可打字
        #if targetEnvironment(simulator)
        status = .unavailable
        return
        #else
        if ProcessInfo.processInfo.isiOSAppOnMac { status = .unavailable; return }
        guard await requestSpeech(), await requestMic() else { status = .denied; return }
        guard let recognizer, recognizer.isAvailable else { status = .unavailable; return }
        committedText = ""
        transcript = ""
        seconds = 0
        do {
            try beginAudio()
            running = true
            status = .listening
            startRecognition()
            startTimer()
        } catch {
            status = .unavailable
        }
        #endif
    }

    func stop() {
        running = false
        gen &+= 1                 // 使所有在途回调失效
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

    // MARK: - 音频采集(整段录音期间只装一次 tap)

    private func beginAudio() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
            let level = SpeechDictation.rms(buffer)
            Task { @MainActor [weak self] in self?.pushLevel(level) }
        }
        engine.prepare()
        try engine.start()
    }

    // MARK: - 识别段(可重启,实现连续衔接)

    private func startRecognition() {
        guard running, let recognizer else { return }
        request?.endAudio()
        task?.cancel()
        gen &+= 1
        let myGen = gen

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if #available(iOS 16.0, *) { req.addsPunctuation = true }
        // 不强制 requiresOnDeviceRecognition:让系统选更准的识别(通常联网,人名/生僻词更好)
        request = req

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            let seg = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let hadError = error != nil
            Task { @MainActor in
                guard myGen == self.gen else { return }   // 忽略旧段的迟到回调
                if let seg { self.transcript = self.committedText + seg }
                if isFinal {
                    if let seg { self.committedText += seg }
                    self.startRecognition()               // 本段结束,累积并重启继续听
                } else if hadError {
                    if self.running { self.startRecognition() }
                }
            }
        }
    }

    // MARK: - 波形 / 计时

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

    // MARK: - 权限

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
