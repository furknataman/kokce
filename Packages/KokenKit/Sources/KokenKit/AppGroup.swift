import Foundation

/// Uygulama ve widget'ın paylaştığı App Group.
public enum AppGroup {
    public static let identifier = "group.com.solvy.kokce"

    public static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    /// Uzaktan indirilen kataloğun yazıldığı dosya. Tek yazıcı uygulamadır.
    public static var cacheURL: URL? {
        containerURL?.appendingPathComponent("words.json")
    }

    public static var defaults: UserDefaults? {
        UserDefaults(suiteName: identifier)
    }

    /// Gömülü katalog. Uygulamada uygulamanın, widget'ta uzantının bundle'ı —
    /// ikisine de aynı dosya kopyalanır, bu yüzden widget uygulama hiç
    /// açılmadan çalışır.
    public static func bundledCatalogURL(in bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: "words", withExtension: "json")
    }
}
