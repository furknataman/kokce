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

    @Test("Zincirdeki biçimler de aranır")
    func searchesChainForms() throws {
        let catalog = try CatalogLoader.decode(Fixtures.catalogData)
        let found = WordSearch.filter(catalog.words, query: "qalam")
        #expect(found.map(\.id) == ["kalem"])
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
        #expect(url.absoluteString == "koken://word/%C3%A7ay")
        #expect(DeepLink.wordID(from: url) == "çay")
    }

    @Test("Başka bağlantılar yok sayılır")
    func ignoresOtherLinks() throws {
        #expect(DeepLink.wordID(from: URL(string: "koken://ayarlar")!) == nil)
        #expect(DeepLink.wordID(from: URL(string: "https://solvy.app/word/kalem")!) == nil)
        #expect(DeepLink.wordID(from: URL(string: "koken://word/")!) == nil)
    }
}
