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

    /// Kullanıcının en son istediği durum. Toggle'ın kendisi izin diyaloğu
    /// açıkken değişebildiği için karar, izin dönüşünde bu alandan okunur.
    private var desiredEnabled = false
    /// Süren planlama işi. Planlama "hepsini sil, tek tek ekle" adımlarından
    /// oluşur; örtüşen iki çağrı bu adımları birbirine karıştırıp yarım kuyruk
    /// bırakıyordu. Tüm işler tek zincirde sırayla koşar.
    private var work: Task<Void, Never>?

    init(preferences: UserDefaults = .standard) {
        self.preferences = preferences
        isEnabled = preferences.bool(forKey: Self.enabledKey)
        desiredEnabled = isEnabled
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
        desiredEnabled = enabled
        guard enabled else {
            store(enabled: false, denied: false)
            await enqueue { $0.cancelAll() }
            return
        }
        let granted = await scheduler.requestAuthorization()
        // İzin diyaloğu beklenirken kullanıcı vazgeçmiş olabilir: karar, o anki
        // istekle verilir, diyaloğa girilen anki istekle değil.
        guard desiredEnabled else {
            await enqueue { $0.cancelAll() }
            return
        }
        store(enabled: granted, denied: !granted)
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
            await enqueue { $0.cancelAll() }
            return
        }
        // İzin sistem ayarlarından geri alınmış olabilir.
        guard await scheduler.isAuthorized() else {
            store(enabled: false, denied: true)
            await enqueue { $0.cancelAll() }
            return
        }
        isDenied = false
        let hour = hour, minute = minute
        await enqueue { scheduler in
            await scheduler.reschedule(catalog: catalog, mode: mode, hour: hour, minute: minute)
        }
    }

    private func store(enabled: Bool, denied: Bool) {
        isEnabled = enabled
        isDenied = denied
        preferences.set(enabled, forKey: Self.enabledKey)
    }

    /// İşi sıraya alır: süren iş varsa önce iptal edilir, çıkması beklenir,
    /// sonra yenisi koşar.
    ///
    /// Sonuna eklemek yerine kesmenin sebebi: her planlama ilk iş olarak
    /// bekleyen bildirimlerin hepsini siler, yani yeni bir istek geldiğinde
    /// eski planlama zaten geçersizdir. Sırayla koşsalardı eski iş kuyruğu
    /// doldurup yenisinin onu baştan silmesini bekletirdi. İptal edilen işin
    /// çıkması yine de beklenir; yoksa iki iş aynı anda `add` çağırıp kuyruğu
    /// karıştırır.
    private func enqueue(_ operation: @escaping @Sendable @MainActor (NotificationScheduler) async -> Void) async {
        let previous = work
        previous?.cancel()
        let scheduler = scheduler
        let task = Task { @MainActor in
            await previous?.value
            guard !Task.isCancelled else { return }
            await operation(scheduler)
        }
        work = task
        await task.value
    }

    /// Bekleyen bildirim sayısı; doğrulama ve teşhis için.
    func pendingCount() async -> Int {
        await scheduler.pendingCount()
    }
}
