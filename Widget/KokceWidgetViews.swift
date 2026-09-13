import SwiftUI
import WidgetKit
import KokenKit

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
            default: KokceSmallView(word: word)
            }
        } else {
            Text("widget.empty")
                .font(.caption)
                .foregroundStyle(family == .accessoryRectangular ? Color.primary : Theme.inkSoft)
        }
    }
}

/// Kelime + tek satır anlam.
struct KokceSmallView: View {
    let word: Word

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(word.word)
                .font(.kokenWord(.title2))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(word.shortMeaning)
                .font(.caption)
                .foregroundStyle(Theme.inkSoft)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }
}

/// Kelime + kronolojik köken satırı + kısa anlam.
struct KokceMediumView: View {
    let entry: KokceEntry
    let word: Word

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
            Text(word.shortMeaning)
                .font(.footnote)
                .foregroundStyle(Theme.inkSoft)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
    }
}

/// Kelime + kısa anlam + yolculuğun ilk üç adımı + güncel anlam.
struct KokceLargeView: View {
    let entry: KokceEntry
    let word: Word

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(word.word)
                .font(.kokenWord(.largeTitle))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(word.shortMeaning)
                .font(.subheadline)
                .foregroundStyle(Theme.inkSoft)
                .lineLimit(2)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(entry.steps.enumerated()), id: \.offset) { index, step in
                    KokceStepRow(number: index + 1, step: step)
                }
            }

            Spacer(minLength: 0)

            Text(word.currentMeaning)
                .font(.caption)
                .foregroundStyle(Theme.inkSoft)
                .lineLimit(2)
        }
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

/// Xcode önizlemeleri için sabit örnek; `simctl` kilit ekranı widget'ını
/// ekleyemediğinden dördüncü aile buradan görülür.
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
                   story: "Kamıştan kaleme uzanan bir yolculuk.",
                   firstAttestation: nil,
                   relatives: [],
                   alternatives: nil,
                   funFact: nil,
                   sources: [Source(name: "Nişanyan Sözlük", ref: nil, url: nil)],
                   confidence: .high,
                   reviewed: true),
        originPath: ["Eski Yunanca", "Arapça", "Türkçe"],
        steps: [
            KokceJourneyStep(language: "Eski Yunanca", form: "kálamos", meaning: "kamış"),
            KokceJourneyStep(language: "Arapça", form: "qalam", meaning: "kamış kalem"),
            KokceJourneyStep(language: "Türkçe", form: "kalem", meaning: "yazı aracı")
        ])
}
