import SwiftUI
import KokenKit

/// Bugün sekmesi. Faz 4'te tam kart (yolculuk, tanıklık, akrabalar, paylaş)
/// buraya gelecek; şimdilik günün kelimesi adı ve kısa anlamı.
struct TodayView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            ScrollView {
                if let word = model.todayWord {
                    VStack(alignment: .leading, spacing: 12) {
                        if let origin = model.languageName(word.originLanguage) {
                            Text(origin)
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(Theme.inkSoft)
                        }
                        Text(word.word)
                            .font(.kokenWord())
                            .foregroundStyle(Theme.ink)
                        Text(word.shortMeaning)
                            .font(.body)
                            .foregroundStyle(Theme.inkSoft)
                    }
                    .kokenCard()
                    .padding(20)
                } else {
                    ContentUnavailableView("today.empty", systemImage: "book.closed")
                        .padding(.top, 80)
                }
            }
            .kokenBackground()
            .navigationTitle("tab.today")
        }
    }
}
