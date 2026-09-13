# Kökçe — Kelimelerin hikâyesi

Her gün bir kelimenin hikâyesi: nereden geldi, nasıl değişti, bugün ne anlama
geliyor. Türkçe kelimelerin kökenini anlatan, günün kelimesi odaklı, widget'lı,
ücretsiz ve açık kaynak bir iOS uygulaması.

- **Platform:** iOS 18+, iPhone
- **Bağımlılık yok:** SwiftUI + WidgetKit + yerel `SolvyKit`
- **İçerik:** `Resources/Content/words.json` (gömülü), uzaktan güncellenebilir
- **Kimlikler:** bundle `com.solvy.kokce`, App Group `group.com.solvy.kokce`,
  şema `kokce://`
- **Lisans:** kod MIT (`LICENSE`), içerik CC BY-SA 4.0 (`LICENSE-CONTENT`)

## Görseller

<img src="Design/app-icon-1024.png" alt="Kökçe ikonu" width="120">

Ekran görüntüleri: _Bugün, Sözlük, kelime detayı ve widget aileleri buraya eklenecek._

## Nasıl çalışır

- **Günün kelimesi deterministiktir:** takvimin başlangıcından bugüne gün
  farkı, sabit `Europe/Istanbul` saat dilimiyle hesaplanır; cihazın saat
  dilimi ne olursa olsun herkes aynı kelimeyi görür.
- **İçerik gömülüdür, uzaktan tazelenir:** uygulama `words.json`'ı kendi
  paketinden okur, günde bir kez depodaki güncel dosyayı ETag ile yoklar ve
  yalnızca doğrulamadan geçen yeni sürümü kullanır.
- **Gizlilik:** hesap yok, sunucu yok, izleme yok. Favoriler ve ayarlar
  yalnızca cihazda durur; hiçbir kullanım verisi toplanmaz.

## Geliştirme

```bash
xcodegen generate
xcodebuild build -scheme Koken -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO -quiet
cd Packages/KokenKit && swift test
```

Xcode projesi üretilir, elle düzenlenmez. Kaynak dosya ekledikten sonra
`xcodegen generate` çalıştırın.

---

# Kökçe — The story of words (EN)

A free, open-source iOS app that tells the story of Turkish words: where they
came from, how they changed, what they mean today. One word each day, with
widgets.

- **Platform:** iOS 18+, iPhone
- **No third-party dependencies:** SwiftUI + WidgetKit + local `SolvyKit`
- **Content:** bundled `Resources/Content/words.json`, updatable over the air
- **License:** code MIT (`LICENSE`), content CC BY-SA 4.0 (`LICENSE-CONTENT`)

Content is Turkish only; the interface is Turkish and English.
