import SwiftUI

struct RootTabView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedTab) {
            Tab("tab.today", systemImage: "sun.horizon", value: AppModel.Tab.today) {
                TodayView()
            }
            Tab("tab.dictionary", systemImage: "character.book.closed", value: AppModel.Tab.dictionary) {
                DictionaryView()
            }
            Tab("tab.settings", systemImage: "gearshape", value: AppModel.Tab.settings) {
                SettingsView()
            }
            Tab("tab.search", systemImage: "magnifyingglass", value: AppModel.Tab.search, role: .search) {
                SearchView()
            }
        }
        .tint(Theme.accent)
    }
}
