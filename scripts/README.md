# Köken — İçerik Üretim Hattı

Python 3 standart kütüphanesi dışında bağımlılık yoktur. Tüm komutlar depo
kökünden (`koken/`) çalıştırılır.

## Dosyalar

| Yol | İşi |
|---|---|
| `schema.md` | Kelime veri şeması. Tek doğruluk kaynağı. |
| `prompts/generate_batch.md` | Codex üretim prompt'u (sürüm başlıkta, şu an **v12**). `{{WORDS}}` ve `{{SOURCES}}` yer tutucuları. |
| `prompts/verify_batch.md` | Bağımsız doğrulayıcı prompt'u (v1). `{{ITEMS}}` yer tutucusu. |
| `fetch_sources.py` | Nişanyan ve TDK kayıtlarını indirir. |
| `generate_batch.py` | Kelime listesinden parti üretir (`codex exec`). |
| `crosscheck.py` | Üretilmiş partiyi kaynaklarla programatik karşılaştırır. |
| `validate_words.py` | Parti dosyasını veya birleşik `words.json`'u doğrular. |
| `build_words.py` | Partileri + doğrulayıcı kararlarını birleştirip `words.json` yazar. |
| `wordlist.json` | 550 başlıklık kelime listesi (Codex üretir, elle düzenlenir). |
| `sources/<id>.json` | Kelimenin Nişanyan + TDK kaydı. `_index.json` özet. |
| `batches/NN.json` | Üretilmiş parti (çıplak JSON dizi). `NN.raw.txt` ham çıktıdır. |
| `review/NN.json` | LLM/insan doğrulayıcı kararları. |
| `review/NN.auto.json` | `crosscheck.py` kararları (`ok` / `check`). |
| `fixes/NN.json` | `fix` kararı alan maddelerin düzeltilmiş hâlleri. |
| `log/NN.meta.json` | Parti künyesi: prompt sürümü, model, tarih, istenen kelimeler. |
| `log/NN.codex.log` | Codex oturum kaydı. |
| `tests/sample_batch.json` | Doğrulayıcının kendi kendine testi. |
| `tests/crosscheck/` | Çapraz denetimin kendi kendine testi. |
| `tests/schedule_order_test.py` | Takvimin yalnızca sona eklendiğinin testi. |
| `edebilist.json` | Edebî/az bilinen kelime eki; `wordlist.json` sonuna eklenir. |

## Akış

### 1. Kelime listesi

`scripts/wordlist.json` beklenir (550 kelime); yoksa
`scripts/wordlist.raw.json` kullanılır. Kabul edilen biçimler:
`{"words": [...]}` veya çıplak dizi; öğeler ya düz metin ya da
`{"word": "kalem", "originHint": "ar<grc", "rarity": "gündelik"}` nesnesi
olabilir. İsteğe bağlı `note` alanı kısa bir anlam ipucudur ve prompt'taki
kelime satırına `ipucu anlam` olarak eklenir; `originHint` gibi **kanıt
değildir**, kaynakla çelişirse kaynak esas alınır.

`rarity` (`gündelik` | `az-bilinen`) **kelime listesinin verisidir, model
üretmez**. Prompt'taki kelime satırına yazılır, üretim çıktısına doğrudan
enjekte edilir ve modelin yazdığı değer ne olursa olsun listedeki değerle
değiştirilir.

`originHint` prompt'a kelimenin yanında ipucu olarak geçirilir
(`1. kalem — ipucu: ar<grc`) ve künyeye `originHints` altında yazılır.
Prompt v4 modele ipucunu **doğrulamasını**, kaynakla çelişirse kaynağı esas
alıp ipucunu yok saymasını, atlanmış ara halkaları eklemesini söyler.

### 2. Kaynakları indir

```sh
python3 scripts/fetch_sources.py                  # 550 kelime, ~20 dk
python3 scripts/fetch_sources.py --only kalem,yüz # tek tek
python3 scripts/fetch_sources.py --force          # var olanları yenile
python3 scripts/fetch_sources.py --index-only     # yalnızca özeti yeniden üret
```

Her kelime bir kez çekilir, `scripts/sources/<id>.json` olarak saklanır, var
olan dosya `--force` verilmedikçe atlanır. İstekler arası 1 saniye beklenir.

