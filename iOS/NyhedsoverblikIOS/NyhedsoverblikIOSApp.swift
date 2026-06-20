import SwiftUI
import UserNotifications

// iOS/iPadOS-entry — deler ContentView, FeedStore og alle views med macOS-appen
@main
struct NyhedsoverblikIOSApp: App {
    @StateObject private var store = FeedStore()

    var body: some Scene {
        WindowGroup {
            IOSRootView()
                .environmentObject(store)
                .tint(store.appTheme.accentColor)
                .preferredColorScheme(store.appTheme.colorScheme)
                .task {
                    _ = try? await UNUserNotificationCenter.current()
                        .requestAuthorization(options: [.alert, .sound, .badge])
                }
        }
    }
}
