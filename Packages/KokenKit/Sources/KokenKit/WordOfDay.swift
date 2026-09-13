import Foundation

/// Günün kelimesini deterministik olarak hesaplar.
///
/// Uygulama ve widget bunu birbirinden bağımsız çağırır; aynı günde aynı
/// sonucu vermesi için takvim **gregoryen** ve saat dilimi **Europe/Istanbul**
/// olarak sabitlenmiştir. Gün farkı `dateComponents([.day])` ile alınır —
/// saniye/86400 bölmesi yaz saati ve artık saniye yüzünden kayar.
public enum WordOfDay {

    public static let timeZone = TimeZone(identifier: "Europe/Istanbul") ?? .gmt

    /// Hesaplamada kullanılan sabit takvim.
    public static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    /// `schedule.ids` içindeki sıra numarası; takvim okunamazsa `nil`.
    ///
    /// `start` gününden önceki tarihler ilk kelimeye sabitlenir: negatif mod
    /// yerine kırpma, `ids` sonuna ekleme yapıldığında geçmiş günlerin
    /// değişmemesini garanti eder.
    ///
    // ponytail: ids tükenince modulo ile başa sarar; 500 kelime ≈ 16 ay,
    // o süre içinde yeni kelime eklenerek sarma önlenir.
    public static func index(for date: Date, schedule: Schedule) -> Int? {
        guard !schedule.ids.isEmpty,
              let start = day(from: schedule.start) else { return nil }
        let calendar = calendar
        let from = calendar.startOfDay(for: start)
        let to = calendar.startOfDay(for: date)
        guard let difference = calendar.dateComponents([.day], from: from, to: to).day else { return nil }
        return max(0, difference) % schedule.ids.count
    }

    /// Verilen günün kelime kimliği.
    public static func id(for date: Date, schedule: Schedule) -> String? {
        guard let index = index(for: date, schedule: schedule) else { return nil }
        return schedule.ids[index]
    }

    /// Verilen günün kelimesi. Takvimdeki kimlik katalogda yoksa `nil`.
    public static func word(for date: Date, in catalog: WordCatalog) -> Word? {
        guard let id = id(for: date, schedule: catalog.schedule) else { return nil }
        return catalog.word(id: id)
    }

    /// Bugünden başlayarak `count` günün (tarih, kelime) çiftleri —
    /// widget zaman çizelgesi bunu kullanır.
    public static func upcoming(from date: Date, count: Int, in catalog: WordCatalog) -> [(date: Date, word: Word)] {
        let calendar = calendar
        let start = calendar.startOfDay(for: date)
        return (0..<max(0, count)).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start),
                  let word = word(for: day, in: catalog) else { return nil }
            return (day, word)
        }
    }

    /// `"yyyy-MM-dd"` → Europe/Istanbul gününün başlangıcı. Formatter yerine
    /// elle ayrıştırma: yerel ayardan ve takvim seçiminden etkilenmez.
    ///
    /// Biçim katıdır (4-2-2 rakam) ve tarih takvimde geri döndürülerek
    /// doğrulanır; "2026-02-30" gibi var olmayan günler `nil` döner.
    static func day(from text: String) -> Date? {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }),
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else { return nil }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        let calendar = calendar
        guard let date = calendar.date(from: components) else { return nil }
        // Takvim 31 Şubat'ı sessizce kaydırır; geri okuyup aynı günü doğrularız.
        let roundTrip = calendar.dateComponents([.year, .month, .day], from: date)
        guard roundTrip.year == year, roundTrip.month == month, roundTrip.day == day else { return nil }
        return date
    }
}
