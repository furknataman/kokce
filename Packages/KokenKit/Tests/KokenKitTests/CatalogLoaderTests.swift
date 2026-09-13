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

    /// İçerik hattı akrabası olmayan maddelerde `"relatives": null` yazıyor;
    /// tek bir madde yüzünden 500+ kelimelik katalog çözülmemezlik etmemeli.
    @Test("relatives null gelirse boş liste olur")
    func decodesNullRelatives() throws {
        let json = Fixtures.catalogJSON.replacingOccurrences(
            of: "\"relatives\": [{ \"word\": \"kalemtıraş\", \"relation\": \"birleşik\" }]",
            with: "\"relatives\": null")
        let catalog = try CatalogLoader.decode(Data(json.utf8))
        #expect(catalog.word(id: "kalem")?.relatives.isEmpty == true)
    }

    @Test("Bozuk schedule.start reddedilir")
    func rejectsInvalidScheduleStart() {
        for start in ["2026-2-1", "2026-02-30", "bugün", "2026-02", "20260201"] {
            let catalog = WordCatalog(schemaVersion: 1,
                                      contentVersion: 1,
                                      schedule: Schedule(start: start, ids: ["kalem"]),
                                      languages: [:],
                                      words: [Fixtures.word(id: "kalem")])
            #expect(throws: CatalogLoader.LoadError.invalidScheduleStart(start)) {
                try CatalogLoader.validate(catalog)
            }
        }
    }

    @Test("Boş ids reddedilir")
    func rejectsEmptySchedule() {
        let catalog = WordCatalog(schemaVersion: 1,
                                  contentVersion: 1,
                                  schedule: Schedule(start: "2026-10-01", ids: []),
                                  languages: [:],
                                  words: [Fixtures.word(id: "kalem")])
        #expect(throws: CatalogLoader.LoadError.empty) { try CatalogLoader.validate(catalog) }
    }

    /// Yükleyici widget'ta da koşar; dosya silmek tek yazıcının işidir.
    @Test("Bozuk önbellek yükleyicide silinmez")
    func loaderNeverDeletes() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("koken-loader-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let bundleURL = directory.appendingPathComponent("bundle.json")
        let cacheURL = directory.appendingPathComponent("cache.json")
        try Fixtures.encoded(Fixtures.catalog(contentVersion: 1)).write(to: bundleURL)
        try Data("{ bozuk".utf8).write(to: cacheURL)

        let result = try CatalogLoader.loadResult(bundleURL: bundleURL, cacheURL: cacheURL)
        #expect(result.cacheStatus == .invalid)
        #expect(result.catalog.contentVersion == 1)
        #expect(FileManager.default.fileExists(atPath: cacheURL.path))
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
