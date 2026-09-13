import SwiftUI
import StoreKit
import ReviewKit
import UIKit
import KokenKit

/// Ayarlar sekmesi: günlük bildirim tercihi, içerik durumu, kaynaklar ve
/// hakkında. Bildirim burada yalnızca saklanır; planlamayı
/// `NotificationScheduler` üstlenir.
struct SettingsView: View {

    @Environment(AppModel.self) private var model
    @Environment(\.requestReview) private var requestReview

    private static let repositoryURL = URL(string: "https://github.com/furknataman/kokce")!
    private static let privacyURL = URL(string: "https://github.com/furknataman/kokce/blob/main/PRIVACY.md")!
    private static let systemSettingsURL = URL(string: UIApplication.openSettingsURLString)!

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
            Toggle("settings.notifications.daily", isOn: enabled)
            if model.notifications.isEnabled {
                DatePicker("settings.notifications.time",
                           selection: time,
                           displayedComponents: .hourAndMinute)
            }
            if model.notifications.isDenied {
                Link(destination: Self.systemSettingsURL) {
                    Text("settings.notifications.denied")
                }
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
            Link("settings.privacy", destination: Self.privacyURL)
            Button("settings.rate") {
                requestReview()
                // Elle verilen puan da bekleme süresini başlatır; otomatik
                // istek hemen ardından çıkmaz.
                ReviewManager.markAsked()
            }
        }
        .listRowBackground(Theme.parchmentDeep)
    }

    /// Toggle doğrudan bağlanamaz: açılışı izin isteyen bir async iştir ve
    /// izin verilmezse ayar geri kapanır.
    private var enabled: Binding<Bool> {
        Binding {
            model.notifications.isEnabled
        } set: { isOn in
            Task { await model.setNotifications(isOn) }
        }
    }

    /// Saat seçicisi `Date` ister; tercih saat ve dakika olarak saklanır.
    private var time: Binding<Date> {
        Binding {
            Calendar.current.date(from: DateComponents(hour: model.notifications.hour,
                                                       minute: model.notifications.minute)) ?? .now
        } set: { newValue in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            model.setNotificationTime(hour: parts.hour ?? 9, minute: parts.minute ?? 0)
        }
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
