import SwiftUI

/// Marka paleti ve tipografi. Mürekkep laciverti + parşömen; **kırmızı yok**.
/// Uygulama ve widget aynı dosyayı derler, bu yüzden buraya yalnızca uygulama
/// uzantısında da derlenebilen şeyler girer.
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
    ///
    /// Açık moddaki ton, küçük puntoda okunabilirlik için koyulaştırıldı:
    /// önceki (0.58, 0.44, 0.18) parşömen kart üstünde 3.64:1 veriyordu, yani
    /// WCAG AA'nın küçük metin için istediği 4.5:1'in altında. Şimdiki değer
    /// kart üstünde 4.55:1, ekran zemininde 5.10:1; üstüne yazılan parşömen
    /// rengi metin (seçili çip, zaman çizelgesi numarası) de 5.10:1.
    static let accent = adaptive(light: (0.50, 0.38, 0.16), dark: (0.82, 0.68, 0.38))
    /// Kart kenarlığı, ayraç ve zaman çizelgesi rayı. Kartlar düz zemin +
    /// ince çizgiyle ayrılır; cam yalnızca kontrollerdedir.
    static let border = adaptive(light: (0.84, 0.79, 0.69), dark: (0.20, 0.23, 0.32))

    static let cardCornerRadius: CGFloat = 20
    /// iPad'de metin sütunu bu genişlikte durur; daha geniş satırlar okumayı
    /// zorlaştırır. iPhone'da zaten ekran bundan dar, etkisi yoktur.
    static let contentMaxWidth: CGFloat = 720
    /// Ekran kenarı boşluğu; kartlar ve başlıklar aynı hizada durur.
    static let screenPadding: CGFloat = 20

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

    /// İçerik kartı: düz zemin + ince kenarlık. Cam değil — Liquid Glass
    /// yalnızca gezinme ve kontrollerde kullanılır.
    func kokenCard() -> some View {
        padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.parchmentDeep, in: RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                    .strokeBorder(Theme.border, lineWidth: 1)
            }
    }
}

extension View {
    /// Okunabilir genişlikte, ortalanmış içerik sütunu. Listeler tam
    /// genişlikte kalır; bu yalnızca metin kartları içindir.
    func kokenContentColumn() -> some View {
        frame(maxWidth: Theme.contentMaxWidth)
            .frame(maxWidth: .infinity)
    }
}

extension Font {
    /// Kelime başlıkları serif.
    static func kokenWord(_ style: Font.TextStyle = .largeTitle) -> Font {
        .system(style, design: .serif).weight(.semibold)
    }
}
