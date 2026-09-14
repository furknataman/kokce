import Foundation
import Observation
import WidgetKit
import KokenKit

/// Arayüzün tek durum kaynağı. Depoyu sarar; dosya ve ağ işi actor'da kalır.
@MainActor
@Observable
final class AppModel {

    enum Tab: Hashable {
        case today, dictionary, search, settings
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
    private let router = NotificationRouter()
    /// Günlük bildirim tercihi ve planlaması. Görünümler doğrudan okur.
    let notifications = DailyNotifications()

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
            Task { await refreshNotifications() }
        }
    }
    /// Katalog yüklenmeden gelen deep link'in ya da bildirimin kimliği. Soğuk
    /// açılışta dış giriş `load()` bitmeden gelebilir; kimlik atılmaz, burada
    /// bekler. Giriş noktaları `AppModel+DeepLink` dosyasında, bu yüzden alan
    /// dosyaya kapalı değil.
    var pendingWordID: String?

    init(repository: WordRepository? = nil) {
        // Gömülü katalog her iki hedefin bundle'ındadır; yoksa uygulama
        // içeriksiz açılır ve kullanıcıya boş durum gösterilir.
        self.repository = repository ?? AppGroup.bundledCatalogURL().map { WordRepository(bundleURL: $0) }
        // Özellik gözlemcileri init sırasında çalışmaz: kayıtlı kip okunurken
        // geri yazma ve widget yenileme tetiklenmez.
        self.wordOfDayMode = WordOfDayMode.current()
        // Delege burada bağlanır: soğuk açılışta sistem bildirim yanıtını hemen
        // teslim eder, delege geç bağlanırsa dokunuş kaybolur.
        router.attach(to: self)
    }

    var todayWord: Word? {
        guard let catalog else { return nil }
        return WordOfDay.word(for: today, in: catalog, mode: wordOfDayMode)
    }

    var contentVersion: Int? { catalog?.contentVersion }

    /// İki filtre ekseni uygulanmış sözlük listesi. Arama ayrı sekmededir.
    var filteredWords: [Word] {
        guard let catalog else { return [] }
        return WordSearch.filter(catalog.words,
                                 originLanguage: originFilter,
                                 favoriteIDs: showFavoritesOnly ? favoriteIDs : nil)
    }

    /// Arama sekmesinin sonuçları; sözlük çipleri burada uygulanmaz.
    var searchResults: [Word] {
        guard let catalog else { return [] }
        return WordSearch.filter(catalog.words, query: searchText)
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
        await refreshNotifications()
    }

    /// Uzak katalogu yoklar. Depo zaten günde bir kez ağa çıktığı için her
    /// öne gelişte çağrılması güvenlidir.
    func refreshContent() async {
        guard let repository else { return }
        if await repository.refreshIfNeeded(), let fresh = try? await repository.catalog() {
            apply(fresh)
            // İçerik değişti: widget'lar ve bekleyen bildirimler eski kelimeyi
            // göstermesin.
            WidgetCenter.shared.reloadAllTimelines()
            await refreshNotifications()
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

    /// Akraba kelimenin sözlükteki maddesi; katalogda yoksa `nil` ve çip
    /// bağlantısız çizilir.
    func word(for relative: Relative) -> Word? {
        wordsByName[relative.word.lowercased(with: Self.turkish)]
    }

    // MARK: - Bildirim

    /// Bildirim işleri planlamak için katalog ile kipi ister; görünümler o
    /// bağlamı taşımasın diye sarmalanır.
    func setNotifications(_ enabled: Bool) async {
        await notifications.setEnabled(enabled, catalog: catalog, mode: wordOfDayMode)
    }

    func setNotificationTime(hour: Int, minute: Int) {
        notifications.setTime(hour: hour, minute: minute, catalog: catalog, mode: wordOfDayMode)
    }

    func refreshNotifications() async {
        await notifications.refresh(catalog: catalog, mode: wordOfDayMode)
    }
}
