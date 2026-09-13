# CLAUDE.md

Kökçe — Kelimelerin hikâyesi. Türkçe etimoloji rehberi (iOS). Bu dosya, depoda çalışan Claude Code
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

Kullanıcıya görünen ad **Kökçe**'dir; klasör, şema ve hedef adları (`Koken`,
`KokenKit`, `KokenWidget`) ile Swift modül adları değişmeden kalır.

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
- **Uygulama ve widget App Group paylaşır** (`group.com.solvy.kokce`): önbellek
  dosyası ve favoriler. Uygulama tek yazıcıdır, widget yalnızca okur.
- **Yerel paketler:** `Packages/KokenKit` ve `../SolvyKit` (`SharedKit`,
  `ReviewKit`). KokenKit'in SolvyKit'e bağımlılığı **yoktur**; böylece
  `swift test` host'ta yalıtık çalışır.

## Veri

- Gömülü katalog: `Resources/Content/words.json`, her iki hedefin bundle'ında.
- Okuma önceliği: geçerli önbellek **ve** `contentVersion > bundle.contentVersion`
  → önbellek; aksi hâlde bundle. Bozuk önbellek silinir.
- Depo: https://github.com/furknataman/kokce — uzak katalog adresi
  `WordRepository.remoteURL` sabitindedir, tek yerde durur.
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
- **Deep link:** `kokce://word/<id>`; bilinmeyen id Bugün sekmesine düşer.

## Proje durumu (13 Eylül 2026)

- **Sürüm 1.0 (build 1) App Store incelemesinde** (`WAITING_FOR_REVIEW`). ASC App ID `6811577378`,
  bundle `com.solvy.kokce`, takım `PY8XQ9L8AA`. Ücretsiz, 175 ülke, yaş 4+, kategori Eğitim/Referans,
  metadata TR + en-US, iPhone 6,9" ve iPad 13" ekran görüntüleri yüklü.
- **Build yükleme:** `xcodebuild archive` + `-exportArchive` (`method: app-store-connect`,
  `destination: upload`) **`-allowProvisioningUpdates` ile Xcode hesabından**; ASC API anahtarı
  cloud signing yetkisi vermiyor. Sonraki sürümde `CURRENT_PROJECT_VERSION` artırılır.
- **İçerik:** `words.json` contentVersion 3, 538 kelime (250 gündelik, 288 az bilinen; 429 yüksek /
  109 orta güven; 12 kelime kaynaksız olduğu için elendi). Uzak katalog GitHub `main` dalından çekilir.
- **Mağaza varlıkları:** `Design/app-icon.svg` (ikon), `Design/store/screenshots.html` + `render.sh`
  (`out/` gitignore'da), `Design/store/metadata-tr.md`, `Design/review/kelimeler.html` (insan incelemesi).
- **Çalışma modeli:** Claude orkestra şefi; kod Opus alt ajanları; içerik üretimi ve kod incelemesi
  Codex (`codex exec -s read-only`). İş bitmeden simülatör açılmaz; son denetim tek simülatörde.

### Bilinen eksikler / sonraki adımlar
- Widget'ın kip (`wordOfDay.mode`) okuması imzasız simülatörde doğrulanamadı; gerçek cihazda test et.
- iPad'de Ayarlar formu tam genişlik; `Theme.contentMaxWidth` ile daraltılabilir.
- Elenen kelimeler doğru yazımla yeniden çekilebilir: `siluet`→`silüet`, `iskarmoz`→`ıskarmoz`,
  `nekahat`→`nekahet`, `ağu`→`ağı`, `stakato`→`staccato`; Kubbealtı kaynak olarak hatta yok.
- EN arayüzde köken dili adları Türkçe (`languages` sözlüğü tek dilli).
- ASC "Uygulama Gizliliği" beyanı yalnızca web'den girilir (veri toplanmıyor).
