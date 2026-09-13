import Foundation

/// Favori kelime kimlikleri; App Group `UserDefaults` içinde `[String]`.
///
/// `UserDefaults` iş parçacığı güvenlidir ama SDK'da `Sendable` işaretli
/// değildir; işaretleme bu yüzden elle yapılır.
public struct FavoritesStore: @unchecked Sendable {

    public static let key = "favorites.ids"

    private let defaults: UserDefaults?

    public init(defaults: UserDefaults? = AppGroup.defaults) {
        self.defaults = defaults
    }

    public var ids: [String] {
        defaults?.stringArray(forKey: Self.key) ?? []
    }

    public func contains(_ id: String) -> Bool {
        ids.contains(id)
    }

    /// Favoriyi ters çevirir ve yeni durumu döndürür.
    @discardableResult
    public func toggle(_ id: String) -> Bool {
        var current = ids
        if let index = current.firstIndex(of: id) {
            current.remove(at: index)
            defaults?.set(current, forKey: Self.key)
            return false
        }
        current.append(id)
        defaults?.set(current, forKey: Self.key)
        return true
    }
}
