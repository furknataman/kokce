import SwiftUI
import StoreKit
import ReviewKit
import KokenKit

/// Ayarlar sekmesi: günlük bildirim tercihi, içerik durumu, kaynaklar ve
/// hakkında. Bildirim burada yalnızca saklanır; planlamayı
/// `NotificationScheduler` üstlenir.
struct SettingsView: View {

    @Environment(AppModel.self) private var model
    @Environment(\.requestReview) private var requestReview

    @AppStorage("notifications.enabled") private var notificationsEnabled = false
    @AppStorage("notifications.hour") private var notificationHour = 9
    @AppStorage("notifications.minute") private var notificationMinute = 0

    private let scheduler: any NotificationScheduler = InactiveNotificationScheduler()
    private static let repositoryURL = URL(string: "https://github.com/solvyapp/kokce")!

    var body: some View {
        @Bindable var model = model
        return NavigationStack {
            Form {
                wordOfDay(mode: $model.wordOfDayMode)
                notifications
                content
                about
            }
            .scrollContentBackground(.hidden)
            .kokenBackground()
            .navigationTitle("tab.settings")
            .tint(Theme.accent)
            .task(id: scheduleKey) { await applySchedule() }
        }
    }

    /// Günün kelimesi havuzu. Üç seçenek satır satır listelenir: büyük yazı
    /// boylarında segment denetimi yazıyı kırpıyordu.
    private func wordOfDay(mode: Binding<WordOfDayMode>) -> some View {
        Section {
            Picker("settings.wordOfDay", selection: mode) {
                Text("settings.mode.mixed").tag(WordOfDayMode.mixed)
                Text("settings.mode.everyday").tag(WordOfDayMode.everyday)
                Text("settings.mode.rare").tag(WordOfDayMode.rare)
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } header: {
            Text("settings.wordOfDay")
        } footer: {
            Text("settings.mode.footer")
        }
        .listRowBackground(Theme.parchmentDeep)
    }

    private var notifications: some View {
        Section {
            Toggle("settings.notifications.daily", isOn: $notificationsEnabled)
            if notificationsEnabled {
                DatePicker("settings.notifications.time",
                           selection: time,
                           displayedComponents: .hourAndMinute)
            }
        } header: {
            Text("settings.notifications")
        } footer: {
            Text("settings.notifications.footer")
        }
        .listRowBackground(Theme.parchmentDeep)
    }

    private var content: some View {
        Section("settings.content") {
            Text(contentStatus)
                .font(.footnote)
                .foregroundStyle(Theme.inkSoft)
        }
        .listRowBackground(Theme.parchmentDeep)
    }

    private var about: some View {
        Section("settings.about") {
            Text("settings.sources.body")
                .font(.footnote)
                .foregroundStyle(Theme.inkSoft)
            LabeledContent("settings.licenses") { Text("settings.licenses.value") }
            LabeledContent("settings.version") { Text(appVersion) }
            Link("settings.github", destination: Self.repositoryURL)
            Button("settings.rate") {
                requestReview()
                // Elle verilen puan da bekleme süresini başlatır; otomatik
                // istek hemen ardından çıkmaz.
                ReviewManager.markAsked()
            }
        }
        .listRowBackground(Theme.parchmentDeep)
    }

    /// Saat seçicinin `Date` beklemesi yüzünden saat ve dakika ayrı ayrı
    /// saklanır; `AppStorage` tarih tutamaz.
    private var time: Binding<Date> {
        Binding {
            Calendar.current.date(from: DateComponents(hour: notificationHour,
                                                       minute: notificationMinute)) ?? .now
        } set: { newValue in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            notificationHour = parts.hour ?? 9
            notificationMinute = parts.minute ?? 0
        }
    }

    private var scheduleKey: String {
        "\(notificationsEnabled)-\(notificationHour)-\(notificationMinute)"
    }

    private func applySchedule() async {
        guard notificationsEnabled else {
            await scheduler.cancel()
            return
        }
        await scheduler.schedule(at: DateComponents(hour: notificationHour, minute: notificationMinute))
    }

    private var contentStatus: String {
        let version = model.contentVersion.map(String.init) ?? "—"
        let checked = model.lastCheckedAt?.formatted(date: .abbreviated, time: .shortened)
            ?? String(localized: "settings.content.never")
        return String(format: String(localized: "settings.content.status"), version, checked)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }
}
