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
            Text(word.shortMeaning)
                .font(.caption)
                .foregroundStyle(Theme.inkSoft)
                .lineLimit(3)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 2)
            KokceOriginFooter(name: entry.originName, isRare: word.isRare)
        }
    }
}

/// Sol sütunda kelime ve anlam, sağ üstte filiz ile tarih.
struct KokceMediumView: View {
    let entry: KokceEntry
    let word: Word

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text(word.word)
                    .font(.kokenWord(.title))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if !entry.originPath.isEmpty {
                    Text(entry.originPath.joined(separator: " → "))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Theme.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                // Anlam köken satırının hemen altında durur: Spacer ortaya
                // alınsaydı kısa anlamlarda ortada büyük bir boşluk kalırdı.
                Text(word.shortMeaning)
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSoft)
                    .lineLimit(3)
                    .minimumScaleFactor(0.9)
                Spacer(minLength: 0)
            }
            VStack(alignment: .trailing, spacing: 4) {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text(entry.date, format: .dateTime.day().month(.wide))
                    .font(.caption2)
                    .foregroundStyle(Theme.inkSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
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
            Text(word.story)
                .font(.caption2)
                .foregroundStyle(Theme.inkSoft)
                .lineLimit(6)
                .minimumScaleFactor(0.95)

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

/// Xcode önizlemeleri ve anlık görüntü testi için sabit örnek.
enum KokcePreview {
    static let entry = KokceEntry(
        date: .now,
        word: Word(id: "kalem",
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
                   reviewed: true),
        originPath: ["Eski Yunanca", "Arapça", "Türkçe"],
        originName: "Arapça",
        steps: [
            KokceJourneyStep(language: "Eski Yunanca", form: "kálamos", meaning: "kamış"),
            KokceJourneyStep(language: "Arapça", form: "qalam", meaning: "kamış kalem"),
            KokceJourneyStep(language: "Türkçe", form: "kalem", meaning: "yazı aracı")
        ])
}