- **Nişanyan:** `api/words/<kelime>?session=0` (`?session=0` zorunlu).
  Geçici `Internal Error` yanıtında 1,5 saniye arayla 4 kez denenir.
  Birden çok madde dönebilir; `name` sonundaki rakam atılıp kelimeyle
  eşleşenler alınır (`yüz2` eşleşir, `yüz-` eşleşmez). Saklananlar:
  zincir (dil, biçim, anlam, ilişki — **eskiden yeniye çevrilir**),
  tanıklıklar (tarih, `dateSortable`, eser, alıntı), not, madde bağlantısı.
- **TDK:** `gts?ara=<kelime>`; bulunursa dizi, bulunmazsa hata nesnesi döner.
  Saklananlar: `lisan` ve ilk 3 anlam.
- `%b %i %u` gibi biçim imleri kayıt sırasında temizlenir.

Özet `scripts/sources/_index.json` dosyasındadır: hangi kelimede hangi kaynak
bulundu.

### 3. Üretim

```sh
python3 scripts/generate_batch.py --batch 1            # 1-20. kelimeler
python3 scripts/generate_batch.py --batch 1 --dry-run  # codex çağırmaz, prompt'u basar
python3 scripts/generate_batch.py --all                # tüm partiler, var olanları atlar
python3 scripts/generate_batch.py --rarity-from-wordlist      # tek seferlik onarım
python3 scripts/generate_batch.py --fill-chain-meanings       # boş anlamları doldur
python3 scripts/generate_batch.py --lowercase-chain-meanings  # baş harfleri küçült
python3 scripts/generate_batch.py --normalize-relatives       # relatives null → []
```

`--lowercase-chain-meanings` bir parti dosyasındaki zincir anlamlarının
**tamamı** büyük harfle başlıyorsa baş harfleri küçültür. Birkaçı büyükse
dokunmaz: bunlar özel addır (`Rosa cinsinden bitki`, `İran mitolojisinde`).
Aynı kural üretimden sonra kendiliğinden uygulanır.

`--rarity-from-wordlist` üretim yapmaz: var olan tüm parti dosyalarını gezip
`rarity` alanını kelime listesinden yazar. `rarity` alanı hattın ortasında
eklendiği için eski partileri düzeltmek üzere yazılmıştır.

Parti numaraları **1 tabanlıdır**: `--batch 1` listenin 1-20, `--batch 2`
21-40. aralığıdır. Dosya adları iki hanelidir (`01.json`). Var olan bir parti
`--force` verilmedikçe yeniden üretilmez.

Prompt `codex exec ... -` ile **stdin'den** verilir, son mesaj `-o` ile
`batches/NN.raw.txt` dosyasına yazılır. Script ham çıktıdan JSON diziyi ayıklar
(kod bloğu sarmalayıcısını soyar), `batches/NN.json` yazar, künyeyi
`log/NN.meta.json` dosyasına koyar.

Diğer seçenekler: `--size` (varsayılan 20), `--model` (varsayılan
`gpt-6-astra`), `--timeout` (varsayılan 1800 sn), `--wordlist`.

Prompt'a `{{SOURCES}}` bölümü eklenir: her kelime için Nişanyan zinciri
(eskiden yeniye), en eski tanıklıklar, madde notu ve TDK köken kaydı + ilk
anlam. Prompt v5 bu özetleri **esas** sayar: kaynakla çelişen bilgi yazılmaz,
kaynak metni kopyalanmaz, özette olmayan tanıklık uydurulmaz, Nişanyan
belirsizlik bildiriyorsa `formationType` `tartışmalı` olur ve `alternatives`
doldurulur. Kaynak kaydı bulunamayan kelimelerde eski davranış geçerlidir.

### 4. Doğrulama (programatik)

```sh
python3 scripts/validate_words.py --batch scripts/batches/01.json
python3 scripts/validate_words.py                      # Resources/Content/words.json
python3 scripts/validate_words.py --words yol/words.json
```

Hatalar `dosya:id:alan: mesaj` biçiminde basılır, çıkış kodu `1` olur.
Parti dosyası çıplak dizi, `words.json` kök nesne olarak ele alınır; kelime
kuralları ikisinde de aynıdır.

