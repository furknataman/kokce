import SwiftUI
import KokenKit

/// Arama sekmesi. iOS 26'da sistem, arama rolündeki sekmenin alanını alt
/// çubuğa yerleştirir (Müzik uygulamasındaki gibi); iOS 18'de alan üsttedir.
struct SearchView: View {

    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            content
                .kokenBackground()
                .navigationTitle("tab.search")
                .navigationDestination(for: Word.self) { WordDetailView(word: $0) }
        }
        .searchable(text: $model.searchText, prompt: Text("dictionary.search"))
    }

    @ViewBuilder
    private var content: some View {
        let words = model.searchResults
        if model.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            ContentUnavailableView("search.hint", systemImage: "magnifyingglass")
        } else if words.isEmpty {
            ContentUnavailableView.search(text: model.searchText)
        } else {
            List(words) { word in
                NavigationLink(value: word) { WordRow(word: word) }
                    .listRowBackground(Theme.parchment)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }
}
