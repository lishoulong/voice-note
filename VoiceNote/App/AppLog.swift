import Foundation

/// 轻量文件日志:写入 Documents/voicenote.log。
/// 作用:真机不连 Xcode 也能留痕,事后可用 devicectl 从沙盒拉回分析,
/// 也可在 iPhone「文件」App 里直接查看(已开 UIFileSharingEnabled)。
enum AppLog {
    static let url = FileManager.default
        .urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("voicenote.log")

    private static let queue = DispatchQueue(label: "voicenote.applog")
    private static let maxBytes = 2_000_000   // 超 2MB 截断重来,防无限膨胀

    static func log(_ message: String) {
        let ts = ISO8601DateFormatter().string(from: .now)
        let line = "\(ts) \(message)\n"
        NSLog("[VN] %@", message)   // 连着 Xcode 时 console 同步可见
        queue.async {
            let fm = FileManager.default
            if let size = try? fm.attributesOfItem(atPath: url.path)[.size] as? Int,
               size > maxBytes {
                try? fm.removeItem(at: url)
            }
            if let h = try? FileHandle(forWritingTo: url) {
                defer { try? h.close() }
                _ = try? h.seekToEnd()
                try? h.write(contentsOf: Data(line.utf8))
            } else {
                try? Data(line.utf8).write(to: url)
            }
        }
    }
}
