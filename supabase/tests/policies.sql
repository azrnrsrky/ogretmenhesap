\set ON_ERROR_STOP on
CREATE FUNCTION pg_temp.denied(q text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN EXECUTE q;
  EXCEPTION WHEN insufficient_privilege OR check_violation THEN RETURN;
  END;
  RAISE EXCEPTION 'Expected denial: %',q;
END;
$$;
CREATE FUNCTION pg_temp.rpc_rejected(q text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN EXECUTE q;
  EXCEPTION WHEN raise_exception THEN RETURN;
  END;
  RAISE EXCEPTION 'Expected RPC rejection: %',q;
END;
$$;
INSERT INTO auth.users VALUES
 ('11111111-1111-1111-1111-111111111111','azranurtezcan@users.example.com',now()),
 ('22222222-2222-2222-2222-222222222222','deniz@users.example.com',now()),
 ('33333333-3333-3333-3333-333333333333','ada@users.example.com',now());
\ir ../teacher.sql
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111',true);
INSERT INTO public.learning_resources(id,title,kind,url) VALUES('cccccccc-cccc-cccc-cccc-cccccccccccc','Sayı Avı','game','/games/math');
INSERT INTO public.assignments(id,title,publish_at) VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Okuma ödevi',now()-interval '1 day');
INSERT INTO public.assignment_recipients VALUES('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','22222222-2222-2222-2222-222222222222');
INSERT INTO public.teacher_documents(category,title,body) VALUES('annual_plan','Yıllık plan','Öğretmene özel');
INSERT INTO public.point_awards(student_id,points,reason) VALUES('22222222-2222-2222-2222-222222222222',10,'Katılım');
DO $$ BEGIN ASSERT private.is_teacher(); ASSERT (SELECT count(*)=3 FROM public.profiles); END $$;
SELECT set_config('request.jwt.claim.sub','22222222-2222-2222-2222-222222222222',true);
DO $$ BEGIN
 ASSERT NOT private.is_teacher();
 ASSERT (SELECT count(*)=2 FROM public.profiles);
 ASSERT (SELECT count(*)=0 FROM public.teacher_documents);
 ASSERT (SELECT count(*)=1 FROM public.assignments);
END $$;
SELECT pg_temp.denied($q$UPDATE public.classroom_settings SET teacher_id=auth.uid()$q$);
SELECT pg_temp.denied($q$INSERT INTO public.point_awards(student_id,points,reason) VALUES(auth.uid(),100,'Fake')$q$);
SELECT pg_temp.denied($q$UPDATE public.profiles SET username='teacher' WHERE id=auth.uid()$q$);
INSERT INTO public.user_applications(user_id,title,url) VALUES(auth.uid(),'Canva','https://www.canva.com/');
SELECT pg_temp.denied($q$INSERT INTO public.user_applications(user_id,title,url) VALUES('33333333-3333-3333-3333-333333333333','Fake','https://example.com/')$q$);
INSERT INTO public.activity_events(resource_id,event_type) VALUES('cccccccc-cccc-cccc-cccc-cccccccccccc','game_start');
DO $$ BEGIN ASSERT (SELECT count(*)=0 FROM public.activity_events); END $$;
SELECT pg_temp.denied($q$INSERT INTO public.activity_events(student_id,resource_id,event_type) VALUES('33333333-3333-3333-3333-333333333333','cccccccc-cccc-cccc-cccc-cccccccccccc','game_start')$q$);
INSERT INTO public.messages(recipient_id,body) VALUES('11111111-1111-1111-1111-111111111111','Öğretmenim merhaba');
SELECT pg_temp.denied($q$INSERT INTO public.messages(recipient_id,body) VALUES('33333333-3333-3333-3333-333333333333','İzinsiz')$q$);
SELECT public.submit_assignment('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','İlk yanıt',NULL);
SELECT pg_temp.rpc_rejected($q$SELECT public.submit_assignment('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Tekrar',NULL)$q$);
SELECT pg_temp.denied($q$UPDATE public.submissions SET grade=100,status='graded'$q$);
INSERT INTO storage.objects(bucket_id,name) VALUES('homework-files','22222222-2222-2222-2222-222222222222/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/work.pdf');
SELECT pg_temp.denied($q$INSERT INTO storage.objects(bucket_id,name) VALUES('homework-files','33333333-3333-3333-3333-333333333333/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/fake.pdf')$q$);
SELECT set_config('request.jwt.claim.sub','33333333-3333-3333-3333-333333333333',true);
DO $$ BEGIN
 ASSERT (SELECT count(*)=0 FROM public.user_applications);
 ASSERT (SELECT count(*)=0 FROM public.assignments);
 ASSERT (SELECT count(*)=0 FROM public.submissions);
 ASSERT (SELECT count(*)=0 FROM public.messages);
 ASSERT (SELECT count(*)=0 FROM storage.objects);
 ASSERT (SELECT count(*)=0 FROM public.point_awards);
END $$;
SELECT pg_temp.rpc_rejected($q$SELECT public.submit_assignment('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Yetkisiz',NULL)$q$);
SELECT set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111',true);
DO $$ DECLARE v uuid; BEGIN
 ASSERT (SELECT count(*)=1 FROM public.activity_events);
 ASSERT (SELECT count(*)=1 FROM public.messages);
 SELECT id INTO v FROM public.submissions;
 PERFORM public.review_submission(v,1,NULL,'Biraz daha açıkla.',true);
END $$;
UPDATE public.classroom_settings SET peer_messaging_enabled=true;
SELECT set_config('request.jwt.claim.sub','22222222-2222-2222-2222-222222222222',true);
INSERT INTO public.messages(recipient_id,body) VALUES('33333333-3333-3333-3333-333333333333','İzinli mesaj');
SELECT public.submit_assignment('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Düzeltilmiş yanıt',
'22222222-2222-2222-2222-222222222222/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/work.pdf');
DO $$ BEGIN ASSERT (SELECT count(*)=2 FROM public.submission_versions); END $$;
SELECT set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111',true);
DO $$ DECLARE v uuid; BEGIN
 SELECT id INTO v FROM public.submissions;
 PERFORM public.review_submission(v,2,90,'Başarılı',false);
 ASSERT (SELECT assignment_points=90 AND bonus_points=10 FROM public.student_points WHERE username='deniz');
END $$;
SELECT set_config('request.jwt.claim.sub','33333333-3333-3333-3333-333333333333',true);
DO $$ BEGIN ASSERT (SELECT count(*)=1 FROM public.messages); END $$;
SET LOCAL ROLE anon;
SELECT pg_temp.denied($q$SELECT * FROM public.profiles$q$);
SELECT pg_temp.denied($q$SELECT * FROM public.messages$q$);
SELECT 'PASS: profiles, admin role, private activity, messaging permissions, homework, versioning, grading, points, private attachments, anonymous denial';
ROLLBACK;
