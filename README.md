# Öğretmen Hesap

Azranur SARIKAYA TEZCAN — Sınıf Öğretmeni, Yenilikçi Sınıf Koordinatörü.

Öğretmen ve öğrenci ekranları bulunan, Türkçe ve mobil uyumlu günlük planlayıcı.
Profil, haftalık ders programı, görevler ve kişisel notlar içerir.

## Yerelde çalıştırma

Derleme veya paket kurulumu gerekmez. Python 3 ile:

```sh
cd /workspace/ogretmenhesap
python3 -m http.server 3000 --bind 0.0.0.0
```

## Veri saklama

Veriler tarayıcının localStorage alanında, ekran türüne göre ayrı saklanır.
Sunucu, gerçek hesap, parola, cihazlar arası eşitleme veya öğretmene veri gönderme
bu sürümde bulunmaz. Ekran seçimi erişim kontrolü değildir. Ortak cihazlarda
hassas bilgi kullanmayın; tarayıcı verilerinin silinmesi kayıtları siler.
Aynı tarayıcıdaki öğrenci ekranı tek bir öğrenci profili içindir.

## GitHub Pages

GitHub depo ayarlarında **Pages → Build and deployment → Source: GitHub Actions**
seçin. `main` dalına gönderilen değişiklikler `.github/workflows/pages.yml` ile
yayımlanır. İlk kurulumda Pages etkinleştirilmiş olmalıdır.
Yayımlama adresini başarılı `Publish GitHub Pages` çalışmasının deployment
çıktısından alın.
