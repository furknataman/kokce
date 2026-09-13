import Foundation

/// Günün kelimesinin hangi havuzdan seçileceği. Uygulama yazar, widget okur;
/// ikisi de App Group `UserDefaults`'taki aynı anahtara bakar.
public enum WordOfDayMode: String, Sendable, CaseIterable, Codable {
    /// Takvimin tamamı (varsayılan).
    case mixed
    /// Yalnızca gündelik kelimeler. `rarity` yoksa kelime gündelik sayılır.
    case everyday
    /// Yalnızca az bilinen kelimeler.
    case rare

    public static let defaultsKey = "wordOfDay.mode"

    /// Kayıtlı kip; yazılmamışsa veya tanınmayan bir değerse `.mixed`.
    public static func current(defaults: UserDefaults? = AppGroup.defaults) -> WordOfDayMode {
        guard let raw = defaults?.string(forKey: defaultsKey),
              let mode = WordOfDayMode(rawValue: raw) else { return .mixed }
        return mode
    }

    public static func save(_ mode: WordOfDayMode, defaults: UserDefaults? = AppGroup.defaults) {
        defaults?.set(mode.rawValue, forKey: defaultsKey)
    }
}
