import Foundation

/// 本地模型档位:1.7B 快省(默认保底)/ 4B 高质量(A/B 实测分节、金句、人物显著更好)。
enum ModelTier: String, CaseIterable {
    case qwen1_7B = "qwen3-1.7b"
    case qwen4B   = "qwen3.5-4b"

    static let storageKey = "vn.modelTier"

    /// 当前选用档(默认 1.7B)
    static var active: ModelTier {
        get { ModelTier(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .qwen1_7B }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: storageKey) }
    }

    var displayName: String {
        switch self {
        case .qwen1_7B: "Qwen3 1.7B"
        case .qwen4B:   "Qwen3.5 4B"
        }
    }

    var fileName: String {
        switch self {
        case .qwen1_7B: "Qwen3-1.7B-Q4_K_M.gguf"
        case .qwen4B:   "Qwen3.5-4B-Q4_K_M.gguf"
        }
    }

    /// ModelScope 国内镜像(实测 ~3.7MB/s,远快于 HF)
    var downloadURL: URL {
        switch self {
        case .qwen1_7B: URL(string: "https://modelscope.cn/models/unsloth/Qwen3-1.7B-GGUF/resolve/master/Qwen3-1.7B-Q4_K_M.gguf")!
        case .qwen4B:   URL(string: "https://modelscope.cn/models/unsloth/Qwen3.5-4B-GGUF/resolve/master/Qwen3.5-4B-Q4_K_M.gguf")!
        }
    }

    var sizeLabel: String {
        switch self {
        case .qwen1_7B: "1.1 GB"
        case .qwen4B:   "2.6 GB"
        }
    }

    var detail: String {
        switch self {
        case .qwen1_7B: "快、省内存。分节较粗,适合日常保底。"
        case .qwen4B:   "分节、金句、人物明显更好;慢约一倍,内存偏紧,生成时尽量保持前台。"
        }
    }

    var sourceLabel: String {
        switch self {
        case .qwen1_7B: "本机 · Qwen3-1.7B"
        case .qwen4B:   "本机 · Qwen3.5-4B"
        }
    }

    var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Models/\(fileName)")
    }

    var isDownloaded: Bool { FileManager.default.fileExists(atPath: fileURL.path) }
}
