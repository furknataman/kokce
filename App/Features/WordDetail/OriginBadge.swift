import SwiftUI
import KokenKit

/// Köken rozeti: "Eski Yunanca → Arapça → Türkçe".
///
/// Okuma yönü kronolojiktir — ok, kelimenin gittiği yönü gösterir. Yol
/// `AppModel.originPath` tarafından kurulur; ok sesli okumada anlamsız
/// kaldığı için etiket ayrıca verilir.
struct OriginBadge: View {

    @Environment(AppModel.self) private var model
    let word: Word

    var body: some View {
        let path = model.originPath(for: word)
        if !path.isEmpty {
            Text(path.joined(separator: " → "))
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.inkSoft)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Theme.parchment, in: Capsule())
                .overlay { Capsule().strokeBorder(Theme.border, lineWidth: 1) }
                .accessibilityLabel(accessibilityLabel(path))
        }
    }

    private func accessibilityLabel(_ path: [String]) -> String {
        let spoken = path.joined(separator: String(localized: "detail.badge.a11y.separator"))
        return String(format: String(localized: "detail.badge.a11y"), spoken)
    }
}
