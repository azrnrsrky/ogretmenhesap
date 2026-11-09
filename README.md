# Öğretmen Hesap

Azranur SARIKAYA TEZCAN — Sınıf Öğretmeni, Yenilikçi Sınıf Koordinatörü.

Türkçe, mobil uyumlu öğretmen/öğrenci ekranları. Kullanıcı adı ve şifreyle
Supabase Auth'a giriş; profil, kişisel ders programı, görev ve notlar Supabase'te
saklanır. Yetki kaynağı veritabanındaki tek öğretmen UUID'sidir.

## Çalıştırma

Node.js 22+ ve Python 3 ile:

```sh
npm ci
npm run build
python3 -m http.server 3000 --bind 0.0.0.0
```

`vendor/supabase.js` resmi Supabase istemcisinin kilitlenmiş bağımlılıklardan
üretilen yerel tarayıcı paketidir. Çalışırken CDN gerektirmez.

## Supabase kurulumu

[Kurulum sırası ve erişim kuralları](supabase/README.md). Yeni projede önce
`supabase/schema.sql`, öğretmen Auth hesabını oluşturduktan sonra
`supabase/teacher.sql` çalıştırılır. Kullanıcılar e-posta yazmaz; arayüz dahili
kullanıcı adı adresini üretir. Auth **Confirm email** ayarı kapalı olmalıdır.

Proje URL'si ve yalnızca herkese açık publishable key `supabase-client.js`
içindedir. Secret/service_role anahtarı tarayıcıya veya depoya eklenmez.

SQL şeması öğrenci etkinlik geçmişi, denetimli mesajlar, seçili öğrencilere
ödev atama, teslim/sürüm/geri bildirim, puanlar ve öğretmen belgelerini de kapsar.
**Bu genişletilmiş özelliklerin arayüzleri henüz tamamlanmamıştır.** Mevcut
Supabase projesine şema uygulanması ve gerçek hesaplarla uçtan uca test ayrı
olarak yapılmalıdır. Şema testleri yerel PostgreSQL 17 üzerinde yapılır:

```sh
npm run test:sql
```

## Geçici SQL düğmesi

Ekranın solundaki **SQL kodu** düğmesi şema ve öğretmen yetkisi dosyalarını açar.
Kopyalama, güvenli tarayıcı panosu veya seçili metin üzerinden çalışır. Bu düğme
SQL çalıştırmaz. İş bitince `index.html` içindeki geçici blok/script,
`sql-helper.js` ve ilgili CSS birlikte kaldırılabilir.

## Yayın

Statik arayüz GitHub Pages'te çalışabilir; veri ve Auth Supabase üzerinden
sağlanır. GitHub Settings → Pages → Source: **GitHub Actions** seçin.
`.github/workflows/pages.yml`, main dalına gönderildiğinde yalnız public site
dosyalarını yayımlar. Yayın adresi başarılı Actions deployment çıktısındadır.
Supabase Auth URL ayarlarına canlı site adresi eklenmelidir. Yayın başarısı ve
canlı Supabase işlemleri doğrulanmadan üretim hazır kabul edilmemelidir.
