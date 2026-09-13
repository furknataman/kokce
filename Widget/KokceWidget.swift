import SwiftUI
import WidgetKit
import KokenKit

/// Zaman çizelgesinin tek girdisi. Görünüm katmanı katalogla uğraşmasın diye
/// dil adları ve yolculuk adımları burada hazır hâle getirilir.
struct KokceEntry: TimelineEntry {
    let date: Date
    let word: Word?
    /// Kronolojik köken satırı: "Eski Yunanca → Arapça → Türkçe".
    let originPath: [String]
    /// Tek köken dili adı ("Arapça"); küçük ailenin alt satırı.
    let originName: String?
    /// Yolculuğun ilk üç adımı (systemLarge).
    let steps: [KokceJourneyStep]

    static let empty = KokceEntry(date: .now, word: nil, originPath: [], originName: nil, steps: [])
}

struct KokceJourneyStep: Hashable {
    let language: String
    let form: String
    let meaning: String
}

struct KokceProvider: TimelineProvider {

    /// Uzantının kendi bundle'ındaki katalog; App Group'ta daha yeni bir
    /// önbellek varsa `CatalogLoader` onu seçer. Widget uygulama hiç açılmadan
    /// da çalışır. Yükleyici salt okunurdur: bozuk önbelleği uygulama siler.
    private func catalog() -> WordCatalog? {
        guard let bundleURL = AppGroup.bundledCatalogURL() else { return nil }
        return try? CatalogLoader.load(bundleURL: bundleURL, cacheURL: AppGroup.cacheURL)
    }

    private func entry(for word: Word?, date: Date, in catalog: WordCatalog?) -> KokceEntry {
        guard let word, let catalog else {
            return KokceEntry(date: date, word: nil, originPath: [], originName: nil, steps: [])
        }
        // Zincirdeki ardışık tekrarlar ("Farsça → Farsça") tek ada indirilir.
        var path: [String] = []
        for step in word.chain {
            let name = catalog.languageName(step.language)
            if path.last != name { path.append(name) }
        }
        let steps = word.chain.prefix(3).map {
            KokceJourneyStep(language: catalog.languageName($0.language),
                             form: $0.form,
                             meaning: $0.meaning)
        }
        return KokceEntry(date: date,
                          word: word,
                          originPath: path,
                          originName: word.originLanguage.map { catalog.languageName($0) },
                          steps: steps)
    }

    /// Galeri ve yer tutucu için bundle'daki ilk kelime: her zaman aynı, her
    /// zaman dolu.
    private func firstWordEntry(date: Date = .now) -> KokceEntry {
        let catalog = catalog()
        return entry(for: catalog?.words.first, date: date, in: catalog)
    }

    func placeholder(in context: Context) -> KokceEntry {
        firstWordEntry()
    }

    func getSnapshot(in context: Context, completion: @escaping (KokceEntry) -> Void) {
        completion(firstWordEntry())
    }

    /// Önümüzdeki 7 günün girdisi önceden üretilir; her giriş İstanbul gece
    /// yarısında başlar, böylece widget gün dönümünü sistemden bağımsız çevirir.
    func getTimeline(in context: Context, completion: @escaping (Timeline<KokceEntry>) -> Void) {
        guard let catalog = catalog() else {
            completion(Timeline(entries: [KokceEntry.empty], policy: .atEnd))
            return
        }
        let mode = WordOfDayMode.current()
        let days = WordOfDay.upcoming(from: .now, count: 7, in: catalog, mode: mode)
        let entries = days.map { entry(for: $0.word, date: $0.date, in: catalog) }
        completion(Timeline(entries: entries.isEmpty ? [KokceEntry.empty] : entries, policy: .atEnd))
    }
}

struct KokceWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "KokceWidget", provider: KokceProvider()) { entry in
            KokceWidgetView(entry: entry)
        }
        .configurationDisplayName(Text("widget.title"))
        .description(Text("widget.description"))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
    }
}
