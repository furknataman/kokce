import SwiftUI
import KokenKit

/// İlk yazılı tanıklık. Dönem ve biçim bilinmiyorsa yalnızca kaynak yazılır.
struct AttestationCard: View {

    let attestation: Attestation

    var body: some View {
        SectionCard(title: "detail.attestation", systemImage: "text.book.closed") {
            VStack(alignment: .leading, spacing: 4) {
                Text(attestation.source)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.ink)
                if let detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSoft)
                }
            }
        }
    }

    private var detail: String? {
        let parts = [attestation.period, attestation.form].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Akraba kelime çipleri. Çip, sözlükte karşılığı olan bir maddeye denk
/// geliyorsa o maddeye götürür; gelmiyorsa bağlantısız çizilir.
struct RelativesCard: View {

    @Environment(AppModel.self) private var model
    let relatives: [Relative]

    var body: some View {
        SectionCard(title: "detail.relatives", systemImage: "point.3.connected.trianglepath.dotted") {
            FlowLayout(spacing: 8) {
                ForEach(relatives, id: \.self) { relative in
                    if let target = model.word(for: relative) {
                        NavigationLink(value: target) { RelativeChip(relative: relative) }
                            .buttonStyle(.plain)
                    } else {
                        RelativeChip(relative: relative)
                    }
                }
            }
        }
    }
}

private struct RelativeChip: View {

    let relative: Relative

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(relative.word)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.ink)
            Text(relative.relation)
                .font(.caption2)
                .foregroundStyle(Theme.inkSoft)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Theme.parchment, in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border, lineWidth: 1) }
        .accessibilityElement(children: .combine)
    }
}

/// Kabul görmüş başka köken önerileri.
struct AlternativesCard: View {

    let alternatives: [String]

    var body: some View {
        SectionCard(title: "detail.alternatives", systemImage: "arrow.triangle.branch") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(alternatives, id: \.self) { alternative in
                    Text(alternative)
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSoft)
                }
            }
        }
    }
}

/// Kaynak listesi. Bağlantısı olan kaynak dokunulabilir.
struct SourcesCard: View {

    let sources: [Source]

    var body: some View {
        SectionCard(title: "detail.sources", systemImage: "text.quote") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(sources, id: \.self) { source in
                    if let url = source.url.flatMap(URL.init(string:)) {
                        Link(destination: url) { row(source) }
                            .tint(Theme.accent)
                    } else {
                        row(source)
                    }
                }
            }
        }
    }

    private func row(_ source: Source) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(source.name)
                .font(.footnote.weight(.medium))
                .foregroundStyle(source.url == nil ? Theme.ink : Theme.accent)
            if let ref = source.ref {
                Text(ref)
                    .font(.caption2)
                    .foregroundStyle(Theme.inkSoft)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
