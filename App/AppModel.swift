import Foundation
import Observation
import WidgetKit
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

    /// Gösterilen günün başlangıcı (Europe/Istanbul). Gün dönünce ve uygulama
    /// öne gelince tazelenir; günün kelimesi ile tarih başlığı bunu okur.
    private(set) var today: Date = WordOfDay.calendar.startOfDay(for: .now)

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
    /// Günün kelimesinin hangi havuzdan seçileceği. Uygulama yazar, widget
    /// okur; ikisi de App Group'taki aynı anahtara bakar.
    var wordOfDayMode: WordOfDayMode = .mixed {
        didSet {
            guard oldValue != wordOfDayMode else { return }
            WordOfDayMode.save(wordOfDayMode)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
    /// Katalog yüklenmeden gelen deep link'in kimliği. Soğuk açılışta
    /// `onOpenURL`, `load()` bitmeden gelebilir; kimlik atılmaz, burada bekler.
    private var pendingWordID: String?

    init(repository: WordRepository? = nil) {
        // Gömülü katalog her iki hedefin bundle'ındadır; yoksa uygulama
        // içeriksiz açılır ve kullanıcıya boş durum gösterilir.
        self.repository = repository ?? AppGroup.bundledCatalogURL().map { WordRepository(bundleURL: $0) }
        // Özellik gözlemcileri init sırasında çalışmaz: kayıtlı kip okunurken
        // geri yazma ve widget yenileme tetiklenmez.
        self.wordOfDayMode = WordOfDayMode.current()
    }

    var todayWord: Word? {
        guard let catalog else { return nil }
        return WordOfDay.word(for: today, in: catalog, mode: wordOfDayMode)
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

    // MARK: - Yükleme

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
        resolvePendingDeepLink()
        await refreshContent()
    }

    /// Uzak katalogu yoklar. Depo zaten günde bir kez ağa çıktığı için her
    /// öne gelişte çağrılması güvenlidir.
    func refreshContent() async {
        guard let repository else { return }
        if await repository.refreshIfNeeded(), let fresh = try? await repository.catalog() {
            apply(fresh)
            // İçerik değişti: widget'lar eski kelimeyi göstermesin.
            WidgetCenter.shared.reloadAllTimelines()
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

    // MARK: - Gün dönümü

    /// Gün değiştiyse durumu tazeler. Sahne öne gelince ve gece yarısında
    /// çağrılır; gün aynıysa hiçbir şey yapmaz.
    func refreshDay(now: Date = .now) {
        let start = WordOfDay.calendar.startOfDay(for: now)
        guard start != today else { return }
        today = start
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// İstanbul gece yarısına kadar bekler, günü çevirir, yeniden bekler.
    /// Uygulama arka plandayken `Task.sleep` ilerlemez; o boşluğu sahnenin
    /// `.active` olmasıyla gelen `refreshDay()` kapatır.
    func watchDayChange() async {
        while !Task.isCancelled {
            let next = WordOfDay.calendar.date(byAdding: .day, value: 1, to: today)
                ?? Date.now.addingTimeInterval(3600)
            // Alt sınır, saat geri alındığında döngünün boşa dönmesini önler.
            let seconds = max(1, next.timeIntervalSince(.now))
            try? await Task.sleep(for: .seconds(seconds))
            if Task.isCancelled { return }
            refreshDay()
        }
    }

    // MARK: - Favoriler ve köken

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

    /// Köken yolu, **eskiden yeniye**: zincirin en eski dili → kelimeyi
    /// aktaran dil → Türkçe.
    ///
    /// Okuma yönü kasıtlı olarak kronolojiktir; ok kelimenin gittiği yönü
    /// gösterir. Aynı dil arka arkaya gelirse ("Farsça → Farsça") bir kez
    /// yazılır. `Word.originLanguage` iki alanı tek koda indirgediği için
    /// burada alanlar ayrı ayrı okunur.
    func originPath(for word: Word) -> [String] {
        var codes: [String] = []
        if let ultimate = word.ultimateOrigin { codes.append(ultimate) }
        if let donor = word.donorLanguage { codes.append(donor) }
        if codes.isEmpty, let fallback = word.originLanguage { codes.append(fallback) }
        codes.append("tr")

        var path: [String] = []
        for code in codes where path.last != code {
            path.append(code)
        }
        return path.compactMap { languageName($0) }
    }

    /// Rozet ve paylaşım metni için tek satırlık köken yolu.
    func originText(for word: Word) -> String? {
        let path = originPath(for: word)
        return path.isEmpty ? nil : path.joined(separator: " → ")
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

    // MARK: - Deep link

    /// `kokce://word/<id>` — bilinmeyen kimlik Bugün sekmesine düşer.
    func open(_ url: URL) {
        guard let id = DeepLink.wordID(from: url) else {
            fallBackToToday()
            return
        }
        // Soğuk açılışta katalog henüz yüklenmemiş olabilir. Kimlik atılmaz;
        // `load()` bitince çözülür ve sekme o zaman değişir.
        guard catalog != nil else {
            pendingWordID = id
            return
        }
        show(id: id)
    }

    private func resolvePendingDeepLink() {
        guard let id = pendingWordID else { return }
        pendingWordID = nil
        show(id: id)
    }

    /// Açılan madde filtrelenmiş bir listenin ardında kalmasın diye arama ve
    /// filtreler temizlenir.
    private func show(id: String) {
        guard let word = catalog?.word(id: id) else {
            fallBackToToday()
            return
        }
        searchText = ""
        originFilter = nil
        showFavoritesOnly = false
        dictionaryPath = [word]
        selectedTab = .dictionary
    }

    private func fallBackToToday() {
        pendingWordID = nil
        dictionaryPath = []
        selectedTab = .today
    }
}
