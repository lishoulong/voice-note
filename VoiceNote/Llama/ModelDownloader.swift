import Foundation
import SwiftUI

/// 下载 Qwen3-1.7B GGUF 到 Application Support/Models/。
/// 带 NSLog 诊断,方便在 Xcode console 定位下载卡点。
@MainActor
@Observable
final class ModelDownloader: NSObject {
    static let shared = ModelDownloader()

    enum Status: Equatable { case idle, downloading, done, failed(String) }

    var status: Status
    var progress: Double = 0
    var receivedMB: Double = 0
    var totalMB: Double = 0

    @ObservationIgnored private var task: URLSessionDownloadTask?

    // Qwen3-1.7B Q4_K_M(约 1.1GB)
    static let remoteURL = URL(string: "https://huggingface.co/unsloth/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q4_K_M.gguf")!

    private override init() {
        status = LlamaDiaryEngine.isModelDownloaded ? .done : .idle
        super.init()
    }

    @ObservationIgnored private lazy var session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.allowsCellularAccess = true            // 放宽:允许任意网络,避免 Wi-Fi 判定导致静默等待
        cfg.timeoutIntervalForRequest = 60
        cfg.timeoutIntervalForResource = 3600
        return URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
    }()

    func start() {
        if LlamaDiaryEngine.isModelDownloaded { status = .done; return }
        guard status != .downloading else { return }
        status = .downloading
        progress = 0; receivedMB = 0; totalMB = 0
        NSLog("[Downloader] start -> %@", Self.remoteURL.absoluteString)
        let t = session.downloadTask(with: Self.remoteURL)
        task = t
        t.resume()
        NSLog("[Downloader] resumed, task.state=%ld", t.state.rawValue)
    }

    func cancel() {
        task?.cancel()
        task = nil
        if status == .downloading { status = .idle }
    }

    func deleteModel() {
        try? FileManager.default.removeItem(at: LlamaDiaryEngine.modelURL)
        status = .idle
        progress = 0
        receivedMB = 0
        totalMB = 0
    }
}

extension ModelDownloader: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, taskIsWaitingForConnectivity task: URLSessionTask) {
        NSLog("[Downloader] waiting for connectivity…")
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didWriteData bytesWritten: Int64,
                                totalBytesWritten: Int64,
                                totalBytesExpectedToWrite: Int64) {
        let recv = Double(totalBytesWritten) / 1_048_576
        let total = totalBytesExpectedToWrite > 0 ? Double(totalBytesExpectedToWrite) / 1_048_576 : 0
        let p = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0
        if totalBytesWritten < 2_000_000 {   // 只在开头打几条,避免刷屏
            NSLog("[Downloader] progress %.1f / %.1f MB", recv, total)
        }
        Task { @MainActor in
            self.receivedMB = recv
            self.totalMB = total
            self.progress = p
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didFinishDownloadingTo location: URL) {
        NSLog("[Downloader] finished, moving file to Models/")
        let dest = LlamaDiaryEngine.modelURL
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.moveItem(at: location, to: dest)
            var d = dest
            var vals = URLResourceValues()
            vals.isExcludedFromBackup = true
            try? d.setResourceValues(vals)
            NSLog("[Downloader] done, model in place")
            Task { @MainActor in self.status = .done; self.progress = 1 }
        } catch {
            let msg = error.localizedDescription
            NSLog("[Downloader] move failed: %@", msg)
            Task { @MainActor in self.status = .failed(msg) }
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask,
                                didCompleteWithError error: Error?) {
        if let error {
            NSLog("[Downloader] completed with error: %@", error.localizedDescription)
            let msg = error.localizedDescription
            Task { @MainActor in
                if case .downloading = self.status { self.status = .failed(msg) }
            }
        } else {
            NSLog("[Downloader] task completed without error")
        }
    }
}