`relatives` yalnızca biçim ve ilişki türü açısından denetlenir; akraba
kelimenin madde başı olması **gerekmez** (kalemtıraş listede olmayabilir).
Alan her zaman dizidir: akraba yoksa `[]` olur, `null` reddedilir.

### 5. Çapraz denetim (kaynaklara karşı)

```sh
python3 scripts/crosscheck.py --batch 1
python3 scripts/crosscheck.py --all
python3 scripts/crosscheck.py --all --autofix
```

Partiyi `sources/` ile karşılaştırıp `review/NN.auto.json` yazar. Bakılanlar:

- `donorLanguage` ↔ Nişanyan'ın en yakın aktarım halkası ve TDK `lisan`.
- Zincir halkaları ve sırası ↔ Nişanyan zinciri. `formationType: birleşik`
  maddelerde **sıra denetlenmez**: düz dizi iki kollu bir bileşiği gösteremez,
  yalnızca eksik ve fazla dil bakılır. Bileşik etiket
  (`Farsça / Orta Farsça`) tek halkadır: iki koddan biri kabul edilir, ikiye
  bölünmüşse `check`. `Aramice-Süryanice` için `arc` ve `syc` eşdeğer sayılır.
- `firstAttestation.period` ↔ en küçük `dateSortable` (yüzyıl biçimi aralığa
  çevrilir), `firstAttestation.source` ↔ eser adı (gevşek eşleşme).
  Madde kaynaktan **eski** bir tarih veriyorsa her zaman `check`. **Geç** bir
  tarih veriyorsa yalnızca kaynağın en eski kaydının alıntısı ya da tanımı
  madde başının ilk 4 harfini içeriyorsa `check`; Codex Cumanicus 1303 gibi
  kayıtlar çoğu zaman başka bir sözcüğe aittir.
- Eş kökenli halkalar zincire sızmış mı: `chain[].meaning` içinde "eş
  kökenli" / "akraba biçim" geçiyor mu, kaynakta yalnızca eş kökenli olarak
  geçen bir dil zincire aktarım halkası olarak konmuş mu.
- `formationType: tartışmalı` yalnızca kaynak oluşum türünde ayrışınca
  kullanılmış mı, `alternatives` dolu mu. Veren dil belirsizse `alıntı` +
  `alternatives` beklenir.
- `sources` içindeki Nişanyan bağlantısı doğru mu.

İki nokta önemli: Nişanyan'ın **`eşkökenlilik`** ilişkili adımları sözcüğün
geçtiği yolu değil başka dillerdeki akrabalarını gösterir, zincir
karşılaştırmasına girmez ve prompt'ta ayrı bir "EŞ KÖKENLİLER — `chain`
alanına KOYMA" başlığı altında verilir. Ardışık aynı dil adımları (Arapça kök + Arapça
sözcük) teke indirilir.

`--autofix` parti dosyasını yerinde düzeltir, ama **yalnızca tek bir
deterministik durumda**: `formationType` `tartışmalı`, Nişanyan aktarım
ilişkisinde tartışma kaydı yok ve `donorLanguage` dolu. Bu üçü birden
sağlanınca oluşum türü bellidir ve `alıntı` yazılır. `donorLanguage` boşsa
`öz` ile `türeme` arasında karar verilmez, madde `check` kalır. Kaynak kaydı
yoksa dokunulmaz. `alternatives` hiçbir zaman değiştirilmez. Düzeltilen id'ler
zaman damgasıyla `log/autofix.log` dosyasına eklenir. Komut aynı parti üzerinde
yeniden çalıştırılabilir, ikinci turda değişiklik yapmaz.

Kaynak kaydı olmayan madde her zaman `check` olur; denetlenemeyen şey
onaylanmış sayılmaz. Eşlenemeyen bir dil adı da `check` sebebidir ve adı
raporlanır; `crosscheck.py` içindeki `SOURCE_LANG` sözlüğüne eklenerek
kapatılır.

### 6. Bağımsız doğrulama (Claude)

`prompts/verify_batch.md` içindeki `{{ITEMS}}` yerine partinin maddeleri
konur, bağımsız bir Claude oturumunda çalıştırılır. Çıktı
`review/NN.json` olarak kaydedilir:

