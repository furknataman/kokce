import Foundation

/// `koken://word/<id>` bağlantıları. Kelime kimlikleri Türkçe harf içerir,
/// bu yüzden kodlama tek yerde yapılır.
public enum DeepLink {
    public static let scheme = "koken"
    public static let wordHost = "word"

    public static func url(wordID: String) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = wordHost
        components.path = "/" + wordID
        return components.url
    }

    /// Bağlantıdaki kelime kimliği; başka bir bağlantıysa `nil`.
    public static func wordID(from url: URL) -> String? {
        guard url.scheme == scheme, url.host == wordHost else { return nil }
        let id = url.pathComponents.dropFirst().joined(separator: "/")
        return id.isEmpty ? nil : id
    }
}
