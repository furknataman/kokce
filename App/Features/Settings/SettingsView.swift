import SwiftUI

/// Ayarlar sekmesi. Faz 5'te günlük bildirim, Faz 6'da kaynaklar, hakkında,
/// lisans ve puan verme eklenecek.
struct SettingsView: View {
    var body: some View {
        NavigationStack {
            Form {
            }
            .scrollContentBackground(.hidden)
            .kokenBackground()
            .navigationTitle("tab.settings")
        }
    }
}
