import Foundation

/// Günlük bildirimin planlanma noktası. Ayarlar ekranı saati ve açık/kapalı
/// durumunu saklar, planlamayı buradan ister. Gerçek `UNUserNotificationCenter`
/// uygulaması Faz 5'te bu protokole bağlanır.
protocol NotificationScheduler: Sendable {
    /// Günlük bildirimi verilen saate kurar.
    func schedule(at time: DateComponents) async
    /// Planlanmış tüm bildirimleri kaldırır.
    func cancel() async
}

/// Hiçbir şey planlamayan varsayılan. Ayar yalnızca saklanır.
struct InactiveNotificationScheduler: NotificationScheduler {
    func schedule(at time: DateComponents) async {}
    func cancel() async {}
}
