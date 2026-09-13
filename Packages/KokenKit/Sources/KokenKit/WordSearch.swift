import Foundation

/// Türkçeye duyarlı arama ve köken dili filtresi.
public enum WordSearch {

    private static let turkish = Locale(identifier: "tr_TR")

    /// Aramada karşılaştırılan biçim: Türkçe küçük harf, aksansız, `ı`/`i` eşit.
    ///
    /// Sıra önemlidir. Önce Türkçe kurallarıyla küçültülür (`I` → `ı`,
    /// `İ` → `i`); tersi yapılırsa `İ` önce `I`'ya katlanıp sonra `ı` olur.
    /// Ardından aksan katlaması yapılır (`ş` → `s`, `ğ` → `g`). `ı` harfinin
    /// Unicode ayrışması olmadığı için katlama onu `i`'ye çevirmez; bu eşleme
    /// elle yapılır, böylece "sarki" araması "şarkı"yı bulur.
    public static func normalized(_ text: String) -> String {
        let lowercased = text.lowercased(with: turkish)
        let folded = lowercased.folding(options: [.diacriticInsensitive, .widthInsensitive],
                                        locale: turkish)
        return folded.replacingOccurrences(of: "ı", with: "i")
            .replacingOccurrences(of: "İ", with: "i")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Kelime sorguyla eşleşiyor mu?
    ///
    /// Üç kural var: kelimenin kendisi sorguyla **başlıyorsa**, akraba
    /// kelimelerden biri sorguyla başlıyorsa ya da kısa anlamda sorgu **tam
    /// kelime** olarak geçiyorsa eşleşir.
    ///
    /// Anlam içinde parça arama ve zincirdeki yabancı biçimler bilerek
    /// dışarıda: ikisi de "kal" aramasına "sandalye", "nabız", "akıl" gibi
    /// alakasız maddeleri sokuyordu. Kullanıcı kelimeyi baştan yazar.
    public static func matches(_ word: Word, query: String) -> Bool {
        let needle = normalized(query)
        guard !needle.isEmpty else { return true }
        if normalized(word.word).hasPrefix(needle) { return true }
        if word.relatives.contains(where: { normalized($0.word).hasPrefix(needle) }) { return true }
        return words(in: word.shortMeaning).contains(needle)
    }

    /// Metni arama biçimine getirip kelimelere ayırır.
    static func words(in text: String) -> [String] {
        normalized(text)
            .split { !($0.isLetter || $0.isNumber) }
            .map(String.init)
    }

    /// Arama ve köken dili filtresini birlikte uygular; sıralama korunur.
    ///
    /// - Parameters:
    ///   - originLanguage: Dil kimliği (`"ar"`); `nil` ise filtre yok.
    ///   - favoriteIDs: Verilirse yalnızca bu kimlikler kalır.
    public static func filter(_ words: [Word],
                              query: String = "",
                              originLanguage: String? = nil,
                              favoriteIDs: Set<String>? = nil) -> [Word] {
        words.filter { word in
            if let originLanguage, word.originLanguage != originLanguage { return false }
            if let favoriteIDs, !favoriteIDs.contains(word.id) { return false }
            return matches(word, query: query)
        }
    }

    /// Katalogda geçen köken dilleri, Türkçe adlarına göre sıralı.
    public static func originLanguages(in catalog: WordCatalog) -> [(code: String, name: String)] {
        let codes = Set(catalog.words.compactMap(\.originLanguage))
        return codes
            .map { (code: $0, name: catalog.languageName($0)) }
            .sorted { $0.name.compare($1.name, options: [], range: nil, locale: turkish) == .orderedAscending }
    }
}
