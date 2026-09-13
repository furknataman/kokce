import Foundation
import KokenKit

/// Uygulamaya dışarıdan giriş: `kokce://word/<id>` bağlantısı ve bildirime
/// dokunma. İkisi de aynı yolu kullanır — katalog henüz yüklenmemişse kimlik
/// bekletilir, yükleme bitince çözülür.
extension AppModel {


    /// Bildirimden gelen kimlik. Deep link ile aynı yolu kullanır: katalog
    /// henüz yoksa kimlik bekletilir.
    func openWord(id: String) {
        guard catalog != nil else {
            pendingWordID = id
            return
        }
        show(id: id)
    }

    /// `kokce://word/<id>` — bilinmeyen kimlik Bugün sekmesine düşer.
    func open(_ url: URL) {
        guard let id = DeepLink.wordID(from: url) else {
            fallBackToToday()
            return
        }
        // Soğuk açılışta katalog henüz yüklenmemiş olabilir. Kimlik atılmaz;
        // `load()` bitince çözülür ve sekme o zaman değişir.
        guard catalog != nil else {
            pendingWordID = id
            return
        }
        show(id: id)
    }

    func resolvePendingDeepLink() {
        guard let id = pendingWordID else { return }
        pendingWordID = nil
        show(id: id)
    }

    /// Açılan madde filtrelenmiş bir listenin ardında kalmasın diye arama ve
    /// filtreler temizlenir.
    func show(id: String) {
        guard let word = catalog?.word(id: id) else {
            fallBackToToday()
            return
        }
        searchText = ""
        originFilter = nil
        showFavoritesOnly = false
        dictionaryPath = [word]
        selectedTab = .dictionary
    }

    func fallBackToToday() {
        pendingWordID = nil
        dictionaryPath = []
        selectedTab = .today
    }
}
