#if os(macOS)
import SwiftUI
import UserNotifications

@main
struct NyhedsoverblikApp: App {
    @StateObject private var store = FeedStore()
    @StateObject private var floatingPanel = FloatingPanelController()

    var body: some Scene {
        WindowGroup("Nyhedsoverblik") {
            ContentView()
                .environmentObject(store)
                .environmentObject(floatingPanel)
                .frame(minWidth: 960, minHeight: 640)
                .tint(store.appTheme.accentColor)
                .preferredColorScheme(store.appTheme.colorScheme)
                .background(store.appTheme.backgroundColor ?? Color.clear)
                .task {
                    _ = try? await UNUserNotificationCenter.current()
                        .requestAuthorization(options: [.alert, .sound, .badge])
                }
                .onOpenURL { url in
                    guard url.scheme == "nyhedsoverblik" else { return }
                    switch url.host {
                    case "markallread":  store.markAllSeen()
                    case "increaseFont": store.listFontSize = min(20, store.listFontSize + 1)
                    case "decreaseFont": store.listFontSize = max(11, store.listFontSize - 1)
                    default: break
                    }
                }
        }
        Window("Mini widget", id: "mini-widget") {
            MiniWidgetPanel()
                .environmentObject(store)
                .tint(store.appTheme.accentColor)
                .preferredColorScheme(store.appTheme.colorScheme)
                .background(store.appTheme.backgroundColor ?? Color.clear)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 380, height: 520)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Nyheder") {
                Button("Opdater nu") {
                    Task { await store.refresh() }
                }
                .keyboardShortcut("r", modifiers: .command)

                Divider()

                Button("Marker alle som set") {
                    store.markAllSeen()
                }
                .disabled(store.unseenCount() == 0)

                Divider()

                Toggle("Skjul sport", isOn: $store.filterSport)
                Toggle("Skjul clickbait", isOn: $store.filterClickbait)

                Divider()

                Button(floatingPanel.isVisible ? "Skjul flydende panel" : "Vis flydende panel") {
                    floatingPanel.toggle(store: store)
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            }
        }
    }
}
#endif  // os(macOS)
