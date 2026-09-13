import SwiftUI
import KokenKit

/// Sözlük sekmesi: arama, köken dili çipleri ve madde listesi. Deep link
/// gezinme yığınını doğrudan `AppModel` üzerinden doldurur.
struct DictionaryView: View {

    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.dictionaryPath) {
            VStack(spacing: 0) {
                DictionaryFilterBar()
                content
            }
            .kokenBackground()
            .navigationTitle("tab.dictionary")
            .navigationDestination(for: Word.self) { WordDetailView(word: $0) }
        }
        // Arama alanı yığının çubuğuna aittir. İçerideki VStack'e takılınca
        // büyük yazı boylarında çubukta yer kalmıyor ve alan hiç çizilmiyordu.
        .searchable(text: $model.searchText, prompt: Text("dictionary.search"))
    }

    @ViewBuilder
    private var content: some View {
        let words = model.filteredWords
        if words.isEmpty {
            emptyState
        } else {
            List(words) { word in
                NavigationLink(value: word) { WordRow(word: word) }
                    .listRowBackground(Theme.parchment)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if !model.searchText.isEmpty {
            ContentUnavailableView.search(text: model.searchText)
        } else if model.showFavoritesOnly {
            ContentUnavailableView("dictionary.favorites.empty", systemImage: "star")
        } else {
            ContentUnavailableView("dictionary.empty", systemImage: "character.book.closed")
        }
    }
}

/// Liste satırı: kelime, küçük köken rozeti ve kısa anlam. Yazı tipi
/// büyüdüğünde rozet kelimenin altına iner, satır taşmaz.
private struct WordRow: View {

    @Environment(AppModel.self) private var model
    let word: Word

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    title
                    badge
                }
                VStack(alignment: .leading, spacing: 4) {
                    title
                    badge
                }
            }
            Text(word.shortMeaning)
                .font(.footnote)
                .foregroundStyle(Theme.inkSoft)
        }
        .padding(.vertical, 3)
    }

    private var title: some View {
        Text(word.word)
            .font(.kokenWord(.headline))
            .foregroundStyle(Theme.ink)
    }

    @ViewBuilder
    private var badge: some View {
        if let origin = model.originText(for: word) {
            Text(origin)
                .font(.caption2)
                .foregroundStyle(Theme.inkSoft)
                .lineLimit(1)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Theme.parchmentDeep, in: Capsule())
        }
    }
}
