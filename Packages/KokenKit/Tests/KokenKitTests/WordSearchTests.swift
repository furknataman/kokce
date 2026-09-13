import Foundation
import Testing
import KokenKit

@Suite("Arama")
struct WordSearchTests {

    @Test("Türkçe I/ı/İ/i ayrımına takılmaz")
    func handlesTurkishDottedI() {
        let word = Fixtures.word(id: "ışık", word: "ışık")
        #expect(WordSearch.matches(word, query: "ışık"))
        #expect(WordSearch.matches(word, query: "isik"))
        #expect(WordSearch.matches(word, query: "IŞIK"))
        #expect(WordSearch.matches(word, query: "İSİK"))
    }

    @Test("Aksan duyarsızdır")
    func ignoresDiacritics() {
        let word = Fixtures.word(id: "şarkı", word: "şarkı")
        #expect(WordSearch.matches(word, query: "sarki"))
        #expect(WordSearch.matches(word, query: "şarkı"))
        #expect(WordSearch.matches(word, query: "SARKI"))
        #expect(WordSearch.matches(word, query: "çay") == false)
    }

    @Test("Boş sorgu her kelimeyi geçirir")
    func emptyQueryMatchesAll() {
        #expect(WordSearch.matches(Fixtures.word(id: "kalem"), query: "   "))
    }

    /// Eskiden zincirdeki yabancı biçimler de aranıyordu; arama bu yüzden
    /// alakasız maddeler getiriyordu. Artık yalnızca kelimenin kendisi,
    /// akrabaları ve kısa anlamdaki tam kelimeler aranır.
    @Test("Zincirdeki yabancı biçimler aranmaz")
    func ignoresChainForms() throws {
        let catalog = try CatalogLoader.decode(Fixtures.catalogData)
        #expect(WordSearch.filter(catalog.words, query: "qalam").isEmpty)
    }

    @Test("Eşleşme kelime başından olur")
    func matchesOnlyFromTheStart() {
        let kalem = Fixtures.word(id: "kalem", word: "kalem")
        #expect(WordSearch.matches(kalem, query: "kal"))
        #expect(WordSearch.matches(kalem, query: "kalem"))
        // Ortadan eşleşme yok: "lem" kalem'i getirmemeli.
        #expect(WordSearch.matches(kalem, query: "lem") == false)
    }

    /// Asıl şikâyet: "Kal" araması kalp, nabız, sandalye gibi maddeleri
    /// listeliyordu; ikisi de yalnızca anlam metninde "Kalbin" geçtiği için.
    @Test("Anlam içinde parça eşleşmesi yok")
    func ignoresPartialMeaningMatches() {
        let nabiz = Word(id: "nabız", word: "nabız", partOfSpeech: "isim",
                         formationType: .borrowed, donorLanguage: "ar", ultimateOrigin: "ar",
                         chain: [ChainStep(language: "tr", form: "nabız", meaning: "vuru",
                                           period: nil, reconstructed: false)],
                         shortMeaning: "Kalbin çalışmasıyla atardamarlarda hissedilen vuru.",
                         currentMeaning: "Kalp atışının damardaki yansıması.",
                         story: "Hikâye.", firstAttestation: nil, relatives: [],
                         alternatives: nil, funFact: nil,
                         sources: [Source(name: "Nişanyan Sözlük", ref: nil, url: nil)],
                         confidence: .high, reviewed: true)
        #expect(WordSearch.matches(nabiz, query: "kal") == false)
        // Tam kelime geçerse eşleşir.
        #expect(WordSearch.matches(nabiz, query: "kalbin"))
        #expect(WordSearch.matches(nabiz, query: "vuru"))
    }

    @Test("Akraba kelimeler de aranır")
    func matchesRelatives() {
        let kalem = Word(id: "kalem", word: "kalem", partOfSpeech: "isim",
                         formationType: .borrowed, donorLanguage: "ar", ultimateOrigin: "grc",
                         chain: [ChainStep(language: "tr", form: "kalem", meaning: "yazı aracı",
                                           period: nil, reconstructed: false)],
                         shortMeaning: "Yazı aracı.", currentMeaning: "Yazı aracı.",
                         story: "Hikâye.", firstAttestation: nil,
                         relatives: [Relative(word: "kalemtıraş", relation: "birleşik")],
                         alternatives: nil, funFact: nil,
                         sources: [Source(name: "Nişanyan Sözlük", ref: nil, url: nil)],
                         confidence: .high, reviewed: true)
        #expect(WordSearch.matches(kalem, query: "kalemtıraş"))
        #expect(WordSearch.matches(kalem, query: "kalemti"))
    }

    @Test("Köken dili filtresi ve favoriler birlikte çalışır")
    func filtersByOriginAndFavorites() {
        let words = [
            Fixtures.word(id: "kalem", donorLanguage: "ar"),
            Fixtures.word(id: "pencere", donorLanguage: "fa"),
            Fixtures.word(id: "çay", donorLanguage: "fa")
        ]
        #expect(WordSearch.filter(words, originLanguage: "fa").map(\.id) == ["pencere", "çay"])
        #expect(WordSearch.filter(words, originLanguage: "fa", favoriteIDs: ["çay"]).map(\.id) == ["çay"])
    }
}

@Suite("Deep link")
struct DeepLinkTests {

    @Test("Türkçe harfli kimlik kodlanır ve geri çözülür")
    func roundTripsTurkishID() throws {
        let url = try #require(DeepLink.url(wordID: "çay"))
        #expect(url.absoluteString == "kokce://word/%C3%A7ay")
        #expect(DeepLink.wordID(from: url) == "çay")
    }

    @Test("Başka bağlantılar yok sayılır")
    func ignoresOtherLinks() throws {
        #expect(DeepLink.wordID(from: URL(string: "kokce://ayarlar")!) == nil)
        #expect(DeepLink.wordID(from: URL(string: "https://solvy.app/word/kalem")!) == nil)
        #expect(DeepLink.wordID(from: URL(string: "kokce://word/")!) == nil)
    }
}
