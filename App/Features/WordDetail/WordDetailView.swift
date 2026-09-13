import SwiftUI
import KokenKit

/// Bir kelimenin tam künyesi. Bugün sekmesi bunu günün kelimesiyle, Sözlük
/// listeden seçilen maddeyle gösterir; tek fark başlıktaki gün satırıdır.
struct WordDetailView: View {

    @Environment(AppModel.self) private var model

    let word: Word
    /// Bugün sekmesinde kartın üstünde yazan gün. Sözlükte `nil`.
    var day: Date?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                SectionCard(title: "detail.journey", systemImage: "point.topleft.down.to.point.bottomright.curvepath") {
                    JourneyTimeline(steps: word.chain)
                }
                meaning
                if let attestation = word.firstAttestation {
                    AttestationCard(attestation: attestation)
                }
                if !word.relatives.isEmpty {
                    RelativesCard(relatives: word.relatives)
                }
                if let alternatives = word.alternatives, !alternatives.isEmpty {
                    AlternativesCard(alternatives: alternatives)
                }
                if let funFact = word.funFact {
                    SectionCard(title: "detail.funFact", systemImage: "sparkles") {
                        Text(funFact)
                            .font(.subheadline)
                            .foregroundStyle(Theme.inkSoft)
                    }
                }
                SourcesCard(sources: word.sources)
            }
            .padding(Theme.screenPadding)
        }
        .kokenBackground()
        .scrollIndicators(.hidden)
        .navigationTitle(day == nil ? Text(word.word) : Text("tab.today"))
        .navigationBarTitleDisplayMode(day == nil ? .inline : .large)
        .toolbar { toolbar }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let day {
                Text(day.formatted(.dateTime.day().month(.wide)))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.accent)
            }
            FlowLayout(spacing: 8) {
                OriginBadge(word: word)
                RarityBadge(word: word)
            }
            Text(word.word)
                .font(.kokenWord())
                .foregroundStyle(Theme.ink)
            Text(word.partOfSpeech)
                .font(.caption)
                .italic()
                .foregroundStyle(Theme.inkSoft)
            Text(word.shortMeaning)
                .font(.body)
                .foregroundStyle(Theme.inkSoft)
        }
        .kokenCard()
    }

    private var meaning: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionCard(title: "detail.currentMeaning", systemImage: "character.book.closed") {
                Text(word.currentMeaning)
                    .font(.body)
                    .foregroundStyle(Theme.ink)
            }
            SectionCard(title: "detail.story", systemImage: "book.pages") {
                Text(word.story)
                    .font(.body)
                    .foregroundStyle(Theme.ink)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                model.toggleFavorite(word)
            } label: {
                let isFavorite = model.isFavorite(word)
                Label(isFavorite ? "detail.favorite.remove" : "detail.favorite.add",
                      systemImage: isFavorite ? "star.fill" : "star")
            }
            .tint(Theme.accent)
        }
        ToolbarItem(placement: .topBarTrailing) {
            ShareLink(item: model.shareText(for: word)) {
                Label("detail.share", systemImage: "square.and.arrow.up")
            }
            .tint(Theme.accent)
        }
    }
}
