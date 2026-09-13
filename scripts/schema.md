# Köken — Kelime Veri Şeması (schemaVersion 1)

Bu belge `Resources/Content/words.json` dosyasının ve parti dosyalarının
(`scripts/batches/NN.json`) biçimini tanımlar. `scripts/validate_words.py`
burada yazılanları programatik olarak doğrular; ikisi arasında fark çıkarsa
doğrulayıcı esastır.

Genel kurallar:

- Kodlama UTF-8, tüm metinler **NFC** normalize.
- Türkçe metinlerde sıfır yazım hatası; kesme işareti `'` (U+2019 değil `'`),
  tırnak `"` kullanılır.
- Bilinmeyen bilgi **`null`** yazılır, asla uydurulmaz.
- Hiçbir zorunlu metin alanı boş string (`""`) veya yalnızca boşluk olamaz.
- Bilinmeyen (şemada tanımsız) alan eklenemez.

## 1. Kök nesne (yalnızca `words.json`)

| Alan | Tip | Açıklama |
|---|---|---|
| `schemaVersion` | int | Sabit `1`. Şema kırılırsa artar. |
| `contentVersion` | int ≥ 1 | Her yayında +1. Uzaktan güncellemede cache/bundle karşılaştırması bununla yapılır. |
| `schedule` | nesne | Günün kelimesi takvimi. Aşağıya bakınız. |
| `languages` | nesne | Dil kodu → Türkçe dil adı sözlüğü. `words` içinde geçen **her** kod burada bulunmalıdır. |
| `words` | dizi | En az 1 kelime nesnesi. |

Anahtar sırası yukarıdaki gibidir (`sort_keys` kullanılmaz).

### `schedule`

| Alan | Tip | Açıklama |
|---|---|---|
| `start` | string | `YYYY-MM-DD`. İlk kelimenin gösterileceği gün. Varsayılan `"2026-10-01"`. Bir kez belirlenir, **değiştirilmez**. |
| `ids` | dizi | Benzersiz kelime id'leri. `words` içindeki id kümesine **eşit** olmalıdır. Sıra korunur; yeni id'ler yalnızca **sona** eklenir. |

Günün kelimesi: `index = gün_farkı(start, bugün) % ids.count`, takvim Gregoryen,
saat dilimi `Europe/Istanbul`.

### `languages`

Örnek: `{"ar": "Arapça", "grc": "Eski Yunanca", "tr": "Türkçe"}`.
Değerler boş olamaz. `scripts/build_words.py` bu sözlüğü şemadaki tablodan,
yalnızca kullanılan kodlar için üretir.

## 2. Parti dosyası (`scripts/batches/NN.json`)

Parti dosyası **çıplak JSON dizisidir**: doğrudan kelime nesnelerinden oluşur,
kök nesne sarmalayıcısı yoktur.

```json
[ { "id": "kalem", "...": "..." }, { "id": "liman", "...": "..." } ]
```

## 3. Kelime nesnesi

| Alan | Tip | Boş geçilebilir mi | Açıklama |
|---|---|---|---|
| `id` | string | hayır | Bkz. "id kuralı". |
| `word` | string | hayır | Madde başı, küçük harfle, tekil, yalın hâl. |
| `partOfSpeech` | string | hayır | İzinli değerler aşağıda. |
| `formationType` | string | hayır | İzinli değerler aşağıda. |
| `donorLanguage` | string (dil kodu) | evet (`null`) | Türkçeye **doğrudan** veren dil. Öz Türkçe/yansıma maddelerde `null`. |
| `ultimateOrigin` | string (dil kodu) | evet (`null`) | Zincirin **en eski** bilinen halkasının dili. Bilinmiyorsa `null`. |
| `chain` | dizi | hayır | En az 1 adım. Bkz. "Zincir adımı". |
| `shortMeaning` | string | hayır | **En fazla 80 karakter.** Widget ve liste satırı için tek cümlelik anlam. |
| `currentMeaning` | string | hayır | Bugünkü anlam, 1-2 cümle. |
| `story` | string | hayır | **2-6 cümle.** Kelimenin yolculuğu; akıcı, süssüz Türkçe. |
| `firstAttestation` | nesne | evet (`null`) | İlk tanıklık. Bkz. aşağı. |
| `relatives` | dizi | evet (`null`) | Akraba kelimeler. Bkz. aşağı. |
| `alternatives` | dizi (string) | evet (`null`) | Kaynaklar arasında çelişen alternatif köken açıklamaları, her biri tek cümle. |
| `funFact` | string | evet (`null`) | Tek cümlelik ilginç ayrıntı. |
| `sources` | dizi | hayır | **En az 1** kaynak. Bkz. aşağı. |
| `confidence` | string | hayır | `"yüksek"` veya `"orta"`. |
| `reviewed` | bool | hayır | Bağımsız doğrulayıcıdan geçtiyse `true`. Üretim çıktısında `false`. |

