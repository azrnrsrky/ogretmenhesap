# Supabase kurulumu

Bu dosyalar **yeni bir Supabase projesi** içindir. `schema.sql` bir kez çalıştırılır;
mevcut tabloları silmez veya sessizce üzerine yazmaz. Aynı adlarla tablo/trigger
varsa önce mevcut yapıya uygun migration hazırlanmalıdır. İlk hata tüm işlemi
geri alır.

## Sıra

1. Başlangıçta Authentication ayarlarında **Allow new users to sign up** kapalı
   kalsın; yönetici oluşturulmadan herkese kayıt açmayın.
2. SQL Editor içinde `schema.sql` dosyasının tamamını çalıştırın.
3. Authentication → Users → Add user ile **kendi yönetici hesabınızı** oluşturun:
   dahili e-posta `azranurtezcan@users.example.com`, şifre olarak belirlediğiniz
   öğretmen şifresi, **Auto Confirm User** açık. Bu adres gerçek e-posta değildir.
   Şifreyi SQL dosyasına veya GitHub'a yazmayın.
4. SQL Editor içinde `teacher.sql` çalıştırın. Tek öğretmen UUID'si atanır.
   Kullanıcının gönderdiği `role` metadata'sı hiçbir yetki kazandırmaz.
5. Authentication → Email sağlayıcısını etkin tutun, **Confirm email** kapalı
   olsun. Kullanıcılar e-posta girmediği için dahili adreslere doğrulama postası
   gönderilmez. Minimum şifre uzunluğu belirlediğiniz yönetici şifresiyle uyumlu
   olmalı (Supabase en az 6 karakter ister).
6. Artık **Allow new users to sign up** açılabilir. Canlı sitede Auth rate limits
   ve CAPTCHA yapılandırmasını öğrenci kayıt yoğunluğunuza göre ayarlayın.

## Kullanıcı adıyla giriş

Supabase Auth e-posta/şifre kullanır; arayüz yalnızca kullanıcı adı ve şifre ister.
Öğrencinin kullanıcı adı küçük harfe çevrilip şu biçimde Auth'a gönderilir:

```js
const username = input.trim().toLowerCase();
if (!/^[a-z0-9_.-]{3,32}$/.test(username)) throw new Error('Geçersiz kullanıcı adı');
const email = `${username}@users.example.com`;
await supabase.auth.signUp({ email, password });
// Giriş:
await supabase.auth.signInWithPassword({ email, password });
```

`example.com` rezerve bir örnek alan adıdır, gerçek öğrenci e-postası değildir.
Bu akışta e-posta doğrulama veya e-postayla şifre sıfırlama kullanılmaz. Unutulan
şifreler proje yöneticisi tarafından Auth Admin API veya Dashboard üzerinden
sıfırlanmalıdır; service_role anahtarı tarayıcıya verilmez.

Tarayıcıda **Project URL ve publishable/anon key** kullanılır. Yetkilendirmeyi RLS
sağlar. **service_role / secret key asla tarayıcıya ya da GitHub'a konmaz.**

## Sağlanan yapı

- `profiles`: öğrenci/öğretmen kimlikleri; şifre bulunmaz.
- `classroom_settings`: tek öğretmenin UUID'si ve öğrenci mesajlaşma izni.
- `personal_planners`: hesaba özel program, görev ve notlar.
- `teacher_documents`: yıllık plan, modül, günlük aktivite, not; yalnız öğretmen.
- `learning_resources`, `activity_events`: sistemden açılan kaynaklar ve oyun
  olayları. Geçmişi yalnız öğretmen okur; öğrenci kendi olayını ekleyebilir.
  Bunlar istemcinin bildirdiği olaylardır, doğrulanmış oyun puanı sayılmaz.
  Başka sekmelerde veya sistem dışında gezilen siteler izlenmez.
- `messages`: öğretmen–öğrenci ve izin verildiğinde öğrenci–öğrenci mesajları.
  Öğretmen bütün mesajları görür ve gizleyebilir. Öğrencilere bu denetim açıkça
  bildirilmelidir. Başka öğrencilerin konuşmaları öğrenciye gösterilmez.
- `assignments`, `assignment_recipients`: seçili öğrencilere özel ödevler.
  `publish_at=NULL` taslak; gelecek tarih zamanlanmış yayındır. Her hafta bir
  ödev satırı oluşturulabilir; **otomatik haftalık tekrar bu şemada yoktur**.
- `submissions`, `submission_versions`, `submission_reviews`: teslim, sürümler,
  öğretmen puanı ve geri bildirim. Öğretmen geri gönderdiğinde yeniden teslim.
- `point_awards`, `student_points`: bağımsız ödül puanları ve ödev puanları.
- `homework-files`: özel Storage bucket; PDF/resim, en fazla 10 MB. Dosyalar
  `<öğrenci UUID>/<ödev UUID>/<rastgele dosya adı>` yoluna yüklenir. Teslim edilen
  dosya öğrenci tarafından değiştirilemez. Okuma yalnız sahibi ve öğretmene açık.

## Temel işlemler

Ödev önce taslak oluşturulur, `assignment_recipients` içine seçilen öğrenciler
atanır, sonra `assignments.publish_at` ayarlanır. Öğrenci diğer öğrencilere atanmış
ödevleri ve henüz yayınlanmamış ödevleri okuyamaz.

```js
// Öğrenci: yanıt veya özel bucket'a yüklenmiş dosya yolu.
await supabase.rpc('submit_assignment', {
  p_assignment_id: assignmentId,
  p_content: answer,
  p_attachment_path: null,
});

// Öğretmen: 0–100 puan, son teslim denemesini kontrol eder.
await supabase.rpc('review_submission', {
  p_submission_id: submissionId,
  p_expected_attempt: attempt,
  p_grade: 90,
  p_feedback: 'Çok güzel, açıklamalarını da ekleyebilirsin.',
  p_return: false,
});
// Geri göndermek için p_return:true, p_grade:null ve açıklayıcı geri bildirim.

// Öğretmen: öğrenci–öğrenci mesajlaşmasını aç/kapat.
await supabase.from('classroom_settings')
  .update({ peer_messaging_enabled: true }).eq('id', true);
```

Etkinlik eklerken `.insert(...)` kullanın; `.select()` eklemeyin. Öğrencinin
geçmiş okuma yetkisi olmadığından `RETURNING` ile kayıt okuma isteği reddedilir.

Temel giriş, profil ve kişisel planlayıcı arayüzü bu projeye bağlanmıştır. Mesajlaşma, ödev yönetimi ve öğrenci takibi arayüzleri bu tablolara/RPC’lere ayrıca uyarlanmalıdır. Gerçek projede Auth, Storage ve Realtime akışları ayrıca test edilmelidir.

## Şema testleri

Yerel Docker ortamında `bash supabase/tests/run.sh` komutu geçici PostgreSQL 17
üzerinde şemayı oluşturur ve RLS/RPC testlerini çalıştırır. Test sonunda konteyner
silinir. `tests/fixture.sql` yalnız test için Auth/Storage şemalarını taklit eder;
**gerçek Supabase projesinde çalıştırılmaz**. Bu testler gerçek GoTrue kayıt/giriş,
Storage HTTP servisi veya Realtime teslimatının uçtan uca testi değildir.
