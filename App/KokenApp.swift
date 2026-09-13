import SwiftUI
import KokenKit

@main
struct KokenApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(model)
                .task { await model.load() }
                .task { await model.watchDayChange() }
                .onOpenURL { model.open($0) }
                .onChange(of: scenePhase) { _, phase in
                    // Uygulama günlerce arka planda kalmış olabilir: öne
                    // gelince hem gün hem içerik yeniden yoklanır.
                    guard phase == .active else { return }
                    model.refreshDay()
                    Task {
                        await model.refreshContent()
                        await model.refreshNotifications()
                    }
                }
        }
    }
}
