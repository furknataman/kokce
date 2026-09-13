import Foundation

/// Uygulama ve widget'ın paylaştığı App Group.
public enum AppGroup {
    public static let identifier = "group.com.solvy.kokce"

    public static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    /// Uzaktan indirilen kataloğun yazıldığı dosya. Tek yazıcı uygulamadır.
    ///
    // ponytail: İmzasız simülatör derlemesinde App Group konteyneri hiç
    // oluşmaz ve konteyner nil dönerse uzaktan güncelleme kod yolu hiç
    // çalışmaz. Böyle bir durumda Application Support altına düşülür:
    // uygulama ve widget ayrı dizin görür, yani paylaşım kaybolur — ama akış
    // çalışır ve elle test edilebilir. İmzalı derlemede daima grup kullanılır.
    public static var cacheURL: URL? {
        if let containerURL { return containerURL.appendingPathComponent("words.json") }
        return fallbackDirectory?.appendingPathComponent("words.json")
    }

    /// Grup konteyneri yokken kullanılan yerel dizin.
    static var fallbackDirectory: URL? {
        try? FileManager.default.url(for: .applicationSupportDirectory,
                                     in: .userDomainMask,
                                     appropriateFor: nil,
                                     create: true)
            .appendingPathComponent("Kokce", isDirectory: true)
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
