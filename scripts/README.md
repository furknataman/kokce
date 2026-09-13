# Köken — İçerik Üretim Hattı

Python 3 standart kütüphanesi dışında bağımlılık yoktur. Tüm komutlar depo
kökünden (`koken/`) çalıştırılır.

## Dosyalar

| Yol | İşi |
|---|---|
| `schema.md` | Kelime veri şeması. Tek doğruluk kaynağı. |
| `prompts/generate_batch.md` | Codex üretim prompt'u (sürüm başlıkta, şu an **v3**). `{{WORDS}}` yer tutucusu. |
| `prompts/verify_batch.md` | Bağımsız doğrulayıcı prompt'u (v1). `{{ITEMS}}` yer tutucusu. |
| `generate_batch.py` | Kelime listesinden parti üretir (`codex exec`). |
| `validate_words.py` | Parti dosyasını veya birleşik `words.json`'u doğrular. |
| `build_words.py` | Partileri + doğrulayıcı kararlarını birleştirip `words.json` yazar. |
| `wordlist.json` | 550 başlıklık kelime listesi (Codex üretir, elle düzenlenir). |
| `batches/NN.json` | Üretilmiş parti (çıplak JSON dizi). `NN.raw.txt` ham çıktıdır. |
| `review/NN.json` | Doğrulayıcı kararları. |
| `fixes/NN.json` | `fix` kararı alan maddelerin düzeltilmiş hâlleri. |
| `log/NN.meta.json` | Parti künyesi: prompt sürümü, model, tarih, istenen kelimeler. |
| `log/NN.codex.log` | Codex oturum kaydı. |
| `tests/sample_batch.json` | Doğrulayıcının kendi kendine testi. |

## Akış

### 1. Kelime listesi

`scripts/wordlist.json` beklenir (550 kelime); yoksa
`scripts/wordlist.raw.json` kullanılır. Kabul edilen biçimler:
`{"words": [...]}` veya çıplak dizi; öğeler ya düz metin ya da
`{"word": "kalem", "originHint": "ar<grc"}` nesnesi olabilir.

`originHint` prompt'a kelimenin yanında ipucu olarak geçirilir
(`1. kalem — ipucu: ar<grc`) ve künyeye `originHints` altında yazılır.
Prompt v3 modele ipucunu **doğrulamasını**, kaynakla çelişirse kaynağı esas
alıp ipucunu yok saymasını, atlanmış ara halkaları eklemesini söyler.

### 2. Üretim

```sh
python3 scripts/generate_batch.py --batch 1            # 1-20. kelimeler
python3 scripts/generate_batch.py --batch 1 --dry-run  # codex çağırmaz, prompt'u basar
python3 scripts/generate_batch.py --all                # tüm partiler, var olanları atlar
```

Parti numaraları **1 tabanlıdır**: `--batch 1` listenin 1-20, `--batch 2`
21-40. aralığıdır. Dosya adları iki hanelidir (`01.json`). Var olan bir parti
`--force` verilmedikçe yeniden üretilmez.

Prompt `codex exec ... -` ile **stdin'den** verilir, son mesaj `-o` ile
`batches/NN.raw.txt` dosyasına yazılır. Script ham çıktıdan JSON diziyi ayıklar
(kod bloğu sarmalayıcısını soyar), `batches/NN.json` yazar, künyeyi
`log/NN.meta.json` dosyasına koyar.

Diğer seçenekler: `--size` (varsayılan 20), `--model` (varsayılan
`gpt-6-astra`), `--timeout` (varsayılan 1800 sn), `--wordlist`.

### 3. Doğrulama (programatik)

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

### 4. Bağımsız doğrulama (Claude)

`prompts/verify_batch.md` içindeki `{{ITEMS}}` yerine partinin maddeleri
konur, bağımsız bir Claude oturumunda çalıştırılır. Çıktı
`review/NN.json` olarak kaydedilir:

```json
[{"id": "kalem", "verdict": "ok", "objections": []}]
```

`fix` kararı alan maddelerin düzeltilmiş hâli `fixes/NN.json` içine konur;
eşleştirme sıraya göre değil **id'ye göre** yapılır.

### 5. Birleştirme

```sh
python3 scripts/build_words.py
python3 scripts/build_words.py --out /tmp/deneme.json   # test için
python3 scripts/build_words.py --strict-reviewed        # yalnızca onaylı maddeler
```

Karar işleyişi:

- `ok` → madde alınır, `reviewed: true`.
- `fix` → `fixes/` içindeki aynı id'li madde alınır, `reviewed: true`.
  Düzeltme yoksa madde atlanır ve uyarı basılır.
- `drop` → madde atılır, `schedule.ids` içinden de çıkarılır.
- **Karar yok** → madde alınır, `reviewed: false` yazılır ve sayısı raporlanır.
  Yayın öncesi bu sayının **sıfır** olması beklenir; `--strict-reviewed` bu
  maddeleri tamamen dışarıda bırakır.

`schedule.ids` mevcut `words.json` sırasını korur, düşen id'leri atar, yeni
id'leri sabit tohumla (`random.Random(2026)`) karıştırıp **sona** ekler.
`schedule.start` var olan dosyadan alınır; dosya yoksa `2026-10-01`.
`contentVersion` her çalıştırmada +1. `languages` sözlüğü şemadan, yalnızca
kullanılan kodlar için üretilir. Yazımdan sonra doğrulama otomatik çalışır
(`--no-validate` ile kapatılır).

## Kendi kendine test

```sh
python3 scripts/validate_words.py --batch scripts/tests/sample_batch.json
```

Örnek parti 3 geçerli (`kalem`, `ısırgan`, `hikâye`) ve 1 hatalı (`Yoğurt`) madde
içerir; hatalı maddeden 9 hata beklenir ve çıkış kodu `1` olur.

## Yeni dil kodu eklemek

Önce `schema.md` içindeki tabloya, sonra `validate_words.py` içindeki
`LANGUAGES` sözlüğüne eklenir. `prompts/generate_batch.md` içindeki liste de
güncellenir. Üçü ayrışırsa `build_words.py` hata verip durur.
