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

    /// Sözlükteki köken dili çipi. Sayı, çip şeridinin sırasını belirler.
    struct OriginChip: Identifiable, Hashable {
        let code: String
        let name: String
        let count: Int
        var id: String { code }
    }

    /// Kelime adlarını karşılaştırırken kullanılan yerel ayar. `I/ı` katlaması
    /// Türkçe kurallarıyla yapılmazsa "İzmir" ile "izmir" eşleşmez.
    private static let turkish = Locale(identifier: "tr_TR")

    private let repository: WordRepository?
    private let favorites = FavoritesStore()

    private(set) var catalog: WordCatalog?
    private(set) var failedToLoad = false
    /// Akraba kelime çiplerini maddeye bağlayan ad → kelime dizini. Çipler her
    /// çizimde listeyi taramasın diye katalog yüklenince bir kez kurulur.
    private var wordsByName: [String: Word] = [:]
    /// Köken dili çipleri; katalogla birlikte bir kez hesaplanır.
    private(set) var originChips: [OriginChip] = []

    var selectedTab: Tab = .today
    /// Sözlük sekmesinin gezinme yığını. Deep link buraya yazar.
    var dictionaryPath: [Word] = []
    var searchText = ""
    var originFilter: String?
    /// Favoriler, köken dilinden ayrı bir filtre eksenidir.
    var showFavoritesOnly = false
    private(set) var favoriteIDs: Set<String> = []
    /// Uzak katalogun son yoklanma zamanı; Ayarlar ekranı gösterir.
    private(set) var lastCheckedAt: Date?

    init(repository: WordRepository? = nil) {
        // Gömülü katalog her iki hedefin bundle'ındadır; yoksa uygulama
        // içeriksiz açılır ve kullanıcıya boş durum gösterilir.
        self.repository = repository ?? AppGroup.bundledCatalogURL().map { WordRepository(bundleURL: $0) }
    }

    var todayWord: Word? {
        guard let catalog else { return nil }
        return WordOfDay.word(for: .now, in: catalog)
    }

    var contentVersion: Int? { catalog?.contentVersion }

    /// Arama ve iki filtre ekseni birlikte uygulanmış sözlük listesi.
    var filteredWords: [Word] {
        guard let catalog else { return [] }
        return WordSearch.filter(catalog.words,
                                 query: searchText,
                                 originLanguage: originFilter,
                                 favoriteIDs: showFavoritesOnly ? favoriteIDs : nil)
    }

    /// Çip şeridinde "Tümü" yerine başka bir çip seçili mi? Arama ayrı bir
    /// eksendir, buraya girmez.
    var hasActiveFilter: Bool {
        originFilter != nil || showFavoritesOnly
    }

    func load() async {
        guard let repository else {
            failedToLoad = true
            return
        }
        do {
            apply(try await repository.catalog())
        } catch {
            failedToLoad = true
        }
        favoriteIDs = Set(favorites.ids)
        // Günde bir kez uzak dosyayı yoklar; hata sessizce yutulur.
        if await repository.refreshIfNeeded(), let fresh = try? await repository.catalog() {
            apply(fresh)
        }
        lastCheckedAt = WordRepository.lastCheckedAt()
    }

    /// Katalogdan türeyen dizinleri tek yerde tazeler.
    private func apply(_ catalog: WordCatalog) {
        self.catalog = catalog
        wordsByName = Dictionary(catalog.words.map { ($0.word.lowercased(with: Self.turkish), $0) },
                                 uniquingKeysWith: { first, _ in first })
        originChips = Self.chips(in: catalog)
    }

    private static func chips(in catalog: WordCatalog) -> [OriginChip] {
        var counts: [String: Int] = [:]
        for word in catalog.words {
            // Sayım `originLanguage` üzerinden yapılır; filtreleme de aynı alanı
            // kullanır, yoksa çip kendi sayısından az sonuç gösterir.
            guard let code = word.originLanguage else { continue }
            counts[code, default: 0] += 1
        }
        return counts
            .map { OriginChip(code: $0.key, name: catalog.languageName($0.key), count: $0.value) }
            .sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                return $0.name.compare($1.name, options: [], range: nil, locale: turkish) == .orderedAscending
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

    /// Rozette ve paylaşım metninde geçen köken dilleri: kelimeyi aktaran dil
    /// ve ondan farklıysa zincirin en eski dili.
    ///
    /// `Word.originLanguage` ikisini tek koda indirger; rozet "Arapça ← Eski
    /// Yunanca" diyebilmek için ikisini ayrı ayrı okur. İkisi aynıysa ok
    /// gösterilmez, yoksa "Farsça ← Farsça" gibi bir rozet çıkar.
    func origin(for word: Word) -> (donor: String, ultimate: String?)? {
        guard let donorCode = word.originLanguage,
              let donorName = languageName(donorCode) else { return nil }
        guard let ultimateCode = word.ultimateOrigin,
              ultimateCode != donorCode,
              let ultimateName = languageName(ultimateCode) else { return (donorName, nil) }
        return (donorName, ultimateName)
    }

    /// Rozet ve paylaşım metni için tek satırlık köken özeti.
    func originText(for word: Word) -> String? {
        guard let origin = origin(for: word) else { return nil }
        guard let ultimate = origin.ultimate else { return origin.donor }
        return "\(origin.donor) ← \(ultimate)"
    }

    /// Paylaşılan düz metin. Biçim dizesi katalogdan gelir, metin kaynak
    /// dosyada değil `Localizable.xcstrings` içinde durur.
    func shareText(for word: Word) -> String {
        guard let origin = originText(for: word) else {
            return String(format: String(localized: "share.format.plain"), word.word, word.shortMeaning)
        }
        return String(format: String(localized: "share.format"), word.word, word.shortMeaning, origin)
    }

    /// Akraba kelimenin sözlükteki maddesi; katalogda yoksa `nil` ve çip
    /// bağlantısız çizilir.
    func word(for relative: Relative) -> Word? {
        wordsByName[relative.word.lowercased(with: Self.turkish)]
    }

    /// `koken://word/<id>` — bilinmeyen kimlik Bugün sekmesine düşer.
    ///
    /// Açılan madde filtrelenmiş bir listenin ardında kalmasın diye arama ve
    /// filtreler temizlenir.
    func open(_ url: URL) {
        guard let id = DeepLink.wordID(from: url), let word = catalog?.word(id: id) else {
            dictionaryPath = []
            selectedTab = .today
            return
        }
        searchText = ""
        originFilter = nil
        showFavoritesOnly = false
        dictionaryPath = [word]
        selectedTab = .dictionary
    }
}
