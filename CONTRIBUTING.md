# Katkı

Kökçe'ye en değerli katkı yeni kelime maddesidir. Kod katkıları da hoş karşılanır.

## Yeni kelime eklemek

1. Maddeyi `scripts/schema.md`'deki şemaya birebir uydurun. Alanların
   tamamı zorunludur; bilinmeyen alan **uydurulmaz**, `null` bırakılır.
2. **Kaynak zorunludur.** `sources` en az bir madde içermeli ve gerçekten
   o kelimeyi ele almalıdır. İki bağımsız kaynak uyuşuyorsa `confidence`
   "yüksek", tek kaynak varsa "orta" olur.
3. Kelimeyi `Resources/Content/words.json` içindeki `words` dizisine ekleyin.
4. Kimliğin takvime girmesi için `schedule.ids` listesinin **sonuna** ekleyin.
   Listenin sırası değiştirilmez, araya ekleme yapılmaz: sıra değişirse
   geçmiş günlerin kelimesi kayar ve okurların gördüğü takvim bozulur.
5. `contentVersion` alanını bir artırın.
6. Doğrulayın; hatasız geçmeden PR açmayın:

```bash
python3 scripts/validate_words.py
```

## PR akışı

- Tek PR'da bir konu: kelime eklemek ile kod değişikliğini karıştırmayın.
- Başlık kısa ve Türkçe olsun, açıklamada kaynakları belirtin.
- `main` dalına yalnızca doğrulamadan geçen PR'lar girer; aynı dosya
  uygulamanın uzaktan güncelleme adresidir, bozuk içerik doğrudan
  kullanıcılara gider.
- Türkçe metinlerde yazım hatası kabul edilmez.

## Kod katkısı

```bash
xcodegen generate
xcodebuild build -scheme Koken -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO -quiet
cd Packages/KokenKit && swift test
```

Üçüncü parti bağımlılık eklenmez. `.xcodeproj` üretilir, elle düzenlenmez;
dosya ekleyip çıkardıktan sonra `xcodegen generate` çalıştırın.

## Lisanslar

Katkınızı gönderdiğinizde kodun **MIT** (`LICENSE`), sözlük içeriğinin
**CC BY-SA 4.0** (`LICENSE-CONTENT`) ile yayımlanmasını kabul etmiş olursunuz.
