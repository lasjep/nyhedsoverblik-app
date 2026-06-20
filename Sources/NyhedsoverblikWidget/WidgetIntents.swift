import AppIntents
import WidgetKit

private var cmdURL: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("nyhedsoverblik/widget_cmd.json")
}

private func writeCmd(_ action: String) {
    if let data = try? JSONEncoder().encode(["cmd": action]) {
        try? data.write(to: cmdURL, options: .atomic)
    }
}

struct MarkAllReadIntent: AppIntent {
    static var title: LocalizedStringResource = "Marker alle læst"
    static var description = IntentDescription("Markerer alle synlige nyheder som læst.")

    func perform() async throws -> some IntentResult {
        writeCmd("markAllRead")
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct IncreaseFontIntent: AppIntent {
    static var title: LocalizedStringResource = "Større tekst"

    func perform() async throws -> some IntentResult {
        writeCmd("increaseFont")
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct DecreaseFontIntent: AppIntent {
    static var title: LocalizedStringResource = "Mindre tekst"

    func perform() async throws -> some IntentResult {
        writeCmd("decreaseFont")
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
