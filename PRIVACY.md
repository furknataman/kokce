# Gizlilik

Kökçe hiçbir kişisel veri toplamaz.

- **Hesap yok.** Kayıt, giriş, e-posta ya da profil istenmez.
- **Analitik ve reklam yok.** Uygulamada üçüncü parti SDK bulunmaz; kullanım
  davranışı ölçülmez, hiçbir yere gönderilmez.
- **Veriler yalnızca cihazda.** Favoriler, günün kelimesi kipi ve bildirim
  ayarı cihazın kendi depolamasında durur; iCloud'a veya sunucuya yazılmaz.
- **İçerik güncellemesi.** Uygulama günde en çok bir kez GitHub'daki sözlük
  dosyasını (https://github.com/furknataman/kokce) anonim bir GET isteğiyle
  yoklar. İstekte kimlik, cihaz bilgisi
  veya kullanım verisi yer almaz; yalnızca dosyanın değişip değişmediğini
  anlamak için `If-None-Match` başlığı gönderilir.
- **Bildirimler yereldir.** Günlük hatırlatma cihazda planlanır, sunucudan
  gönderilmez.
- **Silme.** Uygulamayı silmek cihazdaki tüm verisini de siler; bizde saklanan
  bir kopyası yoktur.

Soru veya bildirim: solvyy.app@gmail.com

---

# Privacy (EN)

Kökçe collects no personal data.

- **No account.** No sign-up, sign-in, email, or profile.
- **No analytics, no ads.** The app contains no third-party SDKs; usage is not
  measured and nothing is sent anywhere.
- **Data stays on the device.** Favourites, the word-of-the-day mode, and the
  notification setting live in local storage only.
- **Content updates.** At most once a day the app makes an anonymous GET
  request to the dictionary file on GitHub (github.com/furknataman/kokce), sending only an `If-None-Match`
  header to learn whether the file changed.
- **Notifications are local**, scheduled on the device.
- **Deleting the app** deletes all of its data; we keep no copy.

Questions: solvyy.app@gmail.com
