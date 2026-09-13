import Foundation
import Observation
import KokenKit

/// Günlük bildirim tercihi ve planlaması.
///
/// Tercih yalnızca uygulamayı ilgilendirir — widget okumaz — bu yüzden App
/// Group değil standart bölme kullanılır. Planlamanın kendisi
/// `NotificationScheduler`'dadır; burada tercih, izin ve tetikleme durur.
@MainActor
@Observable
final class DailyNotifications {

    private static let enabledKey = "notifications.enabled"
    private static let hourKey = "notifications.hour"
    private static let minuteKey = "notifications.minute"

    private let scheduler = NotificationScheduler()
    private let preferences: UserDefaults

    private(set) var isEnabled = false
    private(set) var hour = 9
    private(set) var minute = 0
    /// İzin reddedildiyse Ayarlar, sistem ayarlarına götüren bir satır gösterir.
    private(set) var isDenied = false

    init(preferences: UserDefaults = .standard) {
        self.preferences = preferences
        isEnabled = preferences.bool(forKey: Self.enabledKey)
        // Hiç yazılmamışsa varsayılan 09:00 kalır; `integer(forKey:)` yazılmamış
        // anahtar için 0 döndürür ve saat gece yarısına kayardı.
        if preferences.object(forKey: Self.hourKey) != nil {
            hour = preferences.integer(forKey: Self.hourKey)
            minute = preferences.integer(forKey: Self.minuteKey)
        }
    }

    /// Toggle'ın karşılığı. Açılırken izin istenir; kullanıcı reddederse ayar
    /// açık kalmaz ve `isDenied` ile sistem ayarları satırı çıkar.
    func setEnabled(_ enabled: Bool, catalog: WordCatalog?, mode: WordOfDayMode) async {
        guard enabled else {
            isEnabled = false
            isDenied = false
            preferences.set(false, forKey: Self.enabledKey)
            scheduler.cancelAll()
            return
        }
        let granted = await scheduler.requestAuthorization()
        isEnabled = granted
        isDenied = !granted
        preferences.set(granted, forKey: Self.enabledKey)
        await refresh(catalog: catalog, mode: mode)
    }

    func setTime(hour: Int, minute: Int, catalog: WordCatalog?, mode: WordOfDayMode) {
        guard hour != self.hour || minute != self.minute else { return }
        self.hour = hour
        self.minute = minute
        preferences.set(hour, forKey: Self.hourKey)
        preferences.set(minute, forKey: Self.minuteKey)
        Task { await refresh(catalog: catalog, mode: mode) }
    }

    /// Bekleyenleri silip baştan planlar. Her açılışta, saat, kip ve katalog
    /// değişiminde çağrılır.
    func refresh(catalog: WordCatalog?, mode: WordOfDayMode) async {
        guard isEnabled, let catalog else {
            scheduler.cancelAll()
            return
        }
        // İzin sistem ayarlarından geri alınmış olabilir.
        guard await scheduler.isAuthorized() else {
            isEnabled = false
            isDenied = true
            preferences.set(false, forKey: Self.enabledKey)
            scheduler.cancelAll()
            return
        }
        isDenied = false
        await scheduler.reschedule(catalog: catalog, mode: mode, hour: hour, minute: minute)
    }

    /// Bekleyen bildirim sayısı; doğrulama ve teşhis için.
    func pendingCount() async -> Int {
        await scheduler.pendingCount()
    }
}
