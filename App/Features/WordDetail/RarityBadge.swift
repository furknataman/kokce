import SwiftUI
import KokenKit

/// "Az bilinen" rozeti. Şemada `rarity` alanı yoksa kelime gündelik sayılır
/// ve rozet hiç çizilmez; karar `Word.isRare` içindedir.
struct RarityBadge: View {

    let word: Word
    /// Rozetin oturduğu yüzeyin rengi; liste satırı ile kart farklı zeminde.
    var background: Color = Theme.parchment

    var body: some View {
        if word.isRare {
            Text("word.rarity.rare")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(background, in: Capsule())
                .overlay { Capsule().strokeBorder(Theme.accent.opacity(0.4), lineWidth: 1) }
        }
    }
}
