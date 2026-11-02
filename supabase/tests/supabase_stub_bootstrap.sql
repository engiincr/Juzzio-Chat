-- =============================================================================
-- JUZZIO — Supabase uyumlu YEREL TEST iskeleti (yalnızca boş test veritabanı)
--
-- Gerçek Supabase projesinde ÇALIŞTIRMAYIN. Bu dosya, kanonik
-- supabase/juzzio_database.sql dosyasının ve supabase/tests/*.sql testlerinin
-- düz PostgreSQL (CI servis konteyneri veya yerel kurulum) üzerinde
-- çalıştırılabilmesi için Supabase'in sağladığı en küçük nesne kümesini taklit
-- eder: roller (anon/authenticated/service_role), auth şeması (users, sessions,
-- refresh_tokens, uid/jwt/role), storage şeması (buckets, objects, foldername),
-- extensions şeması ve supabase_realtime yayını.
--
-- Kullanım:
--   psql -d juzzio_test -v ON_ERROR_STOP=1 -f supabase/tests/supabase_stub_bootstrap.sql
--   psql -d juzzio_test -v ON_ERROR_STOP=1 --single-transaction -f supabase/juzzio_database.sql
--   psql -d juzzio_test -v ON_ERROR_STOP=1 -f supabase/tests/juzzio_database_tests.sql
-- =============================================================================
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN CREATE ROLE anon NOLOGIN NOINHERIT; END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN CREATE ROLE authenticated NOLOGIN NOINHERIT; END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN CREATE ROLE service_role NOLOGIN NOINHERIT BYPASSRLS; END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'supabase_admin') THEN CREATE ROLE supabase_admin NOLOGIN; END IF;
END $$;
GRANT anon, authenticated, service_role TO CURRENT_USER;

CREATE SCHEMA IF NOT EXISTS extensions;
CREATE SCHEMA IF NOT EXISTS auth;
CREATE SCHEMA IF NOT EXISTS storage;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
GRANT USAGE ON SCHEMA public, extensions, auth, storage TO anon, authenticated, service_role;
GRANT ALL ON SCHEMA public TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO anon, authenticated, service_role;

CREATE TABLE IF NOT EXISTS auth.users (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    instance_id uuid,
    aud text DEFAULT 'authenticated',
    role text DEFAULT 'authenticated',
    email text,
    phone text,
    encrypted_password text,
    email_confirmed_at timestamptz DEFAULT now(),
    raw_user_meta_data jsonb NOT NULL DEFAULT '{}'::jsonb,
    raw_app_meta_data jsonb NOT NULL DEFAULT '{}'::jsonb,
    last_sign_in_at timestamptz,
    banned_until timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS auth.sessions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    user_agent text,
    ip inet
);
CREATE TABLE IF NOT EXISTS auth.refresh_tokens (
    id bigserial PRIMARY KEY,
    token text,
    user_id text,
    session_id uuid,
    revoked boolean DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$
    SELECT NULLIF(COALESCE(current_setting('request.jwt.claim.sub', true),
                           (NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')), '')::uuid
$$;
CREATE OR REPLACE FUNCTION auth.role() RETURNS text LANGUAGE sql STABLE AS $$
    SELECT COALESCE(NULLIF(current_setting('request.jwt.claim.role', true), ''),
                    (NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role'))
$$;
CREATE OR REPLACE FUNCTION auth.jwt() RETURNS jsonb LANGUAGE sql STABLE AS $$
    SELECT COALESCE(NULLIF(current_setting('request.jwt.claims', true), '')::jsonb,
                    jsonb_build_object('sub', current_setting('request.jwt.claim.sub', true)))
$$;
CREATE OR REPLACE FUNCTION auth.email() RETURNS text LANGUAGE sql STABLE AS $$
    SELECT email FROM auth.users WHERE id = auth.uid()
$$;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA auth TO anon, authenticated, service_role;
GRANT SELECT ON auth.users TO service_role;

CREATE TABLE IF NOT EXISTS storage.buckets (
    id text PRIMARY KEY,
    name text NOT NULL UNIQUE,
    owner uuid,
    public boolean DEFAULT false,
    file_size_limit bigint,
    allowed_mime_types text[],
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now()
);
CREATE TABLE IF NOT EXISTS storage.objects (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    bucket_id text REFERENCES storage.buckets(id),
    name text,
    owner uuid,
    owner_id text,
    metadata jsonb,
    path_tokens text[] GENERATED ALWAYS AS (string_to_array(name, '/')) STORED,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now(),
    last_accessed_at timestamptz DEFAULT now(),
    UNIQUE (bucket_id, name)
);
ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;
ALTER TABLE storage.buckets ENABLE ROW LEVEL SECURITY;
CREATE OR REPLACE FUNCTION storage.foldername(name text) RETURNS text[] LANGUAGE sql IMMUTABLE AS $$
    SELECT (string_to_array(name, '/'))[1:array_length(string_to_array(name, '/'), 1) - 1]
$$;
CREATE OR REPLACE FUNCTION storage.filename(name text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT (string_to_array(name, '/'))[array_length(string_to_array(name, '/'), 1)]
$$;
CREATE OR REPLACE FUNCTION storage.extension(name text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT lower(substring(name from '\.([^./]+)$'))
$$;
GRANT ALL ON storage.objects, storage.buckets TO anon, authenticated, service_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA storage TO anon, authenticated, service_role;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
        CREATE PUBLICATION supabase_realtime;
    END IF;
END $$;


-- v0.9.0: Supabase Realtime yetkilendirme iskeleti (yayın/presence RLS'i test edilebilsin)
--  Gerçek Supabase'de realtime.messages ve realtime.topic() hazır gelir; burada topic GUC'den okunur.
CREATE SCHEMA IF NOT EXISTS realtime;
GRANT USAGE ON SCHEMA realtime TO anon, authenticated, service_role;
CREATE TABLE IF NOT EXISTS realtime.messages (
    id BIGSERIAL PRIMARY KEY,
    topic TEXT NOT NULL,
    extension TEXT NOT NULL,
    payload JSONB,
    event TEXT,
    private BOOLEAN DEFAULT true,
    inserted_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE realtime.messages ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT ON realtime.messages TO authenticated;
GRANT USAGE ON SEQUENCE realtime.messages_id_seq TO authenticated;
CREATE OR REPLACE FUNCTION realtime.topic() RETURNS TEXT LANGUAGE sql STABLE AS $$
    SELECT NULLIF(current_setting('realtime.topic', true), '')
$$;
GRANT EXECUTE ON FUNCTION realtime.topic() TO anon, authenticated, service_role;
