-- Existing Supabase projects: run once to add personal application links.
-- New projects: this is already included in schema.sql.
BEGIN;
CREATE TABLE IF NOT EXISTS public.user_applications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  title text NOT NULL CHECK (length(trim(title)) BETWEEN 1 AND 100),
  url text NOT NULL CHECK (length(url) <= 2000 AND url ~ '^https?://[^[:space:]]+$'),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS user_applications_owner ON public.user_applications(user_id, created_at DESC);
ALTER TABLE public.user_applications ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.user_applications FROM anon, authenticated;
GRANT SELECT, DELETE ON public.user_applications TO authenticated;
GRANT INSERT(user_id,title,url) ON public.user_applications TO authenticated;
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='user_applications' AND policyname='own_applications') THEN
    CREATE POLICY own_applications ON public.user_applications FOR ALL TO authenticated
      USING (user_id=(SELECT auth.uid())) WITH CHECK (user_id=(SELECT auth.uid()));
  END IF;
END;
$$;
COMMIT;
