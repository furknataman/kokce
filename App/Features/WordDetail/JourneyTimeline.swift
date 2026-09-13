import SwiftUI
import KokenKit

/// Kelimenin yolculuğu: her adımda dil, biçim ve anlam. Dikey ray, satır
/// yüksekliğine uyduğu için Dynamic Type büyüdüğünde de adımları bağlı tutar.
struct JourneyTimeline: View {

    @Environment(AppModel.self) private var model
    let steps: [ChainStep]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                StepRow(step: step,
                        language: model.languageName(step.language) ?? step.language,
                        isLast: index == steps.count - 1)
            }
        }
    }
}

/// Zaman çizelgesinin tek adımı. VoiceOver satırı tek parça okur; ayrı ayrı
/// gezilen dil/biçim/anlam parçaları bağlamsız kalıyordu.
private struct StepRow: View {

    let step: ChainStep
    let language: String
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            rail
            content.padding(.bottom, isLast ? 0 : 18)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    /// Nokta ve onu bir sonraki adıma bağlayan çizgi. Çizgi esnek yükseklikte
    /// olduğu için satır ne kadar uzarsa ray da o kadar uzar.
    private var rail: some View {
        VStack(spacing: 0) {
            Circle()
                .fill(Theme.accent)
                .frame(width: 9, height: 9)
                .padding(.top, 6)
            if !isLast {
                Rectangle()
                    .fill(Theme.border)
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(width: 9)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(language)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.inkSoft)
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

    /// Yeniden kurulmuş biçimler dil biliminde yıldızla yazılır.
    private var displayForm: String {
        step.reconstructed ? "*" + step.form : step.form
    }

    /// Yıldız sesli okumada "star" diye okunur; etikete biçimin çıplak hâli
    /// girer, yeniden kurulmuşluk ayrı bir cümleyle söylenir.
    private var accessibilityLabel: String {
        var parts = [language, step.form, step.meaning]
        if let period = step.period { parts.append(period) }
        if step.reconstructed { parts.append(String(localized: "detail.reconstructed")) }
        return parts.joined(separator: ", ")
    }
}
