import SwiftUI

enum AppScreen {
    case onboarding
    case home
    case generating
    case result
    case history
    case catchup
    case about
    case settings
}

/// 全局导航与流程状态。设计稿是"单设备整屏切换"的状态机,故用一个 Router 驱动根视图。
@Observable
final class Router {
    var screen: AppScreen
    /// 当前成稿(整理今日 / 查看历史 共用)
    var resultNote: DiaryNote?

    init() {
        // 便于骨架演示/截图:可用环境变量 VN_INITIAL_SCREEN 指定初始页(默认今天页)
        switch ProcessInfo.processInfo.environment["VN_INITIAL_SCREEN"] {
        case "onboarding": screen = .onboarding
        case "generating": screen = .generating
        case "result":     screen = .result
        case "history":    screen = .history
        case "catchup":    screen = .catchup
        case "about":      screen = .about
        case "settings":   screen = .settings
        default:           screen = .home
        }
    }

    func go(_ s: AppScreen) {
        withAnimation(.easeInOut(duration: 0.28)) { screen = s }
    }

    func showResult(_ note: DiaryNote) {
        resultNote = note
        withAnimation(.easeInOut(duration: 0.28)) { screen = .result }
    }
}