```json
[{"id": "kalem", "verdict": "ok", "objections": []}]
```

`fix` kararı alan maddelerin düzeltilmiş hâli `fixes/NN.json` içine konur;
eşleştirme sıraya göre değil **id'ye göre** yapılır.

### 7. Birleştirme

```sh
python3 scripts/build_words.py
python3 scripts/build_words.py --out /tmp/deneme.json   # test için
python3 scripts/build_words.py --strict-reviewed        # yalnızca onaylı maddeler
python3 scripts/build_words.py --no-bump                # contentVersion sabit kalsın
```

Karar işleyişi:

- `ok` → madde alınır, `reviewed: true`.
- `fix` → `fixes/` içindeki aynı id'li madde alınır, `reviewed: true`.
  Düzeltme yoksa madde atlanır ve uyarı basılır.
- `drop` → madde atılır, `schedule.ids` içinden de çıkarılır.
- **Karar yok, `NN.auto.json`'da `ok`** → madde alınır, `reviewed: true`.
  Programatik çapraz denetim bu durumda insan/LLM incelemesinin yerine geçer.
- **Karar yok, `NN.auto.json`'da `check` ya da kayıt yok** → madde alınır,
  `reviewed: false` yazılır ve sayısı raporlanır.
  Yayın öncesi bu sayının **sıfır** olması beklenir; `--strict-reviewed` bu
  maddeleri tamamen dışarıda bırakır.

`review/NN.json` kaydı her zaman `review/NN.auto.json` kaydından **önce
gelir**. Bu, yayınlanan dosyadaki `reviewed: true` değerinin anlamını
genişletir: madde ya insan/LLM incelemesinden ya da programatik çapraz
denetimden geçmiştir.

`schedule.ids` mevcut `words.json` sırasını korur, düşen id'leri atar, yeni
id'leri sabit tohumla (`random.Random(2026)`) karıştırıp **sona** ekler. Var
olan sıranın birebir korunduğu yazımdan önce denetlenir; bozulursa dosya
yazılmaz. Çıktıdaki `schedule:` satırı kaç id'nin değişmediğini söyler. Yeni
id'ler `rarity` değerine göre ikiye ayrılıp oranlarına göre serpiştirilir:
ilk gün `gündelik` bir kelimedir, aynı türden en fazla iki gün üst üste gelir,
fazlalık sona yığılmaz. Düzeltme dosyasında `rarity` yoksa parti dosyasındaki
değer korunur.
`schedule.start` var olan dosyadan alınır; dosya yoksa `2026-10-01`.
`contentVersion` her çalıştırmada +1; içerik değişmeyen yeniden üretimlerde
`--no-bump` ile sabit tutulur. `relatives` alanı `null` ise boş diziye
çevrilir. `languages` sözlüğü şemadan, yalnızca
kullanılan kodlar için üretilir. Yazımdan sonra doğrulama otomatik çalışır
(`--no-validate` ile kapatılır).

## Kendi kendine testler

```sh
python3 scripts/validate_words.py --batch scripts/tests/sample_batch.json

python3 scripts/tests/schedule_order_test.py

python3 scripts/crosscheck.py --batch 1 \
  --batches-dir scripts/tests/crosscheck/batches \
  --sources-dir scripts/tests/crosscheck/sources \
  --review-dir /tmp/koken-test
```

İkinci test, Nişanyan'ın Farsça dediği yerde `donorLanguage: "ar"` yazan bir
maddeyi kullanır; çıktı `check` olmalı ve sebeplerden biri
`donorLanguage ar kaynakla uyuşmuyor (kaynak: fa)` olmalıdır.

Örnek parti 3 geçerli (`kalem`, `ısırgan`, `hikâye`) ve 1 hatalı (`Yoğurt`) madde
içerir; hatalı maddeden 11 hata beklenir ve çıkış kodu `1` olur.

## Yeni dil kodu eklemek

Önce `schema.md` içindeki tabloya, sonra `validate_words.py` içindeki
`LANGUAGES` sözlüğüne eklenir. `prompts/generate_batch.md` içindeki liste de
güncellenir. Üçü ayrışırsa `build_words.py` hata verip durur.
