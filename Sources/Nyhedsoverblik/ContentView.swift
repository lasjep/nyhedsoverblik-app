import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: FeedStore

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)
        } content: {
            ArticleGridView()
                .navigationSplitViewColumnWidth(min: 300, ideal: 460)
        } detail: {
            BrowserPanel(model: store.webViewModel)
        }
        // Auto-luk browser når artikkellisten tømmes (alle læst + skjul læste slået til)
        .onChange(of: store.visibleArticles.isEmpty) { _, isEmpty in
            if isEmpty && store.selectedArticle != nil {
                withAnimation { store.closeBrowser() }
            }
        }
    }
}
