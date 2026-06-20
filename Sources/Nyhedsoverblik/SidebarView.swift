import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var store: FeedStore
    #if os(macOS)
    @EnvironmentObject var floatingPanel: FloatingPanelController
    @Environment(\.openWindow) private var openWindow
    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "v\(v) (\(b))"
    }
    #endif
    @State private var showSettings = false
    @State private var hoveredSourceID: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            List {
                Section("Kilder") {
                    sourceRow(id: "__all__", name: "Alle nyheder",
                              icon: "newspaper", color: .accentColor,
                              count: store.unseenCount())

                    ForEach(store.sources) { src in
                        sourceRow(id: src.id, name: src.name,
                                  icon: nil, color: src.color,
                                  count: store.unseenCount(for: src.id),
                                  disabled: store.disabledSourceIDs.contains(src.id))
                        .contextMenu {
                            Button(store.disabledSourceIDs.contains(src.id)
                                   ? "Aktiver kilde" : "Deaktiver kilde") {
                                store.toggleSource(src.id)
                            }
                        }
                    }
                }

                // Gem + genberegning sker automatisk via FeedStore-pipelines
                Section("Filtre") {
                    Toggle("Skjul sport", isOn: $store.filterSport)
                    Toggle("Skjul clickbait", isOn: $store.filterClickbait)
                    Toggle("Skjul læste", isOn: $store.hideSeen)
                }
                .toggleStyle(.switch)
            }
            .listStyle(.sidebar)

            Divider()

            // Bundlinje — altid synlig, kollapser aldrig
            HStack(spacing: 2) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .frame(width: 28, height: 28)
                }
                .help("Indstillinger")

                #if os(macOS)
                Button {
                    floatingPanel.toggle(store: store)
                } label: {
                    Image(systemName: floatingPanel.isVisible ? "pip.exit" : "pip.enter")
                        .frame(width: 28, height: 28)
                }
                .help(floatingPanel.isVisible ? "Skjul flydende panel (⇧⌘F)" : "Vis flydende panel (⇧⌘F)")

                Button {
                    openWindow(id: "mini-widget")
                } label: {
                    Image(systemName: "rectangle.stack")
                        .frame(width: 28, height: 28)
                }
                .help("Åbn mini-widget")
                #endif

                Spacer()

                #if os(macOS)
                Text(appVersion)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .padding(.trailing, 6)
                #endif
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.platformWindowBackground)
        }
        .navigationTitle("Nyhedsoverblik")
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(store)
        }
    }

    // MARK: – Kilde-række med hover-toggle

    private func sourceRow(id: String, name: String, icon: String?,
                           color: Color, count: Int, disabled: Bool = false) -> some View {
        let selected = store.selectedSourceID == id
        let isHovered = hoveredSourceID == id
        let canToggle = id != "__all__"

        return Button {
            store.selectedSourceID = id
        } label: {
            HStack(spacing: 8) {
                // Ikon / farvedot
                if let icon {
                    Image(systemName: icon)
                        .frame(width: 14)
                        .foregroundStyle(disabled ? .tertiary : .secondary)
                } else {
                    Circle()
                        .fill(disabled ? Color.secondary.opacity(0.3) : color)
                        .frame(width: 8, height: 8)
                        .padding(.leading, 3)
                }

                Text(name)
                    .foregroundStyle(disabled ? .tertiary : .primary)
                    .lineLimit(1)

                Spacer()

                // Højre side: vis øje-toggle ved hover, ellers badge/skjult-ikon
                if canToggle && isHovered {
                    // Øje-knap vises ved hover — toggle kilden
                    Button {
                        store.toggleSource(id)
                    } label: {
                        Image(systemName: disabled ? "eye" : "eye.slash")
                            .font(.caption)
                            .foregroundStyle(disabled ? .secondary : .tertiary)
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(disabled ? "Aktiver kilde" : "Skjul kilde")
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                } else if disabled {
                    Image(systemName: "eye.slash")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else if let err = store.sourceErrors[id] {
                    // Kilden kunne ikke hentes — vis advarsel med fejlen som tooltip
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .help(err)
                } else {
                    badge(count, color: color)
                }
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 4)
            .background(selected ? color.opacity(0.12) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6))
            .animation(.easeOut(duration: 0.12), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { hoveredSourceID = $0 ? id : nil }
    }

    @ViewBuilder
    private func badge(_ count: Int, color: Color) -> some View {
        if count > 0 {
            Text("\(count)")
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(color, in: Capsule())
        }
    }
}
