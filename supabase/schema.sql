-- Öğretmen Hesap · Supabase / PostgreSQL 15+
-- Run once in the SQL Editor of a NEW Supabase project as postgres.
-- Existing application schemas should be backed up and migrated separately.
-- Passwords are managed by Supabase Auth, never by application tables.
BEGIN;
CREATE SCHEMA IF NOT EXISTS private;
REVOKE ALL ON SCHEMA private FROM PUBLIC;
GRANT USAGE ON SCHEMA private TO authenticated;

CREATE TABLE public.profiles (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  username text NOT NULL UNIQUE CHECK (username ~ '^[a-z0-9_.-]{3,32}$'),
  full_name text NOT NULL DEFAULT '' CHECK (length(full_name) <= 100),
  class_name text NOT NULL DEFAULT '' CHECK (length(class_name) <= 80),
  school text NOT NULL DEFAULT '' CHECK (length(school) <= 120),
  created_at timestamptz NOT NULL DEFAULT now()
);

-- A singleton UUID is the ONLY source of teacher authority. User metadata cannot grant it.
CREATE TABLE public.classroom_settings (
  id boolean PRIMARY KEY DEFAULT true CHECK (id),
  teacher_id uuid UNIQUE REFERENCES public.profiles(id) ON DELETE RESTRICT,
  peer_messaging_enabled boolean NOT NULL DEFAULT false
);
INSERT INTO public.classroom_settings(id) VALUES (true);

CREATE FUNCTION private.is_teacher() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT EXISTS (SELECT 1 FROM public.classroom_settings WHERE id AND teacher_id = (SELECT auth.uid()));
$$;
CREATE FUNCTION private.teacher_id() RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT teacher_id FROM public.classroom_settings WHERE id;
$$;
CREATE FUNCTION private.peers_enabled() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT peer_messaging_enabled FROM public.classroom_settings WHERE id;
$$;
CREATE FUNCTION private.is_student(p_id uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = p_id
    AND p.id IS DISTINCT FROM (SELECT private.teacher_id()));
$$;

-- Username-only UI: Auth uses an internal alias username@users.example.com.
-- Ignore all supplied role metadata. Unknown email formats cannot create profiles.
CREATE FUNCTION private.handle_new_user() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_username text;
BEGIN
  IF NEW.email IS NULL OR lower(NEW.email) !~ '^[a-z0-9_.-]{3,32}@users[.]example[.]com$' THEN
    RAISE EXCEPTION 'Use the username registration flow.';
  END IF;
  v_username := split_part(lower(NEW.email), '@', 1);
  INSERT INTO public.profiles(id, username, full_name) VALUES (NEW.id, v_username, v_username);
  RETURN NEW;
END;
$$;
CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE FUNCTION private.handle_new_user();

