import Foundation
import Testing
import KokenKit

@Suite("Günün kelimesi")
struct WordOfDayTests {

    @Test("Başlangıç gününden itibaren sırayla ilerler")
    func walksTheSchedule() {
        let schedule = Schedule(start: "2026-10-01", ids: ["kalem", "pencere", "çay"])
        #expect(WordOfDay.id(for: Fixtures.date("2026-10-01"), schedule: schedule) == "kalem")
        #expect(WordOfDay.id(for: Fixtures.date("2026-10-02"), schedule: schedule) == "pencere")
        #expect(WordOfDay.id(for: Fixtures.date("2026-10-03"), schedule: schedule) == "çay")
        #expect(WordOfDay.id(for: Fixtures.date("2026-10-04"), schedule: schedule) == "kalem")
    }

    /// Aynı **an**, cihazın saat dilimi ne olursa olsun aynı kelimeyi vermeli.
    /// `WordOfDay` hiçbir yerde `TimeZone.current` okumadığı için hesaplama
    /// yalnızca mutlak zamana bağlıdır: 21:30 UTC, İstanbul'da ertesi gündür.
    @Test("Saat dilimi ne olursa olsun aynı sonuç")
    func isTimeZoneIndependent() {
        let schedule = Schedule(start: "2026-10-01", ids: ["kalem", "pencere", "çay"])
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!

        // 2 Ekim 20:30 UTC → İstanbul'da hâlâ 2 Ekim (23:30).
        let lateOnSecond = utc.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 20, minute: 30))!
        // 2 Ekim 21:30 UTC → İstanbul'da 3 Ekim (00:30).
        let earlyOnThird = utc.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 21, minute: 30))!

        #expect(WordOfDay.id(for: lateOnSecond, schedule: schedule) == "pencere")
        #expect(WordOfDay.id(for: earlyOnThird, schedule: schedule) == "çay")
    }

    @Test("ids sonuna ekleme geçmiş günleri değiştirmez")
    func appendingKeepsPastDays() {
        let before = Schedule(start: "2026-10-01", ids: ["kalem", "pencere", "çay"])
        let after = Schedule(start: "2026-10-01", ids: ["kalem", "pencere", "çay", "yelken", "defter"])
        for offset in 0..<3 {
            let day = Fixtures.date("2026-10-0\(offset + 1)")
            #expect(WordOfDay.id(for: day, schedule: before) == WordOfDay.id(for: day, schedule: after))
        }
    }

    /// Başlangıçtan önceki günler ilk kelimeye sabitlenir. Negatif mod yerine
    /// kırpma seçildi: hem çökmez hem de `ids` büyüdükçe sonuç kaymaz.
    @Test("Başlangıçtan önceki gün ilk kelimeyi verir")
    func clampsBeforeStart() {
        let before = Schedule(start: "2026-10-01", ids: ["kalem", "pencere", "çay"])
        let after = Schedule(start: "2026-10-01", ids: ["kalem", "pencere", "çay", "yelken"])
        let day = Fixtures.date("2026-09-13")
        #expect(WordOfDay.id(for: day, schedule: before) == "kalem")
        #expect(WordOfDay.id(for: day, schedule: after) == "kalem")
    }

    @Test("Boş takvim nil döner")
    func emptyScheduleIsNil() {
        #expect(WordOfDay.id(for: .now, schedule: Schedule(start: "2026-10-01", ids: [])) == nil)
        #expect(WordOfDay.id(for: .now, schedule: Schedule(start: "bozuk", ids: ["kalem"])) == nil)
    }

    @Test("Widget için 7 günlük çizelge üretilir")
    func producesUpcomingDays() throws {
        let catalog = try CatalogLoader.decode(Fixtures.catalogData)
        let days = WordOfDay.upcoming(from: Fixtures.date("2026-10-01"), count: 7, in: catalog)
        #expect(days.count == 7)
        #expect(days[0].word.id == "kalem")
        #expect(days[1].word.id == "şarkı")
        #expect(days[2].word.id == "kalem")
    }
}
