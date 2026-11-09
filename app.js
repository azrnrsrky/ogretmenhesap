import { plannerApi } from './supabase-client.js';
'use strict';
const app = document.querySelector('#app');
const safe = value => String(value).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
let role = null;
let page = 'home';
let data;
let currentUser;
let applicationsState = {items: [], loading: false, error: '', loaded: false};
let authMode = 'login';
let authRole = 'student';
let saveQueue = Promise.resolve(true);
let noteTimer;
let lastSaveError = '';
const today = new Date().toLocaleDateString('tr-TR',{day:'numeric',month:'long',year:'numeric',weekday:'long'});
async function api(path, options={}) { return plannerApi(path,options); }
function save() {
  const snapshot = JSON.stringify(data);
  saveQueue = saveQueue.then(async () => {
    try { await api('/api/data', {method:'PUT', body:snapshot}); lastSaveError=''; return true; }
    catch(error) { lastSaveError=error.message; status(error.message); return false; }
  });
  return saveQueue;
}
async function enter(user) {
  const loaded = await api('/api/data');
  applicationsState = {items: [], loading: false, error: '', loaded: false};
  currentUser = user; role=user.role; data=loaded; page='home'; lastSaveError=''; render();
}
function landing() {
  app.innerHTML=`<div class="landing"><section class="welcome"><div class="brand"><span class="brand-icon">✳</span>öğretmenhesap</div><h1>Birlikte öğren,<br>her gün geliş.</h1><p>Azranur SARIKAYA TEZCAN<br>Sınıf Öğretmeni · Yenilikçi Sınıf Koordinatörü</p><p>Günün planı, küçük hedefler ve büyük keşifler.<br>Sınıfımızın dijital köşesine hoş geldin.</p><div class="welcome-detail">✧ &nbsp; Her öğrencinin kendine ait bir alanı var.</div></section><section class="choose"><p class="eyebrow">SINIFIMIZIN DİJİTAL KÖŞESİ</p><h1>${authMode==='register'?'Sınıfımıza katıl 🌱':'Hoş geldin! 🌿'}</h1><p class="sub">${authMode==='register'?'Sadece kullanıcı adını ve şifreni belirle.':'Kendi alanına giriş yap, gününe güzel başla.'}</p><div class="auth-tabs" aria-label="Hesap türü"><button type="button" data-auth-role="student" aria-pressed="${authRole==='student'}" class="${authRole==='student'?'selected':''}">🎒 Öğrenci</button><button type="button" data-auth-role="teacher" aria-pressed="${authRole==='teacher'}" class="${authRole==='teacher'?'selected':''}">📚 Öğretmen</button></div><form id="auth-form" class="auth-form"><label for="username">Kullanıcı adı</label><input id="username" name="username" autocomplete="username" required minlength="3" maxlength="32" spellcheck="false" autocapitalize="none" placeholder="${authRole==='teacher'?'Öğretmen kullanıcı adınız':'Örn. deniz3a'}"><label for="password">Şifre</label><div class="password-field"><input id="password" name="password" type="password" autocomplete="${authMode==='register'?'new-password':'current-password'}" required minlength="6" maxlength="128" placeholder="En az 6 karakter"><button type="button" id="show-password" aria-label="Şifreyi göster">Göster</button></div><p id="auth-error" role="alert" class="auth-error"></p><button class="primary auth-submit">${authMode==='register'?'Kayıt ol ve başla':'Giriş yap'} &nbsp; →</button></form>${authRole==='student'?`<p class="auth-toggle">${authMode==='register'?'Zaten hesabın var mı?':'Henüz kayıtlı değil misin?'} <button id="toggle-auth" class="text-button">${authMode==='register'?'Giriş yap':'Kayıt ol'}</button></p>`:'<p class="notice">Öğretmen hesabı yönetici tarafından oluşturulur. Öğrenci kayıtları öğretmen paneline erişemez.</p>'}<p class="notice">${authMode==='register'?'E-posta veya telefon gerekmez. Kullanıcı adını ve şifreni unutmayacağın şekilde seç. Şifreni kimseyle paylaşma.':'Bilgilerin hesabına özel saklanır. Ortak cihaz kullanıyorsan işin bitince çıkış yap.'}</p></section></div>`;
  app.querySelectorAll('[data-auth-role]').forEach(b=>b.onclick=()=>{authRole=b.dataset.authRole; authMode='login'; landing();});
  const toggle=app.querySelector('#toggle-auth'); if(toggle)toggle.onclick=()=>{authMode=authMode==='login'?'register':'login';landing();};
  app.querySelector('#show-password').onclick=e=>{const p=app.querySelector('#password');p.type=p.type==='password'?'text':'password';e.currentTarget.textContent=p.type==='password'?'Göster':'Gizle';e.currentTarget.setAttribute('aria-label',p.type==='password'?'Şifreyi göster':'Şifreyi gizle');};
  app.querySelector('#auth-form').onsubmit=async e=>{
    e.preventDefault();const form=e.currentTarget,button=form.querySelector('[type=submit]')||form.querySelector('.auth-submit');
    const username=form.elements.username.value.trim(),password=form.elements.password.value;
    button.disabled=true;app.querySelector('#auth-error').textContent='';
    try { const result=await api('/api/'+authMode,{method:'POST',body:JSON.stringify({username,password})}); await enter(result.user); }
    catch(error) { const target=app.querySelector('#auth-error');if(target)target.textContent=error.message;button.disabled=false; }
  };
}
function lessons() {const day=new Date().getDay();const list=data.lessons.filter(l=>Number(l.day)===day).sort((a,b)=>a.time.localeCompare(b.time));return list.length?list.map(l=>`<div class="lesson"><span class="time">${safe(l.time)}</span><span class="stripe"></span><div><strong>${safe(l.name)}</strong><small>${safe(l.room||'Sınıfım')}</small></div><span class="badge">Ders</span></div>`).join(''):'<p class="sub">Bugün için ders eklenmemiş. Programını oluşturarak başlayabilirsin.</p>';}
function tasks() {return data.tasks.length?data.tasks.map((t,i)=>`<div class="task ${t.done?'done':''}"><input type="checkbox" id="task-${i}" data-task="${i}" ${t.done?'checked':''}><label for="task-${i}">${safe(t.text)}</label><button class="delete" data-delete="${i}" aria-label="Görevi sil">×</button></div>`).join(''):'<p class="sub">Küçük bir hedef, güzel bir başlangıç.<br>İlk görevini aşağıdan ekle.</p>';}
function taskCard(){return `<section class="card"><div class="card-header"><div><h2>${role==='teacher'?'Yapılacaklar':'Ödevlerim & hedeflerim'}</h2><p class="eyebrow">Adım adım, hepsi tamamlanır.</p></div><span class="badge">${data.tasks.filter(t=>t.done).length}/${data.tasks.length}</span></div>${tasks()}<form id="task-form" class="add-form"><input name="task" aria-label="Yeni görev" placeholder="Yeni bir görev ekle…" required maxlength="200"><button class="primary" aria-label="Görev ekle">＋</button></form></section>`;}
function profile(){return `<section class="card"><div class="card-header"><h2>Profil bilgilerim</h2></div><form id="profile-form" class="profile-grid"><label>Ad soyad<input name="name" value="${safe(data.profile.name)}" required maxlength="90"></label><label>${role==='teacher'?'Branş':'Sınıf'}<input name="branch" value="${safe(data.profile.branch)}" maxlength="100"></label><label>${role==='teacher'?'Görev / okul':'Okulum'}<input name="school" value="${safe(data.profile.school)}" maxlength="120"></label><button class="primary">Bilgilerimi kaydet</button></form><p class="notice">Bilgilerin hesabına özel olarak sunucuda saklanır. Başka bir cihazdan da kullanıcı adın ve şifrenle giriş yapabilirsin.</p></section>`;}
function schedule(){const days=['Pazar','Pazartesi','Salı','Çarşamba','Perşembe','Cuma','Cumartesi'];return `<section class="card"><div class="card-header"><h2>Haftalık ders programım</h2></div>${data.lessons.length?data.lessons.slice().sort((a,b)=>a.day-b.day||a.time.localeCompare(b.time)).map(l=>`<div class="lesson"><span class="time">${safe(days[l.day])}<br>${safe(l.time)}</span><span class="stripe"></span><div><strong>${safe(l.name)}</strong><small>${safe(l.room)}</small></div><button class="delete" style="margin-left:auto" data-lesson-delete="${data.lessons.indexOf(l)}" aria-label="Dersi sil">×</button></div>`).join(''):'<p class="sub">Programın henüz boş. İlk dersini ekle.</p>'}<form id="lesson-form" class="profile-grid" style="margin-top:25px"><label>Ders adı<input name="name" required maxlength="80" placeholder="Örn. Türkçe"></label><label>Gün<select name="day">${[1,2,3,4,5,6,0].map(d=>`<option value="${d}">${days[d]}</option>`).join('')}</select></label><label>Başlangıç saati<input name="time" type="time" required value="09:00"></label><label>Sınıf / açıklama<input name="room" maxlength="80" placeholder="Örn. 3-A sınıfı"></label><button class="primary">Ders ekle</button></form></section>`;}
function applications() {
  const state = applicationsState;
  return `<section class="card"><div class="card-header"><div><h2>Uygulama bağlantılarım</h2><p class="eyebrow">Sık kullandığın araçlar, tek bir yerde.</p></div><span class="badge">${state.items.length} uygulama</span></div>
    ${state.loading?'<p class="sub" role="status">Uygulamaların yükleniyor…</p>':state.error?`<p class="applications-error" role="alert">${safe(state.error)}</p><button class="text-button" id="retry-applications">Tekrar dene</button>`:state.items.length?`<div class="applications-grid">${state.items.map(item=>`<article class="application-tile"><span class="application-icon" aria-hidden="true">▦</span><h3>${safe(item.title)}</h3><p>${safe(new URL(item.url).hostname)}</p><div class="application-actions"><a class="primary" href="${safe(item.url)}" target="_blank" rel="noopener noreferrer">Uygulamayı aç ↗</a><button class="text-button" data-app-delete="${safe(item.id)}" aria-label="${safe(item.title)} uygulamasını kaldır">Kaldır</button></div></article>`).join('')}</div>`:'<div class="applications-empty"><span aria-hidden="true">▦</span><h3>Sevdiğin araçlara yer aç</h3><p class="sub">Henüz bir uygulama eklemedin. İlk bağlantını aşağıdan ekleyebilirsin.</p></div>'}
    <form id="application-form" class="profile-grid applications-form"><h2>Yeni uygulama ekle</h2><label>Uygulama adı<input name="title" required maxlength="100" placeholder="Örn. Canva"></label><label>Uygulama bağlantısı<input name="url" type="url" required maxlength="2000" placeholder="https://..."></label><button class="primary" ${state.loading||state.error?'disabled':''}>Uygulamayı ekle</button></form></section>`;
}
async function loadApplications() {
  const owner=currentUser?.id;
  applicationsState.loading=true;applicationsState.error='';render();
  try { const items=await api('/api/applications'); if(currentUser?.id!==owner)return;applicationsState.items=items;applicationsState.loaded=true; }
  catch(error){if(currentUser?.id!==owner)return;applicationsState.error=error.message;}
  applicationsState.loading=false;if(page==='applications')render();
}
function render(){if(!['teacher','student'].includes(role))return landing();const teacher=role==='teacher';const first=teacher?data.profile.name.split(' ')[0]+' Öğretmenim':data.profile.name.split(' ')[0];const headings={home:'Güne güzel bir başlangıç',schedule:'Ders programım',tasks:teacher?'Yapılacaklarım':'Ödevlerim & hedeflerim',profile:'Bana ait bilgiler',applications:'Uygulamalarım'};const links=[['home','⌂','Genel bakış'],['schedule','▦','Ders programım'],['tasks','☑',teacher?'Yapılacaklarım':'Ödevlerim'],['applications','▦','Uygulamalarım'],['profile','♧','Profilim']];app.innerHTML=`<div class="shell"><aside class="sidebar"><div class="brand"><span class="brand-icon">✳</span><div>öğretmenhesap<small>BİRLİKTE GELİŞİYORUZ</small></div></div><div class="navlabel">KİŞİSEL ALANIM</div><nav class="nav" aria-label="Ana menü">${links.map(([id,icon,label])=>`<button data-page="${id}" class="${page===id?'active':''}" ${page===id?'aria-current="page"':''}><span>${icon}</span>${label}</button>`).join('')}</nav><div class="sidebar-bottom"><div class="tip">🌱<strong>Her gün küçük bir adım.</strong>Öğrenmek bir yolculuk.<br>Bugünün de bir izi olsun.</div><button class="role-switch" id="switch">↪ Güvenli çıkış</button></div></aside><main><header class="topbar"><div class="breadcrumb">Kişisel alanım &nbsp; / &nbsp; <b>${links.find(l=>l[0]===page)[2]}</b></div><div class="account"><div class="name">${safe(data.profile.name)}<small>${safe(data.profile.branch)}</small></div><span class="avatar">${safe(data.profile.name.slice(0,1))}</span></div></header><div class="greeting"><div><h1>${page==='home'?`Merhaba, ${safe(first)} 👋`:headings[page]}</h1><p class="sub">${page==='home'?'Yeni bir gün, yeni keşifler. Bugün senin için neler var?':'Kendine ait alanı, kendi ritminde düzenle.'}</p></div><div class="date">▦ &nbsp; ${safe(today)}</div></div>${page==='applications'?applications():page==='profile'?profile():page==='schedule'?schedule():page==='tasks'?taskCard():`<section class="hero"><div><small>${teacher?'ÖĞRETMENİN GÜNLÜĞÜ':'BENİM ÖĞRENME YOLCULUĞUM'}</small><h2>${teacher?'Küçük dokunuşlar,<br>kocaman yarınlar.':'Bugün yeni bir şey<br>keşfetmeye ne dersin?'}</h2><p>${teacher?'İlham verdiğin her çocukla, gelecek biraz daha güzelleşir.':'Merak et, dene ve öğren. Her adımın çok değerli.'}</p></div><div class="hero-art" aria-hidden="true">✎</div></section><div class="stats"><div class="stat"><span class="stat-icon">▦</span><div><strong>${data.lessons.filter(l=>Number(l.day)===new Date().getDay()).length}</strong><small>Bugünkü ders</small></div></div><div class="stat"><span class="stat-icon">☑</span><div><strong>${data.tasks.filter(t=>!t.done).length}</strong><small>Bekleyen görev</small></div></div><div class="stat"><span class="stat-icon">✧</span><div><strong>${data.tasks.filter(t=>t.done).length}</strong><small>Tamamlanan hedef</small></div></div></div><div class="grid"><div><section class="card"><div class="card-header"><div><h2>Bugünün dersleri</h2><p class="eyebrow">Günün akışı, bir bakışta.</p></div><button class="text-button" data-page="schedule">Programı düzenle ↗</button></div>${lessons()}</section><section class="card"><div class="card-header"><h2>Bir not bırak ✎</h2><span class="eyebrow">AKLIMDA KALSIN</span></div><textarea class="note" id="note" aria-label="Kişisel notum" placeholder="Bir fikir, bir hatırlatma, güzel bir an…" maxlength="10000">${safe(data.note)}</textarea><div class="note-footer"><span>Yalnızca senin hesabında saklanır</span><button class="text-button" id="save-note">Notu kaydet ↗</button></div></section></div><div>${taskCard()}<section class="card" style="background:#eef1e2"><p class="eyebrow">GÜNÜN HATIRLATMASI</p><h2 style="line-height:1.8;margin:12px 0">“Bir çocuğun hayatına dokunmak,<br>geleceğe dokunmaktır.”</h2><p class="eyebrow">Sevgiyle, sabırla, birlikte. 🌿</p></section></div></div>`}<p id="status" role="status" aria-live="polite"></p><footer><span>© ${new Date().getFullYear()} öğretmenhesap</span><span>Azranur SARIKAYA TEZCAN · Birlikte öğreniyoruz.</span></footer></main></div>`;bind();}
function status(message){const target=document.querySelector('#status')||document.querySelector('#auth-error');if(target)target.textContent=lastSaveError||message;}
async function persist(message) { const ok=await save(); if(role){render();status(ok?message:lastSaveError);} }
function bind(){
  const retry=app.querySelector('#retry-applications');if(retry)retry.onclick=()=>loadApplications();
  const af=app.querySelector('#application-form');if(af)af.onsubmit=async e=>{
    e.preventDefault();const f=new FormData(af);let url;
    try { url=new URL(f.get('url').trim());if(!['https:','http:'].includes(url.protocol)||url.username||url.password)throw new Error(); }
    catch { status('Geçerli bir http veya https bağlantısı girin.');return; }
    const title=f.get('title').trim();if(!title)return;
    const button=af.querySelector('button');button.disabled=true;
    try { await api('/api/applications',{method:'POST',body:JSON.stringify({title,url:url.href})});await loadApplications();status('Uygulama eklendi.'); }
    catch(error){status(error.message);button.disabled=false;}
  };
  app.querySelectorAll('[data-app-delete]').forEach(button=>button.onclick=async()=>{
    button.disabled=true;
    try { await api('/api/applications',{method:'DELETE',body:JSON.stringify({id:button.dataset.appDelete})});await loadApplications();status('Uygulama kaldırıldı.'); }
    catch(error){status(error.message);button.disabled=false;}
  });
  app.querySelectorAll('[data-page]').forEach(b=>b.onclick=()=>{page=b.dataset.page;render();if(page==='applications'&&!applicationsState.loaded&&!applicationsState.loading)loadApplications();if(lastSaveError)status(lastSaveError);});
  app.querySelector('#switch').onclick=async e=>{
    const button=e.currentTarget;button.disabled=true;clearTimeout(noteTimer);
    if(!await save()){button.disabled=false;return;}
    try { await api('/api/logout',{method:'POST',body:'{}'});role=null;data=null;currentUser=null;authMode='login';landing(); }
    catch(error){status(error.message);button.disabled=false;}
  };
  app.querySelectorAll('[data-task]').forEach(b=>b.onchange=()=>{data.tasks[+b.dataset.task].done=b.checked;persist('Görev güncellendi.');});
  app.querySelectorAll('[data-delete]').forEach(b=>b.onclick=()=>{data.tasks.splice(+b.dataset.delete,1);persist('Görev silindi.');});
  app.querySelectorAll('[data-lesson-delete]').forEach(b=>b.onclick=()=>{data.lessons.splice(+b.dataset.lessonDelete,1);persist('Ders silindi.');});
  const tf=app.querySelector('#task-form');if(tf)tf.onsubmit=async e=>{e.preventDefault();const text=tf.elements.task.value.trim();if(!text)return;tf.querySelector('button').disabled=true;data.tasks.push({text,done:false});await persist('Görev eklendi.');};
  const pf=app.querySelector('#profile-form');if(pf)pf.onsubmit=async e=>{e.preventDefault();const f=new FormData(pf);const name=f.get('name').trim();if(!name)return;data.profile={name,branch:f.get('branch').trim(),school:f.get('school').trim()};pf.querySelector('button').disabled=true;await persist('Profil bilgilerin kaydedildi.');};
  const lf=app.querySelector('#lesson-form');if(lf)lf.onsubmit=async e=>{e.preventDefault();const f=new FormData(lf);const name=f.get('name').trim();if(!name)return;data.lessons.push({name,day:Number(f.get('day')),time:f.get('time'),room:f.get('room').trim()});lf.querySelector('button').disabled=true;await persist('Ders eklendi.');};
  const note=app.querySelector('#note');if(note){note.oninput=()=>{data.note=note.value;clearTimeout(noteTimer);noteTimer=setTimeout(()=>save().then(ok=>{if(ok)status('Notun kaydedildi.');}),600);};app.querySelector('#save-note').onclick=async()=>{clearTimeout(noteTimer);data.note=note.value;const ok=await save();status(ok?'Notun kaydedildi.':lastSaveError);};}
}
async function boot(){
  app.innerHTML='<p class="boot-message" role="status">Sınıfımız hazırlanıyor…</p>';
  try{const result=await api('/api/me');if(result.user)await enter(result.user);else landing();}
  catch(error){landing();app.querySelector('#auth-error').textContent=error.message;}
}
boot();
