import Foundation
import UserNotifications

/// Bildirime dokunulduğunda ilgili kelimeyi açar.
///
/// Delege uygulama açılışının en başında, `AppModel` kurulurken bağlanır:
/// soğuk açılışta sistem yanıtı hemen teslim eder, delege geç bağlanırsa
/// dokunuş kaybolur. Katalog henüz yüklenmemişse kimlik `AppModel` içinde
/// bekletilir, deep link ile aynı yol kullanılır.
@MainActor
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {

    private weak var model: AppModel?

    func attach(to model: AppModel) {
        self.model = model
        UNUserNotificationCenter.current().delegate = self
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let id = response.notification.request.content.userInfo["wordId"] as? String
        guard let id else { return }
        await MainActor.run { model?.openWord(id: id) }
    }

    /// Uygulama önplandayken de bildirim görünsün; yoksa test sırasında
    /// gönderilen bildirim sessizce yutulur.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
