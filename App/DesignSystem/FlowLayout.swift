import SwiftUI

/// Çipleri satır satır dizen akış düzeni.
///
/// `LazyVGrid` sabit bir sütun genişliği ister; Dynamic Type büyüdükçe çip
/// yazısı sütunu taşırır. Buradaki her çip, **kullanılabilir genişlik teklif
/// edilerek** ölçülür: kısa çip doğal genişliğinde kalır, tek başına satıra
/// sığmayan uzun çip ise kırpılmak yerine kendi içinde sarar.
struct FlowLayout: Layout {

    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let limit = proposal.width ?? .infinity
        let rows = rows(in: limit, subviews: subviews)
        let width = proposal.width ?? rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var y = bounds.minY
        for row in rows(in: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for item in row.items {
                subviews[item.index].place(at: CGPoint(x: x, y: y),
                                           proposal: ProposedViewSize(item.size))
                x += item.size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Item {
        let index: Int
        let size: CGSize
    }

    private struct Row {
        var items: [Item] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(in maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            // Teklif edilen genişlik sınırı: metin bu genişliğe sarar, böylece
            // hiçbir çip kabın dışına taşmaz.
            let size = subviews[index].sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            let needed = current.items.isEmpty ? size.width : current.width + spacing + size.width
            if needed > maxWidth, !current.items.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.items.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.items.append(Item(index: index, size: size))
        }
        if !current.items.isEmpty { rows.append(current) }
        return rows
    }
}
