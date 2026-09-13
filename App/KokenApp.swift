import SwiftUI
import KokenKit

@main
struct KokenApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(model)
                .task { await model.load() }
                .onOpenURL { model.open($0) }
        }
    }
}
