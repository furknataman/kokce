import Foundation

// Katalog şeması. `scripts/validate_words.py` ile birebir aynı kuralları
// tanımlar; alan eklenirse iki taraf da güncellenir.

/// Kelime kataloğunun tamamı: sürüm bilgisi, takvim, dil adları ve kelimeler.
public struct WordCatalog: Codable, Sendable, Equatable {
    /// Şema sürümü. Uygulama yalnızca `WordCatalog.supportedSchemaVersion` okur.
    public let schemaVersion: Int
    /// İçerik sürümü. Uzak dosya ancak bundle'dakinden büyükse kullanılır.
    public let contentVersion: Int
    public let schedule: Schedule
    /// Dil kimliği → Türkçe dil adı (`"ar"` → `"Arapça"`).
    public let languages: [String: String]
    public let words: [Word]

    public static let supportedSchemaVersion = 1

    public init(schemaVersion: Int,
                contentVersion: Int,
                schedule: Schedule,
                languages: [String: String],
                words: [Word]) {
        self.schemaVersion = schemaVersion
        self.contentVersion = contentVersion
        self.schedule = schedule
        self.languages = languages
        self.words = words
    }

    /// Kimliğe göre kelime. Deep link ve widget bunu kullanır.
    public func word(id: String) -> Word? {
        words.first { $0.id == id }
    }

    /// Dil kimliğinin okunabilir adı; tanımsızsa kimliğin kendisi.
    public func languageName(_ code: String) -> String {
        languages[code] ?? code
    }
}

/// Günün kelimesi takvimi. `ids` listesine yalnızca **sona** ekleme yapılır;
/// başa ekleme veya sıra değişimi geçmiş günlerin kelimesini kaydırır.
public struct Schedule: Codable, Sendable, Equatable {
    /// `"yyyy-MM-dd"` biçiminde başlangıç günü (Europe/Istanbul).
    public let start: String
    public let ids: [String]

    public init(start: String, ids: [String]) {
        self.start = start
        self.ids = ids
    }
}

public struct Word: Codable, Sendable, Equatable, Identifiable, Hashable {
    public let id: String
    public let word: String
    /// "isim", "sıfat", "fiil" …
    public let partOfSpeech: String
    public let formationType: FormationType
    /// Kelimenin Türkçeye doğrudan geçtiği dil (alıntıysa).
    public let donorLanguage: String?
    /// Zincirin en eski bilinen dili.
    public let ultimateOrigin: String?
    /// Kelimenin yolculuğu; son adım her zaman `tr`.
    public let chain: [ChainStep]
    public let shortMeaning: String
    public let currentMeaning: String
    /// 2-4 cümlelik hikâye.
    public let story: String
    public let firstAttestation: Attestation?
    public let relatives: [Relative]
    /// Kabul görmüş başka köken önerileri; yoksa `null`.
    public let alternatives: [String]?
    public let funFact: String?
    public let sources: [Source]
    public let confidence: Confidence
    public let reviewed: Bool
    /// "gündelik" veya "az-bilinen". Eski içerikte alan yoktur; `nil` gelir ve
    /// gündelik sayılır.
    public let rarity: String?

    public init(id: String,
                word: String,
                partOfSpeech: String,
                formationType: FormationType,
                donorLanguage: String?,
                ultimateOrigin: String?,
                chain: [ChainStep],
                shortMeaning: String,
                currentMeaning: String,
                story: String,
                firstAttestation: Attestation?,
                relatives: [Relative],
                alternatives: [String]?,
                funFact: String?,
                sources: [Source],
                confidence: Confidence,
                reviewed: Bool,
                rarity: String? = nil) {
        self.id = id
        self.word = word
        self.partOfSpeech = partOfSpeech
        self.formationType = formationType
        self.donorLanguage = donorLanguage
        self.ultimateOrigin = ultimateOrigin
        self.chain = chain
        self.shortMeaning = shortMeaning
        self.currentMeaning = currentMeaning
        self.story = story
        self.firstAttestation = firstAttestation
        self.relatives = relatives
        self.alternatives = alternatives
        self.funFact = funFact
        self.sources = sources
        self.confidence = confidence
        self.reviewed = reviewed
        self.rarity = rarity
    }

    public static let rarityEveryday = "gündelik"
    public static let rarityRare = "az-bilinen"

    /// Günün kelimesi kipinde ayırt edici olan tek soru.
    public var isRare: Bool { rarity == Self.rarityRare }

    /// Rozette ve filtre çiplerinde gösterilen köken dili.
    public var originLanguage: String? {
        donorLanguage ?? ultimateOrigin ?? chain.first?.language
    }
}

public enum FormationType: String, Codable, Sendable, CaseIterable {
    case borrowed = "alıntı"
    case derived = "türeme"
    case compound = "birleşik"
    case native = "öz"
    case onomatopoeic = "yansıma"
    case abbreviation = "kısaltma"
    case disputed = "tartışmalı"
}

public enum Confidence: String, Codable, Sendable, CaseIterable {
    case high = "yüksek"
    case medium = "orta"
    case low = "düşük"
}

/// Yolculuğun tek adımı: bir dildeki biçim ve anlam.
public struct ChainStep: Codable, Sendable, Equatable, Hashable {
    public let language: String
    public let form: String
    public let meaning: String
    /// "13. yy" gibi; bilinmiyorsa `null`.
    public let period: String?
    /// Biçim yeniden kurulmuşsa (`*` ile gösterilir) `true`.
    public let reconstructed: Bool

    public init(language: String, form: String, meaning: String, period: String?, reconstructed: Bool) {
        self.language = language
        self.form = form
        self.meaning = meaning
        self.period = period
        self.reconstructed = reconstructed
    }
}

/// İlk yazılı tanıklık. Bilinmiyorsa alan tümüyle `null` bırakılır, uydurulmaz.
public struct Attestation: Codable, Sendable, Equatable, Hashable {
    public let source: String
    public let period: String?
    public let form: String?

    public init(source: String, period: String?, form: String?) {
        self.source = source
        self.period = period
        self.form = form
    }
}

/// Akraba kelime ve ilişki türü ("birleşik", "türeme", "aynı kökten"…).
public struct Relative: Codable, Sendable, Equatable, Hashable {
    public let word: String
    public let relation: String

    public init(word: String, relation: String) {
        self.word = word
        self.relation = relation
    }
}

public struct Source: Codable, Sendable, Equatable, Hashable {
    public let name: String
    /// "kalem maddesi" gibi kaynak içi konum.
    public let ref: String?
    public let url: String?

    public init(name: String, ref: String?, url: String?) {
        self.name = name
        self.ref = ref
        self.url = url
    }
}
