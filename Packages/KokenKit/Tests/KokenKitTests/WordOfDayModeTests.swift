import Foundation
import Testing
import KokenKit

@Suite("Günün kelimesi kipi")
struct WordOfDayModeTests {

    /// kalem ve çay gündelik, pencere ve yelken az bilinen.
    private var catalog: WordCatalog {
        Fixtures.catalog(ids: ["kalem", "pencere", "çay", "yelken"],
                         rarities: ["pencere": Word.rarityRare, "yelken": Word.rarityRare])
    }

    @Test("Kip havuzu süzer")
    func filtersPool() {
        #expect(WordOfDay.scheduledIDs(mode: .mixed, in: catalog) == ["kalem", "pencere", "çay", "yelken"])
        #expect(WordOfDay.scheduledIDs(mode: .everyday, in: catalog) == ["kalem", "çay"])
        #expect(WordOfDay.scheduledIDs(mode: .rare, in: catalog) == ["pencere", "yelken"])
    }

    @Test("Aynı gün, kipe göre farklı kelime")
    func modeChangesTheWord() {
        let day = Fixtures.date("2026-10-02")
        #expect(WordOfDay.id(for: day, in: catalog, mode: .mixed) == "pencere")
        #expect(WordOfDay.id(for: day, in: catalog, mode: .everyday) == "çay")
        #expect(WordOfDay.id(for: day, in: catalog, mode: .rare) == "yelken")
    }

    /// Kip sabitken sonuç yalnızca mutlak zamana bağlıdır; cihazın saat dilimi
    /// hesaba hiç girmez.
    @Test("Aynı kip her cihazda aynı kelimeyi verir")
    func sameModeIsTimeZoneIndependent() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        // İkisi de İstanbul'da 3 Ekim: 00:30 ve 23:00.
        let earlyOnThird = utc.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 21, minute: 30))!
        let lateOnThird = utc.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: 20, minute: 0))!

        for mode in WordOfDayMode.allCases {
            #expect(WordOfDay.id(for: earlyOnThird, in: catalog, mode: mode)
                    == WordOfDay.id(for: lateOnThird, in: catalog, mode: mode))
        }
    }

    @Test("rarity yoksa kelime gündelik sayılır")
    func missingRarityIsEveryday() {
        let plain = Fixtures.catalog(ids: ["kalem", "pencere"])
        #expect(plain.word(id: "kalem")?.rarity == nil)
        #expect(plain.word(id: "kalem")?.isRare == false)
        #expect(WordOfDay.scheduledIDs(mode: .everyday, in: plain) == ["kalem", "pencere"])
    }

    @Test("Süzgeç boş kalırsa tüm takvime düşülür")
    func fallsBackWhenPoolIsEmpty() {
        let everydayOnly = Fixtures.catalog(ids: ["kalem", "pencere"])
        #expect(WordOfDay.scheduledIDs(mode: .rare, in: everydayOnly) == ["kalem", "pencere"])
        #expect(WordOfDay.id(for: Fixtures.date("2026-10-01"), in: everydayOnly, mode: .rare) == "kalem")
    }

    @Test("Karışık kip takvimin kendisidir")
    func mixedMatchesSchedule() {
        let day = Fixtures.date("2026-10-05")
        #expect(WordOfDay.id(for: day, in: catalog, mode: .mixed)
                == WordOfDay.id(for: day, schedule: catalog.schedule))
    }

    @Test("Kip App Group bölmesinde saklanır")
    func persistsMode() throws {
        let suiteName = "koken.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { UserDefaults.standard.removeSuite(named: suiteName) }

        #expect(WordOfDayMode.current(defaults: defaults) == .mixed)
        WordOfDayMode.save(.rare, defaults: defaults)
        #expect(defaults.string(forKey: "wordOfDay.mode") == "rare")
        #expect(WordOfDayMode.current(defaults: defaults) == .rare)

        defaults.set("tanınmayan", forKey: WordOfDayMode.defaultsKey)
        #expect(WordOfDayMode.current(defaults: defaults) == .mixed)
    }

    @Test("Eski JSON'da rarity yoksa çözüm kırılmaz")
    func decodesCatalogWithoutRarity() throws {
        let catalog = try CatalogLoader.decode(Fixtures.catalogData)
        #expect(catalog.word(id: "kalem")?.rarity == nil)
    }

    @Test("rarity alanı JSON'dan okunur")
    func decodesRarity() throws {
        // Yalnızca kalem maddesinin güveni "yüksek"; alan oraya eklenir.
        let json = Fixtures.catalogJSON.replacingOccurrences(
            of: "\"confidence\": \"yüksek\"",
            with: "\"rarity\": \"az-bilinen\", \"confidence\": \"yüksek\"")
        let catalog = try CatalogLoader.decode(Data(json.utf8))
        #expect(catalog.word(id: "kalem")?.rarity == "az-bilinen")
        #expect(catalog.word(id: "kalem")?.isRare == true)
    }
}
