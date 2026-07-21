import SwiftUI

// Splash under første hentning: bygger sig op med staggered animation og
// viser live fremdrift per kilde. Vises KUN mens der reelt hentes — den
// tilføjer ingen kunstig ventetid.
struct SplashView: View {
    @EnvironmentObject var store: FeedStore
    @State private var appeared = false

    private var progress: Double {
        store.refreshTotal == 0 ? 0
            : Double(store.fetchedSourceIDs.count) / Double(store.refreshTotal)
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "newspaper.fill")
                .font(.system(size: 54))
                .foregroundStyle(Color.accentColor)
                .symbolEffect(.pulse, isActive: progress < 1)
                .scaleEffect(appeared ? 1 : 0.5)
                .opacity(appeared ? 1 : 0)

            Text("Nyhedsoverblik")
                .font(.system(size: 32, weight: .bold, design: .serif))
                .padding(.top, 18)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 14)
                .animation(.spring(response: 0.55, dampingFraction: 0.8).delay(0.12), value: appeared)

            // Kilderne lyser op efterhånden som de er hentet
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 116), spacing: 6)], spacing: 7) {
                ForEach(Array(store.activeSources.enumerated()), id: \.element.id) { idx, src in
                    let done = store.fetchedSourceIDs.contains(src.id)
                    HStack(spacing: 5) {
                        Circle()
                            .fill(src.color)
                            .frame(width: 7, height: 7)
                            .opacity(done ? 1 : 0.25)
                        Text(src.name)
                            .font(.caption)
                            .lineLimit(1)
                            .foregroundStyle(done ? .primary : .tertiary)
                        Spacer(minLength: 0)
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.secondary)
                            .opacity(done ? 1 : 0)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.platformControlBackground.opacity(done ? 1 : 0.45),
                                in: Capsule())
                    .animation(.easeOut(duration: 0.25), value: done)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 10)
                    // Staggered indflyvning — kilderne "bygger sig op" én efter én
                    .animation(.spring(response: 0.5, dampingFraction: 0.8)
                        .delay(0.2 + Double(idx) * 0.035), value: appeared)
                }
            }
            .frame(maxWidth: 540)
            .padding(.top, 34)
            .padding(.horizontal, 24)

            VStack(spacing: 7) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 300)
                    .animation(.easeOut(duration: 0.3), value: progress)
                Text("\(store.fetchedSourceIDs.count) af \(store.refreshTotal) kilder hentet")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            .padding(.top, 30)
            .opacity(appeared ? 1 : 0)
            .animation(.easeOut(duration: 0.4).delay(0.35), value: appeared)

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.platformWindowBackground)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.75)) { appeared = true }
        }
    }
}
