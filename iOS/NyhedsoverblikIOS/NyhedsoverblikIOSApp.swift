import SwiftUI
import UserNotifications

// iOS/iPadOS-entry — deler ContentView, FeedStore og alle views med macOS-appen
@main
struct NyhedsoverblikIOSApp: App {
    @StateObject private var store = FeedStore()
    @Environment(\.scenePhase) private var scenePhase

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
        // Pause = læst (samme adfærd som macOS): app i baggrunden markerer
        // alle viste overskrifter som læst — browseren forbliver åben, så
        // artiklen man læser stadig er der når man vender tilbage
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                store.markAllSeen(closingBrowser: false)
            }
        }
    }
}