### id kuralı

`id`, `word` alanından şu dönüşümle **birebir** üretilir:

1. NFC normalize.
2. Türkçeye duyarlı küçük harf: `İ` → `i`, `I` → `ı`, diğerleri `str.lower()`.
   (Python'un düz `.lower()` metodu `İ` için birleşik nokta bırakır, `I` için
   `ı` yerine `i` verir; bu yüzden özel eşleme zorunludur.)
3. Türkçe harfler korunur: `ç ğ ı i̇ ö ş ü`.
4. Boşluk ve alt çizgi → `-`.
5. Baş/son boşluklar atılır.

Örnek: `İmza` → `imza`, `Isırgan` → `ısırgan`, `deli bal` → `deli-bal`.
`id` tüm koleksiyonda benzersizdir.

### Zincir adımı (`chain[]`)

| Alan | Tip | Boş geçilebilir mi | Açıklama |
|---|---|---|---|
| `language` | string | hayır | Dil kodu. |
| `form` | string | hayır | O dildeki biçim; Latin harfli çevriyazı (örn. `kálamos`, `qalam`). |
| `meaning` | string | hayır | O aşamadaki anlam. |
| `period` | string | evet (`null`) | Örn. `"13. yy"`, `"MÖ 5. yy"`. Bilinmiyorsa `null`. |
| `reconstructed` | bool | hayır | Biçim varsayımsal/rekonstrüksiyon ise `true` (yazımda `*` kullanılmaz, bu alan işaretler). |

Kurallar:
- Zincir **eskiden yeniye** sıralanır.
- **Son adımın `language` değeri `"tr"` olmak zorundadır.**
- Son adımın `form` değeri madde başıyla aynı olmalıdır (küçük farklar için
  `alternatives` kullanılır).

### `firstAttestation`

`null` ya da üç alanı da dolu nesne:

| Alan | Tip | Açıklama |
|---|---|---|
| `source` | string | Tanıklığın geçtiği eser/sözlük, örn. `"Kutadgu Bilig"`. |
| `period` | string | Örn. `"1069"`, `"13. yy"`. |
| `form` | string | Tanıklıktaki yazım. |

Üçünden biri bilinmiyorsa nesnenin tamamı `null` yazılır.

### `relatives[]`

| Alan | Tip | Açıklama |
|---|---|---|
| `word` | string | Akraba kelime (madde başı olmak zorunda **değil**). |
| `relation` | string | İzinli değerler aşağıda. |

### `sources[]`

| Alan | Tip | Boş geçilebilir mi | Açıklama |
|---|---|---|---|
| `name` | string | hayır | Kaynak adı, örn. `"Nişanyan Sözlük"`. |
| `ref` | string | hayır | Madde/sayfa, örn. `"kalem maddesi"`. |
| `url` | string | evet (`null`) | Varsa `http://` veya `https://` ile başlar. |

Kabul edilen kaynaklar: **Nişanyan Sözlük**, **TDK Güncel Türkçe Sözlük**,
**Kubbealtı Lugatı**, **Tietze (Tarihi ve Etimolojik Türkiye Türkçesi Lugatı)**.
Uydurma kaynak veya uydurma URL maddeyi düşürür.

### `confidence`

Model kanaati değil, **kaynak sayımı**dır:

- `"yüksek"` — en az 2 kaynak aynı kökeni veriyor.
- `"orta"` — tek kaynak var ya da ayrıntıda küçük fark var.
- Kaynaklar çelişiyor ve çelişki çözülemiyorsa madde **atılır** (üçüncü bir
  değer yoktur).

## 4. İzinli değerler

### `formationType`

| Değer | Anlamı |
|---|---|
| `alıntı` | Başka bir dilden alınmış. |
| `türeme` | Türkçe kök + Türkçe ek. |
| `birleşik` | İki sözcüğün kaynaşması. |
| `öz` | Eski Türkçeden süreklilikle gelen, alıntı olmayan. |
| `yansıma` | Ses taklidi. |
| `kısaltma` | Kırpma/kısaltma yoluyla. |
| `tartışmalı` | Kaynaklar oluşum türünde ayrışıyor. |

### `relation`

