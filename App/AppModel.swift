import Foundation
import Observation
import KokenKit

/// Arayüzün tek durum kaynağı. Depoyu sarar; dosya ve ağ işi actor'da kalır.
@MainActor
@Observable
final class AppModel {

    enum Tab: Hashable {
        case today, dictionary, settings
    }

    private let repository: WordRepository?
    private let favorites = FavoritesStore()

    private(set) var catalog: WordCatalog?
    private(set) var failedToLoad = false

    var selectedTab: Tab = .today
    var selectedWordID: String?
    var searchText = ""
    var originFilter: String?
    private(set) var favoriteIDs: Set<String> = []

    init(repository: WordRepository? = nil) {
        // Gömülü katalog her iki hedefin bundle'ındadır; yoksa uygulama
        // içeriksiz açılır ve kullanıcıya boş durum gösterilir.
        self.repository = repository ?? AppGroup.bundledCatalogURL().map { WordRepository(bundleURL: $0) }
    }

    var todayWord: Word? {
        guard let catalog else { return nil }
        return WordOfDay.word(for: .now, in: catalog)
    }

    /// Arama ve filtre uygulanmış sözlük listesi.
    var filteredWords: [Word] {
        guard let catalog else { return [] }
        return WordSearch.filter(catalog.words, query: searchText, originLanguage: originFilter)
    }

    /// Detay görünümüne bağlanan seçim.
    var selectedWord: Word? {
        get { selectedWordID.flatMap { catalog?.word(id: $0) } }
        set { selectedWordID = newValue?.id }
    }

    func load() async {
        guard let repository else {
            failedToLoad = true
            return
        }
        do {
            catalog = try await repository.catalog()
        } catch {
            failedToLoad = true
        }
        favoriteIDs = Set(favorites.ids)
        // Günde bir kez uzak dosyayı yoklar; hata sessizce yutulur.
        if await repository.refreshIfNeeded() {
            catalog = try? await repository.catalog()
        }
    }

    func isFavorite(_ word: Word) -> Bool {
        favoriteIDs.contains(word.id)
    }

    func toggleFavorite(_ word: Word) {
        if favorites.toggle(word.id) {
            favoriteIDs.insert(word.id)
        } else {
            favoriteIDs.remove(word.id)
        }
    }

    func languageName(_ code: String?) -> String? {
        guard let code, let catalog else { return nil }
        return catalog.languageName(code)
    }

    /// `koken://word/<id>` — bilinmeyen kimlik Bugün sekmesine düşer.
    func open(_ url: URL) {
        guard let id = DeepLink.wordID(from: url), catalog?.word(id: id) != nil else {
            selectedWordID = nil
            selectedTab = .today
            return
        }
        selectedWordID = id
        selectedTab = .dictionary
    }
}
