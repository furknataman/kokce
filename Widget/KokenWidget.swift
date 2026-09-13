import SwiftUI
import WidgetKit
import KokenKit

/// Günün kelimesi widget'ı. Faz 5'te medium, large ve kilit ekranı aileleri,
/// deep link ve yeniden yükleme tetikleri eklenecek.
struct KokenEntry: TimelineEntry {
    let date: Date
    let word: Word?
}

struct KokenProvider: TimelineProvider {

    /// Uzantının kendi bundle'ındaki katalog; App Group'ta daha yeni bir
    /// önbellek varsa `CatalogLoader` onu seçer. Böylece widget uygulama hiç
    /// açılmadan da çalışır.
    private func catalog() -> WordCatalog? {
        guard let bundleURL = AppGroup.bundledCatalogURL() else { return nil }
        return try? CatalogLoader.load(bundleURL: bundleURL, cacheURL: AppGroup.cacheURL)
    }

    func placeholder(in context: Context) -> KokenEntry {
        KokenEntry(date: .now, word: catalog().flatMap { WordOfDay.word(for: .now, in: $0) })
    }

    func getSnapshot(in context: Context, completion: @escaping (KokenEntry) -> Void) {
        completion(placeholder(in: context))
    }

    /// Önümüzdeki 7 günün girdisi önceden üretilir; gece yarısı sınırında
    /// widget kendi kendine döner, sistemden yeni zaman çizelgesi beklemez.
    func getTimeline(in context: Context, completion: @escaping (Timeline<KokenEntry>) -> Void) {
        guard let catalog = catalog() else {
            completion(Timeline(entries: [KokenEntry(date: .now, word: nil)], policy: .atEnd))
            return
        }
        let entries = WordOfDay.upcoming(from: .now, count: 7, in: catalog)
            .map { KokenEntry(date: $0.date, word: $0.word) }
        completion(Timeline(entries: entries.isEmpty ? [KokenEntry(date: .now, word: nil)] : entries,
                            policy: .atEnd))
    }
}

struct KokenWidgetView: View {
    let entry: KokenEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let word = entry.word {
                Text(word.word)
                    .font(.kokenWord(.title2))
                    .foregroundStyle(Theme.ink)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(word.shortMeaning)
                    .font(.caption)
                    .foregroundStyle(Theme.inkSoft)
                    .lineLimit(3)
            } else {
                Text("today.empty")
                    .font(.caption)
                    .foregroundStyle(Theme.inkSoft)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(entry.word.flatMap { DeepLink.url(wordID: $0.id) })
    }
}

struct KokenWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "KokenWidget", provider: KokenProvider()) { entry in
            KokenWidgetView(entry: entry)
                .containerBackground(Theme.parchment, for: .widget)
        }
        .configurationDisplayName(Text("widget.title"))
        .description(Text("widget.description"))
        .supportedFamilies([.systemSmall])
    }
}
