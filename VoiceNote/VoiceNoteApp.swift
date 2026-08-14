import SwiftUI
import SwiftData
import UserNotifications

@main
struct VoiceNoteApp: App {
    init() {
        // 让「生成完成」的本地通知在 App 前台时也以横幅展示
        UNUserNotificationCenter.current().delegate = NotificationPresenter.shared
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(SampleData.container)
    }
}