CREATE TABLE public.personal_planners (
  user_id uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  schedule jsonb NOT NULL DEFAULT '[]'::jsonb CHECK (jsonb_typeof(schedule) = 'array' AND octet_length(schedule::text) <= 65536),
  tasks jsonb NOT NULL DEFAULT '[]'::jsonb CHECK (jsonb_typeof(tasks) = 'array' AND octet_length(tasks::text) <= 65536),
  notes text NOT NULL DEFAULT '' CHECK (length(notes) <= 20000),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE FUNCTION private.touch_updated_at() RETURNS trigger
LANGUAGE plpgsql SET search_path = '' AS $$
BEGIN NEW.updated_at := now(); RETURN NEW; END;
$$;
CREATE TRIGGER touch_planner BEFORE UPDATE ON public.personal_planners
FOR EACH ROW EXECUTE FUNCTION private.touch_updated_at();

CREATE TABLE public.teacher_documents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  category text NOT NULL CHECK (category IN ('annual_plan','module','daily_activity','note')),
  title text NOT NULL CHECK (length(trim(title)) BETWEEN 1 AND 200),
  body text NOT NULL DEFAULT '' CHECK (length(body) <= 100000),
  plan_date date,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER touch_document BEFORE UPDATE ON public.teacher_documents
FOR EACH ROW EXECUTE FUNCTION private.touch_updated_at();

CREATE TABLE public.learning_resources (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL CHECK (length(trim(title)) BETWEEN 1 AND 200),
  kind text NOT NULL CHECK (kind IN ('game','website','module')),
  url text NOT NULL CHECK (url ~ '^https://[^[:space:]]+$' OR url ~ '^/games/[a-z0-9-]+$'),
  description text NOT NULL DEFAULT '' CHECK (length(description) <= 4000),
  enabled boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Only in-app activity. Client-submitted game scores are observations, not awarded grades.
-- Students can append their own events but cannot read any activity history.
CREATE TABLE public.activity_events (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  student_id uuid NOT NULL DEFAULT auth.uid() REFERENCES public.profiles(id) ON DELETE CASCADE,
  resource_id uuid NOT NULL REFERENCES public.learning_resources(id) ON DELETE RESTRICT,
  event_type text NOT NULL CHECK (event_type IN ('resource_open','game_start','game_finish')),
  reported_score integer CHECK (reported_score BETWEEN 0 AND 100),
  occurred_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX activity_student_time ON public.activity_events(student_id, occurred_at DESC);

CREATE TABLE public.messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sender_id uuid NOT NULL DEFAULT auth.uid() REFERENCES public.profiles(id) ON DELETE CASCADE,
  recipient_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  body text NOT NULL CHECK (length(trim(body)) BETWEEN 1 AND 4000),
  hidden_by_teacher boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (sender_id <> recipient_id)
);
CREATE INDEX messages_sender_time ON public.messages(sender_id, created_at DESC);
CREATE INDEX messages_recipient_time ON public.messages(recipient_id, created_at DESC);

CREATE TABLE public.assignments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL CHECK (length(trim(title)) BETWEEN 1 AND 200),
  instructions text NOT NULL DEFAULT '' CHECK (length(instructions) <= 20000),
  -- NULL is a draft; future timestamps schedule publication. Each row is one assignment.
  publish_at timestamptz,
  due_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (due_at IS NULL OR publish_at IS NULL OR due_at >= publish_at)
);
CREATE TABLE public.assignment_recipients (
  assignment_id uuid NOT NULL REFERENCES public.assignments(id) ON DELETE CASCADE,
  student_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  PRIMARY KEY (assignment_id, student_id)
);
CREATE INDEX recipients_student ON public.assignment_recipients(student_id, assignment_id);
CREATE FUNCTION private.can_access_assignment(p_id uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT private.is_teacher() OR EXISTS (
    SELECT 1 FROM public.assignments a JOIN public.assignment_recipients r ON r.assignment_id=a.id
    WHERE a.id=p_id AND r.student_id=(SELECT auth.uid()) AND a.publish_at <= now());
$$;

CREATE TABLE public.submissions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  assignment_id uuid NOT NULL,
  student_id uuid NOT NULL,
  content text NOT NULL DEFAULT '' CHECK (length(content) <= 20000),
  attachment_path text,
  attempt integer NOT NULL DEFAULT 1 CHECK (attempt > 0),
  status text NOT NULL DEFAULT 'submitted' CHECK (status IN ('submitted','returned','graded')),
  grade integer CHECK (grade BETWEEN 0 AND 100),
  feedback text NOT NULL DEFAULT '' CHECK (length(feedback) <= 10000),
  submitted_at timestamptz NOT NULL DEFAULT now(),
  reviewed_at timestamptz,
  UNIQUE (assignment_id, student_id),
  FOREIGN KEY (assignment_id, student_id) REFERENCES public.assignment_recipients(assignment_id, student_id) ON DELETE CASCADE,
  CHECK (length(trim(content)) > 0 OR attachment_path IS NOT NULL),
  CHECK ((status='graded' AND grade IS NOT NULL) OR (status<>'graded' AND grade IS NULL))
);
CREATE INDEX submissions_student ON public.submissions(student_id, submitted_at DESC);
CREATE TABLE public.submission_versions (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  submission_id uuid NOT NULL REFERENCES public.submissions(id) ON DELETE CASCADE,
  attempt integer NOT NULL,
  content text NOT NULL,
  attachment_path text,
  submitted_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (submission_id, attempt)
);
CREATE TABLE public.submission_reviews (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  submission_id uuid NOT NULL REFERENCES public.submissions(id) ON DELETE CASCADE,
  attempt integer NOT NULL,
  grade integer CHECK (grade BETWEEN 0 AND 100),
  feedback text NOT NULL CHECK (length(feedback) <= 10000),
  returned boolean NOT NULL,
  reviewed_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.point_awards (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  points integer NOT NULL CHECK (points BETWEEN 1 AND 1000),
  reason text NOT NULL CHECK (length(trim(reason)) BETWEEN 1 AND 1000),
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Explicit grants: client users cannot alter identity, timestamps, grades or ownership.
REVOKE ALL ON public.profiles, public.classroom_settings, public.personal_planners,
  public.teacher_documents, public.learning_resources, public.activity_events, public.messages,
  public.assignments, public.assignment_recipients, public.submissions, public.submission_versions,
  public.submission_reviews, public.point_awards FROM anon, authenticated;
GRANT SELECT ON public.profiles TO authenticated;
GRANT UPDATE(full_name, class_name, school) ON public.profiles TO authenticated;
GRANT SELECT ON public.classroom_settings TO authenticated;
GRANT UPDATE(peer_messaging_enabled) ON public.classroom_settings TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.personal_planners, public.teacher_documents,
  public.learning_resources, public.assignments, public.assignment_recipients TO authenticated;
GRANT SELECT, DELETE ON public.activity_events TO authenticated;
GRANT INSERT(student_id, resource_id, event_type, reported_score) ON public.activity_events TO authenticated;
GRANT USAGE ON SEQUENCE public.activity_events_id_seq TO authenticated;
GRANT SELECT ON public.messages TO authenticated;
GRANT INSERT(sender_id, recipient_id, body) ON public.messages TO authenticated;
GRANT UPDATE(hidden_by_teacher) ON public.messages TO authenticated;
GRANT SELECT ON public.submissions, public.submission_versions, public.submission_reviews TO authenticated;
GRANT SELECT, INSERT, DELETE ON public.point_awards TO authenticated;

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.classroom_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.personal_planners ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.teacher_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.learning_resources ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.activity_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.assignment_recipients ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.submissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.submission_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.submission_reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.point_awards ENABLE ROW LEVEL SECURITY;

CREATE POLICY profiles_read ON public.profiles FOR SELECT TO authenticated
USING (id=(SELECT auth.uid()) OR private.is_teacher() OR id=private.teacher_id() OR private.peers_enabled());
CREATE POLICY profiles_edit ON public.profiles FOR UPDATE TO authenticated
USING (id=(SELECT auth.uid())) WITH CHECK (id=(SELECT auth.uid()));
CREATE POLICY settings_read ON public.classroom_settings FOR SELECT TO authenticated USING (true);
CREATE POLICY settings_teacher ON public.classroom_settings FOR UPDATE TO authenticated
USING (private.is_teacher()) WITH CHECK (private.is_teacher());
CREATE POLICY own_planner ON public.personal_planners FOR ALL TO authenticated
USING (user_id=(SELECT auth.uid())) WITH CHECK (user_id=(SELECT auth.uid()));
CREATE POLICY teacher_documents_private ON public.teacher_documents FOR ALL TO authenticated
USING (private.is_teacher()) WITH CHECK (private.is_teacher());
CREATE POLICY resource_read ON public.learning_resources FOR SELECT TO authenticated
USING (enabled OR private.is_teacher());
CREATE POLICY resource_teacher ON public.learning_resources FOR ALL TO authenticated
USING (private.is_teacher()) WITH CHECK (private.is_teacher());
CREATE POLICY activity_teacher_read ON public.activity_events FOR SELECT TO authenticated USING (private.is_teacher());
CREATE POLICY activity_teacher_delete ON public.activity_events FOR DELETE TO authenticated USING (private.is_teacher());
CREATE POLICY activity_append ON public.activity_events FOR INSERT TO authenticated
WITH CHECK (student_id=(SELECT auth.uid()) AND private.is_student(student_id)
  AND EXISTS (SELECT 1 FROM public.learning_resources r WHERE r.id=resource_id AND r.enabled));
CREATE POLICY messages_read ON public.messages FOR SELECT TO authenticated
USING (private.is_teacher() OR (NOT hidden_by_teacher AND (sender_id=(SELECT auth.uid()) OR recipient_id=(SELECT auth.uid()))));
CREATE POLICY messages_send ON public.messages FOR INSERT TO authenticated
WITH CHECK (sender_id=(SELECT auth.uid()) AND
  (private.is_teacher() OR recipient_id=private.teacher_id() OR private.peers_enabled()));
CREATE POLICY messages_moderate ON public.messages FOR UPDATE TO authenticated
USING (private.is_teacher()) WITH CHECK (private.is_teacher());
CREATE POLICY assignments_read ON public.assignments FOR SELECT TO authenticated
USING (private.can_access_assignment(id));
CREATE POLICY assignments_teacher ON public.assignments FOR ALL TO authenticated
USING (private.is_teacher()) WITH CHECK (private.is_teacher());
CREATE POLICY recipients_read ON public.assignment_recipients FOR SELECT TO authenticated
USING (private.is_teacher() OR (student_id=(SELECT auth.uid()) AND private.can_access_assignment(assignment_id)));
CREATE POLICY recipients_teacher ON public.assignment_recipients FOR ALL TO authenticated
USING (private.is_teacher()) WITH CHECK (private.is_teacher() AND private.is_student(student_id));
CREATE POLICY submissions_read ON public.submissions FOR SELECT TO authenticated
USING (student_id=(SELECT auth.uid()) OR private.is_teacher());
CREATE POLICY versions_read ON public.submission_versions FOR SELECT TO authenticated
USING (EXISTS (SELECT 1 FROM public.submissions s WHERE s.id=submission_id AND (s.student_id=(SELECT auth.uid()) OR private.is_teacher())));
CREATE POLICY reviews_read ON public.submission_reviews FOR SELECT TO authenticated
USING (EXISTS (SELECT 1 FROM public.submissions s WHERE s.id=submission_id AND (s.student_id=(SELECT auth.uid()) OR private.is_teacher())));
CREATE POLICY awards_read ON public.point_awards FOR SELECT TO authenticated
USING (student_id=(SELECT auth.uid()) OR private.is_teacher());
CREATE POLICY awards_teacher_insert ON public.point_awards FOR INSERT TO authenticated
WITH CHECK (private.is_teacher() AND private.is_student(student_id));
CREATE POLICY awards_teacher_delete ON public.point_awards FOR DELETE TO authenticated USING (private.is_teacher());

-- Submit and review only through these atomic RPCs. Table writes are not granted.
CREATE FUNCTION public.submit_assignment(p_assignment_id uuid, p_content text, p_attachment_path text DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_uid uuid := auth.uid(); v_id uuid; v_status text; v_attempt integer;
BEGIN
  IF v_uid IS NULL OR NOT private.is_student(v_uid) THEN RAISE EXCEPTION 'Student access required.'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.assignment_recipients r JOIN public.assignments a ON a.id=r.assignment_id
    WHERE r.student_id=v_uid AND a.id=p_assignment_id AND a.publish_at <= now()) THEN
    RAISE EXCEPTION 'Assignment unavailable.';
  END IF;
  IF p_content IS NULL OR length(p_content)>20000 OR (length(trim(p_content))=0 AND p_attachment_path IS NULL) THEN
    RAISE EXCEPTION 'Provide an answer or attachment (maximum 20000 characters).';
  END IF;
  IF p_attachment_path IS NOT NULL AND (
    split_part(p_attachment_path,'/',1) <> v_uid::text OR
    split_part(p_attachment_path,'/',2) <> p_assignment_id::text OR
    NOT EXISTS (SELECT 1 FROM storage.objects WHERE bucket_id='homework-files' AND name=p_attachment_path)
  ) THEN RAISE EXCEPTION 'Invalid attachment.'; END IF;
  -- Serialize simultaneous submissions by the same student, including their first submission.
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_uid::text || p_assignment_id::text, 0));
  SELECT id,status,attempt INTO v_id,v_status,v_attempt FROM public.submissions
    WHERE assignment_id=p_assignment_id AND student_id=v_uid FOR UPDATE;
  IF v_status IN ('submitted','graded') THEN RAISE EXCEPTION 'Wait for the teacher to return this assignment.'; END IF;
  IF v_id IS NULL THEN
    INSERT INTO public.submissions(assignment_id,student_id,content,attachment_path)
    VALUES(p_assignment_id,v_uid,p_content,p_attachment_path) RETURNING id,attempt INTO v_id,v_attempt;
  ELSE
    UPDATE public.submissions SET content=p_content,attachment_path=p_attachment_path,attempt=attempt+1,
      status='submitted',grade=NULL,feedback='',reviewed_at=NULL,submitted_at=now()
    WHERE id=v_id RETURNING attempt INTO v_attempt;
  END IF;
  INSERT INTO public.submission_versions(submission_id,attempt,content,attachment_path)
  VALUES(v_id,v_attempt,p_content,p_attachment_path);
  RETURN v_id;
END;
$$;
CREATE FUNCTION public.review_submission(p_submission_id uuid, p_expected_attempt integer,
  p_grade integer, p_feedback text, p_return boolean DEFAULT false)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_row public.submissions%ROWTYPE;
BEGIN
  IF NOT private.is_teacher() THEN RAISE EXCEPTION 'Teacher access required.'; END IF;
  SELECT * INTO v_row FROM public.submissions WHERE id=p_submission_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Submission not found.'; END IF;
  IF p_expected_attempt IS NULL OR v_row.attempt <> p_expected_attempt THEN
    RAISE EXCEPTION 'Submission changed; refresh before reviewing.';
  END IF;
  IF p_feedback IS NULL OR length(p_feedback)>10000 OR p_return IS NULL THEN RAISE EXCEPTION 'Invalid feedback.'; END IF;
  IF NOT p_return AND (p_grade IS NULL OR p_grade NOT BETWEEN 0 AND 100) THEN RAISE EXCEPTION 'Grade must be 0–100.'; END IF;
  IF p_return AND length(trim(p_feedback))=0 THEN RAISE EXCEPTION 'Explain why the work is being returned.'; END IF;
  UPDATE public.submissions SET status=CASE WHEN p_return THEN 'returned' ELSE 'graded' END,
    grade=CASE WHEN p_return THEN NULL ELSE p_grade END,feedback=p_feedback,reviewed_at=now()
  WHERE id=p_submission_id;
  INSERT INTO public.submission_reviews(submission_id,attempt,grade,feedback,returned)
  VALUES(p_submission_id,v_row.attempt,CASE WHEN p_return THEN NULL ELSE p_grade END,p_feedback,p_return);
END;
$$;

CREATE VIEW public.student_points WITH (security_invoker=true) AS
SELECT p.id AS student_id, p.username, p.full_name,
  COALESCE((SELECT sum(s.grade) FROM public.submissions s WHERE s.student_id=p.id AND s.status='graded'),0) AS assignment_points,
  COALESCE((SELECT sum(a.points) FROM public.point_awards a WHERE a.student_id=p.id),0) AS bonus_points
FROM public.profiles p WHERE p.id IS DISTINCT FROM private.teacher_id()
  AND (p.id=(SELECT auth.uid()) OR private.is_teacher());
GRANT SELECT ON public.student_points TO authenticated;

-- Private PDF/image attachments. No overwriting/deleting previously submitted work by students.
INSERT INTO storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
VALUES('homework-files','homework-files',false,10485760,ARRAY['application/pdf','image/jpeg','image/png','image/webp']);
CREATE POLICY homework_upload ON storage.objects FOR INSERT TO authenticated
WITH CHECK (bucket_id='homework-files' AND (storage.foldername(name))[1]=(SELECT auth.uid())::text
  AND private.is_student((SELECT auth.uid())) AND EXISTS (
    SELECT 1 FROM public.assignment_recipients r JOIN public.assignments a ON a.id=r.assignment_id
    WHERE r.student_id=(SELECT auth.uid()) AND a.publish_at <= now()
      AND r.assignment_id::text=(storage.foldername(name))[2]));
CREATE POLICY homework_read ON storage.objects FOR SELECT TO authenticated
USING (bucket_id='homework-files' AND (private.is_teacher() OR (storage.foldername(name))[1]=(SELECT auth.uid())::text));
CREATE POLICY homework_teacher_delete ON storage.objects FOR DELETE TO authenticated
USING (bucket_id='homework-files' AND private.is_teacher());

-- Functions default to PUBLIC execution in PostgreSQL; remove that default explicitly.
REVOKE ALL ON FUNCTION private.is_teacher(),private.teacher_id(),private.peers_enabled(),
  private.is_student(uuid),private.can_access_assignment(uuid),private.handle_new_user(),private.touch_updated_at()
FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.is_teacher(),private.teacher_id(),private.peers_enabled(),
  private.is_student(uuid),private.can_access_assignment(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.submit_assignment(uuid,text,text),public.review_submission(uuid,integer,integer,text,boolean)
FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.submit_assignment(uuid,text,text),public.review_submission(uuid,integer,integer,text,boolean)
TO authenticated;

-- Optional real-time messages. RLS still filters delivered rows.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname='supabase_realtime')
    AND NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname='supabase_realtime' AND schemaname='public' AND tablename='messages') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.messages;
  END IF;
END;
$$;
COMMIT;
