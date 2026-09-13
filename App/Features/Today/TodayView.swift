import SwiftUI
import KokenKit

/// Bugün sekmesi: günün kelimesinin tam künyesi. Görünümün kendisi Sözlük ile
/// ortaktır; buradaki tek fark kartın üstündeki gün satırıdır.
struct TodayView: View {

    @Environment(AppModel.self) private var model
    /// Akraba kelime çiplerinden açılan maddeler bu yığına biner.
    @State private var path: [Word] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let word = model.todayWord {
                    WordDetailView(word: word, day: .now)
                } else {
                    ContentUnavailableView("today.empty", systemImage: "book.closed")
                        .kokenBackground()
                        .navigationTitle("tab.today")
                }
            }
            .navigationDestination(for: Word.self) { WordDetailView(word: $0) }
        }
    }
}
