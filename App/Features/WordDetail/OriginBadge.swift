import SwiftUI
import KokenKit

/// Köken rozeti: "Arapça ← Eski Yunanca". Soldaki dil kelimeyi Türkçeye
/// aktaran dil, sağdaki zincirin bilinen en eski dilidir; ikisi aynıysa tek ad
/// yazılır. Ok sesli okumada anlamsız kaldığı için etiket ayrıca verilir.
struct OriginBadge: View {

    @Environment(AppModel.self) private var model
    let word: Word

    var body: some View {
        if let origin = model.origin(for: word) {
            Text(text(origin))
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.inkSoft)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Theme.parchment, in: Capsule())
                .overlay { Capsule().strokeBorder(Theme.border, lineWidth: 1) }
                .accessibilityLabel(accessibilityLabel(origin))
        }
    }

    private func text(_ origin: (donor: String, ultimate: String?)) -> String {
        guard let ultimate = origin.ultimate else { return origin.donor }
        return "\(origin.donor) ← \(ultimate)"
    }

    private func accessibilityLabel(_ origin: (donor: String, ultimate: String?)) -> String {
        guard let ultimate = origin.ultimate else {
            return String(format: String(localized: "detail.badge.a11y.single"), origin.donor)
        }
        return String(format: String(localized: "detail.badge.a11y"), origin.donor, ultimate)
    }
}
