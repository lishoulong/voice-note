import SwiftUI
import SwiftData

@main
struct VoiceNoteApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(SampleData.container)
    }
}
