import Foundation
import SwiftUI

/// 按档位下载 GGUF 到 Application Support/Models/(源:ModelScope 国内镜像)。
/// 一次只下一个档;带 NSLog/AppLog 诊断。
@MainActor
@Observable
final class ModelDownloader: NSObject {
    static let shared = ModelDownloader()

    enum Status: Equatable { case idle, downloading, failed(String) }

    var status: Status = .idle
    /// 正在下载的档位(nil = 没有进行中的下载)
    var downloadingTier: ModelTier?
    var progress: Double = 0
    var receivedMB: Double = 0
    var totalMB: Double = 0

    @ObservationIgnored private var task: URLSessionDownloadTask?
    @ObservationIgnored private var targetTier: ModelTier?

    private override init() { super.init() }

    @ObservationIgnored private lazy var session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.allowsCellularAccess = true
        cfg.timeoutIntervalForRequest = 60
        cfg.timeoutIntervalForResource = 7200
        return URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
    }()

    func start(tier: ModelTier) {
        if tier.isDownloaded { return }
        guard downloadingTier == nil else { return }   // 一次只下一个
        downloadingTier = tier
        targetTier = tier
        status = .downloading
        progress = 0; receivedMB = 0; totalMB = 0
        AppLog.log("下载器: 开始下载 \(tier.displayName) <- \(tier.downloadURL.absoluteString)")
        let t = session.downloadTask(with: tier.downloadURL)
        task = t
        t.resume()
    }

    func cancel() {
        task?.cancel()
        task = nil
        downloadingTier = nil
        if status == .downloading { status = .idle }
    }

    func deleteModel(tier: ModelTier) {
        try? FileManager.default.removeItem(at: tier.fileURL)
        AppLog.log("下载器: 已删除 \(tier.displayName)")
    }
}

extension ModelDownloader: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, taskIsWaitingForConnectivity task: URLSessionTask) {
        AppLog.log("下载器: 等待网络连接…")
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didWriteData bytesWritten: Int64,
                                totalBytesWritten: Int64,
                                totalBytesExpectedToWrite: Int64) {
        let recv = Double(totalBytesWritten) / 1_048_576
        let total = totalBytesExpectedToWrite > 0 ? Double(totalBytesExpectedToWrite) / 1_048_576 : 0
        let p = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0
        Task { @MainActor in
            self.receivedMB = recv
            self.totalMB = total
            self.progress = p
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didFinishDownloadingTo location: URL) {
        // 必须在回调内同步移动:location 临时文件回调返回后即被清理
        let fm = FileManager.default
        // targetTier 是 MainActor 隔离的;这里用下载 URL 反查档位,避免跨隔离读取
        let url = downloadTask.originalRequest?.url
        let tier = ModelTier.allCases.first { $0.downloadURL == url } ?? .qwen1_7B
        let dest = tier.fileURL
        do {
            try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.moveItem(at: location, to: dest)
            var d = dest
            var vals = URLResourceValues()
            vals.isExcludedFromBackup = true
            try? d.setResourceValues(vals)
            AppLog.log("下载器: \(tier.displayName) 下载完成并就位")
            Task { @MainActor in
                self.status = .idle
                self.downloadingTier = nil
                self.progress = 1
            }
        } catch {
            let msg = error.localizedDescription
            AppLog.log("下载器: 移动文件失败 \(msg)")
            Task { @MainActor in
                self.status = .failed(msg)
                self.downloadingTier = nil
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask,
                                didCompleteWithError error: Error?) {
        guard let error else { return }
        let msg = error.localizedDescription
        AppLog.log("下载器: 失败 \(msg)")
        Task { @MainActor in
            if case .downloading = self.status {
                self.status = .failed(msg)
                self.downloadingTier = nil
            }
        }
    }
}
