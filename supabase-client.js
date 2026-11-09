import { createClient } from './vendor/supabase.js';
// Publishable key intentionally public. RLS, never the key, grants user permissions.
export const supabase = createClient(
  'https://zslydvggihqqqtbelvav.supabase.co',
  'sb_publishable_AWQoCp_7e3Wy9nCCdHsuLw_C0L4t5P1'
);
function checked(result) {
  if (result.error) {
    const code = result.error.code;
    if (['42P01', 'PGRST205'].includes(code)) throw new Error('Önce SQL kodu düğmesindeki veritabanı şemasını Supabase SQL Editor’da çalıştırın.');
    if (code === 'invalid_credentials') throw new Error('Kullanıcı adı veya şifre hatalı.');
    throw new Error(result.error.message);
  }
  return result.data;
}
async function identity(user) {
  const settings = checked(await supabase.from('classroom_settings').select('teacher_id').eq('id',true).single());
  return {id:user.id, username:user.email.split('@')[0], role:settings.teacher_id===user.id?'teacher':'student'};
}
export async function plannerApi(path, options={}) {
  const body = options.body ? JSON.parse(options.body) : {};
  if(path==='/api/me') {
    const session=checked(await supabase.auth.getSession());
    if(!session.session) return {user:null};
    const result=await supabase.auth.getUser();
    if(result.error) { await supabase.auth.signOut({scope:'local'}); return {user:null}; }
    return {user:await identity(result.data.user)};
  }
  if(path==='/api/login'||path==='/api/register') {
    const username=String(body.username||'').trim().toLowerCase();
    if(!/^[a-z0-9_.-]{3,32}$/.test(username))throw new Error('Kullanıcı adı 3–32 harf, rakam, nokta, tire veya alt çizgi içermeli. Türkçe karakter kullanmayın.');
    const credentials={email:username+'@users.example.com',password:body.password};
    const result=checked(await (path==='/api/register'?supabase.auth.signUp(credentials):supabase.auth.signInWithPassword(credentials)));
    if(!result.session) throw new Error('Hesap doğrulama bekliyor. Öğretmeninizin Supabase ayarlarında Confirm email seçeneğini kapatması gerekiyor.');
    return {user:await identity(result.user)};
  }
  if(path==='/api/logout') { checked(await supabase.auth.signOut()); return {ok:true}; }
  if(path==='/api/data') {
    const {user}=checked(await supabase.auth.getUser());
    if(!user) throw new Error('Lütfen tekrar giriş yapın.');
    if(options.method==='PUT') {
      checked(await supabase.from('profiles').update({full_name:body.profile.name,class_name:body.profile.branch,school:body.profile.school}).eq('id',user.id));
      checked(await supabase.from('personal_planners').upsert({user_id:user.id,schedule:body.lessons,tasks:body.tasks,notes:body.note},{onConflict:'user_id'}));
      return {saved:true};
    }
    const profile=checked(await supabase.from('profiles').select('full_name,username,class_name,school').eq('id',user.id).single());
    const planner=checked(await supabase.from('personal_planners').select('schedule,tasks,notes').eq('user_id',user.id).maybeSingle());
    return {profile:{name:profile.full_name||profile.username,branch:profile.class_name,school:profile.school},lessons:planner?.schedule||[],tasks:planner?.tasks||[],note:planner?.notes||''};
  }
  throw new Error('Desteklenmeyen işlem.');
}
