import SwiftUI

// Cross-platform systemfarver — gør at views deles mellem macOS og iOS/iPadOS
#if canImport(AppKit)
import AppKit

extension Color {
    static let platformWindowBackground  = Color(nsColor: .windowBackgroundColor)
    static let platformControlBackground = Color(nsColor: .controlBackgroundColor)
    static let platformSeparator         = Color(nsColor: .separatorColor)
    static let platformTextBackground    = Color(nsColor: .textBackgroundColor)
}
#else
import UIKit

extension Color {
    static let platformWindowBackground  = Color(uiColor: .systemBackground)
    static let platformControlBackground = Color(uiColor: .secondarySystemBackground)
    static let platformSeparator         = Color(uiColor: .separator)
    static let platformTextBackground    = Color(uiColor: .systemBackground)
}
#endif
