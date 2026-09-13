import SwiftUI
import WidgetKit
import KokenKit

/// Metinler uzantının kendi `Localizable.xcstrings` dosyasından gelir.
/// `Bundle(for:)` widget'ta uzantının, anlık görüntü testinde test hedefinin
/// bundle'ını verir; `Bundle.main` ikisinde de yanlış yeri gösterirdi.
enum KokceStrings {
    static let bundle = Bundle(for: BundleToken.self)
    private final class BundleToken {}
}

/// Ailelere göre dallanan kök görünüm. Zemin ve deep link tek yerde tanımlanır.
struct KokceWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: KokceEntry

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .widgetURL(entry.word.flatMap { DeepLink.url(wordID: $0.id) })
            .containerBackground(for: .widget) {
                // Kilit ekranı ailesi sistemin kendi zeminini kullanır.
                if family == .accessoryRectangular {
                    Color.clear
                } else {
                    Theme.parchment
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if let word = entry.word {
            switch family {
            case .accessoryRectangular: KokceAccessoryView(word: word)
            case .systemMedium: KokceMediumView(entry: entry, word: word)
            case .systemLarge: KokceLargeView(entry: entry, word: word)
            default: KokceSmallView(entry: entry, word: word)
            }
        } else {
            Text("widget.empty", bundle: KokceStrings.bundle)
                .font(.caption)
                .foregroundStyle(family == .accessoryRectangular ? Color.primary : Theme.inkSoft)
        }
    }
}

/// Etiket + kelime + anlam + köken dili. Kesme yok: anlam üç satıra kadar
/// açılır, gerekirse hafifçe küçülür.
struct KokceSmallView: View {
    let entry: KokceEntry
    let word: Word

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            KokceLabel()
            Text(word.word)
                .font(.kokenWord(.title2))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            // Kesme yerine satır sayısını düşür: üçü sığmıyorsa ikiye,
            // o da sığmıyorsa bire iner.
            ViewThatFits(in: .vertical) {
                meaning(lines: 3)
                meaning(lines: 2)
                meaning(lines: 1)
            }
            Spacer(minLength: 2)
            KokceOriginFooter(name: entry.originName, isRare: word.isRare)
        }
    }

    private func meaning(lines: Int) -> some View {
        Text(word.shortMeaning)
            .font(.caption)
            .foregroundStyle(Theme.inkSoft)
            .lineLimit(lines)
            .minimumScaleFactor(0.85)
    }
}

/// Sol sütunda kelime ve anlam, sağ üstte filiz ile tarih.
struct KokceMediumView: View {
    let entry: KokceEntry
    let word: Word

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(word.word)
                    .font(.kokenWord(.title))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 6)
                Text(entry.date, format: .dateTime.day().month(.wide))
                    .font(.caption)
                    .foregroundStyle(Theme.inkSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Image(systemName: "leaf.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.accent)
            }
            if !entry.originPath.isEmpty {
                Text(entry.originPath.joined(separator: " → "))
                    .font(.caption)
                    .foregroundStyle(Theme.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Text(word.shortMeaning)
                .font(.subheadline)
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.9)
            // Kalan alanı hikâye doldurur. Adaylar en uzundan kısaya sıralı;
            // ViewThatFits tam sığanı seçer, böylece ne "…" ile kesme olur ne
            // de altta boş şerit kalır. Satır sınırı yalnızca son çarede var.
            ViewThatFits(in: .vertical) {
                summary(0)
                summary(1)
                summary(2)
                summary(2, lines: 3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func summary(_ index: Int, lines: Int? = nil) -> some View {
        Text(entry.summaries.indices.contains(index)
             ? entry.summaries[index]
             : (entry.summaries.last ?? word.currentMeaning))
            .font(.footnote)
            .foregroundStyle(Theme.inkSoft)
            .lineLimit(lines)
            .minimumScaleFactor(0.85)
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

/// Kelime, anlam, yolculuk ve hikâye; alan sonuna kadar kullanılır.
struct KokceLargeView: View {
    let entry: KokceEntry
    let word: Word

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(word.word)
                .font(.kokenWord(.largeTitle))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(word.shortMeaning)
                .font(.subheadline)
                .foregroundStyle(Theme.inkSoft)
                .lineLimit(2)

            KokceRule()

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(entry.steps.enumerated()), id: \.offset) { index, step in
                    KokceStepRow(number: index + 1, step: step)
                }
            }

            KokceRule()

            Text(word.currentMeaning)
                .font(.caption)
                .foregroundStyle(Theme.ink)
                .lineLimit(3)
            // Hikâyenin tamamı sığmıyorsa ilk iki, sonra ilk cümleye düşülür.
            ViewThatFits(in: .vertical) {
                story(0)
                story(1)
                story(2)
                story(2, lines: 4)
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Text(verbatim: "Kökçe")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Theme.accent.opacity(0.85))
            }
        }
    }
}

