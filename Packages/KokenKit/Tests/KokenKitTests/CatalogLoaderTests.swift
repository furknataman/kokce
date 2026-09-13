import Foundation
import Testing
import KokenKit

@Suite("Katalog çözümü")
struct CatalogLoaderTests {

    @Test("Örnek JSON şemaya uygun çözülür")
    func decodesFixture() throws {
        let catalog = try CatalogLoader.decode(Fixtures.catalogData)
        #expect(catalog.schemaVersion == 1)
        #expect(catalog.words.count == 2)
        #expect(catalog.languageName("grc") == "Eski Yunanca")

        let kalem = try #require(catalog.word(id: "kalem"))
        #expect(kalem.formationType == .borrowed)
        #expect(kalem.confidence == .high)
        #expect(kalem.chain.count == 3)
        #expect(kalem.chain.last?.language == "tr")
        #expect(kalem.firstAttestation?.source == "Kutadgu Bilig")
        #expect(kalem.relatives.first?.relation == "birleşik")
        #expect(kalem.alternatives == nil)
        #expect(kalem.originLanguage == "ar")

        let sarki = try #require(catalog.word(id: "şarkı"))
        #expect(sarki.word == "şarkı")
        #expect(sarki.sources.first?.url == nil)
    }

    @Test("Takvimde katalogda olmayan kimlik varsa reddedilir")
    func rejectsUnknownScheduleID() {
        let broken = WordCatalog(schemaVersion: 1,
                                 contentVersion: 1,
                                 schedule: Schedule(start: "2026-10-01", ids: ["yok"]),
                                 languages: [:],
                                 words: [Fixtures.word(id: "kalem")])
        #expect(throws: CatalogLoader.LoadError.unknownScheduleID("yok")) {
            try CatalogLoader.validate(broken)
        }
    }

    @Test("Desteklenmeyen şema sürümü reddedilir")
    func rejectsUnsupportedSchema() {
        let future = WordCatalog(schemaVersion: 2,
                                 contentVersion: 1,
                                 schedule: Schedule(start: "2026-10-01", ids: ["kalem"]),
                                 languages: [:],
                                 words: [Fixtures.word(id: "kalem")])
        #expect(throws: CatalogLoader.LoadError.unsupportedSchema(2)) {
            try CatalogLoader.validate(future)
        }
    }
}