| Değer | Anlamı |
|---|---|
| `türev` | Aynı kökten ek alarak türemiş. |
| `birleşik` | Bu kelimeyi içeren birleşik sözcük. |
| `akraba` | Aynı kökten, Türkçe içinde ayrı yoldan gelen. |
| `eş köken` | Aynı uzak kökenden gelen, başka dilden alınmış ikiz (doublet). |

### `partOfSpeech`

`isim`, `sıfat`, `fiil`, `zarf`, `zamir`, `edat`, `bağlaç`, `ünlem`, `deyim`.

## 5. Dil kodları

ISO 639 temellidir; ISO'da karşılığı olmayan üç kod projeye özeldir
(`tr-new`, `otk` kullanım daralması, `ota`).

| Kod | Dil |
|---|---|
| `tr` | Türkçe |
| `otk` | Eski Türkçe |
| `ota` | Osmanlı Türkçesi |
| `tr-new` | Dil Devrimi türetmesi |
| `trk` | Ana Türkçe |
| `tt` | Tatarca |
| `ky` | Kırgızca |
| `az` | Azerbaycan Türkçesi |
| `ug` | Uygurca |
| `ar` | Arapça |
| `fa` | Farsça |
| `pal` | Pehlevice |
| `peo` | Eski Farsça |
| `ae` | Avestaca |
| `sog` | Soğdca |
| `ku` | Kürtçe |
| `fr` | Fransızca |
| `grc` | Eski Yunanca |
| `el` | Yunanca |
| `it` | İtalyanca |
| `en` | İngilizce |
| `la` | Latince |
| `de` | Almanca |
| `ru` | Rusça |
| `mn` | Moğolca |
| `hy` | Ermenice |
| `es` | İspanyolca |
| `pt` | Portekizce |
| `nl` | Felemenkçe |
| `sa` | Sanskritçe |
| `he` | İbranice |
| `arc` | Aramice |
| `syc` | Süryanice |
| `akk` | Akkadca |
| `sux` | Sümerce |
| `egy` | Eski Mısırca |
| `hu` | Macarca |
| `bg` | Bulgarca |
| `sr` | Sırpça |
| `ro` | Rumence |
| `sq` | Arnavutça |
| `hi` | Hintçe |
| `ur` | Urduca |
| `ms` | Malayca |
| `ja` | Japonca |
| `zh` | Çince |
| `ine` | Hint-Avrupa ana dili |
| `sla` | Slav ana dili |
| `sem` | Sami ana dili |

Yeni kod gerekirse **önce** bu tabloya ve `scripts/validate_words.py`
içindeki `LANGUAGES` sözlüğüne eklenir; üretim prompt'u tabloyu buradan alır.

## 6. Tam örnek

```json
{
  "id": "kalem",
  "word": "kalem",
  "partOfSpeech": "isim",
  "formationType": "alıntı",
  "donorLanguage": "ar",
  "ultimateOrigin": "grc",
  "chain": [
    {"language": "grc", "form": "kálamos", "meaning": "kamış", "period": null, "reconstructed": false},
    {"language": "ar", "form": "qalam", "meaning": "kamış kalem", "period": null, "reconstructed": false},
    {"language": "tr", "form": "kalem", "meaning": "yazı aracı", "period": "13. yy", "reconstructed": false}
  ],
  "shortMeaning": "Yazı yazmaya yarayan araç.",
  "currentMeaning": "Mürekkep, kurşun veya boya ile yazı yazmaya ve çizim yapmaya yarayan araç.",
  "story": "Eski Yunancada kálamos basitçe kamış demekti. Kamışın ucu eğik kesilip mürekkebe batırılınca yazı aracına dönüştü ve sözcük Arapçaya qalam olarak geçti. Türkçeye Arapçadan gelen kalem, kamışla bağını çoktan koparmış olsa da adını hâlâ o sazlıktan taşır.",
  "firstAttestation": {"source": "Kutadgu Bilig", "period": "1069", "form": "kalem"},
  "relatives": [
    {"word": "kalemtıraş", "relation": "birleşik"},
    {"word": "kalemlik", "relation": "türev"}
  ],
  "alternatives": null,
  "funFact": "Aynı Yunanca kökten gelen kalamar, mürekkebi yüzünden bu adı alır.",
  "sources": [
    {"name": "Nişanyan Sözlük", "ref": "kalem maddesi", "url": "https://www.nisanyansozluk.com/kelime/kalem"},
    {"name": "TDK Güncel Türkçe Sözlük", "ref": "kalem", "url": null}
  ],
  "confidence": "yüksek",
  "reviewed": true
}
```
