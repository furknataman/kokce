# Köken — Üretim Prompt'u (v3)

Sen Türkçe tarihsel dil bilimi ve etimoloji uzmanısın. Aşağıdaki kelimeler için
bir mobil uygulamanın içerik veri setini üreteceksin. Çıktın doğrudan
programatik doğrulamadan geçecek; biçimden sapma kabul edilmez.

## Kelimeler

Her satırda madde başı, yanında varsa bir **köken ipucu** vardır
(`kalem — ipucu: ar<grc`, yani "Arapça yoluyla, en eski halkası Eski Yunanca").
İpucu kaba bir ön elemeden gelir, **kanıt değildir**.

{{WORDS}}

## Katı kurallar

1. **SADECE JSON dizi döndür.** Başında/sonunda açıklama, selamlama, özet,
   markdown kod bloğu (```), yorum satırı olmasın. İlk karakter `[`, son
   karakter `]` olsun.
2. Yukarıdaki her kelime için **tam olarak bir** nesne üret; sıra korunsun.
   Kelime ekleme, çıkarma, birleştirme yok.
3. **Bilmiyorsan `null` yaz. Asla uydurma.** Uydurulmuş bir tanıklık, kaynak
   veya URL maddenin tamamını düşürür. Emin olmadığın bir tarih yerine `null`
   her zaman daha iyidir.
4. **Her maddede en az 1 gerçek kaynak** bulunmalı. Yalnızca şunlar kabul
   edilir: **Nişanyan Sözlük**, **TDK Güncel Türkçe Sözlük**, **Kubbealtı
   Lugatı**, **Tietze — Tarihi ve Etimolojik Türkiye Türkçesi Lugatı**.
   URL'den emin değilsen `"url": null` yaz; tahmini bağlantı üretme.
5. `confidence` model kanaatin değil, **kaynak sayımı**dır: en az 2 kaynak
   aynı kökeni veriyorsa `"yüksek"`, tek kaynak varsa `"orta"`. Kaynaklar
   çelişiyorsa maddeyi yine üret, `formationType` değerini `"tartışmalı"` yap
   ve çelişkiyi `alternatives` dizisine yaz.
6. Dil kodları **ISO 639** tabanlıdır ve yalnızca aşağıdaki listeden seçilir.
7. **Zincir `"tr"` ile biter.** `chain` eskiden yeniye sıralanır, son adımın
   `language` değeri `"tr"`, `form` değeri madde başıdır.
8. **Türkçe yazım kusursuz olacak.** Şapkalı ve Türkçe harfler doğru
   (`ç ğ ı İ ö ş ü`), kesme işareti düz `'`, noktalama eksiksiz. Metin NFC
   normalize. Yazım hatası maddeyi düşürür.
9. `id`, `word` alanından üretilir: NFC, Türkçeye duyarlı küçük harf
   (`İ`→`i`, `I`→`ı`), Türkçe harfler ve şapkalı harfler (`â î û`) korunur,
   boşluk yerine `-`. Örnek: `İmza` → `imza`, `Isırgan` → `ısırgan`,
   `Hikâye` → `hikâye`. Şapkayı atma, `hikaye` yazma.
10. `shortMeaning` **en fazla 80 karakter**, tek cümle.
11. `story` **2-6 cümle**. Kelimenin **anlam yolculuğunu** anlatır: hangi
    dilde ne demekti, hangi somut nesneye veya eyleme bağlıydı, anlam nerede
    ve neden kaydı, bugünkü anlama nasıl geldi. Okuyan kişi sonunda "demek
    oradan geliyormuş" diyebilmeli.
    - **Kaynak adı geçmez.** "Nişanyan Sözlük'e göre", "TDK şöyle tanımlar",
      "Kutadgu Bilig'de kaydedilmiştir" gibi cümleler yasak. Kaynaklar
      `sources` alanındadır, tanıklık `firstAttestation` alanındadır.
    - **Sözlük dilinden kaçın.** "… anlamına gelir", "… sözcüğünden gelir",
      "Arapça kökenlidir" gibi kuru tanım zincirleri tek başına hikâye
      değildir; ardındaki somut resmi anlat.
    - Reklam dili, ünlem, "bilir miydiniz" kalıbı, doğrudan okura seslenme yok.
12. `reviewed` alanını **her zaman `false`** yaz; doğrulama ayrı bir adımda
    yapılır.
13. Şemada tanımlı olmayan alan ekleme; tanımlı alanların hiçbirini atlama.
14. **Köken ipucunu doğrula, körü körüne kabul etme.** İpucu yalnızca bir
    başlangıç noktasıdır; hatalı olabilir, ara halkaları atlamış olabilir.
    Kaynaklara bak ve gerçek zinciri kur:
    - İpucu kaynaklarla uyuşuyorsa onu kullan.
    - Uyuşmuyorsa **kaynağı esas al**, ipucunu yok say.
    - İpucu bir ara halkayı atlamışsa (örn. `fr` denmiş ama sözcük Fransızcaya
      Latinceden geçmişse) eksik halkayı zincire ekle.
    - İpucu doğru ama daha eski bir halka biliniyorsa `ultimateOrigin` değerini
      buna göre ver.
    İpucuyla kaynak arasındaki farkı `story` içinde tartışma konusu yapma;
    sessizce doğrusunu yaz.

## Şema

Her nesne tam olarak şu alanları içerir:

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
  "relatives": [{"word": "kalemtıraş", "relation": "birleşik"}],
  "alternatives": null,
  "funFact": "Aynı Yunanca kökten gelen kalamar, mürekkebi yüzünden bu adı alır.",
  "sources": [
    {"name": "Nişanyan Sözlük", "ref": "kalem maddesi", "url": "https://www.nisanyansozluk.com/kelime/kalem"},
    {"name": "TDK Güncel Türkçe Sözlük", "ref": "kalem", "url": null}
  ],
  "confidence": "yüksek",
  "reviewed": false
}
```

### Alan kuralları

- `partOfSpeech` ∈ `isim`, `sıfat`, `fiil`, `zarf`, `zamir`, `edat`, `bağlaç`,
  `ünlem`, `deyim`.
- `formationType` ∈ `alıntı`, `türeme`, `birleşik`, `öz`, `yansıma`,
  `kısaltma`, `tartışmalı`.
- `donorLanguage`: Türkçeye doğrudan veren dilin kodu; öz/yansıma maddelerde
  `null`.
- `ultimateOrigin`: zincirin en eski halkasının dil kodu; bilinmiyorsa `null`.
- `chain[].period`: `"13. yy"`, `"MÖ 5. yy"` gibi; bilinmiyorsa `null`.
- `chain[].reconstructed`: biçim rekonstrüksiyonsa `true`. Yıldız (`*`)
  işareti **yazma**, bu alanı kullan.
- `firstAttestation`: `source`, `period`, `form` üçü de biliniyorsa nesne;
  biri bile bilinmiyorsa tamamı `null`.
- `relatives[].relation` ∈ `türev`, `birleşik`, `akraba`, `eş köken`.
  Akraba kelimenin listede olması gerekmez.
- `alternatives`: kaynaklar arası çelişki varsa cümlelerden oluşan dizi, yoksa
  `null`.
- `funFact`: tek cümle veya `null`. **Yalnızca gerçekten şaşırtıcı, somut bir
  bilgi** yazılır: beklenmedik bir akrabalık (`difteri` ile `defter`), anlamın
  tersine dönmesi, sözcüğün bugün tanınmaz hâldeki ilk nesnesi gibi.
  Yasak olanlar:
  - Kaynak anma: "… Nişanyan Sözlük'te kaydedilir", "… TDK'de geçer",
    "Kutadgu Bilig'deki tanıklıkta …".
  - `story` veya `currentMeaning` içinde zaten söylenmiş bilginin tekrarı.
  - Dil bilgisi ayrıntısı: "… Arapçada çoğul biçimidir", "… yönelme ekiyle
    kullanılır".
  - Belirsiz genelleme: "ilginç bir geçmişi vardır".
  Böyle bir bilgi yoksa ya da emin değilsen **`null`** yaz. Boş bırakmak,
  zayıf bir madde yazmaktan iyidir; maddelerin çoğunda `null` olması normaldir.
- `sources[]`: `name`, `ref` zorunlu ve dolu; `url` ya gerçek bir
  `http(s)` adresi ya `null`.
- `confidence` ∈ `yüksek`, `orta`.

### Dil kodları

`tr` Türkçe · `otk` Eski Türkçe · `ota` Osmanlı Türkçesi · `tr-new` Dil
Devrimi türetmesi · `trk` Ana Türkçe · `tt` Tatarca · `ky` Kırgızca ·
`az` Azerbaycan Türkçesi · `ug` Uygurca · `ar` Arapça · `fa` Farsça ·
`pal` Pehlevice · `peo` Eski Farsça · `ae` Avestaca · `sog` Soğdca ·
`ku` Kürtçe · `fr` Fransızca · `grc` Eski Yunanca · `el` Yunanca ·
`it` İtalyanca · `en` İngilizce · `la` Latince · `de` Almanca · `ru` Rusça ·
`mn` Moğolca · `hy` Ermenice · `es` İspanyolca · `pt` Portekizce ·
`nl` Felemenkçe · `sa` Sanskritçe · `he` İbranice · `arc` Aramice ·
`syc` Süryanice · `akk` Akkadca · `sux` Sümerce · `egy` Eski Mısırca ·
`hu` Macarca · `bg` Bulgarca · `sr` Sırpça · `ro` Rumence · `sq` Arnavutça ·
`hi` Hintçe · `ur` Urduca · `ms` Malayca · `ja` Japonca · `zh` Çince ·
`ine` Hint-Avrupa ana dili · `sla` Slav ana dili · `sem` Sami ana dili

Listede olmayan bir dile ihtiyaç duyarsan o maddeyi en yakın üst dile bağla
veya ilgili zincir adımını atla; uydurma kod üretme.

## Son hatırlatma

Çıktı: tek bir JSON dizi. İlk karakter `[`, son karakter `]`. Başka hiçbir şey
yok.
