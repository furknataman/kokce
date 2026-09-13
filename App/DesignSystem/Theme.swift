import SwiftUI

/// Marka paleti ve tipografi. Mürekkep laciverti + parşömen; **kırmızı yok**.
/// Uygulama ve widget aynı dosyayı derler.
enum Theme {

    /// Başlıklar ve ana metin.
    static let ink = adaptive(light: (0.10, 0.15, 0.29), dark: (0.90, 0.91, 0.95))
    /// İkincil metin, rozet yazısı.
    static let inkSoft = adaptive(light: (0.32, 0.36, 0.48), dark: (0.68, 0.71, 0.80))
    /// Ekran zemini.
    static let parchment = adaptive(light: (0.97, 0.95, 0.90), dark: (0.07, 0.08, 0.13))
    /// Kart ve rozet zemini.
    static let parchmentDeep = adaptive(light: (0.93, 0.90, 0.83), dark: (0.12, 0.14, 0.21))
    /// Vurgu: eskitilmiş altın.
    static let accent = adaptive(light: (0.58, 0.44, 0.18), dark: (0.82, 0.68, 0.38))

    static let cardCornerRadius: CGFloat = 20

    private static func adaptive(light: (Double, Double, Double),
                                 dark: (Double, Double, Double)) -> Color {
        Color(uiColor: UIColor { traits in
            let channels = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: channels.0, green: channels.1, blue: channels.2, alpha: 1)
        })
    }
}

extension View {
    /// Ekranların parşömen zemini.
    func kokenBackground() -> some View {
        background(Theme.parchment.ignoresSafeArea())
    }

    /// İçerik kartı. Cam değil: Liquid Glass yalnızca gezinme ve kontrollerde.
    func kokenCard() -> some View {
        padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.parchmentDeep, in: RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
    }
}

extension Font {
    /// Kelime başlıkları serif.
    static func kokenWord(_ style: Font.TextStyle = .largeTitle) -> Font {
        .system(style, design: .serif).weight(.semibold)
    }
}