private extension KokceLargeView {
    func story(_ index: Int, lines: Int? = nil) -> some View {
        Text(entry.storyOptions.indices.contains(index)
             ? entry.storyOptions[index]
             : (entry.storyOptions.last ?? word.story))
            .font(.caption2)
            .foregroundStyle(Theme.inkSoft)
            .lineLimit(lines)
            .minimumScaleFactor(0.95)
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

/// Kilit ekranı. Renkler sistemden gelir; kelime vurgulanabilir.
struct KokceAccessoryView: View {
    let word: Word

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(word.word)
                .font(.headline)
                .lineLimit(1)
                .widgetAccentable()
            Text(word.shortMeaning)
                .font(.caption)
                .lineLimit(2)
        }
    }
}

/// "GÜNÜN KELİMESİ" — büyük harfli metin katalogda hazır durur; Türkçede
/// `i` harfinin büyütülmesi yerel ayara bağlı olduğu için kodda çevrilmez.
private struct KokceLabel: View {
    var body: some View {
        Text("widget.label.today", bundle: KokceStrings.bundle)
            .font(.caption2.weight(.semibold))
            .tracking(0.9)
            .foregroundStyle(Theme.accent)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

private struct KokceOriginFooter: View {
    let name: String?
    let isRare: Bool

    var body: some View {
        if let name {
            HStack(spacing: 4) {
                Text(name)
                if isRare {
                    Text(verbatim: "·")
                    Text("widget.rarity.rare", bundle: KokceStrings.bundle)
                }
            }
            .font(.caption2)
            .foregroundStyle(Theme.inkSoft)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
    }
}

/// İnce altın ayırıcı.
private struct KokceRule: View {
    var body: some View {
        Rectangle()
            .fill(Theme.accent.opacity(0.35))
            .frame(height: 1)
    }
}

private struct KokceStepRow: View {
    let number: Int
    let step: KokceJourneyStep

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Theme.parchment)
                .frame(width: 18, height: 18)
                .background(Theme.accent, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text("\(step.language) · \(step.form)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text(step.meaning)
                    .font(.caption2)
                    .foregroundStyle(Theme.inkSoft)
                    .lineLimit(1)
            }
        }
    }
}

#Preview("Küçük", as: .systemSmall) {
    KokceWidget()
} timeline: {
    KokcePreview.entry
}

#Preview("Orta", as: .systemMedium) {
    KokceWidget()
} timeline: {
    KokcePreview.entry
}

#Preview("Büyük", as: .systemLarge) {
    KokceWidget()
} timeline: {
    KokcePreview.entry
}

#Preview("Kilit ekranı", as: .accessoryRectangular) {
    KokceWidget()
} timeline: {
    KokcePreview.entry
}

/// Xcode önizlemeleri ve anlık görüntü testi için sabit örnekler: biri uzun
/// metinli (kalem), biri kısa (çay).
enum KokcePreview {

