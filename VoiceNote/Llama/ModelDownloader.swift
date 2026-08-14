import Foundation
import SwiftUI

/// 下载 Qwen3-1.7B GGUF 到 Application Support/Models/。
/// MVP:default session + 进度 + 排除 iCloud 备份 + 默认 Wi-Fi。
/// TODO:换 background session(app 挂起继续)+ resume data 断点续传。
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
        cfg.allowsCellularAccess = false      // 默认仅 Wi-Fi
        cfg.waitsForConnectivity = true
        return URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
    }()

    func start() {
        if LlamaDiaryEngine.isModelDownloaded { status = .done; return }
        guard status != .downloading else { return }
        status = .downloading
        progress = 0
        let t = session.downloadTask(with: Self.remoteURL)
        task = t
        t.resume()
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
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didWriteData bytesWritten: Int64,
                                totalBytesWritten: Int64,
                                totalBytesExpectedToWrite: Int64) {
        let p = totalBytesExpectedToWrite > 0
            ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0
        let recv = Double(totalBytesWritten) / 1_048_576
        let total = Double(totalBytesExpectedToWrite) / 1_048_576
        Task { @MainActor in
            self.progress = p
            self.receivedMB = recv
            self.totalMB = total
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didFinishDownloadingTo location: URL) {
        // 必须在回调内同步移动:location 临时文件回调返回后即被清理
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
            Task { @MainActor in self.status = .done; self.progress = 1 }
        } catch {
            let msg = error.localizedDescription
            Task { @MainActor in self.status = .failed(msg) }
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask,
                                didCompleteWithError error: Error?) {
        guard let error else { return }
        let msg = error.localizedDescription
        Task { @MainActor in
            if case .downloading = self.status { self.status = .failed(msg) }
        }
    }
}
