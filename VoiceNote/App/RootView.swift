import SwiftUI
import SwiftData

/// 根视图:按 Router.screen 整屏切换(还原设计稿"单设备状态机")。
struct RootView: View {
    @State private var router = Router()

    var body: some View {
        ZStack {
            switch router.screen {
            case .onboarding: OnboardingView()
            case .home:       HomeView()
            case .generating: GeneratingView()
            case .result:     ResultView()
            case .history:    HistoryView()
            case .catchup:    CatchupView()
            case .about:      AboutView()
            case .settings:   SettingsView()
            }
        }
        .environment(router)
    }
}

#Preview {
    RootView().modelContainer(SampleData.container)
}
