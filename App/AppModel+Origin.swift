import Foundation
import KokenKit

/// Köken yolunun metne dönüşmesi. Rozet, liste satırı ve paylaşım metni aynı
/// yolu kullanır, bu yüzden kural tek yerde durur.
extension AppModel {

    /// Köken yolu, **eskiden yeniye**: zincirin en eski dili → kelimeyi
    /// aktaran dil → Türkçe.
    ///
    /// Okuma yönü kasıtlı olarak kronolojiktir; ok kelimenin gittiği yönü
    /// gösterir. Aynı dil arka arkaya gelirse ("Farsça → Farsça") bir kez
    /// yazılır. `Word.originLanguage` iki alanı tek koda indirgediği için
    /// burada alanlar ayrı ayrı okunur.
    func originPath(for word: Word) -> [String] {
        var codes: [String] = []
        if let ultimate = word.ultimateOrigin { codes.append(ultimate) }
        if let donor = word.donorLanguage { codes.append(donor) }
        if codes.isEmpty, let fallback = word.originLanguage { codes.append(fallback) }
        codes.append("tr")

        var path: [String] = []
        for code in codes where path.last != code {
            path.append(code)
        }
        return path.compactMap { languageName($0) }
    }

    /// Rozet ve paylaşım metni için tek satırlık köken yolu.
    func originText(for word: Word) -> String? {
        let path = originPath(for: word)
        return path.isEmpty ? nil : path.joined(separator: " → ")
    }

    /// Paylaşılan düz metin. Biçim dizesi katalogdan gelir, metin kaynak
    /// dosyada değil `Localizable.xcstrings` içinde durur.
    func shareText(for word: Word) -> String {
        guard let origin = originText(for: word) else {
            return String(format: String(localized: "share.format.plain"), word.word, word.shortMeaning)
        }
        return String(format: String(localized: "share.format"), word.word, word.shortMeaning, origin)
    }
}
