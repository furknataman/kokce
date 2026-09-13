import SwiftUI
import KokenKit

/// Kelimenin yolculuğu, eskiden yeniye: en üstte zincirin en eski dili, en
/// altta Türkçe. Adımlar numaralıdır ve aralarındaki çizgi yönlüdür, böylece
/// hangi biçimin hangisinden geldiği okunmadan görülür.
struct JourneyTimeline: View {

    @Environment(AppModel.self) private var model
    let steps: [ChainStep]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                StepRow(step: step,
                        language: model.languageName(step.language) ?? step.language,
                        number: index + 1,
                        isFirst: index == 0,
                        isLast: index == steps.count - 1)
            }
        }
    }
}

/// Zaman çizelgesinin tek adımı. VoiceOver satırı tek parça okur; ayrı ayrı
/// gezilen numara/dil/biçim parçaları bağlamsız kalıyordu.
private struct StepRow: View {

    /// Numara dairesi yazıyla birlikte büyür, yoksa büyük puntoda rakam taşar.
    @ScaledMetric(relativeTo: .caption2) private var markerSize: CGFloat = 24

    let step: ChainStep
    let language: String
    let number: Int
    let isFirst: Bool
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            rail
            content.padding(.bottom, isLast ? 0 : 20)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    /// Numaralı daire ve bir sonraki adıma inen yönlü çizgi. Çizgi esnek
    /// yükseklikte olduğu için satır uzadıkça ray da uzar.
    private var rail: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle().fill(Theme.accent)
                Text("\(number)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.parchment)
            }
            .frame(width: markerSize, height: markerSize)
            if !isLast { connector }
        }
        .frame(width: markerSize)
    }

    private var connector: some View {
        ZStack(alignment: .bottom) {
            Rectangle()
                .fill(Theme.border)
                .frame(width: 1)
                .frame(maxHeight: .infinity)
            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 7))
                .foregroundStyle(Theme.border)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 3)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(language)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.inkSoft)
                if let marker {
                    Text(marker)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.parchment, in: Capsule())
                }
            }
            Text(displayForm)
                .font(.system(.title3, design: .serif).italic())
                .foregroundStyle(Theme.ink)
            Text(step.meaning)
                .font(.subheadline)
                .foregroundStyle(Theme.inkSoft)
            if let period = step.period {
                Text(period)
                    .font(.caption2)
                    .foregroundStyle(Theme.inkSoft)
            }
            if step.reconstructed {
                Text("detail.reconstructed")
                    .font(.caption2)
                    .foregroundStyle(Theme.inkSoft)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// İlk adım kökeni, son adım bugünkü biçimi işaretler; arası etiketsizdir.
    /// Tek adımlık zincirde "Bugün" kazanır: o biçim hâlâ kullanılandır.
    private var marker: String? {
        if isLast { return String(localized: "detail.timeline.today") }
        if isFirst { return String(localized: "detail.timeline.origin") }
        return nil
    }

    /// Yeniden kurulmuş biçimler dil biliminde yıldızla yazılır.
    private var displayForm: String {
        step.reconstructed ? "*" + step.form : step.form
    }

    /// Yıldız sesli okumada "star" diye okunur; etikete biçimin çıplak hâli
    /// girer, yeniden kurulmuşluk ayrı bir cümleyle söylenir.
    private var accessibilityLabel: String {
        var parts = [String(format: String(localized: "detail.timeline.step"), number), language]
        if let marker { parts.append(marker) }
        parts.append(step.form)
        parts.append(step.meaning)
        if let period = step.period { parts.append(period) }
        if step.reconstructed { parts.append(String(localized: "detail.reconstructed")) }
        return parts.joined(separator: ", ")
    }
}
