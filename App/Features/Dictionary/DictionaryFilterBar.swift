import SwiftUI

/// Köken dili ve favori çipleri. Diller kelime sayısına göre sıralıdır, eşit
/// sayıda olanlar Türkçe alfabetik gelir.
struct DictionaryFilterBar: View {

    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                FilterChip(title: Text("dictionary.filter.all"), isSelected: !model.hasActiveFilter) {
                    model.originFilter = nil
                    model.showFavoritesOnly = false
                }
                FilterChip(title: Text("dictionary.filter.favorites"), isSelected: model.showFavoritesOnly) {
                    model.showFavoritesOnly.toggle()
                }
                ForEach(model.originChips) { chip in
                    FilterChip(title: Text(chip.name), isSelected: model.originFilter == chip.code) {
                        model.originFilter = model.originFilter == chip.code ? nil : chip.code
                    }
                }
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.vertical, 10)
        }
        .scrollIndicators(.hidden)
    }
}

/// Tek çip. Liquid Glass yalnızca burada, yani bir kontrolde kullanılır;
/// içerik kartları düz zeminde kalır. iOS 18'de cam yerine ince materyal.
private struct FilterChip: View {

    let title: Text
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) { chip }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private var chip: some View {
        if #available(iOS 26.0, *) {
            label.glassEffect(isSelected ? .regular.tint(Theme.accent) : .regular, in: .capsule)
        } else {
            label.background(isSelected ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.thinMaterial),
                             in: .capsule)
        }
    }

    private var label: some View {
        title
            .font(.subheadline.weight(.medium))
            .foregroundStyle(isSelected ? Theme.parchment : Theme.ink)
            .lineLimit(1)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
    }
}
