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
    /// Orta ailenin alt bloğu için özet adayları, **en uzundan kısaya**.
    /// `ViewThatFits` sığan ilkini seçer: böylece alan dolar ve metin kesilmez.
    let summaries: [String]
    /// Büyük ailenin hikâye adayları, yine en uzundan kısaya.
    let storyOptions: [String]

    static let empty = KokceEntry(date: .now, word: nil, originPath: [], originName: nil,
                                  steps: [], summaries: [], storyOptions: [])
}

struct KokceJourneyStep: Hashable {
    let language: String
    let form: String
    let meaning: String
}

/// Widget'ın kısa metinleri. Hikâye uzun, alan dar: ilk cümle çoğu kelimede
/// hikâyenin can alıcı kısmıdır.
enum KokceSummary {

    /// Orta ailenin özet adayları, en uzundan kısaya. Hikâyenin üç, iki ve bir
    /// cümlesi ile güncel anlam; kısa anlamı tekrarlayan ya da boş olanlar
    /// elenir. Görünüm bunlardan sığan ilkini seçer.
    static func summaries(for word: Word) -> [String] {
        let candidates = [sentences(word.story, limit: 3),
                          sentences(word.story, limit: 2),
                          word.currentMeaning,
                          sentences(word.story, limit: 1)]
        return unique(candidates, notMatching: word.shortMeaning)
    }

    /// Büyük ailenin hikâye adayları: tamamı, ilk iki cümle, ilk cümle.
    static func storyOptions(for word: Word) -> [String] {
        let candidates = [word.story,
                          sentences(word.story, limit: 2),
                          sentences(word.story, limit: 1),
                          word.currentMeaning]
        return unique(candidates, notMatching: word.shortMeaning)
    }

    private static func unique(_ candidates: [String], notMatching excluded: String) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for candidate in candidates {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, normalized(trimmed) != normalized(excluded) else { continue }
            guard seen.insert(normalized(trimmed)).inserted else { continue }
            result.append(trimmed)
        }
        return result
    }

    /// İlk `limit` cümle. Cümle sonu, noktalama + boşluk + büyük harf olarak
    /// aranır; "13. yüzyıl" gibi sıra sayıları bu yüzden bölmez.
    static func sentences(_ text: String, limit: Int) -> String {
        let characters = Array(text)
        var found = 0
        var end = characters.count
        for index in characters.indices where ".!?".contains(characters[index]) {
            let next = index + 1
            guard next < characters.count else { break }
            guard characters[next] == " " || characters[next] == "\n" else { continue }
            let following = characters[(next + 1)...].first
            guard following == nil || following!.isUppercase else { continue }
            found += 1
            if found == limit {
                end = next
                break
            }
        }
        return String(characters[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
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
            return KokceEntry(date: date, word: nil, originPath: [], originName: nil,
                              steps: [], summaries: [], storyOptions: [])
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
                          steps: steps,
                          summaries: KokceSummary.summaries(for: word),
                          storyOptions: KokceSummary.storyOptions(for: word))
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
