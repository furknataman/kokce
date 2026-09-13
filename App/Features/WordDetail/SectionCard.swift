import SwiftUI

/// Detay ekranındaki başlıklı bölüm kartı: düz zemin, ince kenarlık, üstte
/// simgeli başlık. Cam değil — Liquid Glass yalnızca kontrollerde.
struct SectionCard<Content: View>: View {

    let title: LocalizedStringKey
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .kokenCard()
    }
}
