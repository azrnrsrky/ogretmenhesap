-- Run ONLY in the Supabase SQL Editor as project owner, AFTER creating your
-- own Auth user in Dashboard. Keep public signups disabled until this succeeds.
-- Never expose SQL Editor/admin/service_role access to the browser.
BEGIN;
DO $$
DECLARE v_id uuid; v_previous uuid;
BEGIN
  SELECT id INTO v_id FROM auth.users
  WHERE lower(email)='azranurtezcan@users.example.com' AND email_confirmed_at IS NOT NULL;
  IF v_id IS NULL THEN
    RAISE EXCEPTION 'First create and confirm your own teacher account in Authentication > Users.';
  END IF;
  SELECT teacher_id INTO v_previous FROM public.classroom_settings WHERE id FOR UPDATE;
  IF v_previous IS NOT NULL AND v_previous <> v_id THEN
    RAISE EXCEPTION 'A different teacher is already configured; inspect it before replacing.';
  END IF;
  UPDATE public.classroom_settings SET teacher_id=v_id WHERE id;
  UPDATE public.profiles SET full_name='Azranur SARIKAYA TEZCAN',
    class_name='Sınıf Öğretmeni',school='Yenilikçi Sınıf Koordinatörü'
  WHERE id=v_id;
END;
$$;
COMMIT;
