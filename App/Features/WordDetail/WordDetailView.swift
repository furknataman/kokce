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
            .kokenContentColumn()
        }
        .kokenBackground()
        .scrollIndicators(.hidden)
        // iOS 26'da sekme çubuğu içeriğin üzerinde yüzer. Güvenli alan son
        // kartı çubuğun altında bırakmıyor ama kart çubuğa yapışıyordu; bu
        // pay kartı çubuktan ayırır. iOS 18'de de fazladan alt boşluk olur.
        .contentMargins(.bottom, 16, for: .scrollContent)
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
        // Araç çubuğu öğelerine iOS 26 cam görünümü sistem tarafından zaten
        // verilir; `.buttonStyle(.glass)` eklenince kapsülün içine ikinci bir
        // kapsül biniyor. Cam, çubuğun dışındaki kontrollerde (filtre çipleri)
        // elle uygulanır.
        ToolbarItem(placement: .topBarTrailing) { favoriteButton }
        ToolbarItem(placement: .topBarTrailing) { shareButton }
    }

    private var favoriteButton: some View {
        Button {
            model.toggleFavorite(word)
        } label: {
            let isFavorite = model.isFavorite(word)
            Label(isFavorite ? "detail.favorite.remove" : "detail.favorite.add",
                  systemImage: isFavorite ? "star.fill" : "star")
        }
        .tint(Theme.accent)
    }

    private var shareButton: some View {
        ShareLink(item: model.shareText(for: word)) {
            Label("detail.share", systemImage: "square.and.arrow.up")
        }
        .tint(Theme.accent)
    }

}