    static let entry = makeEntry(word: kalem,
                                 path: ["Eski Yunanca", "Arapça", "Türkçe"],
                                 originName: "Arapça",
                                 steps: [
                                    KokceJourneyStep(language: "Eski Yunanca", form: "kálamos", meaning: "kamış"),
                                    KokceJourneyStep(language: "Arapça", form: "qalam", meaning: "kamış kalem"),
                                    KokceJourneyStep(language: "Türkçe", form: "kalem", meaning: "yazı aracı")
                                 ])

    static let shortEntry = makeEntry(word: cay,
                                      path: ["Çince", "Farsça", "Türkçe"],
                                      originName: "Farsça",
                                      steps: [
                                        KokceJourneyStep(language: "Çince", form: "chá", meaning: "çay bitkisi"),
                                        KokceJourneyStep(language: "Farsça", form: "çāy", meaning: "çay"),
                                        KokceJourneyStep(language: "Türkçe", form: "çay", meaning: "çay")
                                      ])

    static func makeEntry(word: Word,
                          path: [String],
                          originName: String,
                          steps: [KokceJourneyStep]) -> KokceEntry {
        KokceEntry(date: .now,
                   word: word,
                   originPath: path,
                   originName: originName,
                   steps: steps,
                   summaries: KokceSummary.summaries(for: word),
                   storyOptions: KokceSummary.storyOptions(for: word))
    }

    static let kalem = Word(
        id: "kalem",
        word: "kalem",
        partOfSpeech: "isim",
        formationType: .borrowed,
        donorLanguage: "ar",
        ultimateOrigin: "grc",
        chain: [
            ChainStep(language: "grc", form: "kálamos", meaning: "kamış", period: nil, reconstructed: false),
            ChainStep(language: "ar", form: "qalam", meaning: "kamış kalem", period: nil, reconstructed: false),
            ChainStep(language: "tr", form: "kalem", meaning: "yazı aracı", period: nil, reconstructed: false)
        ],
        shortMeaning: "Yazı yazmaya yarayan araç.",
        currentMeaning: "Yazı yazmak veya çizmek için kullanılan, ucundan boya, mürekkep ya da grafit bırakan araç.",
        story: "Eski Yunancada kálamos, kıyıda biten kamışın adıydı. Ucu eğik kesilip mürekkebe batırılan bu kamış, Arapçaya qalam biçiminde geçti ve yazının aracı oldu. Türkçeye Arapçadan gelen kelime, kamış çoktan yerini madene bıraksa da adını korudu.",
        firstAttestation: nil,
        relatives: [],
        alternatives: nil,
        funFact: nil,
        sources: [Source(name: "Nişanyan Sözlük", ref: nil, url: nil)],
        confidence: .high,
        reviewed: true)

    static let cay = Word(
        id: "çay",
        word: "çay",
        partOfSpeech: "isim",
        formationType: .borrowed,
        donorLanguage: "fa",
        ultimateOrigin: "zh",
        chain: [
            ChainStep(language: "zh", form: "chá", meaning: "çay bitkisi", period: nil, reconstructed: false),
            ChainStep(language: "fa", form: "çāy", meaning: "çay", period: nil, reconstructed: false),
            ChainStep(language: "tr", form: "çay", meaning: "çay", period: nil, reconstructed: false)
        ],
        shortMeaning: "Çay bitkisinin yaprağından demlenen içecek.",
        currentMeaning: "Çay bitkisinin kurutulmuş yaprağının kaynar suda demlenmesiyle elde edilen içecek.",
        story: "Çayın anayurdu Çin'de kelimenin biçimi chá idi.",
        firstAttestation: nil,
        relatives: [],
        alternatives: nil,
        funFact: nil,
        sources: [Source(name: "Nişanyan Sözlük", ref: nil, url: nil)],
        confidence: .high,
        reviewed: true)
}
