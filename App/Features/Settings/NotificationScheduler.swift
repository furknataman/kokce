import Foundation
import UserNotifications
import KokenKit

/// Günlük bildirimleri planlar.
///
/// İleriye dönük 30 istek kurulur: iOS aynı anda en fazla 64 bekleyen bildirim
/// tutar ve kabul edilen sınır, uygulama 30 gün hiç açılmazsa bildirimlerin
/// durmasıdır. Kısmi güncelleme yoktur — saat, kip veya katalog değişince eski
/// istekler geçersizdir, hepsi silinip baştan kurulur.
@MainActor
final class NotificationScheduler {

    /// Aynı anda bekletilen bildirim sayısı.
    static let pendingLimit = 30
    /// Kaç gün ileriye bakılacağı. Bugünün saati geçmişse bir gün fazladan
    /// bakılır, böylece kullanıcıda her zaman 30 bekleyen bildirim olur.
    private static let lookahead = 31

    private let center = UNUserNotificationCenter.current()

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// İzin sistem ayarlarından geri alınmış olabilir; planlamadan önce bakılır.
    func isAuthorized() async -> Bool {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: true
        default: false
        }
    }

    func cancelAll() {
        center.removeAllPendingNotificationRequests()
    }

    /// Bekleyen kaç bildirim var? Doğrulama ve teşhis için.
    func pendingCount() async -> Int {
        await center.pendingNotificationRequests().count
    }

    /// Bekleyenleri silip önümüzdeki günleri baştan planlar.
    func reschedule(catalog: WordCatalog,
                    mode: WordOfDayMode,
                    hour: Int,
                    minute: Int,
                    now: Date = .now) async {
        center.removeAllPendingNotificationRequests()

        // Bildirim saati CİHAZIN yerel saatine göre kurulur: kullanıcı nerede
        // olursa olsun seçtiği saatte çalar. Hangi kelimenin düşeceği ayrı bir
        // sorudur ve `WordOfDay` içinde İstanbul gününe göre yanıtlanır, yani
        // takvim saat diliminden etkilenmez.
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        var scheduled = 0

        for offset in 0..<Self.lookahead where scheduled < Self.pendingLimit {
            // Uzun döngü sırasında iş iptal edilmiş olabilir; yarım kuyruk
            // bırakmamak için her adımda bakılır.
            if Task.isCancelled { return }
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let fire = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day),
                  // Bugünün saati geçtiyse o gün atlanır.
                  fire > now,
                  // Kelime, bildirimin çalacağı ana karşılık gelen İstanbul
                  // gününden okunur.
                  let word = WordOfDay.word(for: fire, in: catalog, mode: mode) else { continue }

            let request = UNNotificationRequest(identifier: Self.identifier(for: fire, calendar: calendar),
                                                content: content(for: word),
                                                trigger: Self.trigger(at: fire, calendar: calendar))
            try? await center.add(request)
            scheduled += 1
        }
    }

    private func content(for word: Word) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = String(format: String(localized: "notification.title"), word.word)
        content.body = word.shortMeaning
        content.sound = .default
        content.userInfo = ["wordId": word.id]
        return content
    }

    /// `wod-YYYY-MM-DD` — bildirimin çalacağı yerel gün. Biçimlendirici yerine
    /// elle kurulur: yerel ayardan ve takvim seçiminden etkilenmez.
    private static func identifier(for day: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "wod-%04d-%02d-%02d",
                      parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Saat dilimi bilinçli olarak boş bırakılır: bileşenler cihazın o anki
    /// takvimine göre yorumlanır, böylece kullanıcı saat dilimi değiştirse de
    /// bildirim yine seçtiği yerel saatte çalar.
    private static func trigger(at date: Date, calendar: Calendar) -> UNCalendarNotificationTrigger {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
    }
}
