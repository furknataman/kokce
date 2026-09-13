import Foundation
import KokenKit

/// Test verisi. Kaynak dosyası olarak paketlenmez: gömülü kaynak `Bundle.module`
/// gerektirir ve testlerin ileride bir Xcode hedefine taşınmasını zorlaştırır.
enum Fixtures {

    /// Elle yazılmış, gerçek şemayı birebir izleyen JSON.
    static let catalogJSON = """
    {
      "schemaVersion": 1,
      "contentVersion": 1,
      "schedule": { "start": "2026-10-01", "ids": ["kalem", "şarkı"] },
      "languages": { "ar": "Arapça", "grc": "Eski Yunanca", "tr": "Türkçe" },
      "words": [
        {
          "id": "kalem",
          "word": "kalem",
          "partOfSpeech": "isim",
          "formationType": "alıntı",
          "donorLanguage": "ar",
          "ultimateOrigin": "grc",
          "chain": [
            { "language": "grc", "form": "kálamos", "meaning": "kamış", "period": null, "reconstructed": false },
            { "language": "ar", "form": "qalam", "meaning": "kamış kalem", "period": null, "reconstructed": false },
            { "language": "tr", "form": "kalem", "meaning": "yazı aracı", "period": "13. yy", "reconstructed": false }
          ],
          "shortMeaning": "Yazı yazma aracı.",
          "currentMeaning": "Yazı yazmaya yarayan araç.",
          "story": "Kamıştan kaleme uzanan bir yolculuk.",
          "firstAttestation": { "source": "Kutadgu Bilig", "period": "11. yy", "form": "kalem" },
          "relatives": [{ "word": "kalemtıraş", "relation": "birleşik" }],
          "alternatives": null,
          "funFact": null,
          "sources": [{ "name": "Nişanyan Sözlük", "ref": "kalem maddesi", "url": "https://www.nisanyansozluk.com/" }],
          "confidence": "yüksek",
          "reviewed": true
        },
        {
          "id": "şarkı",
          "word": "şarkı",
          "partOfSpeech": "isim",
          "formationType": "alıntı",
          "donorLanguage": "ar",
          "ultimateOrigin": "ar",
          "chain": [
            { "language": "ar", "form": "şarḳī", "meaning": "doğuya ait", "period": null, "reconstructed": false },
            { "language": "tr", "form": "şarkı", "meaning": "besteli söz", "period": null, "reconstructed": false }
          ],
          "shortMeaning": "Besteli söz, ezgi.",
          "currentMeaning": "Söz ve ezgiden oluşan müzik parçası.",
          "story": "Doğuya ait olan, doğunun ezgisi oldu.",
          "firstAttestation": null,
          "relatives": [],
          "alternatives": null,
          "funFact": null,
          "sources": [{ "name": "Nişanyan Sözlük", "ref": "şarkı maddesi", "url": null }],
          "confidence": "orta",
          "reviewed": true
        }
      ]
    }
    """

    static let catalogData = Data(catalogJSON.utf8)

    static func word(id: String,
                     word: String? = nil,
                     donorLanguage: String? = "ar",
                     rarity: String? = nil) -> Word {
        Word(id: id,
             word: word ?? id,
             partOfSpeech: "isim",
             formationType: .borrowed,
             donorLanguage: donorLanguage,
             ultimateOrigin: donorLanguage,
             chain: [ChainStep(language: "tr", form: word ?? id, meaning: "anlam", period: nil, reconstructed: false)],
             shortMeaning: "Kısa anlam.",
             currentMeaning: "Güncel anlam.",
             story: "Hikâye.",
             firstAttestation: nil,
             relatives: [],
             alternatives: nil,
             funFact: nil,
             sources: [Source(name: "Nişanyan Sözlük", ref: nil, url: nil)],
             confidence: .high,
             reviewed: true,
             rarity: rarity)
    }

    static func catalog(contentVersion: Int = 1,
                        ids: [String] = ["kalem", "pencere", "çay"],
                        start: String = "2026-10-01",
                        rarities: [String: String] = [:]) -> WordCatalog {
        WordCatalog(schemaVersion: 1,
                    contentVersion: contentVersion,
                    schedule: Schedule(start: start, ids: ids),
                    languages: ["ar": "Arapça", "tr": "Türkçe"],
                    words: ids.map { word(id: $0, rarity: rarities[$0]) })
    }

    static func encoded(_ catalog: WordCatalog) -> Data {
        (try? JSONEncoder().encode(catalog)) ?? Data()
    }

    /// Europe/Istanbul saatiyle verilen günün öğle vakti.
    static func date(_ text: String) -> Date {
        var components = DateComponents()
        let parts = text.split(separator: "-").compactMap { Int($0) }
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        components.hour = 12
        return WordOfDay.calendar.date(from: components)!
    }
}
