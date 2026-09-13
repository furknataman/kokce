import SwiftUI
import KokenKit

/// Sözlük sekmesi. Faz 4'te filtre çipleri, favoriler ve tam detay görünümü
/// eklenecek; şimdilik arama ve liste.
struct DictionaryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            List(model.filteredWords) { word in
                Button {
                    model.selectedWordID = word.id
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(word.word)
                            .font(.kokenWord(.headline))
                            .foregroundStyle(Theme.ink)
                        Text(word.shortMeaning)
                            .font(.footnote)
                            .foregroundStyle(Theme.inkSoft)
                    }
                }
                .listRowBackground(Theme.parchment)
            }
            .listStyle(.plain)
            .kokenBackground()
            .scrollContentBackground(.hidden)
            .searchable(text: $model.searchText, prompt: Text("dictionary.search"))
            .navigationTitle("tab.dictionary")
            .navigationDestination(item: $model.selectedWord) { word in
                WordDetailView(word: word)
            }
        }
    }
}

/// Faz 4'te zaman çizelgesi, ilk tanıklık, akrabalar ve kaynaklarla dolacak.
struct WordDetailView: View {
    let word: Word

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(word.word)
                    .font(.kokenWord())
                    .foregroundStyle(Theme.ink)
                Text(word.currentMeaning)
                    .foregroundStyle(Theme.inkSoft)
            }
            .kokenCard()
            .padding(20)
        }
        .kokenBackground()
        .navigationBarTitleDisplayMode(.inline)
    }
}
