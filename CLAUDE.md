# CLAUDE.md

Köken — Türkçe etimoloji rehberi (iOS). Bu dosya, depoda çalışan Claude Code
oturumları için konvansiyonları tanımlar. Plan: `~/.claude/plans/yeni-bir-proje-yapman-wobbly-minsky.md`.

## Komutlar

```bash
xcodegen generate          # Kaynak dosya ekleyince/silince/yeniden adlandırınca HER ZAMAN. .xcodeproj üretilir, elle düzenlenmez.
xcodebuild build -scheme Koken -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO -quiet
cd Packages/KokenKit && swift test          # alan mantığı testleri, macOS host'ta çalışır
python3 scripts/validate_words.py           # içerik doğrulaması
```

Zincir: Xcode 26.6, Swift 6.3, XcodeGen 2.44. Simülatör adı için
`xcrun simctl list devices available` (bu makinede `iPhone 17 Pro` yok).

## Mimari

Yalnızca yerli yığın, **üçüncü parti bağımlılık yok**: SwiftUI + WidgetKit +
String Catalogs. iOS 18+, iPhone. Hesap yok, sunucu yok; içerik yerelden okunur.

- **`project.yml` tek doğruluk kaynağıdır** (XcodeGen). `.xcodeproj`/`.pbxproj`
  elle düzenlenmez.
- **Klasörler:** `App/` (`Navigation/`, `DesignSystem/`, `Features/<Sekme>/`) ·
  `Packages/KokenKit/` (modeller, `WordRepository`, `WordOfDay`, arama —
  uygulama **ve** widget'a bağlanır) · `Widget/` · `Resources/`
  (`Assets.xcassets`, `Localizable.xcstrings`, `Content/words.json`) ·
  `scripts/` (içerik hattı).
- **Uygulama ve widget App Group paylaşır** (`group.com.solvy.koken`): önbellek
  dosyası ve favoriler. Uygulama tek yazıcıdır, widget yalnızca okur.
- **Yerel paketler:** `Packages/KokenKit` ve `../SolvyKit` (`SharedKit`,
  `ReviewKit`). KokenKit'in SolvyKit'e bağımlılığı **yoktur**; böylece
  `swift test` host'ta yalıtık çalışır.

## Veri

- Gömülü katalog: `Resources/Content/words.json`, her iki hedefin bundle'ında.
- Okuma önceliği: geçerli önbellek **ve** `contentVersion > bundle.contentVersion`
  → önbellek; aksi hâlde bundle. Bozuk önbellek silinir.
- Uzaktan güncelleme: günde bir kez `If-None-Match` (ETag) ile GET, 10 sn
  timeout, 2 MB sınır; tam decode + doğrulama geçerse App Group konteynerine
  atomik yazılır. Delta yok, tam dosya değişimi.
- Kelime kimliği, `word` alanının Türkçe küçük harfli biçimidir (`çay` → `çay`,
  boşluk → `-`); kuralın tek doğruluk kaynağı `scripts/validate_words.py`.
  Deep link'te kimlik yüzde kodlanır (`KokenKit/DeepLink`).
- Günün kelimesi: `schedule.start`'tan bugüne gregoryen gün farkı, sabit
  `Europe/Istanbul`, `% schedule.ids.count`. `ids` listesine **yalnızca sona
  eklenir**; başa ekleme/sıra değişimi geçmiş günleri kaydırır.

## Konvansiyonlar

- **Swift 6:** tüm hedeflerde `SWIFT_VERSION 6.0`, `SWIFT_STRICT_CONCURRENCY complete`.
  UI durumu `@MainActor @Observable`; dosya/ağ işi `actor WordRepository`;
  modeller `Sendable`.
- **Yerelleştirme iki ayrı kanal:** arayüz metinleri
  `Resources/Localizable.xcstrings` (açık anahtar: `tab.today`, düz metin
  değil; kaynak dil Türkçe) · sözlük içeriği yalnızca Türkçe, JSON'da.
- **Türkçe metinler kusursuz olmalı** (App Store kalitesi). İçerikte bilinmeyen
  alan `null` bırakılır, uydurulmaz.
- **Tasarım:** `App/DesignSystem/Theme.swift`. Mürekkep laciverti + parşömen
  tonları; **kırmızı kullanılmaz**. Kelime başlıkları `.fontDesign(.serif)`.
  Liquid Glass yalnızca gezinme/kontrollerde, `#available(iOS 26)` arkasında.
- **Deep link:** `koken://word/<id>`; bilinmeyen id Bugün sekmesine düşer.
