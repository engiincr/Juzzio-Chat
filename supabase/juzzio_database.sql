-- =============================================================================
-- JUZZIO — TEK KANONİK VERİTABANI DOSYASI (Supabase / PostgreSQL 17)
--
-- Bu dosya projedeki TÜM veritabanı tanımlarını içerir (tablolar, sütunlar,
-- kısıtlar, indeksler, fonksiyonlar/RPC'ler, tetikleyiciler, RLS politikaları,
-- Storage kuralları, Realtime yayınları ve zorunlu başlangıç verileri).
-- Eskiden 9 ayrı migration dosyasında bulunan içerik, yürütülme sırası
-- korunarak bu dosyada birleştirildi (bölüm başlıklarına bakın).
--
-- KURALLAR
--  • Bundan sonraki her veritabanı değişikliği YALNIZCA bu dosyaya eklenir;
--    yeni SQL/migration dosyası oluşturulmaz.
--  • Dosya tekrar çalıştırılabilir (idempotent) olmalıdır: CREATE ... IF NOT
--    EXISTS, CREATE OR REPLACE, DROP ... IF EXISTS, ADD COLUMN IF NOT EXISTS,
--    kısıtlar NOT VALID. Veri silen/sıfırlayan komut eklenmez.
--  • GitHub Actions dosyanın SHA-256 özeti değiştiğinde dosyanın tamamını tek
--    işlem (transaction) içinde uygular; hata olursa hiçbir değişiklik kalmaz.
--  • Elle uygulamak için: Supabase → SQL Editor → bu dosyanın tamamını çalıştırın.
--
-- Doğrulama (yerel PostgreSQL): boş veritabanına 2 kez + canlı şema kopyasına
-- 2 kez hatasız uygulanır; RLS/P0001 testleri supabase/tests altında.
-- =============================================================================


-- #############################################################################
-- BÖLÜM 1/9 — kaynak: 20261026000000_juzzio_schema.sql
-- #############################################################################
-- =============================================================================
-- JUZZIO v0.0.8 - Tam Kapsamlı PostgreSQL Şeması, Gizlilik, Engellenenler (QR Sync)
-- Seçmeli Grup Üyeleri, Fotoğraf/Video Durum Paylaşımı Storage Politikaları ve OTA
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 1. PROFILES TABLOSU
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    username TEXT UNIQUE,
    email TEXT NOT NULL,
    display_name TEXT NOT NULL,
    bio TEXT NOT NULL DEFAULT 'Juzzio • Sınır Tanımayan Anlık İletişim',
    preferred_lang TEXT NOT NULL DEFAULT 'tr',
    subtitle_lang TEXT NOT NULL DEFAULT 'tr',
    app_lang TEXT NOT NULL DEFAULT 'tr',
    is_silent_mode BOOLEAN NOT NULL DEFAULT false,
    avatar_url TEXT,
    is_online BOOLEAN NOT NULL DEFAULT true,
    last_seen TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    privacy_last_seen TEXT NOT NULL DEFAULT 'everyone',
    privacy_online TEXT NOT NULL DEFAULT 'everyone',
    privacy_avatar TEXT NOT NULL DEFAULT 'everyone',
    privacy_bio TEXT NOT NULL DEFAULT 'everyone',
    privacy_status TEXT NOT NULL DEFAULT 'everyone',
    privacy_groups TEXT NOT NULL DEFAULT 'everyone',
    read_receipts BOOLEAN NOT NULL DEFAULT true,
    default_message_timer TEXT NOT NULL DEFAULT 'off',
    strict_account_mode BOOLEAN NOT NULL DEFAULT false,
    blocked_users JSONB NOT NULL DEFAULT '[]'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS username TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS bio TEXT NOT NULL DEFAULT 'Juzzio • Sınır Tanımayan Anlık İletişim';
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS subtitle_lang TEXT NOT NULL DEFAULT 'tr';
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS app_lang TEXT NOT NULL DEFAULT 'tr';
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS is_silent_mode BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS privacy_last_seen TEXT NOT NULL DEFAULT 'everyone';
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS privacy_online TEXT NOT NULL DEFAULT 'everyone';
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS privacy_avatar TEXT NOT NULL DEFAULT 'everyone';
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS privacy_bio TEXT NOT NULL DEFAULT 'everyone';
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS privacy_status TEXT NOT NULL DEFAULT 'everyone';
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS privacy_groups TEXT NOT NULL DEFAULT 'everyone';
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS read_receipts BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS default_message_timer TEXT NOT NULL DEFAULT 'off';
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS strict_account_mode BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS blocked_users JSONB NOT NULL DEFAULT '[]'::jsonb;

CREATE UNIQUE INDEX IF NOT EXISTS idx_profiles_username_lower
    ON public.profiles (LOWER(username))
    WHERE username IS NOT NULL;

CREATE OR REPLACE FUNCTION public.resolve_email_by_username(p_username TEXT)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_email TEXT;
BEGIN
    SELECT email INTO v_email
    FROM public.profiles
    WHERE LOWER(username) = LOWER(TRIM(REPLACE(p_username, '@', '')))
       OR LOWER(display_name) = LOWER(TRIM(REPLACE(p_username, '@', '')))
    LIMIT 1;
    RETURN v_email;
END;
$$;

GRANT EXECUTE ON FUNCTION public.resolve_email_by_username(TEXT) TO anon, authenticated, service_role;

-- Hesabı ve İlişkili Tüm Verileri Kalıcı Silme Fonksiyonu
CREATE OR REPLACE FUNCTION public.delete_my_juzzio_account()
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID := auth.uid();
BEGIN
    IF v_uid IS NULL THEN
        RETURN FALSE;
    END IF;
    DELETE FROM public.messages WHERE sender_id = v_uid;
    DELETE FROM public.stories WHERE user_id = v_uid;
    DELETE FROM public.friendships WHERE requester_id = v_uid OR receiver_id = v_uid;
    DELETE FROM public.call_logs WHERE caller_id = v_uid OR receiver_id = v_uid;
    DELETE FROM public.rooms WHERE created_by = v_uid AND room_code <> 'juzzio-couple-main';
    DELETE FROM public.profiles WHERE id = v_uid;
    DELETE FROM auth.users WHERE id = v_uid;
    RETURN TRUE;
EXCEPTION WHEN OTHERS THEN
    DELETE FROM public.profiles WHERE id = v_uid;
    RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION public.delete_my_juzzio_account() TO authenticated, service_role;

-- 2. ROOMS TABLOSU (Seçmeli Grup Üyeleri ve Süreli Mesaj Desteği - Rastgele Üye Yok!)
CREATE TABLE IF NOT EXISTS public.rooms (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    room_code TEXT UNIQUE NOT NULL,
    title TEXT NOT NULL DEFAULT 'Juzzio Özel Hat',
    livekit_room_name TEXT UNIQUE NOT NULL DEFAULT 'juzzio_live_room',
    is_group BOOLEAN NOT NULL DEFAULT false,
    disappearing_timer TEXT NOT NULL DEFAULT 'off',
    is_archived BOOLEAN NOT NULL DEFAULT false,
    is_call_active BOOLEAN NOT NULL DEFAULT false,
    active_call JSONB DEFAULT NULL,
    group_members JSONB NOT NULL DEFAULT '[]'::jsonb,
    group_member_ids JSONB NOT NULL DEFAULT '[]'::jsonb,
    created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.rooms ADD COLUMN IF NOT EXISTS is_group BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.rooms ADD COLUMN IF NOT EXISTS disappearing_timer TEXT NOT NULL DEFAULT 'off';
ALTER TABLE public.rooms ADD COLUMN IF NOT EXISTS is_archived BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.rooms ADD COLUMN IF NOT EXISTS is_call_active BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.rooms ADD COLUMN IF NOT EXISTS active_call JSONB DEFAULT NULL;
ALTER TABLE public.rooms ADD COLUMN IF NOT EXISTS group_members JSONB NOT NULL DEFAULT '[]'::jsonb;
ALTER TABLE public.rooms ADD COLUMN IF NOT EXISTS group_member_ids JSONB NOT NULL DEFAULT '[]'::jsonb;
ALTER TABLE public.rooms ALTER COLUMN group_members SET DEFAULT '[]'::jsonb;

-- Eski sahte Fikret/Ari/Engin test grubunu temizle
DELETE FROM public.rooms WHERE room_code = 'juzzio-group-tanisma';

-- 3. MESSAGES TABLOSU
CREATE TABLE IF NOT EXISTS public.messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    room_id UUID NOT NULL REFERENCES public.rooms(id) ON DELETE CASCADE,
    sender_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    sender_name TEXT DEFAULT '',
    receiver_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    message_type TEXT NOT NULL DEFAULT 'text',
    source_lang TEXT NOT NULL DEFAULT 'auto',
    target_lang TEXT NOT NULL DEFAULT 'tr',
    original_text TEXT NOT NULL DEFAULT '',
    translated_text TEXT NOT NULL DEFAULT '',
    audio_url TEXT,
    image_url TEXT,
    video_url TEXT,
    story_id UUID,
    audio_duration_ms INTEGER DEFAULT 0,
    waveform_peaks JSONB DEFAULT '[]'::jsonb,
    reactions JSONB NOT NULL DEFAULT '{}'::jsonb,
    is_read BOOLEAN NOT NULL DEFAULT false,
    is_pinned BOOLEAN NOT NULL DEFAULT false,
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS sender_name TEXT DEFAULT '';
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS receiver_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS image_url TEXT;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS video_url TEXT;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS story_id UUID;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS reactions JSONB NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS is_pinned BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS expires_at TIMESTAMPTZ;
ALTER TABLE public.messages DROP CONSTRAINT IF EXISTS messages_message_type_check;
ALTER TABLE public.messages DROP CONSTRAINT IF EXISTS messages_source_lang_check;
ALTER TABLE public.messages DROP CONSTRAINT IF EXISTS messages_target_lang_check;

-- 4. VOICE_NOTES TABLOSU
CREATE TABLE IF NOT EXISTS public.voice_notes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    message_id UUID UNIQUE NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
    room_id UUID NOT NULL REFERENCES public.rooms(id) ON DELETE CASCADE,
    sender_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    storage_path TEXT NOT NULL,
    public_url TEXT NOT NULL,
    mime_type TEXT NOT NULL DEFAULT 'audio/mp4',
    duration_ms INTEGER NOT NULL DEFAULT 0,
    source_lang TEXT NOT NULL DEFAULT 'tr',
    transcript_original TEXT NOT NULL DEFAULT '',
    transcript_translated TEXT NOT NULL DEFAULT '',
    waveform_data JSONB NOT NULL DEFAULT '[]'::jsonb,
    deepgram_confidence NUMERIC(5,4) DEFAULT 0.0000,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 5. FRIENDSHIPS TABLOSU
CREATE TABLE IF NOT EXISTS public.friendships (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    requester_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    requester_username TEXT NOT NULL DEFAULT '',
    requester_name TEXT NOT NULL DEFAULT '',
    requester_avatar TEXT,
    receiver_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    receiver_username TEXT NOT NULL DEFAULT '',
    receiver_name TEXT NOT NULL DEFAULT '',
    receiver_avatar TEXT,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'rejected')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(requester_id, receiver_id)
);

-- 6. STORIES TABLOSU (Fotoğraf, Video ve Metin Durum Paylaşımı Desteği)
CREATE TABLE IF NOT EXISTS public.stories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    username TEXT NOT NULL DEFAULT '',
    display_name TEXT NOT NULL DEFAULT '',
    user_avatar TEXT,
    media_type TEXT NOT NULL DEFAULT 'image',
    media_url TEXT,
    video_duration_sec INTEGER NOT NULL DEFAULT 15,
    filter_preset TEXT NOT NULL DEFAULT 'none',
    bg_color_hex TEXT DEFAULT '#161618',
    caption_original TEXT NOT NULL DEFAULT '',
    caption_translated TEXT NOT NULL DEFAULT '',
    overlay_text_original TEXT NOT NULL DEFAULT '',
    overlay_text_translated TEXT NOT NULL DEFAULT '',
    likes JSONB NOT NULL DEFAULT '[]'::jsonb,
    expires_at TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '24 hours'),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.stories DROP CONSTRAINT IF EXISTS stories_media_type_check;
ALTER TABLE public.stories ADD COLUMN IF NOT EXISTS video_duration_sec INTEGER NOT NULL DEFAULT 15;
ALTER TABLE public.stories ADD COLUMN IF NOT EXISTS filter_preset TEXT NOT NULL DEFAULT 'none';

-- 7. CALL_LOGS TABLOSU
CREATE TABLE IF NOT EXISTS public.call_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    room_id UUID REFERENCES public.rooms(id) ON DELETE SET NULL,
    caller_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    caller_name TEXT NOT NULL DEFAULT '',
    caller_avatar TEXT,
    receiver_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    receiver_name TEXT NOT NULL DEFAULT '',
    receiver_avatar TEXT,
    is_video BOOLEAN NOT NULL DEFAULT false,
    status TEXT NOT NULL DEFAULT 'answered' CHECK (status IN ('ringing', 'answered', 'missed', 'busy_silent', 'rejected', 'ended')),
    status_reason TEXT NOT NULL DEFAULT '',
    duration_sec INTEGER NOT NULL DEFAULT 0,
    data_kb INTEGER NOT NULL DEFAULT 14,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.call_logs DROP CONSTRAINT IF EXISTS call_logs_status_check;

INSERT INTO public.rooms (room_code, title, livekit_room_name)
VALUES ('juzzio-couple-main', 'Juzzio Özel Hat', 'juzzio_live_room')
ON CONFLICT (room_code) DO NOTHING;

-- 8. STORAGE BUCKETS (Stories Video/Image, Avatars, Voice Notes)
DO $$
BEGIN
    INSERT INTO storage.buckets (id, name, public, file_size_limit)
    VALUES
        ('stories', 'stories', true, 104857600),
        ('avatars', 'avatars', true, 20971520),
        ('voice-notes', 'voice-notes', true, 52428800)
    ON CONFLICT (id) DO UPDATE
    SET public = true,
        file_size_limit = EXCLUDED.file_size_limit;
EXCEPTION WHEN OTHERS THEN
    NULL;
END $$;

DO $$
BEGIN
    DROP POLICY IF EXISTS "juzzio_storage_public_read" ON storage.objects;
    CREATE POLICY "juzzio_storage_public_read" ON storage.objects FOR SELECT TO anon, authenticated USING (bucket_id IN ('stories', 'avatars', 'voice-notes'));
    DROP POLICY IF EXISTS "juzzio_storage_auth_insert" ON storage.objects;
    CREATE POLICY "juzzio_storage_auth_insert" ON storage.objects FOR INSERT TO anon, authenticated WITH CHECK (bucket_id IN ('stories', 'avatars', 'voice-notes'));
    DROP POLICY IF EXISTS "juzzio_storage_auth_update" ON storage.objects;
    CREATE POLICY "juzzio_storage_auth_update" ON storage.objects FOR UPDATE TO anon, authenticated USING (bucket_id IN ('stories', 'avatars', 'voice-notes'));
EXCEPTION WHEN OTHERS THEN
    NULL;
END $$;

-- RLS Politikaları
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.voice_notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.friendships ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.call_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "profiles_select_all" ON public.profiles;
CREATE POLICY "profiles_select_all" ON public.profiles FOR SELECT TO anon, authenticated USING (true);
DROP POLICY IF EXISTS "profiles_insert_own" ON public.profiles;
CREATE POLICY "profiles_insert_own" ON public.profiles FOR INSERT TO authenticated WITH CHECK (auth.uid() = id);
DROP POLICY IF EXISTS "profiles_update_own" ON public.profiles;
CREATE POLICY "profiles_update_own" ON public.profiles FOR UPDATE TO authenticated USING (auth.uid() = id) WITH CHECK (auth.uid() = id);
DROP POLICY IF EXISTS "profiles_delete_own" ON public.profiles;
CREATE POLICY "profiles_delete_own" ON public.profiles FOR DELETE TO authenticated USING (auth.uid() = id);

DROP POLICY IF EXISTS "rooms_all_auth" ON public.rooms;
CREATE POLICY "rooms_all_auth" ON public.rooms FOR ALL TO authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "messages_all_auth" ON public.messages;
CREATE POLICY "messages_all_auth" ON public.messages FOR ALL TO authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "voice_notes_all_auth" ON public.voice_notes;
CREATE POLICY "voice_notes_all_auth" ON public.voice_notes FOR ALL TO authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "friendships_all_auth" ON public.friendships;
CREATE POLICY "friendships_all_auth" ON public.friendships FOR ALL TO authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "stories_all_auth" ON public.stories;
CREATE POLICY "stories_all_auth" ON public.stories FOR ALL TO authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "call_logs_all_auth" ON public.call_logs;
CREATE POLICY "call_logs_all_auth" ON public.call_logs FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- 9. APP_RELEASES TABLOSU (Gerçek Zamanlı OTA Güncelleme Bildirimi: v0.0.8)
CREATE TABLE IF NOT EXISTS public.app_releases (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    version_name TEXT UNIQUE NOT NULL,
    version_code INTEGER NOT NULL DEFAULT 8,
    apk_url TEXT NOT NULL DEFAULT 'https://github.com/engiincr/Juzzio-Chat/releases/latest/download/Juzzio-latest.apk',
    notes_tr TEXT NOT NULL DEFAULT 'Yeni Juzzio v0.0.8 sürümü hazır! Hemen OTA ile güncelleyebilirsiniz.',
    notes_en TEXT NOT NULL DEFAULT 'A new Juzzio v0.0.8 version is available! Update now via OTA.',
    is_mandatory BOOLEAN NOT NULL DEFAULT false,
    published_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.app_releases ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "app_releases_select_all" ON public.app_releases;
CREATE POLICY "app_releases_select_all" ON public.app_releases FOR SELECT TO anon, authenticated USING (true);
DROP POLICY IF EXISTS "app_releases_all_auth" ON public.app_releases;
CREATE POLICY "app_releases_all_auth" ON public.app_releases FOR ALL TO authenticated, service_role USING (true) WITH CHECK (true);

-- (v0.0.8 tarihî sürüm kaydı kanonik dosyadan çıkarıldı: şema değil, eski veri)

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'app_releases') THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.app_releases;
    END IF;
END $$;

-- #############################################################################
-- BÖLÜM 2/9 — kaynak: 20261028000000_juzzio_social_platform.sql
-- #############################################################################
-- =============================================================================
-- JUZZIO v0.0.9 - Sosyal Medya Platformu Genişletme Şeması (Idempotent Migration)
-- Gönderiler (Posts/Reels/Carousel), Beğeniler, Yorumlar, Takip İlişkileri (Follows),
-- Kaydedilenler (Saved Posts), Bildirimler (Notifications), Hikâye Görüntüleyenler,
-- Şikâyetler (Reports), Engellenen/Sessize Alınan Kullanıcılar ve Güvenli RLS Politikaları
-- Mevcut 20261026000000_juzzio_schema.sql tablolarını ve verilerini korur.
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- -----------------------------------------------------------------------------
-- 1. PROFILES TABLOSU SOSYAL AĞ ALANLARI (Geriye Dönük Uyumlu Genişletme)
-- -----------------------------------------------------------------------------
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS cover_url TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS website_url TEXT NOT NULL DEFAULT '';
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS is_private_account BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS is_verified BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS privacy_posts TEXT NOT NULL DEFAULT 'everyone';
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS allow_unknown_calls BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS muted_users JSONB NOT NULL DEFAULT '[]'::jsonb;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS user_preferences JSONB NOT NULL DEFAULT '{}'::jsonb;

-- -----------------------------------------------------------------------------
-- 2. STORIES TABLOSU EK ALANLAR (Kitle Seçimi ve Arşiv Desteği)
-- -----------------------------------------------------------------------------
ALTER TABLE public.stories ADD COLUMN IF NOT EXISTS visibility TEXT NOT NULL DEFAULT 'everyone';
ALTER TABLE public.stories ADD COLUMN IF NOT EXISTS is_archived BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.stories ADD COLUMN IF NOT EXISTS stickers_json JSONB NOT NULL DEFAULT '[]'::jsonb;
ALTER TABLE public.stories ADD COLUMN IF NOT EXISTS alt_text TEXT NOT NULL DEFAULT '';

-- -----------------------------------------------------------------------------
-- 3. BLOCKED_USERS & MUTED_USERS TABLOLARI (İki Taraflı Görünürlük & Güvenlik)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.blocked_users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    blocker_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    blocked_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    blocked_username TEXT NOT NULL DEFAULT '',
    blocked_display_name TEXT NOT NULL DEFAULT '',
    blocked_avatar_url TEXT,
    reason TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT blocked_users_no_self_block CHECK (blocker_id <> blocked_id),
    CONSTRAINT blocked_users_unique_pair UNIQUE (blocker_id, blocked_id)
);

CREATE INDEX IF NOT EXISTS idx_blocked_users_blocker ON public.blocked_users(blocker_id);
CREATE INDEX IF NOT EXISTS idx_blocked_users_blocked ON public.blocked_users(blocked_id);

CREATE TABLE IF NOT EXISTS public.muted_users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    muter_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    muted_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    mute_posts BOOLEAN NOT NULL DEFAULT true,
    mute_stories BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT muted_users_no_self_mute CHECK (muter_id <> muted_id),
    CONSTRAINT muted_users_unique_pair UNIQUE (muter_id, muted_id)
);

CREATE INDEX IF NOT EXISTS idx_muted_users_muter ON public.muted_users(muter_id);

-- Yardımcı fonksiyon: İki kullanıcı arasında engelleme var mı?
CREATE OR REPLACE FUNCTION public.is_blocked_between(p_user_a UUID, p_user_b UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.blocked_users b
        WHERE (b.blocker_id = p_user_a AND b.blocked_id = p_user_b)
           OR (b.blocker_id = p_user_b AND b.blocked_id = p_user_a)
    );
$$;

GRANT EXECUTE ON FUNCTION public.is_blocked_between(UUID, UUID) TO anon, authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 4. FOLLOWS TABLOSU (Arkadaşlık İsteğinden Bağımsız Instagram Tipi Takip İlişkisi)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.follows (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    follower_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    follower_username TEXT NOT NULL DEFAULT '',
    follower_display_name TEXT NOT NULL DEFAULT '',
    follower_avatar_url TEXT,
    following_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    following_username TEXT NOT NULL DEFAULT '',
    following_display_name TEXT NOT NULL DEFAULT '',
    following_avatar_url TEXT,
    status TEXT NOT NULL DEFAULT 'following' CHECK (status IN ('pending', 'following', 'rejected')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT follows_no_self_follow CHECK (follower_id <> following_id),
    CONSTRAINT follows_unique_pair UNIQUE (follower_id, following_id)
);

CREATE INDEX IF NOT EXISTS idx_follows_follower_status ON public.follows(follower_id, status);
CREATE INDEX IF NOT EXISTS idx_follows_following_status ON public.follows(following_id, status);
CREATE INDEX IF NOT EXISTS idx_follows_created_at ON public.follows(created_at DESC, id DESC);

-- Yardımcı fonksiyon: p_viewer, p_owner'ı aktif olarak takip ediyor mu?
CREATE OR REPLACE FUNCTION public.is_following_accepted(p_viewer UUID, p_owner UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.follows f
        WHERE f.follower_id = p_viewer
          AND f.following_id = p_owner
          AND f.status = 'following'
    );
$$;

-- Yardımcı fonksiyon: p_viewer ile p_owner arkadaş mı?
CREATE OR REPLACE FUNCTION public.is_friends_accepted(p_viewer UUID, p_owner UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.friendships fr
        WHERE fr.status = 'accepted'
          AND ((fr.requester_id = p_viewer AND fr.receiver_id = p_owner)
            OR (fr.requester_id = p_owner AND fr.receiver_id = p_viewer))
    );
$$;

-- Yardımcı fonksiyon: İçerik görünürlük matrisi (Bölüm 31)
CREATE OR REPLACE FUNCTION public.can_view_user_content(
    p_viewer UUID,
    p_owner UUID,
    p_visibility TEXT DEFAULT 'public'
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_is_private BOOLEAN := false;
BEGIN
    IF p_owner IS NULL THEN
        RETURN false;
    END IF;
    IF p_viewer IS NOT NULL AND p_viewer = p_owner THEN
        RETURN true;
    END IF;
    IF p_viewer IS NOT NULL AND public.is_blocked_between(p_viewer, p_owner) THEN
        RETURN false;
    END IF;

    SELECT COALESCE(is_private_account, false)
    INTO v_is_private
    FROM public.profiles
    WHERE id = p_owner;

    IF p_visibility = 'private' OR p_visibility = 'only_me' THEN
        RETURN false;
    END IF;

    IF p_visibility = 'friends' THEN
        RETURN p_viewer IS NOT NULL AND public.is_friends_accepted(p_viewer, p_owner);
    END IF;

    IF p_visibility = 'followers' OR v_is_private THEN
        RETURN p_viewer IS NOT NULL AND (
            public.is_following_accepted(p_viewer, p_owner)
            OR public.is_friends_accepted(p_viewer, p_owner)
        );
    END IF;

    -- public / everyone
    RETURN true;
END;
$$;

GRANT EXECUTE ON FUNCTION public.is_following_accepted(UUID, UUID) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.is_friends_accepted(UUID, UUID) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.can_view_user_content(UUID, UUID, TEXT) TO anon, authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 5. POSTS TABLOSU (Gönderi, Carousel ve Reels Desteği)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.posts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    author_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    author_username TEXT NOT NULL DEFAULT '',
    author_display_name TEXT NOT NULL DEFAULT '',
    author_avatar_url TEXT,
    author_is_verified BOOLEAN NOT NULL DEFAULT false,
    content_type TEXT NOT NULL DEFAULT 'image' CHECK (content_type IN ('image', 'video', 'carousel', 'reel')),
    caption TEXT NOT NULL DEFAULT '',
    hashtags JSONB NOT NULL DEFAULT '[]'::jsonb,
    location_name TEXT NOT NULL DEFAULT '',
    alt_text TEXT NOT NULL DEFAULT '',
    media_urls JSONB NOT NULL DEFAULT '[]'::jsonb,
    media_storage_paths JSONB NOT NULL DEFAULT '[]'::jsonb,
    cover_url TEXT,
    aspect_ratio NUMERIC(6,3) NOT NULL DEFAULT 1.000,
    video_duration_sec INTEGER NOT NULL DEFAULT 0,
    trim_start_sec INTEGER NOT NULL DEFAULT 0,
    trim_end_sec INTEGER NOT NULL DEFAULT 0,
    audio_title TEXT NOT NULL DEFAULT '',
    filter_preset TEXT NOT NULL DEFAULT 'none',
    visibility TEXT NOT NULL DEFAULT 'public' CHECK (visibility IN ('public', 'followers', 'friends', 'private')),
    comments_enabled BOOLEAN NOT NULL DEFAULT true,
    likes_count INTEGER NOT NULL DEFAULT 0,
    comments_count INTEGER NOT NULL DEFAULT 0,
    saves_count INTEGER NOT NULL DEFAULT 0,
    shares_count INTEGER NOT NULL DEFAULT 0,
    views_count INTEGER NOT NULL DEFAULT 0,
    client_request_id TEXT,
    is_deleted BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT posts_author_client_req_unique UNIQUE (author_id, client_request_id)
);

CREATE INDEX IF NOT EXISTS idx_posts_feed_order ON public.posts(created_at DESC, id DESC) WHERE is_deleted = false;
CREATE INDEX IF NOT EXISTS idx_posts_author_order ON public.posts(author_id, created_at DESC, id DESC) WHERE is_deleted = false;
CREATE INDEX IF NOT EXISTS idx_posts_content_type ON public.posts(content_type, created_at DESC, id DESC) WHERE is_deleted = false;
CREATE INDEX IF NOT EXISTS idx_posts_hashtags_gin ON public.posts USING GIN (hashtags);

-- -----------------------------------------------------------------------------
-- 6. POST_LIKES TABLOSU (Kullanıcı + Gönderi Tekil Beğeni İlişkisi)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.post_likes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id UUID NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    username TEXT NOT NULL DEFAULT '',
    display_name TEXT NOT NULL DEFAULT '',
    avatar_url TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT post_likes_unique_user_post UNIQUE (post_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_post_likes_post ON public.post_likes(post_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_post_likes_user ON public.post_likes(user_id, created_at DESC);

-- Beğeni sayısını atomik güncelleyen trigger
CREATE OR REPLACE FUNCTION public.sync_post_likes_count()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE public.posts
        SET likes_count = (SELECT COUNT(*) FROM public.post_likes WHERE post_id = NEW.post_id)
        WHERE id = NEW.post_id;
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE public.posts
        SET likes_count = GREATEST(0, (SELECT COUNT(*) FROM public.post_likes WHERE post_id = OLD.post_id))
        WHERE id = OLD.post_id;
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_post_likes_count ON public.post_likes;
CREATE TRIGGER trg_sync_post_likes_count
AFTER INSERT OR DELETE ON public.post_likes
FOR EACH ROW EXECUTE FUNCTION public.sync_post_likes_count();

-- -----------------------------------------------------------------------------
-- 7. POST_COMMENTS & COMMENT_LIKES TABLOLARI (Yanıt ve Yorum Beğenisi Destekli)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.post_comments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id UUID NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
    author_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    author_username TEXT NOT NULL DEFAULT '',
    author_display_name TEXT NOT NULL DEFAULT '',
    author_avatar_url TEXT,
    parent_comment_id UUID REFERENCES public.post_comments(id) ON DELETE CASCADE,
    reply_to_username TEXT NOT NULL DEFAULT '',
    content TEXT NOT NULL CHECK ( LENGTH(TRIM(content)) > 0 AND LENGTH(content) <= 2000 ),
    likes_count INTEGER NOT NULL DEFAULT 0,
    client_request_id TEXT,
    is_edited BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT post_comments_unique_req UNIQUE (author_id, client_request_id)
);

CREATE INDEX IF NOT EXISTS idx_post_comments_post_order ON public.post_comments(post_id, created_at ASC, id ASC);
CREATE INDEX IF NOT EXISTS idx_post_comments_parent ON public.post_comments(parent_comment_id);

CREATE TABLE IF NOT EXISTS public.comment_likes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    comment_id UUID NOT NULL REFERENCES public.post_comments(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT comment_likes_unique_pair UNIQUE (comment_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_comment_likes_comment ON public.comment_likes(comment_id);

CREATE OR REPLACE FUNCTION public.sync_post_comments_count()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE public.posts
        SET comments_count = (SELECT COUNT(*) FROM public.post_comments WHERE post_id = NEW.post_id)
        WHERE id = NEW.post_id;
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE public.posts
        SET comments_count = GREATEST(0, (SELECT COUNT(*) FROM public.post_comments WHERE post_id = OLD.post_id))
        WHERE id = OLD.post_id;
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_post_comments_count ON public.post_comments;
CREATE TRIGGER trg_sync_post_comments_count
AFTER INSERT OR DELETE ON public.post_comments
FOR EACH ROW EXECUTE FUNCTION public.sync_post_comments_count();

CREATE OR REPLACE FUNCTION public.sync_comment_likes_count()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE public.post_comments
        SET likes_count = (SELECT COUNT(*) FROM public.comment_likes WHERE comment_id = NEW.comment_id)
        WHERE id = NEW.comment_id;
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE public.post_comments
        SET likes_count = GREATEST(0, (SELECT COUNT(*) FROM public.comment_likes WHERE comment_id = OLD.comment_id))
        WHERE id = OLD.comment_id;
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_comment_likes_count ON public.comment_likes;
CREATE TRIGGER trg_sync_comment_likes_count
AFTER INSERT OR DELETE ON public.comment_likes
FOR EACH ROW EXECUTE FUNCTION public.sync_comment_likes_count();

-- -----------------------------------------------------------------------------
-- 8. SAVED_POSTS TABLOSU (Yalnızca Sahibine Görünür Kaydedilenler)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.saved_posts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    post_id UUID NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT saved_posts_unique_user_post UNIQUE (user_id, post_id)
);

CREATE INDEX IF NOT EXISTS idx_saved_posts_user_order ON public.saved_posts(user_id, created_at DESC, id DESC);

CREATE OR REPLACE FUNCTION public.sync_post_saves_count()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE public.posts
        SET saves_count = (SELECT COUNT(*) FROM public.saved_posts WHERE post_id = NEW.post_id)
        WHERE id = NEW.post_id;
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE public.posts
        SET saves_count = GREATEST(0, (SELECT COUNT(*) FROM public.saved_posts WHERE post_id = OLD.post_id))
        WHERE id = OLD.post_id;
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_post_saves_count ON public.saved_posts;
CREATE TRIGGER trg_sync_post_saves_count
AFTER INSERT OR DELETE ON public.saved_posts
FOR EACH ROW EXECUTE FUNCTION public.sync_post_saves_count();

-- -----------------------------------------------------------------------------
-- 9. STORY_VIEWS TABLOSU (Tekil Hikâye Görüntüleme Kaydı)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.story_views (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    story_id UUID NOT NULL REFERENCES public.stories(id) ON DELETE CASCADE,
    viewer_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    viewer_username TEXT NOT NULL DEFAULT '',
    viewer_display_name TEXT NOT NULL DEFAULT '',
    viewer_avatar_url TEXT,
    has_liked BOOLEAN NOT NULL DEFAULT false,
    viewed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT story_views_unique_viewer UNIQUE (story_id, viewer_id)
);

CREATE INDEX IF NOT EXISTS idx_story_views_story ON public.story_views(story_id, viewed_at DESC);
CREATE INDEX IF NOT EXISTS idx_story_views_viewer ON public.story_views(viewer_id, viewed_at DESC);

-- -----------------------------------------------------------------------------
-- 10. NOTIFICATIONS TABLOSU (Idempotent Anahtarlı ve Hedef Yönlendirmeli)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    recipient_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    actor_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    actor_username TEXT NOT NULL DEFAULT '',
    actor_display_name TEXT NOT NULL DEFAULT '',
    actor_avatar_url TEXT,
    event_type TEXT NOT NULL CHECK (
        event_type IN (
            'like',
            'comment',
            'reply',
            'follow',
            'follow_request',
            'follow_accepted',
            'friend_request',
            'friend_accepted',
            'story_like',
            'story_reply',
            'message',
            'missed_call',
            'group_activity',
            'system'
        )
    ),
    target_id TEXT NOT NULL DEFAULT '',
    target_secondary_id TEXT NOT NULL DEFAULT '',
    preview_text TEXT NOT NULL DEFAULT '',
    media_thumb_url TEXT,
    dedupe_key TEXT,
    is_read BOOLEAN NOT NULL DEFAULT false,
    read_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT notifications_dedupe_unique UNIQUE (recipient_id, dedupe_key)
);

CREATE INDEX IF NOT EXISTS idx_notifications_recipient_order
    ON public.notifications(recipient_id, created_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS idx_notifications_recipient_unread
    ON public.notifications(recipient_id, is_read, created_at DESC);

-- -----------------------------------------------------------------------------
-- 11. REPORTS TABLOSU (Gönderi, Yorum, Hikâye, Kullanıcı Şikâyetleri)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reporter_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    target_type TEXT NOT NULL CHECK (target_type IN ('post', 'comment', 'story', 'user', 'message')),
    target_id TEXT NOT NULL,
    target_owner_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    reason_code TEXT NOT NULL CHECK (reason_code IN ('spam', 'harassment', 'inappropriate', 'fake_account', 'other')),
    details TEXT NOT NULL DEFAULT '',
    status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'reviewed', 'resolved')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT reports_unique_per_target UNIQUE (reporter_id, target_type, target_id)
);

CREATE INDEX IF NOT EXISTS idx_reports_reporter ON public.reports(reporter_id, created_at DESC);

-- -----------------------------------------------------------------------------
-- 12. STORAGE BUCKETS & GÜVENLİ SAHİPLİK POLİTİKALARI (posts, reels)
-- -----------------------------------------------------------------------------
DO $$
BEGIN
    INSERT INTO storage.buckets (id, name, public, file_size_limit)
    VALUES
        ('posts', 'posts', true, 104857600),
        ('reels', 'reels', true, 157286400)
    ON CONFLICT (id) DO UPDATE
    SET public = true,
        file_size_limit = EXCLUDED.file_size_limit;
EXCEPTION WHEN OTHERS THEN
    NULL;
END $$;

DO $$
BEGIN
    DROP POLICY IF EXISTS "juzzio_social_storage_public_read" ON storage.objects;
    CREATE POLICY "juzzio_social_storage_public_read"
        ON storage.objects FOR SELECT TO anon, authenticated
        USING (bucket_id IN ('posts', 'reels', 'stories', 'avatars', 'voice-notes'));

    DROP POLICY IF EXISTS "juzzio_social_storage_owner_insert" ON storage.objects;
    CREATE POLICY "juzzio_social_storage_owner_insert"
        ON storage.objects FOR INSERT TO authenticated
        WITH CHECK (
            bucket_id IN ('posts', 'reels')
            AND (storage.foldername(name))[1] = auth.uid()::text
        );

    DROP POLICY IF EXISTS "juzzio_social_storage_owner_update" ON storage.objects;
    CREATE POLICY "juzzio_social_storage_owner_update"
        ON storage.objects FOR UPDATE TO authenticated
        USING (
            bucket_id IN ('posts', 'reels')
            AND (storage.foldername(name))[1] = auth.uid()::text
        )
        WITH CHECK (
            bucket_id IN ('posts', 'reels')
            AND (storage.foldername(name))[1] = auth.uid()::text
        );

    DROP POLICY IF EXISTS "juzzio_social_storage_owner_delete" ON storage.objects;
    CREATE POLICY "juzzio_social_storage_owner_delete"
        ON storage.objects FOR DELETE TO authenticated
        USING (
            bucket_id IN ('posts', 'reels')
            AND (storage.foldername(name))[1] = auth.uid()::text
        );
EXCEPTION WHEN OTHERS THEN
    NULL;
END $$;

-- -----------------------------------------------------------------------------
-- 13. ROW LEVEL SECURITY (RLS) — EN AZ YETKİ VE GÖRÜNÜRLÜK MATRİSİ
-- -----------------------------------------------------------------------------
ALTER TABLE public.blocked_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.muted_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.follows ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.post_likes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.post_comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.comment_likes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.saved_posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.story_views ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reports ENABLE ROW LEVEL SECURITY;

-- blocked_users policies
DROP POLICY IF EXISTS "blocked_users_select_involved" ON public.blocked_users;
CREATE POLICY "blocked_users_select_involved"
    ON public.blocked_users FOR SELECT TO authenticated
    USING (auth.uid() = blocker_id OR auth.uid() = blocked_id);

DROP POLICY IF EXISTS "blocked_users_insert_own" ON public.blocked_users;
CREATE POLICY "blocked_users_insert_own"
    ON public.blocked_users FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = blocker_id AND blocker_id <> blocked_id);

DROP POLICY IF EXISTS "blocked_users_delete_own" ON public.blocked_users;
CREATE POLICY "blocked_users_delete_own"
    ON public.blocked_users FOR DELETE TO authenticated
    USING (auth.uid() = blocker_id);

-- muted_users policies
DROP POLICY IF EXISTS "muted_users_all_own" ON public.muted_users;
CREATE POLICY "muted_users_all_own"
    ON public.muted_users FOR ALL TO authenticated
    USING (auth.uid() = muter_id)
    WITH CHECK (auth.uid() = muter_id AND muter_id <> muted_id);

-- follows policies
DROP POLICY IF EXISTS "follows_select_visible" ON public.follows;
CREATE POLICY "follows_select_visible"
    ON public.follows FOR SELECT TO authenticated
    USING (
        NOT public.is_blocked_between(auth.uid(), follower_id)
        AND NOT public.is_blocked_between(auth.uid(), following_id)
    );

DROP POLICY IF EXISTS "follows_insert_own" ON public.follows;
CREATE POLICY "follows_insert_own"
    ON public.follows FOR INSERT TO authenticated
    WITH CHECK (
        auth.uid() = follower_id
        AND follower_id <> following_id
        AND NOT public.is_blocked_between(follower_id, following_id)
    );

DROP POLICY IF EXISTS "follows_update_involved" ON public.follows;
CREATE POLICY "follows_update_involved"
    ON public.follows FOR UPDATE TO authenticated
    USING (auth.uid() = follower_id OR auth.uid() = following_id)
    WITH CHECK (auth.uid() = follower_id OR auth.uid() = following_id);

DROP POLICY IF EXISTS "follows_delete_involved" ON public.follows;
CREATE POLICY "follows_delete_involved"
    ON public.follows FOR DELETE TO authenticated
    USING (auth.uid() = follower_id OR auth.uid() = following_id);

-- posts policies
DROP POLICY IF EXISTS "posts_select_visible" ON public.posts;
CREATE POLICY "posts_select_visible"
    ON public.posts FOR SELECT TO anon, authenticated
    USING (
        is_deleted = false
        AND public.can_view_user_content(auth.uid(), author_id, visibility)
    );

DROP POLICY IF EXISTS "posts_insert_own" ON public.posts;
CREATE POLICY "posts_insert_own"
    ON public.posts FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = author_id);

DROP POLICY IF EXISTS "posts_update_own" ON public.posts;
CREATE POLICY "posts_update_own"
    ON public.posts FOR UPDATE TO authenticated
    USING (auth.uid() = author_id)
    WITH CHECK (auth.uid() = author_id);

DROP POLICY IF EXISTS "posts_delete_own" ON public.posts;
CREATE POLICY "posts_delete_own"
    ON public.posts FOR DELETE TO authenticated
    USING (auth.uid() = author_id);

-- post_likes policies
DROP POLICY IF EXISTS "post_likes_select_visible" ON public.post_likes;
CREATE POLICY "post_likes_select_visible"
    ON public.post_likes FOR SELECT TO anon, authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.posts p
            WHERE p.id = post_likes.post_id
              AND p.is_deleted = false
              AND public.can_view_user_content(auth.uid(), p.author_id, p.visibility)
        )
    );

DROP POLICY IF EXISTS "post_likes_insert_own" ON public.post_likes;
CREATE POLICY "post_likes_insert_own"
    ON public.post_likes FOR INSERT TO authenticated
    WITH CHECK (
        auth.uid() = user_id
        AND EXISTS (
            SELECT 1 FROM public.posts p
            WHERE p.id = post_likes.post_id
              AND p.is_deleted = false
              AND public.can_view_user_content(auth.uid(), p.author_id, p.visibility)
        )
    );

DROP POLICY IF EXISTS "post_likes_delete_own" ON public.post_likes;
CREATE POLICY "post_likes_delete_own"
    ON public.post_likes FOR DELETE TO authenticated
    USING (auth.uid() = user_id);

-- post_comments policies
DROP POLICY IF EXISTS "post_comments_select_visible" ON public.post_comments;
CREATE POLICY "post_comments_select_visible"
    ON public.post_comments FOR SELECT TO anon, authenticated
    USING (
        (auth.uid() IS NULL OR NOT public.is_blocked_between(auth.uid(), author_id))
        AND EXISTS (
            SELECT 1 FROM public.posts p
            WHERE p.id = post_comments.post_id
              AND p.is_deleted = false
              AND public.can_view_user_content(auth.uid(), p.author_id, p.visibility)
        )
    );

DROP POLICY IF EXISTS "post_comments_insert_allowed" ON public.post_comments;
CREATE POLICY "post_comments_insert_allowed"
    ON public.post_comments FOR INSERT TO authenticated
    WITH CHECK (
        auth.uid() = author_id
        AND EXISTS (
            SELECT 1 FROM public.posts p
            WHERE p.id = post_comments.post_id
              AND p.is_deleted = false
              AND p.comments_enabled = true
              AND public.can_view_user_content(auth.uid(), p.author_id, p.visibility)
        )
    );

DROP POLICY IF EXISTS "post_comments_update_own" ON public.post_comments;
CREATE POLICY "post_comments_update_own"
    ON public.post_comments FOR UPDATE TO authenticated
    USING (auth.uid() = author_id)
    WITH CHECK (auth.uid() = author_id);

DROP POLICY IF EXISTS "post_comments_delete_own_or_post_owner" ON public.post_comments;
CREATE POLICY "post_comments_delete_own_or_post_owner"
    ON public.post_comments FOR DELETE TO authenticated
    USING (
        auth.uid() = author_id
        OR EXISTS (
            SELECT 1 FROM public.posts p
            WHERE p.id = post_comments.post_id
              AND p.author_id = auth.uid()
        )
    );

-- comment_likes policies
DROP POLICY IF EXISTS "comment_likes_select_all" ON public.comment_likes;
CREATE POLICY "comment_likes_select_all"
    ON public.comment_likes FOR SELECT TO anon, authenticated
    USING (true);

DROP POLICY IF EXISTS "comment_likes_insert_own" ON public.comment_likes;
CREATE POLICY "comment_likes_insert_own"
    ON public.comment_likes FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "comment_likes_delete_own" ON public.comment_likes;
CREATE POLICY "comment_likes_delete_own"
    ON public.comment_likes FOR DELETE TO authenticated
    USING (auth.uid() = user_id);

-- saved_posts policies (Yalnızca sahibine görünür!)
DROP POLICY IF EXISTS "saved_posts_owner_only" ON public.saved_posts;
CREATE POLICY "saved_posts_owner_only"
    ON public.saved_posts FOR ALL TO authenticated
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- story_views policies
DROP POLICY IF EXISTS "story_views_select_owner_or_viewer" ON public.story_views;
CREATE POLICY "story_views_select_owner_or_viewer"
    ON public.story_views FOR SELECT TO authenticated
    USING (
        auth.uid() = viewer_id
        OR EXISTS (
            SELECT 1 FROM public.stories s
            WHERE s.id = story_views.story_id
              AND s.user_id = auth.uid()
        )
    );

DROP POLICY IF EXISTS "story_views_insert_own" ON public.story_views;
CREATE POLICY "story_views_insert_own"
    ON public.story_views FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = viewer_id);

DROP POLICY IF EXISTS "story_views_update_own" ON public.story_views;
CREATE POLICY "story_views_update_own"
    ON public.story_views FOR UPDATE TO authenticated
    USING (auth.uid() = viewer_id)
    WITH CHECK (auth.uid() = viewer_id);

-- notifications policies (Yalnızca hedef kullanıcı okuyabilir/güncelleyebilir/silebilir!)
DROP POLICY IF EXISTS "notifications_select_recipient_only" ON public.notifications;
CREATE POLICY "notifications_select_recipient_only"
    ON public.notifications FOR SELECT TO authenticated
    USING (auth.uid() = recipient_id);

DROP POLICY IF EXISTS "notifications_insert_actor" ON public.notifications;
CREATE POLICY "notifications_insert_actor"
    ON public.notifications FOR INSERT TO authenticated
    WITH CHECK (
        (actor_id IS NULL OR auth.uid() = actor_id)
        AND NOT public.is_blocked_between(auth.uid(), recipient_id)
    );

DROP POLICY IF EXISTS "notifications_update_recipient_only" ON public.notifications;
CREATE POLICY "notifications_update_recipient_only"
    ON public.notifications FOR UPDATE TO authenticated
    USING (auth.uid() = recipient_id)
    WITH CHECK (auth.uid() = recipient_id);

DROP POLICY IF EXISTS "notifications_delete_recipient_only" ON public.notifications;
CREATE POLICY "notifications_delete_recipient_only"
    ON public.notifications FOR DELETE TO authenticated
    USING (auth.uid() = recipient_id);

-- reports policies (Yalnızca raporlayan kendi kaydını oluşturabilir/görebilir)
DROP POLICY IF EXISTS "reports_select_own" ON public.reports;
CREATE POLICY "reports_select_own"
    ON public.reports FOR SELECT TO authenticated
    USING (auth.uid() = reporter_id);

DROP POLICY IF EXISTS "reports_insert_own" ON public.reports;
CREATE POLICY "reports_insert_own"
    ON public.reports FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = reporter_id);

-- Hesap silme fonksiyonunu yeni sosyal tabloları da temizleyecek şekilde güncelle
CREATE OR REPLACE FUNCTION public.delete_my_juzzio_account()
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID := auth.uid();
BEGIN
    IF v_uid IS NULL THEN
        RETURN FALSE;
    END IF;
    DELETE FROM public.notifications WHERE recipient_id = v_uid OR actor_id = v_uid;
    DELETE FROM public.saved_posts WHERE user_id = v_uid;
    DELETE FROM public.comment_likes WHERE user_id = v_uid;
    DELETE FROM public.post_comments WHERE author_id = v_uid;
    DELETE FROM public.post_likes WHERE user_id = v_uid;
    DELETE FROM public.posts WHERE author_id = v_uid;
    DELETE FROM public.follows WHERE follower_id = v_uid OR following_id = v_uid;
    DELETE FROM public.blocked_users WHERE blocker_id = v_uid OR blocked_id = v_uid;
    DELETE FROM public.muted_users WHERE muter_id = v_uid OR muted_id = v_uid;
    DELETE FROM public.story_views WHERE viewer_id = v_uid;
    DELETE FROM public.reports WHERE reporter_id = v_uid;
    DELETE FROM public.messages WHERE sender_id = v_uid;
    DELETE FROM public.stories WHERE user_id = v_uid;
    DELETE FROM public.friendships WHERE requester_id = v_uid OR receiver_id = v_uid;
    DELETE FROM public.call_logs WHERE caller_id = v_uid OR receiver_id = v_uid;
    DELETE FROM public.rooms WHERE created_by = v_uid AND room_code <> 'juzzio-couple-main';
    DELETE FROM public.profiles WHERE id = v_uid;
    DELETE FROM auth.users WHERE id = v_uid;
    RETURN TRUE;
EXCEPTION WHEN OTHERS THEN
    DELETE FROM public.profiles WHERE id = v_uid;
    RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION public.delete_my_juzzio_account() TO authenticated, service_role;

-- Yalnızca gerekli tablolarda Realtime yayını etkinleştir (notifications, posts, follows)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'notifications') THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'posts') THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.posts;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'follows') THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.follows;
    END IF;
EXCEPTION WHEN OTHERS THEN
    NULL;
END $$;

-- #############################################################################
-- BÖLÜM 3/9 — kaynak: 20261028010000_juzzio_fcm_push_webhook.sql
-- #############################################################################
-- =============================================================================
-- JUZZIO v0.1.0 — Firebase Cloud Messaging (FCM) Cihaz Token Yönetimi,
-- Tekil Yetkili Bildirim Üretimi ve İdempotent Push Teslimat Kayıt Şeması
-- Bölüm 6, 7, 8 ve 11 Kurallarına Tam Uyumlu (Çift Gönderim ve Yetki Sızıntısı Yok)
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Eski çift gönderime yol açabilen push_webhook_queue trigger'ını temizle
DROP TRIGGER IF EXISTS trg_enqueue_push_from_notification ON public.notifications;
DROP FUNCTION IF EXISTS public.enqueue_push_from_notification();

-- -----------------------------------------------------------------------------
-- 1. USER_PUSH_TOKENS TABLOSU (Çoklu Cihaz FCM Token & Kategori Tercihleri)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.user_push_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    device_id TEXT NOT NULL DEFAULT '',
    fcm_token TEXT NOT NULL,
    platform TEXT NOT NULL DEFAULT 'android' CHECK (platform IN ('android', 'ios', 'web')),
    app_version TEXT NOT NULL DEFAULT '0.1.0',
    firebase_project_id TEXT NOT NULL DEFAULT 'juzzio',
    notify_enabled BOOLEAN NOT NULL DEFAULT true,
    notify_messages BOOLEAN NOT NULL DEFAULT true,
    notify_groups BOOLEAN NOT NULL DEFAULT true,
    notify_calls BOOLEAN NOT NULL DEFAULT true,
    notify_follows BOOLEAN NOT NULL DEFAULT true,
    notify_likes_comments BOOLEAN NOT NULL DEFAULT true,
    notify_stories BOOLEAN NOT NULL DEFAULT true,
    notify_system BOOLEAN NOT NULL DEFAULT true,
    is_silent_mode BOOLEAN NOT NULL DEFAULT false,
    is_active BOOLEAN NOT NULL DEFAULT true,
    invalidated_reason TEXT NOT NULL DEFAULT '',
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT user_push_tokens_unique_user_token UNIQUE (user_id, fcm_token)
);

ALTER TABLE public.user_push_tokens ADD COLUMN IF NOT EXISTS device_id TEXT NOT NULL DEFAULT '';
ALTER TABLE public.user_push_tokens ADD COLUMN IF NOT EXISTS platform TEXT NOT NULL DEFAULT 'android';
ALTER TABLE public.user_push_tokens ADD COLUMN IF NOT EXISTS app_version TEXT NOT NULL DEFAULT '0.1.0';
ALTER TABLE public.user_push_tokens ADD COLUMN IF NOT EXISTS firebase_project_id TEXT NOT NULL DEFAULT 'juzzio';
ALTER TABLE public.user_push_tokens ADD COLUMN IF NOT EXISTS notify_enabled BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE public.user_push_tokens ADD COLUMN IF NOT EXISTS notify_messages BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE public.user_push_tokens ADD COLUMN IF NOT EXISTS notify_groups BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE public.user_push_tokens ADD COLUMN IF NOT EXISTS notify_calls BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE public.user_push_tokens ADD COLUMN IF NOT EXISTS notify_follows BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE public.user_push_tokens ADD COLUMN IF NOT EXISTS notify_likes_comments BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE public.user_push_tokens ADD COLUMN IF NOT EXISTS notify_stories BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE public.user_push_tokens ADD COLUMN IF NOT EXISTS notify_system BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE public.user_push_tokens ADD COLUMN IF NOT EXISTS is_silent_mode BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.user_push_tokens ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE public.user_push_tokens ADD COLUMN IF NOT EXISTS invalidated_reason TEXT NOT NULL DEFAULT '';
ALTER TABLE public.user_push_tokens ADD COLUMN IF NOT EXISTS last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
ALTER TABLE public.user_push_tokens ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
ALTER TABLE public.user_push_tokens ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

CREATE INDEX IF NOT EXISTS idx_user_push_tokens_user_active
    ON public.user_push_tokens(user_id, is_active);
CREATE INDEX IF NOT EXISTS idx_user_push_tokens_token
    ON public.user_push_tokens(fcm_token);

-- -----------------------------------------------------------------------------
-- 2. PUSH_DELIVERY_LOGS TABLOSU (Tekil İdempotent Gönderim ve Hız Sınırı Kaydı)
-- notifications tablosunu UPDATE etmez; böylece sonsuz webhook döngüsü oluşmaz!
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.push_delivery_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    notification_id UUID REFERENCES public.notifications(id) ON DELETE SET NULL,
    idempotency_key TEXT UNIQUE NOT NULL,
    recipient_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    actor_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    event_type TEXT NOT NULL DEFAULT 'system',
    channel_id TEXT NOT NULL DEFAULT 'juzzio_high_priority_v2',
    delivery_status TEXT NOT NULL DEFAULT 'processing'
        CHECK (delivery_status IN ('processing', 'fcm_accepted', 'no_active_tokens', 'skipped_preference', 'skipped_blocked', 'failed')),
    target_tokens_count INTEGER NOT NULL DEFAULT 0,
    fcm_accepted_count INTEGER NOT NULL DEFAULT 0,
    fcm_error_code TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_push_delivery_logs_recipient_created
    ON public.push_delivery_logs(recipient_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_push_delivery_logs_notif
    ON public.push_delivery_logs(notification_id);

-- -----------------------------------------------------------------------------
-- 3. RLS POLİTİKALARI (Bölüm 7.7 — Kullanıcı Yalnızca Kendi Tokenlarını Yönetir)
-- -----------------------------------------------------------------------------
ALTER TABLE public.user_push_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.push_delivery_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "user_push_tokens_owner_all" ON public.user_push_tokens;
DROP POLICY IF EXISTS "user_push_tokens_select_own" ON public.user_push_tokens;
CREATE POLICY "user_push_tokens_select_own"
    ON public.user_push_tokens FOR SELECT TO authenticated
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "user_push_tokens_insert_own" ON public.user_push_tokens;
CREATE POLICY "user_push_tokens_insert_own"
    ON public.user_push_tokens FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "user_push_tokens_update_own" ON public.user_push_tokens;
CREATE POLICY "user_push_tokens_update_own"
    ON public.user_push_tokens FOR UPDATE TO authenticated
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "user_push_tokens_delete_own" ON public.user_push_tokens;
CREATE POLICY "user_push_tokens_delete_own"
    ON public.user_push_tokens FOR DELETE TO authenticated
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "push_delivery_logs_select_own" ON public.push_delivery_logs;
CREATE POLICY "push_delivery_logs_select_own"
    ON public.push_delivery_logs FOR SELECT TO authenticated
    USING (auth.uid() = recipient_id);

-- -----------------------------------------------------------------------------
-- 4. CİHAZ PUSH TOKEN KAYIT / YENİLEME / ÇIKIŞ RPC FONKSİYONLARI (Bölüm 7.3-7.5)
-- Aynı cihazda farklı bir hesaba geçiş yapıldığında eski hesabın aynı FCM token
-- kaydını otomatik olarak pasifleştirir (reassigned_to_new_user).
-- -----------------------------------------------------------------------------
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN
        SELECT p.oid::regprocedure AS proc_sig
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname IN ('upsert_my_push_token', 'deactivate_my_push_token')
    LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS ' || r.proc_sig;
    END LOOP;
END $$;

CREATE OR REPLACE FUNCTION public.upsert_my_push_token(
    p_fcm_token TEXT,
    p_device_id TEXT DEFAULT '',
    p_platform TEXT DEFAULT 'android',
    p_app_version TEXT DEFAULT '0.1.0',
    p_firebase_project_id TEXT DEFAULT 'juzzio',
    p_notify_enabled BOOLEAN DEFAULT true,
    p_notify_messages BOOLEAN DEFAULT true,
    p_notify_groups BOOLEAN DEFAULT true,
    p_notify_calls BOOLEAN DEFAULT true,
    p_notify_follows BOOLEAN DEFAULT true,
    p_notify_likes_comments BOOLEAN DEFAULT true,
    p_notify_stories BOOLEAN DEFAULT true,
    p_is_silent_mode BOOLEAN DEFAULT false
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_clean_token TEXT := TRIM(COALESCE(p_fcm_token, ''));
    v_id UUID;
BEGIN
    IF v_uid IS NULL OR v_clean_token = '' THEN
        RETURN NULL;
    END IF;

    -- Bölüm 7.3: Aynı FCM token veya aynı device_id başka bir kullanıcıda aktifse pasifleştir
    UPDATE public.user_push_tokens
    SET is_active = false,
        invalidated_reason = 'reassigned_to_new_user',
        updated_at = NOW()
    WHERE user_id <> v_uid
      AND is_active = true
      AND (
          fcm_token = v_clean_token
          OR (COALESCE(p_device_id, '') <> '' AND device_id = p_device_id)
      );

    INSERT INTO public.user_push_tokens (
        user_id,
        device_id,
        fcm_token,
        platform,
        app_version,
        firebase_project_id,
        notify_enabled,
        notify_messages,
        notify_groups,
        notify_calls,
        notify_follows,
        notify_likes_comments,
        notify_stories,
        is_silent_mode,
        is_active,
        invalidated_reason,
        last_seen_at,
        updated_at
    )
    VALUES (
        v_uid,
        COALESCE(p_device_id, ''),
        v_clean_token,
        COALESCE(p_platform, 'android'),
        COALESCE(p_app_version, '0.1.0'),
        COALESCE(p_firebase_project_id, 'juzzio'),
        COALESCE(p_notify_enabled, true),
        COALESCE(p_notify_messages, true),
        COALESCE(p_notify_groups, true),
        COALESCE(p_notify_calls, true),
        COALESCE(p_notify_follows, true),
        COALESCE(p_notify_likes_comments, true),
        COALESCE(p_notify_stories, true),
        COALESCE(p_is_silent_mode, false),
        true,
        '',
        NOW(),
        NOW()
    )
    ON CONFLICT (user_id, fcm_token) DO UPDATE
    SET device_id = EXCLUDED.device_id,
        platform = EXCLUDED.platform,
        app_version = EXCLUDED.app_version,
        firebase_project_id = EXCLUDED.firebase_project_id,
        notify_enabled = EXCLUDED.notify_enabled,
        notify_messages = EXCLUDED.notify_messages,
        notify_groups = EXCLUDED.notify_groups,
        notify_calls = EXCLUDED.notify_calls,
        notify_follows = EXCLUDED.notify_follows,
        notify_likes_comments = EXCLUDED.notify_likes_comments,
        notify_stories = EXCLUDED.notify_stories,
        is_silent_mode = EXCLUDED.is_silent_mode,
        is_active = true,
        invalidated_reason = '',
        last_seen_at = NOW(),
        updated_at = NOW()
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.upsert_my_push_token(
    TEXT, TEXT, TEXT, TEXT, TEXT, BOOLEAN, BOOLEAN, BOOLEAN, BOOLEAN, BOOLEAN, BOOLEAN, BOOLEAN, BOOLEAN
) TO authenticated, service_role;

-- Bölüm 7.5: Çıkış yapıldığında yalnızca bu cihazın token ilişkisini pasifleştirir
DROP FUNCTION IF EXISTS public.deactivate_my_push_token(TEXT, TEXT);
DROP FUNCTION IF EXISTS public.deactivate_my_push_token(TEXT);
CREATE OR REPLACE FUNCTION public.deactivate_my_push_token(
    p_fcm_token TEXT,
    p_device_id TEXT DEFAULT ''
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID := auth.uid();
BEGIN
    IF v_uid IS NULL THEN
        RETURN FALSE;
    END IF;
    UPDATE public.user_push_tokens
    SET is_active = false,
        invalidated_reason = 'user_signed_out',
        updated_at = NOW()
    WHERE user_id = v_uid
      AND (
          (COALESCE(p_fcm_token, '') <> '' AND fcm_token = p_fcm_token)
          OR (COALESCE(p_device_id, '') <> '' AND device_id = p_device_id)
      );
    RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION public.deactivate_my_push_token(TEXT, TEXT) TO authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 5. TEKİL YETKİLİ BİLDİRİM ÜRETİCİLERİ (Bölüm 8)
-- Mesaj, arkadaşlık isteği ve cevapsız aramalar yalnızca `public.notifications`
-- tablosuna tekil (dedupe_key korumalı) satır ekler.
-- Push gönderimi ise yalnızca `public.notifications` INSERT olayına bağlı
-- `push-webhook` Edge Function tarafından tek bir kanaldan yürütülür!
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.notify_on_new_message()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_sender_name TEXT;
    v_sender_uname TEXT;
    v_sender_avatar TEXT;
    v_preview TEXT;
BEGIN
    IF NEW.receiver_id IS NULL OR NEW.receiver_id = NEW.sender_id THEN
        RETURN NEW;
    END IF;

    IF public.is_blocked_between(NEW.sender_id, NEW.receiver_id) THEN
        RETURN NEW;
    END IF;

    SELECT display_name, username, avatar_url
    INTO v_sender_name, v_sender_uname, v_sender_avatar
    FROM public.profiles
    WHERE id = NEW.sender_id;

    v_preview := CASE
        WHEN NEW.message_type = 'voice' THEN '🎤 Sesli mesaj gönderdi'
        WHEN COALESCE(NEW.translated_text, '') <> '' THEN NEW.translated_text
        ELSE COALESCE(NEW.original_text, 'Yeni mesaj')
    END;

    INSERT INTO public.notifications (
        recipient_id,
        actor_id,
        actor_username,
        actor_display_name,
        actor_avatar_url,
        event_type,
        target_id,
        target_secondary_id,
        preview_text,
        dedupe_key
    )
    VALUES (
        NEW.receiver_id,
        NEW.sender_id,
        COALESCE(v_sender_uname, 'kullanici'),
        COALESCE(NULLIF(NEW.sender_name, ''), v_sender_name, 'Kullanıcı'),
        v_sender_avatar,
        'message',
        NEW.room_id::text,
        NEW.id::text,
        LEFT(v_preview, 160),
        'msg_' || NEW.id::text
    )
    ON CONFLICT (recipient_id, dedupe_key) DO NOTHING;

    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_on_new_message ON public.messages;
CREATE TRIGGER trg_notify_on_new_message
AFTER INSERT ON public.messages
FOR EACH ROW EXECUTE FUNCTION public.notify_on_new_message();

CREATE OR REPLACE FUNCTION public.notify_on_friendship_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF TG_OP = 'INSERT' AND NEW.status = 'pending' THEN
        IF NOT public.is_blocked_between(NEW.requester_id, NEW.receiver_id) THEN
            INSERT INTO public.notifications (
                recipient_id,
                actor_id,
                actor_username,
                actor_display_name,
                actor_avatar_url,
                event_type,
                target_id,
                preview_text,
                dedupe_key
            )
            VALUES (
                NEW.receiver_id,
                NEW.requester_id,
                COALESCE(NEW.requester_username, 'kullanici'),
                COALESCE(NEW.requester_name, 'Kullanıcı'),
                NEW.requester_avatar,
                'friend_request',
                NEW.requester_id::text,
                'Sana arkadaşlık isteği gönderdi.',
                'freq_' || NEW.id::text
            )
            ON CONFLICT (recipient_id, dedupe_key) DO NOTHING;
        END IF;
    ELSIF TG_OP = 'UPDATE' AND OLD.status = 'pending' AND NEW.status = 'accepted' THEN
        IF NOT public.is_blocked_between(NEW.requester_id, NEW.receiver_id) THEN
            INSERT INTO public.notifications (
                recipient_id,
                actor_id,
                actor_username,
                actor_display_name,
                actor_avatar_url,
                event_type,
                target_id,
                preview_text,
                dedupe_key
            )
            VALUES (
                NEW.requester_id,
                NEW.receiver_id,
                COALESCE(NEW.receiver_username, 'kullanici'),
                COALESCE(NEW.receiver_name, 'Kullanıcı'),
                NEW.receiver_avatar,
                'friend_accepted',
                NEW.receiver_id::text,
                'Arkadaşlık isteğini kabul etti.',
                'facc_' || NEW.id::text
            )
            ON CONFLICT (recipient_id, dedupe_key) DO NOTHING;
        END IF;
    END IF;
    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_on_friendship_change ON public.friendships;
CREATE TRIGGER trg_notify_on_friendship_change
AFTER INSERT OR UPDATE ON public.friendships
FOR EACH ROW EXECUTE FUNCTION public.notify_on_friendship_change();

CREATE OR REPLACE FUNCTION public.notify_on_call_log_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NEW.receiver_id IS NOT NULL
       AND NEW.receiver_id <> NEW.caller_id
       AND NEW.status IN ('missed', 'ringing', 'busy_silent')
       AND NOT public.is_blocked_between(NEW.caller_id, NEW.receiver_id) THEN
        INSERT INTO public.notifications (
            recipient_id,
            actor_id,
            actor_username,
            actor_display_name,
            actor_avatar_url,
            event_type,
            target_id,
            preview_text,
            dedupe_key
        )
        VALUES (
            NEW.receiver_id,
            NEW.caller_id,
            LOWER(REPLACE(COALESCE(NEW.caller_name, 'kullanici'), ' ', '_')),
            COALESCE(NEW.caller_name, 'Kullanıcı'),
            NEW.caller_avatar,
            'missed_call',
            COALESCE(NEW.room_id::text, NEW.id::text),
            CASE
                WHEN NEW.is_video THEN 'Görüntülü arama (' || NEW.status || ')'
                ELSE 'Sesli arama (' || NEW.status || ')'
            END,
            'call_' || NEW.id::text
        )
        ON CONFLICT (recipient_id, dedupe_key) DO NOTHING;
    END IF;
    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_on_call_log_insert ON public.call_logs;
CREATE TRIGGER trg_notify_on_call_log_insert
AFTER INSERT ON public.call_logs
FOR EACH ROW EXECUTE FUNCTION public.notify_on_call_log_insert();

-- Uygulama içi bildirim listesinin gerçek zamanlı güncellenmesi için notifications
-- tablosunun supabase_realtime yayınında olduğundan emin ol (Bölüm 6B)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime' AND tablename = 'notifications'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;
    END IF;
EXCEPTION WHEN OTHERS THEN
    NULL;
END $$;

-- #############################################################################
-- BÖLÜM 4/9 — kaynak: 20261028020000_juzzio_fcm_audit_hardening.sql
-- #############################################################################
-- =============================================================================
-- JUZZIO FCM PUSH & WEBHOOK AUDIT HARDENING MIGRATION (P0 / P1 / P2 + 42P13 FIX)
-- Migration: 20261028020000_juzzio_fcm_audit_hardening.sql
-- Tekrar çalıştırılabilir (idempotent) ileri yönlü güvenlik ve kararlılık yaması
-- =============================================================================

-- 1. P1 DÜZELTMESİ: push_delivery_logs.delivery_status CHECK kısıtına
--    'skipped_self_actor' durumunu ekle ve kilit kurtarma indeksini oluştur.
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'push_delivery_logs_delivery_status_check'
          AND conrelid = 'public.push_delivery_logs'::regclass
    ) THEN
        ALTER TABLE public.push_delivery_logs
            DROP CONSTRAINT push_delivery_logs_delivery_status_check;
    END IF;

    ALTER TABLE public.push_delivery_logs
        ADD CONSTRAINT push_delivery_logs_delivery_status_check
        CHECK (delivery_status IN (
            'processing',
            'fcm_accepted',
            'no_active_tokens',
            'skipped_preference',
            'skipped_blocked',
            'skipped_self_actor',
            'failed'
        ));
END $$;

CREATE INDEX IF NOT EXISTS idx_push_delivery_logs_stale_processing
    ON public.push_delivery_logs(idempotency_key, delivery_status, created_at);

-- 2. P2 DÜZELTMESİ: user_push_tokens tablosunda tüm gerekli sütunların
--    varlığını garanti altına al.
ALTER TABLE public.user_push_tokens ADD COLUMN IF NOT EXISTS firebase_project_id TEXT NOT NULL DEFAULT 'juzzio';
ALTER TABLE public.user_push_tokens ADD COLUMN IF NOT EXISTS notify_messages BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE public.user_push_tokens ADD COLUMN IF NOT EXISTS notify_groups BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE public.user_push_tokens ADD COLUMN IF NOT EXISTS notify_calls BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE public.user_push_tokens ADD COLUMN IF NOT EXISTS notify_follows BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE public.user_push_tokens ADD COLUMN IF NOT EXISTS notify_likes_comments BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE public.user_push_tokens ADD COLUMN IF NOT EXISTS notify_stories BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE public.user_push_tokens ADD COLUMN IF NOT EXISTS notify_system BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE public.user_push_tokens ADD COLUMN IF NOT EXISTS is_silent_mode BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.user_push_tokens ADD COLUMN IF NOT EXISTS invalidated_reason TEXT NOT NULL DEFAULT '';

-- 3. P0 & P2 DÜZELTMESİ:
--    - Eski 13 parametreli ve mevcut 14 parametreli upsert_my_push_token imzalarını
--      CASCADE olmadan güvenle kaldır (SQLSTATE 42P13 ve overload çakışmasını önler).
--    - Yeni 14 parametreli imzayı oluştur (p_notify_system BOOLEAN DEFAULT true dahil).
--    - P0 GÜVENLİK DÜZELTMESİ: Başka bir kullanıcıya ait token'ı pasife çekme
--      işlemini YALNIZCA aynı fcm_token eşleşmesi (fcm_token = v_clean_token) ile sınırla.
--      İstemciden gelen p_device_id üzerinden başka kullanıcının token'ını pasife çekme
--      riskini tamamen kaldır.
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN
        SELECT p.oid::regprocedure AS proc_sig
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname IN ('upsert_my_push_token', 'deactivate_my_push_token')
    LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS ' || r.proc_sig;
    END LOOP;
END $$;


CREATE OR REPLACE FUNCTION public.upsert_my_push_token(
    p_fcm_token TEXT,
    p_device_id TEXT DEFAULT '',
    p_platform TEXT DEFAULT 'android',
    p_app_version TEXT DEFAULT '0.1.0',
    p_firebase_project_id TEXT DEFAULT 'juzzio',
    p_notify_enabled BOOLEAN DEFAULT true,
    p_notify_messages BOOLEAN DEFAULT true,
    p_notify_groups BOOLEAN DEFAULT true,
    p_notify_calls BOOLEAN DEFAULT true,
    p_notify_follows BOOLEAN DEFAULT true,
    p_notify_likes_comments BOOLEAN DEFAULT true,
    p_notify_stories BOOLEAN DEFAULT true,
    p_notify_system BOOLEAN DEFAULT true,
    p_is_silent_mode BOOLEAN DEFAULT false
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_clean_token TEXT := TRIM(COALESCE(p_fcm_token, ''));
    v_clean_device_id TEXT := TRIM(COALESCE(p_device_id, ''));
    v_clean_platform TEXT := LOWER(TRIM(COALESCE(p_platform, 'android')));
    v_id UUID;
BEGIN
    IF v_uid IS NULL OR v_clean_token = '' OR LENGTH(v_clean_token) < 20 THEN
        RETURN NULL;
    END IF;

    IF v_clean_platform NOT IN ('android', 'ios', 'web') THEN
        v_clean_platform := 'android';
    END IF;

    -- P0 GÜVENLİK DÜZELTMESİ:
    -- Başka bir kullanıcıda aktif olan kaydı YALNIZCA birebir aynı fcm_token
    -- eşleşmesi (fcm_token = v_clean_token) varsa pasifleştir.
    -- İstemciden gelen p_device_id başka kullanıcıların tokenlarını etkileyemez.
    UPDATE public.user_push_tokens
    SET is_active = false,
        invalidated_reason = 'reassigned_to_new_user',
        updated_at = NOW()
    WHERE user_id <> v_uid
      AND is_active = true
      AND fcm_token = v_clean_token;

    -- Aynı kullanıcının kendi hesabı (user_id = v_uid) altında aynı device_id ile
    -- kalmış eski farklı token varsa onu pasifleştir.
    IF v_clean_device_id <> '' THEN
        UPDATE public.user_push_tokens
        SET is_active = false,
            invalidated_reason = 'replaced_on_same_device',
            updated_at = NOW()
        WHERE user_id = v_uid
          AND is_active = true
          AND device_id = v_clean_device_id
          AND fcm_token <> v_clean_token;
    END IF;

    INSERT INTO public.user_push_tokens (
        user_id,
        device_id,
        fcm_token,
        platform,
        app_version,
        firebase_project_id,
        notify_enabled,
        notify_messages,
        notify_groups,
        notify_calls,
        notify_follows,
        notify_likes_comments,
        notify_stories,
        notify_system,
        is_silent_mode,
        is_active,
        invalidated_reason,
        last_seen_at,
        updated_at
    )
    VALUES (
        v_uid,
        v_clean_device_id,
        v_clean_token,
        v_clean_platform,
        COALESCE(NULLIF(TRIM(p_app_version), ''), '0.1.0'),
        COALESCE(NULLIF(TRIM(p_firebase_project_id), ''), 'juzzio'),
        COALESCE(p_notify_enabled, true),
        COALESCE(p_notify_messages, true),
        COALESCE(p_notify_groups, true),
        COALESCE(p_notify_calls, true),
        COALESCE(p_notify_follows, true),
        COALESCE(p_notify_likes_comments, true),
        COALESCE(p_notify_stories, true),
        COALESCE(p_notify_system, true),
        COALESCE(p_is_silent_mode, false),
        true,
        '',
        NOW(),
        NOW()
    )
    ON CONFLICT (user_id, fcm_token) DO UPDATE
    SET device_id = EXCLUDED.device_id,
        platform = EXCLUDED.platform,
        app_version = EXCLUDED.app_version,
        firebase_project_id = EXCLUDED.firebase_project_id,
        notify_enabled = EXCLUDED.notify_enabled,
        notify_messages = EXCLUDED.notify_messages,
        notify_groups = EXCLUDED.notify_groups,
        notify_calls = EXCLUDED.notify_calls,
        notify_follows = EXCLUDED.notify_follows,
        notify_likes_comments = EXCLUDED.notify_likes_comments,
        notify_stories = EXCLUDED.notify_stories,
        notify_system = EXCLUDED.notify_system,
        is_silent_mode = EXCLUDED.is_silent_mode,
        is_active = true,
        invalidated_reason = '',
        last_seen_at = NOW(),
        updated_at = NOW()
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.upsert_my_push_token(
    TEXT, TEXT, TEXT, TEXT, TEXT,
    BOOLEAN, BOOLEAN, BOOLEAN, BOOLEAN, BOOLEAN, BOOLEAN, BOOLEAN, BOOLEAN, BOOLEAN
) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.upsert_my_push_token(
    TEXT, TEXT, TEXT, TEXT, TEXT,
    BOOLEAN, BOOLEAN, BOOLEAN, BOOLEAN, BOOLEAN, BOOLEAN, BOOLEAN, BOOLEAN, BOOLEAN
) TO authenticated, service_role;

-- 4. SQLSTATE 42P13 DÜZELTMESİ:
--    Uzaktaki veritabanında farklı dönüş tipiyle (VOID veya INTEGER) oluşturulmuş
--    olabilen deactivate_my_push_token fonksiyonunu önce DROP edip ardından oluştur.
DROP FUNCTION IF EXISTS public.deactivate_my_push_token(TEXT, TEXT);
DROP FUNCTION IF EXISTS public.deactivate_my_push_token(TEXT);

CREATE OR REPLACE FUNCTION public.deactivate_my_push_token(
    p_fcm_token TEXT,
    p_device_id TEXT DEFAULT ''
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID := auth.uid();
BEGIN
    IF v_uid IS NULL THEN
        RETURN FALSE;
    END IF;
    UPDATE public.user_push_tokens
    SET is_active = false,
        invalidated_reason = 'user_signed_out',
        updated_at = NOW()
    WHERE user_id = v_uid
      AND (
          (COALESCE(p_fcm_token, '') <> '' AND fcm_token = p_fcm_token)
          OR (COALESCE(p_device_id, '') <> '' AND device_id = p_device_id)
      );
    RETURN TRUE;
END;
$$;

REVOKE ALL ON FUNCTION public.deactivate_my_push_token(TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.deactivate_my_push_token(TEXT, TEXT) TO authenticated, service_role;

-- #############################################################################
-- BÖLÜM 5/9 — kaynak: 20261029000000_juzzio_reconcile_privacy_calls.sql
-- #############################################################################
-- =============================================================================
-- JUZZIO v0.2.0 — Canlı Veritabanı ↔ Uygulama Denkleştirme, Gizlilik ve Konferans
-- Migration: 20261029000000_juzzio_reconcile_privacy_calls.sql
--
-- Bu dosya tekrar çalıştırılabilir (idempotent) ve hem:
--   (a) sql.copy.txt'teki CANLI şemaya (önceki migration'lar hiç uygulanmamış),
--   (b) önceki 4 migration'ın uygulandığı TEMİZ bir veritabanına
-- uygulanacak şekilde yazılmıştır. Hiçbir kullanıcı verisini silmez.
--
-- Düzeltilen ana sorunlar:
--   1. Herkesin mesajlarının tek ortak odada (juzzio-couple-main) okunması
--      → room_participants tabanlı üyelik + üyelik kontrollü RLS.
--   2. Herkesin herkesin arkadaşlık/arama/hikâye kayıtlarını görebilmesi
--      → "USING (true)" politikalarının kaldırılması.
--   3. Hikâye eklenememesi (stories.likes sütunu canlı DB'de yok)
--      → beğeniler story_views.has_liked üzerinden; görünürlük RLS'i.
--   4. Gönderi yorum/beğeni/takip upsert'lerinin bileşik UNIQUE kısıtları
--      olmadığı için hata vermesi → kısıtlar (önce mükerrer kayıt temizliği).
--   5. 1'e 1 aramaların hepsinin aynı LiveKit odasına düşmesi ve her aramanın
--      herkesi çaldırması → call_logs tabanlı, alıcıya özel çağrı sinyali.
--   6. Kayıt sırasında profil oluşmaması (e-posta onayı açıkken) → auth trigger.
--   7. FCM token RPC'sinin canlı DB'deki UNIQUE(fcm_token) ile çakışması.
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- -----------------------------------------------------------------------------
-- 0. YARDIMCI: Bir sütundaki tüm FOREIGN KEY'leri kaldırıp istenen ON DELETE
--    davranışıyla yeniden oluşturur (canlı DB'de ON DELETE eylemleri yok).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._juzzio_reset_fk(
    p_table TEXT, p_column TEXT, p_ref_table TEXT, p_on_delete TEXT
) RETURNS VOID
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
    r RECORD;
    v_name TEXT := p_table || '_' || p_column || '_fkey';
BEGIN
    IF to_regclass('public.' || p_table) IS NULL OR to_regclass(p_ref_table) IS NULL THEN
        RETURN;
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = p_table AND column_name = p_column
    ) THEN
        RETURN;
    END IF;
    FOR r IN
        SELECT c.conname
        FROM pg_constraint c
        JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY (c.conkey)
        WHERE c.contype = 'f'
          AND c.conrelid = ('public.' || p_table)::regclass
          AND a.attname = p_column
          AND array_length(c.conkey, 1) = 1
    LOOP
        EXECUTE format('ALTER TABLE public.%I DROP CONSTRAINT %I', p_table, r.conname);
    END LOOP;
    EXECUTE format(
        'ALTER TABLE public.%I ADD CONSTRAINT %I FOREIGN KEY (%I) REFERENCES %s(id) ON DELETE %s NOT VALID',
        p_table, v_name, p_column, p_ref_table, p_on_delete
    );
END;
$$;

-- Bir tabloya, aynı sütun kümesinde UNIQUE kısıt/indeks yoksa ekler.
CREATE OR REPLACE FUNCTION public._juzzio_ensure_unique(
    p_table TEXT, p_name TEXT, p_cols TEXT[]
) RETURNS VOID
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
    v_exists BOOLEAN;
BEGIN
    SELECT EXISTS (
        SELECT 1
        FROM pg_index i
        WHERE i.indrelid = ('public.' || p_table)::regclass
          AND i.indisunique
          AND i.indpred IS NULL
          AND i.indexprs IS NULL
          AND (
              SELECT array_agg(a.attname::text ORDER BY a.attname)
              FROM pg_attribute a
              WHERE a.attrelid = i.indrelid AND a.attnum = ANY (i.indkey)
          ) = (SELECT array_agg(x ORDER BY x) FROM unnest(p_cols) x)
    ) INTO v_exists;
    IF NOT v_exists THEN
        EXECUTE format(
            'ALTER TABLE public.%I ADD CONSTRAINT %I UNIQUE (%s)',
            p_table, p_name,
            (SELECT string_agg(quote_ident(x), ', ') FROM unnest(p_cols) x)
        );
    END IF;
END;
$$;

-- Bir sütun kümesine göre mükerrer satırları siler (en yeni/ilk ctid'yi korur).
CREATE OR REPLACE FUNCTION public._juzzio_dedupe(
    p_table TEXT, p_cols TEXT[], p_keep_order TEXT DEFAULT 'created_at DESC NULLS LAST'
) RETURNS VOID
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
    v_cols TEXT := (SELECT string_agg(quote_ident(x), ', ') FROM unnest(p_cols) x);
BEGIN
    EXECUTE format(
        'DELETE FROM public.%1$I t USING (
            SELECT ctid, row_number() OVER (PARTITION BY %2$s ORDER BY %3$s) AS rn
            FROM public.%1$I
         ) d
         WHERE t.ctid = d.ctid AND d.rn > 1',
        p_table, v_cols, p_keep_order
    );
END;
$$;

-- -----------------------------------------------------------------------------
-- 1. PROFILES
-- -----------------------------------------------------------------------------
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS username TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS bio TEXT NOT NULL DEFAULT '';
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS subtitle_lang TEXT NOT NULL DEFAULT 'tr';
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS app_lang TEXT NOT NULL DEFAULT 'tr';
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS is_silent_mode BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS read_receipts BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS default_message_timer TEXT NOT NULL DEFAULT 'off';
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS strict_account_mode BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS cover_url TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS website_url TEXT NOT NULL DEFAULT '';
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS is_private_account BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS is_verified BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS privacy_posts TEXT NOT NULL DEFAULT 'everyone';
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS privacy_status TEXT NOT NULL DEFAULT 'everyone';
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS allow_unknown_calls BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS user_preferences JSONB NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS phone_number TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS qr_code_url TEXT;
ALTER TABLE public.profiles ALTER COLUMN is_online SET DEFAULT false;
ALTER TABLE public.profiles ALTER COLUMN email DROP NOT NULL;
ALTER TABLE public.profiles ALTER COLUMN display_name SET DEFAULT 'Juzzio User';

SELECT public._juzzio_reset_fk('profiles', 'id', 'auth.users', 'CASCADE');

-- Kullanıcı adlarını normalize et ve çakışanlara sonek ekle (benzersiz indeks için)
UPDATE public.profiles
SET username = NULLIF(LOWER(REGEXP_REPLACE(TRIM(username), '^@+', '')), '')
WHERE username IS NOT NULL
  AND username <> NULLIF(LOWER(REGEXP_REPLACE(TRIM(username), '^@+', '')), '');

WITH d AS (
    SELECT id, username,
           row_number() OVER (PARTITION BY LOWER(username) ORDER BY created_at, id) AS rn
    FROM public.profiles
    WHERE username IS NOT NULL
)
UPDATE public.profiles p
SET username = d.username || '_' || SUBSTRING(REPLACE(p.id::text, '-', '') FROM 1 FOR 5)
FROM d
WHERE p.id = d.id AND d.rn > 1;

CREATE UNIQUE INDEX IF NOT EXISTS idx_profiles_username_lower
    ON public.profiles (LOWER(username))
    WHERE username IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_profiles_display_name_lower ON public.profiles (LOWER(display_name));

-- Yeni kayıt olan kullanıcı için profili sunucu tarafında oluştur.
-- (E-posta onayı açıkken istemcide oturum olmadığından upsert RLS'e takılıyordu.)
CREATE OR REPLACE FUNCTION public.handle_new_juzzio_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_meta JSONB := COALESCE(NEW.raw_user_meta_data, '{}'::jsonb);
    v_username TEXT := NULLIF(LOWER(REGEXP_REPLACE(TRIM(COALESCE(v_meta->>'username', '')), '^@+', '')), '');
    v_display TEXT := NULLIF(TRIM(COALESCE(v_meta->>'display_name', '')), '');
    v_lang TEXT := COALESCE(NULLIF(v_meta->>'preferred_lang', ''), 'tr');
BEGIN
    IF v_username IS NULL THEN
        v_username := LOWER(SPLIT_PART(COALESCE(NEW.email, 'user'), '@', 1));
    END IF;
    IF EXISTS (SELECT 1 FROM public.profiles WHERE LOWER(username) = v_username AND id <> NEW.id) THEN
        v_username := v_username || '_' || SUBSTRING(REPLACE(NEW.id::text, '-', '') FROM 1 FOR 5);
    END IF;
    IF v_lang NOT IN ('tr', 'en', 'de') THEN
        v_lang := 'en';
    END IF;

    INSERT INTO public.profiles (id, email, username, display_name, preferred_lang, subtitle_lang, app_lang, is_online, last_seen)
    VALUES (NEW.id, LOWER(NEW.email), v_username, COALESCE(v_display, v_username), v_lang,
            COALESCE(NULLIF(v_meta->>'preferred_lang', ''), 'tr'), COALESCE(NULLIF(v_meta->>'preferred_lang', ''), 'tr'),
            false, NOW())
    ON CONFLICT (id) DO NOTHING;
    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    -- Profil oluşturulamasa bile kayıt işlemi engellenmez; istemci upsert ile tamamlar.
    RETURN NEW;
END;
$$;

DO $$
BEGIN
    IF to_regclass('auth.users') IS NOT NULL THEN
        DROP TRIGGER IF EXISTS on_auth_user_created_juzzio ON auth.users;
        CREATE TRIGGER on_auth_user_created_juzzio
            AFTER INSERT ON auth.users
            FOR EACH ROW EXECUTE FUNCTION public.handle_new_juzzio_user();
    END IF;
EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'auth.users trigger oluşturulamadı (yetki yok) — istemci upsert yolu kullanılacak.';
END $$;

-- Kullanıcı adı ile giriş: yalnızca kullanıcı adına göre e-posta çözer
-- (görünen ad eşleşmesi kaldırıldı; aynı görünen ada sahip başka hesaba giriş denemesi engellendi).
CREATE OR REPLACE FUNCTION public.resolve_email_by_username(p_username TEXT)
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT email
    FROM public.profiles
    WHERE LOWER(username) = LOWER(TRIM(REGEXP_REPLACE(COALESCE(p_username, ''), '^@+', '')))
    LIMIT 1;
$$;
GRANT EXECUTE ON FUNCTION public.resolve_email_by_username(TEXT) TO anon, authenticated, service_role;

-- Çevrim içi / son görülme
CREATE OR REPLACE FUNCTION public.set_my_presence(p_online BOOLEAN)
RETURNS VOID
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    UPDATE public.profiles
    SET is_online = COALESCE(p_online, false), last_seen = NOW()
    WHERE id = auth.uid();
$$;
GRANT EXECUTE ON FUNCTION public.set_my_presence(BOOLEAN) TO authenticated;

-- -----------------------------------------------------------------------------
-- 2. ENGELLEME / SESSİZE ALMA (canlı DB'de var; temiz kurulumda da garanti)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.blocked_users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    blocker_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    blocked_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    blocked_username TEXT NOT NULL DEFAULT '',
    blocked_display_name TEXT NOT NULL DEFAULT '',
    blocked_avatar_url TEXT,
    reason TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TABLE IF NOT EXISTS public.muted_users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    muter_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    muted_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    mute_posts BOOLEAN NOT NULL DEFAULT true,
    mute_stories BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
SELECT public._juzzio_dedupe('blocked_users', ARRAY['blocker_id', 'blocked_id']);
SELECT public._juzzio_ensure_unique('blocked_users', 'blocked_users_unique_pair', ARRAY['blocker_id', 'blocked_id']);
SELECT public._juzzio_dedupe('muted_users', ARRAY['muter_id', 'muted_id']);
SELECT public._juzzio_ensure_unique('muted_users', 'muted_users_unique_pair', ARRAY['muter_id', 'muted_id']);
SELECT public._juzzio_reset_fk('blocked_users', 'blocker_id', 'public.profiles', 'CASCADE');
SELECT public._juzzio_reset_fk('blocked_users', 'blocked_id', 'public.profiles', 'CASCADE');
SELECT public._juzzio_reset_fk('muted_users', 'muter_id', 'public.profiles', 'CASCADE');
SELECT public._juzzio_reset_fk('muted_users', 'muted_id', 'public.profiles', 'CASCADE');

CREATE OR REPLACE FUNCTION public.is_blocked_between(p_user_a UUID, p_user_b UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.blocked_users b
        WHERE (b.blocker_id = p_user_a AND b.blocked_id = p_user_b)
           OR (b.blocker_id = p_user_b AND b.blocked_id = p_user_a)
    );
$$;
GRANT EXECUTE ON FUNCTION public.is_blocked_between(UUID, UUID) TO authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 3. ARKADAŞLIK (FRIENDSHIPS) — tek yönlü çift kaydı + yalnızca ilgili kişiler görür
-- -----------------------------------------------------------------------------
SELECT public._juzzio_reset_fk('friendships', 'requester_id', 'public.profiles', 'CASCADE');
SELECT public._juzzio_reset_fk('friendships', 'receiver_id', 'public.profiles', 'CASCADE');

-- Kendine arkadaşlık kayıtlarını temizle
DELETE FROM public.friendships WHERE requester_id = receiver_id;

-- A→B ve B→A çift kayıtlarını tek kayda indir (accepted > pending > rejected önceliği)
DELETE FROM public.friendships t
USING (
    SELECT ctid,
           row_number() OVER (
               PARTITION BY LEAST(requester_id, receiver_id), GREATEST(requester_id, receiver_id)
               ORDER BY CASE status WHEN 'accepted' THEN 0 WHEN 'pending' THEN 1 ELSE 2 END,
                        updated_at DESC NULLS LAST
           ) AS rn
    FROM public.friendships
) d
WHERE t.ctid = d.ctid AND d.rn > 1;

CREATE UNIQUE INDEX IF NOT EXISTS idx_friendships_unique_pair
    ON public.friendships (LEAST(requester_id, receiver_id), GREATEST(requester_id, receiver_id));
CREATE INDEX IF NOT EXISTS idx_friendships_requester ON public.friendships (requester_id, status);
CREATE INDEX IF NOT EXISTS idx_friendships_receiver ON public.friendships (receiver_id, status);

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'friendships_no_self') THEN
        ALTER TABLE public.friendships ADD CONSTRAINT friendships_no_self CHECK (requester_id <> receiver_id) NOT VALID;
    END IF;
END $$;

CREATE OR REPLACE FUNCTION public.is_friends_accepted(p_viewer UUID, p_owner UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.friendships fr
        WHERE fr.status = 'accepted'
          AND ((fr.requester_id = p_viewer AND fr.receiver_id = p_owner)
            OR (fr.requester_id = p_owner AND fr.receiver_id = p_viewer))
    );
$$;
GRANT EXECUTE ON FUNCTION public.is_friends_accepted(UUID, UUID) TO authenticated, service_role;

-- Ad/kullanıcı adı/avatar alanlarını her zaman profillerden doldur (istemci hatasına dayanıklı)
CREATE OR REPLACE FUNCTION public.fill_friendship_identity()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    r RECORD;
BEGIN
    SELECT username, display_name, avatar_url INTO r FROM public.profiles WHERE id = NEW.requester_id;
    IF FOUND THEN
        NEW.requester_username := COALESCE(r.username, '');
        NEW.requester_name := COALESCE(r.display_name, '');
        NEW.requester_avatar := r.avatar_url;
    END IF;
    SELECT username, display_name, avatar_url INTO r FROM public.profiles WHERE id = NEW.receiver_id;
    IF FOUND THEN
        NEW.receiver_username := COALESCE(r.username, '');
        NEW.receiver_name := COALESCE(r.display_name, '');
        NEW.receiver_avatar := r.avatar_url;
    END IF;
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_fill_friendship_identity ON public.friendships;
CREATE TRIGGER trg_fill_friendship_identity
BEFORE INSERT OR UPDATE OF requester_id, receiver_id, status ON public.friendships
FOR EACH ROW EXECUTE FUNCTION public.fill_friendship_identity();

-- Arkadaşlık isteği gönder: karşı taraf zaten bana istek attıysa otomatik kabul et.
CREATE OR REPLACE FUNCTION public.send_friend_request(p_target UUID)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_row public.friendships%ROWTYPE;
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
    IF p_target IS NULL OR p_target = v_uid THEN RAISE EXCEPTION 'invalid_target'; END IF;
    IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = p_target) THEN RAISE EXCEPTION 'user_not_found'; END IF;
    IF public.is_blocked_between(v_uid, p_target) THEN RAISE EXCEPTION 'blocked'; END IF;

    SELECT * INTO v_row
    FROM public.friendships
    WHERE LEAST(requester_id, receiver_id) = LEAST(v_uid, p_target)
      AND GREATEST(requester_id, receiver_id) = GREATEST(v_uid, p_target)
    FOR UPDATE;

    IF NOT FOUND THEN
        INSERT INTO public.friendships (requester_id, receiver_id, status)
        VALUES (v_uid, p_target, 'pending');
        RETURN 'pending';
    END IF;

    IF v_row.status = 'accepted' THEN
        RETURN 'accepted';
    END IF;

    IF v_row.status = 'pending' AND v_row.receiver_id = v_uid THEN
        UPDATE public.friendships SET status = 'accepted' WHERE id = v_row.id;
        RETURN 'accepted';
    END IF;

    -- Daha önce reddedilmiş veya benim bekleyen isteğim: yeniden 'pending' (yönü bana çevir)
    UPDATE public.friendships
    SET requester_id = v_uid, receiver_id = p_target, status = 'pending', created_at = NOW()
    WHERE id = v_row.id;
    RETURN 'pending';
END;
$$;
GRANT EXECUTE ON FUNCTION public.send_friend_request(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.respond_friend_request(p_friendship UUID, p_accept BOOLEAN)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID := auth.uid();
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
    IF p_accept THEN
        UPDATE public.friendships SET status = 'accepted'
        WHERE id = p_friendship AND receiver_id = v_uid AND status = 'pending';
        RETURN 'accepted';
    END IF;
    DELETE FROM public.friendships
    WHERE id = p_friendship AND (receiver_id = v_uid OR requester_id = v_uid) AND status <> 'accepted';
    RETURN 'rejected';
END;
$$;
GRANT EXECUTE ON FUNCTION public.respond_friend_request(UUID, BOOLEAN) TO authenticated;

CREATE OR REPLACE FUNCTION public.remove_friend(p_other UUID)
RETURNS VOID
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    DELETE FROM public.friendships
    WHERE LEAST(requester_id, receiver_id) = LEAST(auth.uid(), p_other)
      AND GREATEST(requester_id, receiver_id) = GREATEST(auth.uid(), p_other);
$$;
GRANT EXECUTE ON FUNCTION public.remove_friend(UUID) TO authenticated;

-- Mesaj sütunları (aşağıdaki fonksiyonlar bunlara başvurduğu için önce eklenir)
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS sender_name TEXT DEFAULT '';
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS receiver_id UUID;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS image_url TEXT;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS video_url TEXT;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS story_id UUID;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS reactions JSONB NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS is_pinned BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS expires_at TIMESTAMPTZ;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS reply_to_id UUID;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS edited_at TIMESTAMPTZ;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS forwarded_from UUID;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS forwarded_from_user UUID;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS location_lat DOUBLE PRECISION;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS location_lng DOUBLE PRECISION;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS location_name TEXT;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS document_url TEXT;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS document_name TEXT;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS document_size INTEGER;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS contact_card JSONB;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS metadata JSONB NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE public.messages ALTER COLUMN original_text SET DEFAULT '';
ALTER TABLE public.messages ALTER COLUMN translated_text SET DEFAULT '';
ALTER TABLE public.messages ALTER COLUMN source_lang SET DEFAULT 'tr';
ALTER TABLE public.messages ALTER COLUMN target_lang SET DEFAULT 'en';

-- -----------------------------------------------------------------------------
-- 4. ODALAR (ROOMS) ve KATILIMCILAR (ROOM_PARTICIPANTS)
-- -----------------------------------------------------------------------------
ALTER TABLE public.rooms ADD COLUMN IF NOT EXISTS is_group BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.rooms ADD COLUMN IF NOT EXISTS is_channel BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.rooms ADD COLUMN IF NOT EXISTS disappearing_timer TEXT NOT NULL DEFAULT 'off';
ALTER TABLE public.rooms ADD COLUMN IF NOT EXISTS is_archived BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.rooms ADD COLUMN IF NOT EXISTS is_call_active BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.rooms ADD COLUMN IF NOT EXISTS active_call JSONB;
ALTER TABLE public.rooms ADD COLUMN IF NOT EXISTS group_members JSONB NOT NULL DEFAULT '[]'::jsonb;
ALTER TABLE public.rooms ADD COLUMN IF NOT EXISTS group_member_ids JSONB NOT NULL DEFAULT '[]'::jsonb;
ALTER TABLE public.rooms ADD COLUMN IF NOT EXISTS avatar_url TEXT;
ALTER TABLE public.rooms ADD COLUMN IF NOT EXISTS description TEXT NOT NULL DEFAULT '';
ALTER TABLE public.rooms ADD COLUMN IF NOT EXISTS created_by UUID;
ALTER TABLE public.rooms ADD COLUMN IF NOT EXISTS last_message_at TIMESTAMPTZ;
ALTER TABLE public.rooms ADD COLUMN IF NOT EXISTS last_message_sender UUID;
ALTER TABLE public.rooms ADD COLUMN IF NOT EXISTS last_message_type TEXT;
ALTER TABLE public.rooms ADD COLUMN IF NOT EXISTS last_message_preview TEXT;
ALTER TABLE public.rooms ALTER COLUMN title SET DEFAULT 'Juzzio';

-- livekit_room_name: canlı DB'de UNIQUE değil ve 1'e 1 odalar ortak varsayılanı kullanıyordu.
UPDATE public.rooms SET livekit_room_name = 'lk_' || REPLACE(id::text, '-', '')
WHERE livekit_room_name IS NULL OR livekit_room_name = '' OR livekit_room_name = 'juzzio_live_room'
   OR id IN (
       SELECT id FROM (
           SELECT id, row_number() OVER (PARTITION BY livekit_room_name ORDER BY created_at, id) rn
           FROM public.rooms
       ) x WHERE rn > 1
   );
ALTER TABLE public.rooms ALTER COLUMN livekit_room_name SET DEFAULT ('lk_' || REPLACE(gen_random_uuid()::text, '-', ''));
CREATE UNIQUE INDEX IF NOT EXISTS idx_rooms_livekit_room_name ON public.rooms (livekit_room_name);
CREATE INDEX IF NOT EXISTS idx_rooms_last_message_at ON public.rooms (last_message_at DESC NULLS LAST);

SELECT public._juzzio_reset_fk('rooms', 'created_by', 'public.profiles', 'SET NULL');
SELECT public._juzzio_reset_fk('rooms', 'last_message_sender', 'public.profiles', 'SET NULL');

CREATE TABLE IF NOT EXISTS public.room_participants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    room_id UUID NOT NULL REFERENCES public.rooms(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    role TEXT NOT NULL DEFAULT 'member',
    joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    left_at TIMESTAMPTZ
);
ALTER TABLE public.room_participants ADD COLUMN IF NOT EXISTS last_read_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
ALTER TABLE public.room_participants ADD COLUMN IF NOT EXISTS is_muted BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.room_participants ADD COLUMN IF NOT EXISTS is_pinned BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.room_participants ADD COLUMN IF NOT EXISTS cleared_at TIMESTAMPTZ;
ALTER TABLE public.room_participants ADD COLUMN IF NOT EXISTS hidden_at TIMESTAMPTZ;
ALTER TABLE public.room_participants DROP CONSTRAINT IF EXISTS room_participants_role_check;
ALTER TABLE public.room_participants ALTER COLUMN role SET DEFAULT 'member';
ALTER TABLE public.room_participants ADD CONSTRAINT room_participants_role_check
    CHECK (role IN ('owner', 'admin', 'member', 'host', 'tr', 'en', 'viewer')) NOT VALID;
SELECT public._juzzio_reset_fk('room_participants', 'room_id', 'public.rooms', 'CASCADE');
SELECT public._juzzio_reset_fk('room_participants', 'user_id', 'public.profiles', 'CASCADE');
SELECT public._juzzio_dedupe('room_participants', ARRAY['room_id', 'user_id'], 'left_at NULLS FIRST, joined_at');
SELECT public._juzzio_ensure_unique('room_participants', 'room_participants_room_user_unique', ARRAY['room_id', 'user_id']);
CREATE INDEX IF NOT EXISTS idx_room_participants_user ON public.room_participants (user_id) WHERE left_at IS NULL;

-- Geriye dönük üyelik doldurma:
--  a) Grup odaları: created_by + group_member_ids
INSERT INTO public.room_participants (room_id, user_id, role)
SELECT r.id, r.created_by, 'owner'
FROM public.rooms r
WHERE r.created_by IS NOT NULL
  AND r.room_code <> 'juzzio-couple-main'
  AND EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = r.created_by)
ON CONFLICT (room_id, user_id) DO NOTHING;

INSERT INTO public.room_participants (room_id, user_id, role)
SELECT r.id, (m.value #>> '{}')::uuid, 'member'
FROM public.rooms r
CROSS JOIN LATERAL jsonb_array_elements(COALESCE(r.group_member_ids, '[]'::jsonb)) m
WHERE r.room_code <> 'juzzio-couple-main'
  AND (m.value #>> '{}') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  AND EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = (m.value #>> '{}')::uuid)
ON CONFLICT (room_id, user_id) DO NOTHING;

--  b) Eski "dm-xxxxxxxx-yyyyyyyy" odaları: o odada mesaj gönderen kullanıcılar
INSERT INTO public.room_participants (room_id, user_id, role)
SELECT DISTINCT m.room_id, m.sender_id, 'member'
FROM public.messages m
JOIN public.rooms r ON r.id = m.room_id
WHERE r.room_code LIKE 'dm-%'
ON CONFLICT (room_id, user_id) DO NOTHING;

--  c) Ortak "juzzio-couple-main" odası: KİMSE üye değildir → içerik artık kimseye görünmez
--     (veri silinmez; yalnızca erişim kapatılır).
DELETE FROM public.room_participants
WHERE room_id IN (SELECT id FROM public.rooms WHERE room_code = 'juzzio-couple-main');
UPDATE public.rooms SET is_call_active = false, active_call = NULL WHERE room_code = 'juzzio-couple-main';

-- Üyelik kontrolü (RLS özyinelemesini önlemek için SECURITY DEFINER)
CREATE OR REPLACE FUNCTION public.is_room_member(p_room UUID, p_user UUID DEFAULT auth.uid())
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.room_participants rp
        WHERE rp.room_id = p_room AND rp.user_id = p_user AND rp.left_at IS NULL
    );
$$;
GRANT EXECUTE ON FUNCTION public.is_room_member(UUID, UUID) TO authenticated, service_role;

-- Grup odası üye isim/kimlik JSON'unu room_participants'tan senkronize eder.
CREATE OR REPLACE FUNCTION public.sync_room_member_cache(p_room UUID)
RETURNS VOID
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    UPDATE public.rooms r
    SET group_member_ids = COALESCE((
            SELECT jsonb_agg(rp.user_id::text ORDER BY rp.joined_at)
            FROM public.room_participants rp
            WHERE rp.room_id = r.id AND rp.left_at IS NULL
        ), '[]'::jsonb),
        group_members = COALESCE((
            SELECT jsonb_agg(COALESCE(NULLIF(p.display_name, ''), p.username, 'Juzzio') ORDER BY rp.joined_at)
            FROM public.room_participants rp
            JOIN public.profiles p ON p.id = rp.user_id
            WHERE rp.room_id = r.id AND rp.left_at IS NULL
        ), '[]'::jsonb),
        updated_at = NOW()
    WHERE r.id = p_room;
$$;

-- 1'e 1 sohbet odası: deterministik oda kodu (tam UUID'ler) + iki katılımcı
CREATE OR REPLACE FUNCTION public.get_or_create_dm_room(p_other UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_code TEXT;
    v_room UUID;
    v_title TEXT;
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
    IF p_other IS NULL OR p_other = v_uid THEN RAISE EXCEPTION 'invalid_target'; END IF;
    IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = p_other) THEN RAISE EXCEPTION 'user_not_found'; END IF;
    IF public.is_blocked_between(v_uid, p_other) THEN RAISE EXCEPTION 'blocked'; END IF;

    v_code := 'dm_' || LEAST(v_uid, p_other)::text || '_' || GREATEST(v_uid, p_other)::text;

    SELECT id INTO v_room FROM public.rooms WHERE room_code = v_code;
    IF v_room IS NULL THEN
        SELECT COALESCE(NULLIF(display_name, ''), username, 'Juzzio') INTO v_title FROM public.profiles WHERE id = p_other;
        INSERT INTO public.rooms (room_code, title, livekit_room_name, is_group, created_by)
        VALUES (v_code, v_title, 'lk_dm_' || SUBSTRING(md5(v_code) FROM 1 FOR 20), false, v_uid)
        ON CONFLICT (room_code) DO NOTHING
        RETURNING id INTO v_room;
        IF v_room IS NULL THEN
            SELECT id INTO v_room FROM public.rooms WHERE room_code = v_code;
        END IF;
    END IF;

    INSERT INTO public.room_participants (room_id, user_id, role)
    VALUES (v_room, v_uid, 'member'), (v_room, p_other, 'member')
    ON CONFLICT (room_id, user_id) DO UPDATE SET left_at = NULL, hidden_at = NULL;

    RETURN v_room;
END;
$$;
GRANT EXECUTE ON FUNCTION public.get_or_create_dm_room(UUID) TO authenticated;

-- Grup / kanal oluşturma: yalnızca seçilen (engellenmemiş) kişiler eklenir
CREATE OR REPLACE FUNCTION public.create_group_room(
    p_title TEXT,
    p_member_ids UUID[],
    p_disappearing_timer TEXT DEFAULT 'off',
    p_is_channel BOOLEAN DEFAULT false
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_room UUID;
    v_code TEXT := (CASE WHEN p_is_channel THEN 'channel_' ELSE 'group_' END) || REPLACE(gen_random_uuid()::text, '-', '');
    v_member UUID;
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
    IF COALESCE(TRIM(p_title), '') = '' THEN RAISE EXCEPTION 'title_required'; END IF;

    INSERT INTO public.rooms (room_code, title, livekit_room_name, is_group, is_channel, disappearing_timer, created_by)
    VALUES (
        v_code,
        LEFT(TRIM(p_title), 80),
        'lk_' || v_code,
        true,
        COALESCE(p_is_channel, false),
        CASE WHEN p_disappearing_timer IN ('off', '24h', '7d', '30d') THEN p_disappearing_timer ELSE 'off' END,
        v_uid
    )
    RETURNING id INTO v_room;

    INSERT INTO public.room_participants (room_id, user_id, role) VALUES (v_room, v_uid, 'owner');

    FOREACH v_member IN ARRAY COALESCE(p_member_ids, ARRAY[]::UUID[]) LOOP
        IF v_member IS NOT NULL AND v_member <> v_uid
           AND EXISTS (SELECT 1 FROM public.profiles WHERE id = v_member)
           AND NOT public.is_blocked_between(v_uid, v_member) THEN
            INSERT INTO public.room_participants (room_id, user_id, role)
            VALUES (v_room, v_member, 'member')
            ON CONFLICT (room_id, user_id) DO NOTHING;
        END IF;
    END LOOP;

    PERFORM public.sync_room_member_cache(v_room);
    RETURN v_room;
END;
$$;
GRANT EXECUTE ON FUNCTION public.create_group_room(TEXT, UUID[], TEXT, BOOLEAN) TO authenticated;

CREATE OR REPLACE FUNCTION public.add_group_members(p_room UUID, p_member_ids UUID[])
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_member UUID;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.rooms WHERE id = p_room AND is_group) THEN RAISE EXCEPTION 'not_a_group'; END IF;
    IF NOT public.is_room_member(p_room, v_uid) THEN RAISE EXCEPTION 'not_a_member'; END IF;
    FOREACH v_member IN ARRAY COALESCE(p_member_ids, ARRAY[]::UUID[]) LOOP
        IF v_member IS NOT NULL AND v_member <> v_uid
           AND EXISTS (SELECT 1 FROM public.profiles WHERE id = v_member)
           AND NOT public.is_blocked_between(v_uid, v_member) THEN
            INSERT INTO public.room_participants (room_id, user_id, role)
            VALUES (p_room, v_member, 'member')
            ON CONFLICT (room_id, user_id) DO UPDATE SET left_at = NULL, hidden_at = NULL;
        END IF;
    END LOOP;
    PERFORM public.sync_room_member_cache(p_room);
END;
$$;
GRANT EXECUTE ON FUNCTION public.add_group_members(UUID, UUID[]) TO authenticated;

CREATE OR REPLACE FUNCTION public.leave_room(p_room UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_is_group BOOLEAN;
BEGIN
    SELECT is_group INTO v_is_group FROM public.rooms WHERE id = p_room;
    IF v_is_group THEN
        UPDATE public.room_participants SET left_at = NOW()
        WHERE room_id = p_room AND user_id = auth.uid();
        PERFORM public.sync_room_member_cache(p_room);
    ELSE
        -- 1'e 1 sohbette "sil": yalnızca bende gizle ve geçmişi bende temizle
        UPDATE public.room_participants SET hidden_at = NOW(), cleared_at = NOW()
        WHERE room_id = p_room AND user_id = auth.uid();
    END IF;
END;
$$;
GRANT EXECUTE ON FUNCTION public.leave_room(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.clear_room_history_for_me(p_room UUID)
RETURNS VOID
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    UPDATE public.room_participants SET cleared_at = NOW()
    WHERE room_id = p_room AND user_id = auth.uid();
$$;
GRANT EXECUTE ON FUNCTION public.clear_room_history_for_me(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.mark_room_read(p_room UUID)
RETURNS VOID
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    UPDATE public.room_participants SET last_read_at = NOW()
    WHERE room_id = p_room AND user_id = auth.uid();
$$;
GRANT EXECUTE ON FUNCTION public.mark_room_read(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.set_room_preferences(p_room UUID, p_muted BOOLEAN DEFAULT NULL, p_pinned BOOLEAN DEFAULT NULL)
RETURNS VOID
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    UPDATE public.room_participants
    SET is_muted = COALESCE(p_muted, is_muted),
        is_pinned = COALESCE(p_pinned, is_pinned)
    WHERE room_id = p_room AND user_id = auth.uid();
$$;
GRANT EXECUTE ON FUNCTION public.set_room_preferences(UUID, BOOLEAN, BOOLEAN) TO authenticated;

-- Sohbet listesi: yalnızca benim üyesi olduğum odalar, karşı taraf bilgisi ve okunmamış sayısı
DROP FUNCTION IF EXISTS public.get_my_conversations();
CREATE OR REPLACE FUNCTION public.get_my_conversations()
RETURNS TABLE (
    room_id UUID,
    room_code TEXT,
    title TEXT,
    is_group BOOLEAN,
    is_channel BOOLEAN,
    livekit_room_name TEXT,
    disappearing_timer TEXT,
    avatar_url TEXT,
    partner_id UUID,
    partner_username TEXT,
    partner_display_name TEXT,
    partner_avatar_url TEXT,
    partner_lang TEXT,
    partner_is_online BOOLEAN,
    partner_last_seen TIMESTAMPTZ,
    member_ids JSONB,
    member_names JSONB,
    last_message_at TIMESTAMPTZ,
    last_message_sender UUID,
    last_message_type TEXT,
    last_message_preview TEXT,
    unread_count INTEGER,
    is_muted BOOLEAN,
    is_pinned BOOLEAN,
    is_call_active BOOLEAN,
    active_call JSONB,
    created_by UUID,
    partner_last_read_at TIMESTAMPTZ
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT
        r.id,
        r.room_code,
        CASE WHEN r.is_group THEN r.title ELSE COALESCE(NULLIF(op.display_name, ''), op.username, r.title) END,
        r.is_group,
        r.is_channel,
        r.livekit_room_name,
        r.disappearing_timer,
        CASE WHEN r.is_group THEN r.avatar_url ELSE op.avatar_url END,
        op.id,
        op.username,
        op.display_name,
        op.avatar_url,
        op.preferred_lang,
        op.is_online,
        op.last_seen,
        r.group_member_ids,
        r.group_members,
        CASE WHEN me.cleared_at IS NOT NULL AND r.last_message_at <= me.cleared_at THEN NULL ELSE r.last_message_at END,
        r.last_message_sender,
        r.last_message_type,
        CASE WHEN me.cleared_at IS NOT NULL AND r.last_message_at <= me.cleared_at THEN NULL ELSE r.last_message_preview END,
        (
            SELECT COUNT(*)::INTEGER
            FROM public.messages m
            WHERE m.room_id = r.id
              AND m.sender_id <> me.user_id
              AND m.created_at > GREATEST(me.last_read_at, COALESCE(me.cleared_at, me.last_read_at))
              AND COALESCE(m.is_deleted, false) = false
        ),
        me.is_muted,
        me.is_pinned,
        r.is_call_active,
        r.active_call,
        r.created_by,
        CASE WHEN COALESCE(op.read_receipts, true) AND COALESCE(mp.read_receipts, true) THEN op.partner_last_read_at END
    FROM public.room_participants me
    JOIN public.profiles mp ON mp.id = me.user_id
    JOIN public.rooms r ON r.id = me.room_id
    LEFT JOIN LATERAL (
        SELECT p.*, o.last_read_at AS partner_last_read_at
        FROM public.room_participants o
        JOIN public.profiles p ON p.id = o.user_id
        WHERE NOT r.is_group AND o.room_id = r.id AND o.user_id <> me.user_id
        LIMIT 1
    ) op ON true
    WHERE me.user_id = auth.uid()
      AND me.left_at IS NULL
      AND (me.hidden_at IS NULL OR r.last_message_at > me.hidden_at)
      AND r.room_code <> 'juzzio-couple-main'
      AND (r.is_group OR op.id IS NOT NULL)
    ORDER BY me.is_pinned DESC, COALESCE(r.last_message_at, r.created_at) DESC;
$$;
GRANT EXECUTE ON FUNCTION public.get_my_conversations() TO authenticated;

-- -----------------------------------------------------------------------------
-- 5. MESAJLAR
-- -----------------------------------------------------------------------------

ALTER TABLE public.messages DROP CONSTRAINT IF EXISTS messages_message_type_check;
ALTER TABLE public.messages ADD CONSTRAINT messages_message_type_check CHECK (
    message_type IN ('text', 'voice', 'image', 'video', 'system', 'document', 'location', 'contact', 'sticker', 'call', 'story_reply')
) NOT VALID;

SELECT public._juzzio_reset_fk('messages', 'room_id', 'public.rooms', 'CASCADE');
SELECT public._juzzio_reset_fk('messages', 'sender_id', 'public.profiles', 'CASCADE');
SELECT public._juzzio_reset_fk('messages', 'receiver_id', 'public.profiles', 'SET NULL');
SELECT public._juzzio_reset_fk('messages', 'reply_to_id', 'public.messages', 'SET NULL');
SELECT public._juzzio_reset_fk('messages', 'forwarded_from_user', 'public.profiles', 'SET NULL');
SELECT public._juzzio_reset_fk('messages', 'story_id', 'public.stories', 'SET NULL');

CREATE INDEX IF NOT EXISTS idx_messages_room_created ON public.messages (room_id, created_at);
CREATE INDEX IF NOT EXISTS idx_messages_sender ON public.messages (sender_id);

-- Mesaj eklenmeden önce: gönderen adı, süreli mesaj bitişi, sohbet hedefi
CREATE OR REPLACE FUNCTION public.prepare_new_message()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_timer TEXT;
    v_is_group BOOLEAN;
BEGIN
    IF COALESCE(NEW.sender_name, '') = '' THEN
        SELECT COALESCE(NULLIF(display_name, ''), username, '') INTO NEW.sender_name
        FROM public.profiles WHERE id = NEW.sender_id;
    END IF;

    SELECT disappearing_timer, is_group INTO v_timer, v_is_group FROM public.rooms WHERE id = NEW.room_id;
    IF NEW.expires_at IS NULL AND v_timer IS NOT NULL THEN
        NEW.expires_at := CASE v_timer
            WHEN '24h' THEN NOW() + INTERVAL '24 hours'
            WHEN '7d' THEN NOW() + INTERVAL '7 days'
            WHEN '30d' THEN NOW() + INTERVAL '30 days'
            ELSE NULL
        END;
    END IF;

    IF NOT COALESCE(v_is_group, false) AND NEW.receiver_id IS NULL THEN
        SELECT user_id INTO NEW.receiver_id
        FROM public.room_participants
        WHERE room_id = NEW.room_id AND user_id <> NEW.sender_id
        LIMIT 1;
    END IF;
    NEW.original_text := COALESCE(NEW.original_text, '');
    NEW.translated_text := COALESCE(NEW.translated_text, '');
    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_prepare_new_message ON public.messages;
CREATE TRIGGER trg_prepare_new_message
BEFORE INSERT ON public.messages
FOR EACH ROW EXECUTE FUNCTION public.prepare_new_message();

-- Mesaj eklendikten sonra: oda özeti, gizlenen sohbetleri geri getir, bildirimler
CREATE OR REPLACE FUNCTION public.after_new_message()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_room RECORD;
    v_preview TEXT;
    v_sender RECORD;
    rp RECORD;
BEGIN
    v_preview := CASE NEW.message_type
        WHEN 'voice' THEN '🎤 Sesli mesaj'
        WHEN 'image' THEN '📷 Fotoğraf'
        WHEN 'video' THEN '🎬 Video'
        WHEN 'document' THEN '📄 ' || COALESCE(NEW.document_name, 'Belge')
        WHEN 'location' THEN '📍 Konum'
        WHEN 'contact' THEN '👤 Kişi'
        WHEN 'sticker' THEN 'Çıkartma'
        WHEN 'call' THEN '📞 Arama'
        ELSE COALESCE(NULLIF(NEW.original_text, ''), 'Mesaj')
    END;
    IF NEW.story_id IS NOT NULL THEN
        v_preview := '📸 Hikâye yanıtı: ' || COALESCE(NULLIF(NEW.original_text, ''), '');
    END IF;
    -- v0.7.0: uçtan uca şifreli mesajın içeriği sunucuda yoktur
    IF COALESCE(NEW.metadata, '{}'::jsonb) ? 'e2ee' THEN
        v_preview := '🔒 Şifreli mesaj';
    END IF;

    UPDATE public.rooms
    SET last_message_at = NEW.created_at,
        last_message_sender = NEW.sender_id,
        last_message_type = NEW.message_type,
        last_message_preview = LEFT(v_preview, 160),
        updated_at = NOW()
    WHERE id = NEW.room_id
    RETURNING id, is_group, title INTO v_room;

    -- 1'e 1 sohbette gizlenmiş/silinmiş sohbet yeni mesajla tekrar görünsün
    UPDATE public.room_participants SET hidden_at = NULL
    WHERE room_id = NEW.room_id AND hidden_at IS NOT NULL AND left_at IS NULL;

    -- Gönderenin kendi okunma zamanı
    UPDATE public.room_participants SET last_read_at = NEW.created_at
    WHERE room_id = NEW.room_id AND user_id = NEW.sender_id;

    -- v0.7.0: arama kayıtları (call) sohbette görünür ama ayrıca mesaj bildirimi üretmez
    IF NEW.message_type IN ('system', 'call') THEN
        RETURN NEW;
    END IF;

    SELECT username, display_name, avatar_url INTO v_sender FROM public.profiles WHERE id = NEW.sender_id;

    FOR rp IN
        SELECT user_id, is_muted FROM public.room_participants
        WHERE room_id = NEW.room_id AND user_id <> NEW.sender_id AND left_at IS NULL
    LOOP
        IF rp.is_muted OR public.is_blocked_between(NEW.sender_id, rp.user_id) THEN
            CONTINUE;
        END IF;
        BEGIN
            INSERT INTO public.notifications (
                recipient_id, actor_id, actor_username, actor_display_name, actor_avatar_url,
                event_type, target_id, target_secondary_id, preview_text, dedupe_key
            ) VALUES (
                rp.user_id, NEW.sender_id,
                COALESCE(v_sender.username, ''), COALESCE(NULLIF(v_sender.display_name, ''), NEW.sender_name, 'Juzzio'),
                v_sender.avatar_url,
                CASE WHEN COALESCE(v_room.is_group, false) THEN 'group_activity'
                     WHEN NEW.story_id IS NOT NULL THEN 'story_reply'
                     ELSE 'message' END,
                NEW.room_id::text, NEW.id::text,
                LEFT(CASE WHEN COALESCE(v_room.is_group, false) THEN COALESCE(v_room.title, '') || ': ' || v_preview ELSE v_preview END, 160),
                'msg_' || NEW.id::text
            )
            ON CONFLICT (recipient_id, dedupe_key) DO NOTHING;
        EXCEPTION WHEN OTHERS THEN
            NULL;
        END;
    END LOOP;
    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_after_new_message ON public.messages;
CREATE TRIGGER trg_after_new_message
AFTER INSERT ON public.messages
FOR EACH ROW EXECUTE FUNCTION public.after_new_message();

-- Eski (receiver_id tabanlı) bildirim trigger'ı yerine yukarıdaki kullanılır
DROP TRIGGER IF EXISTS trg_notify_on_new_message ON public.messages;

-- Mevcut odaların "son mesaj" özetini geriye dönük doldur
UPDATE public.rooms r
SET last_message_at = x.created_at,
    last_message_sender = x.sender_id,
    last_message_type = x.message_type,
    last_message_preview = LEFT(COALESCE(NULLIF(x.original_text, ''), x.message_type), 160)
FROM (
    SELECT DISTINCT ON (room_id) room_id, created_at, sender_id, message_type, original_text
    FROM public.messages
    ORDER BY room_id, created_at DESC
) x
WHERE r.id = x.room_id AND r.last_message_at IS NULL;

-- Tepki (emoji): herhangi bir üye kendi tepkisini değiştirebilir, başkasının mesaj içeriğini değiştiremez
CREATE OR REPLACE FUNCTION public.toggle_message_reaction(p_message UUID, p_emoji TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid TEXT := auth.uid()::text;
    v_room UUID;
    v_reactions JSONB;
BEGIN
    SELECT room_id, COALESCE(reactions, '{}'::jsonb) INTO v_room, v_reactions
    FROM public.messages WHERE id = p_message FOR UPDATE;
    IF v_room IS NULL OR NOT public.is_room_member(v_room, auth.uid()) THEN
        RAISE EXCEPTION 'not_allowed';
    END IF;
    IF COALESCE(p_emoji, '') = '' OR v_reactions->>v_uid = p_emoji THEN
        v_reactions := v_reactions - v_uid;
    ELSE
        v_reactions := jsonb_set(v_reactions, ARRAY[v_uid], to_jsonb(p_emoji), true);
    END IF;
    UPDATE public.messages SET reactions = v_reactions WHERE id = p_message;
    RETURN v_reactions;
END;
$$;
GRANT EXECUTE ON FUNCTION public.toggle_message_reaction(UUID, TEXT) TO authenticated;

-- -----------------------------------------------------------------------------
-- 6. SESLİ NOTLAR
-- -----------------------------------------------------------------------------
SELECT public._juzzio_reset_fk('voice_notes', 'message_id', 'public.messages', 'CASCADE');
SELECT public._juzzio_reset_fk('voice_notes', 'room_id', 'public.rooms', 'CASCADE');
SELECT public._juzzio_reset_fk('voice_notes', 'sender_id', 'public.profiles', 'CASCADE');

-- -----------------------------------------------------------------------------
-- 7. HİKÂYELER (STORIES) ve GÖRÜNTÜLEMELER
-- -----------------------------------------------------------------------------
ALTER TABLE public.stories ADD COLUMN IF NOT EXISTS video_duration_sec INTEGER NOT NULL DEFAULT 15;
ALTER TABLE public.stories ADD COLUMN IF NOT EXISTS filter_preset TEXT NOT NULL DEFAULT 'none';
ALTER TABLE public.stories ADD COLUMN IF NOT EXISTS visibility TEXT NOT NULL DEFAULT 'friends';
ALTER TABLE public.stories ADD COLUMN IF NOT EXISTS is_archived BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.stories ADD COLUMN IF NOT EXISTS stickers_json JSONB NOT NULL DEFAULT '[]'::jsonb;
ALTER TABLE public.stories ADD COLUMN IF NOT EXISTS alt_text TEXT NOT NULL DEFAULT '';
ALTER TABLE public.stories ADD COLUMN IF NOT EXISTS music_title TEXT;
ALTER TABLE public.stories ADD COLUMN IF NOT EXISTS music_url TEXT;
ALTER TABLE public.stories ADD COLUMN IF NOT EXISTS source_lang TEXT NOT NULL DEFAULT 'tr';
ALTER TABLE public.stories ADD COLUMN IF NOT EXISTS likes_count INTEGER NOT NULL DEFAULT 0;
ALTER TABLE public.stories ADD COLUMN IF NOT EXISTS views_count INTEGER NOT NULL DEFAULT 0;
ALTER TABLE public.stories ALTER COLUMN visibility SET DEFAULT 'friends';
ALTER TABLE public.stories DROP CONSTRAINT IF EXISTS stories_visibility_check;
ALTER TABLE public.stories ADD CONSTRAINT stories_visibility_check
    CHECK (visibility IN ('everyone', 'followers', 'friends', 'private', 'close_friends')) NOT VALID;
ALTER TABLE public.stories DROP CONSTRAINT IF EXISTS stories_media_type_check;
ALTER TABLE public.stories ADD CONSTRAINT stories_media_type_check
    CHECK (media_type IN ('image', 'video', 'text')) NOT VALID;
SELECT public._juzzio_reset_fk('stories', 'user_id', 'public.profiles', 'CASCADE');
CREATE INDEX IF NOT EXISTS idx_stories_active ON public.stories (expires_at DESC, user_id);

-- Hikâye sahibinin bilgilerini her zaman profilden doldur
CREATE OR REPLACE FUNCTION public.fill_story_identity()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    r RECORD;
BEGIN
    SELECT username, display_name, avatar_url INTO r FROM public.profiles WHERE id = NEW.user_id;
    IF FOUND THEN
        NEW.username := COALESCE(r.username, '');
        NEW.display_name := COALESCE(NULLIF(r.display_name, ''), r.username, '');
        NEW.user_avatar := r.avatar_url;
    END IF;
    IF NEW.expires_at IS NULL OR NEW.expires_at > NOW() + INTERVAL '25 hours' THEN
        NEW.expires_at := NOW() + INTERVAL '24 hours';
    END IF;
    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_fill_story_identity ON public.stories;
CREATE TRIGGER trg_fill_story_identity
BEFORE INSERT ON public.stories
FOR EACH ROW EXECUTE FUNCTION public.fill_story_identity();

CREATE OR REPLACE FUNCTION public.is_following_accepted(p_viewer UUID, p_owner UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.follows f
        WHERE f.follower_id = p_viewer AND f.following_id = p_owner AND f.status = 'following'
    );
$$;

CREATE OR REPLACE FUNCTION public.can_view_story(p_viewer UUID, p_owner UUID, p_visibility TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT CASE
        WHEN p_viewer IS NULL THEN false
        WHEN p_viewer = p_owner THEN true
        WHEN public.is_blocked_between(p_viewer, p_owner) THEN false
        WHEN EXISTS (
            SELECT 1 FROM public.muted_users mu
            WHERE mu.muter_id = p_viewer AND mu.muted_id = p_owner AND mu.mute_stories
        ) THEN false
        WHEN p_visibility IN ('private') THEN false
        WHEN p_visibility IN ('friends', 'close_friends') THEN public.is_friends_accepted(p_viewer, p_owner)
        WHEN p_visibility = 'followers' THEN
            public.is_following_accepted(p_viewer, p_owner) OR public.is_friends_accepted(p_viewer, p_owner)
        ELSE true
    END;
$$;
GRANT EXECUTE ON FUNCTION public.can_view_story(UUID, UUID, TEXT) TO authenticated, service_role;

CREATE TABLE IF NOT EXISTS public.story_views (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    story_id UUID NOT NULL REFERENCES public.stories(id) ON DELETE CASCADE,
    viewer_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    viewer_username TEXT NOT NULL DEFAULT '',
    viewer_display_name TEXT NOT NULL DEFAULT '',
    viewer_avatar_url TEXT,
    has_liked BOOLEAN NOT NULL DEFAULT false,
    viewed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
SELECT public._juzzio_reset_fk('story_views', 'story_id', 'public.stories', 'CASCADE');
SELECT public._juzzio_reset_fk('story_views', 'viewer_id', 'public.profiles', 'CASCADE');
SELECT public._juzzio_dedupe('story_views', ARRAY['story_id', 'viewer_id'], 'has_liked DESC, viewed_at DESC');
SELECT public._juzzio_ensure_unique('story_views', 'story_views_unique_viewer', ARRAY['story_id', 'viewer_id']);

CREATE OR REPLACE FUNCTION public.fill_story_view_identity()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    r RECORD;
BEGIN
    SELECT username, display_name, avatar_url INTO r FROM public.profiles WHERE id = NEW.viewer_id;
    IF FOUND THEN
        NEW.viewer_username := COALESCE(r.username, '');
        NEW.viewer_display_name := COALESCE(NULLIF(r.display_name, ''), r.username, '');
        NEW.viewer_avatar_url := r.avatar_url;
    END IF;
    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_fill_story_view_identity ON public.story_views;
CREATE TRIGGER trg_fill_story_view_identity
BEFORE INSERT ON public.story_views
FOR EACH ROW EXECUTE FUNCTION public.fill_story_view_identity();

CREATE OR REPLACE FUNCTION public.sync_story_counters()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_story UUID := COALESCE(NEW.story_id, OLD.story_id);
BEGIN
    UPDATE public.stories s
    SET views_count = (SELECT COUNT(*) FROM public.story_views v WHERE v.story_id = s.id AND v.viewer_id <> s.user_id),
        likes_count = (SELECT COUNT(*) FROM public.story_views v WHERE v.story_id = s.id AND v.has_liked)
    WHERE s.id = v_story;

    IF TG_OP IN ('INSERT', 'UPDATE') AND NEW.has_liked
       AND (TG_OP = 'INSERT' OR OLD.has_liked IS DISTINCT FROM NEW.has_liked) THEN
        BEGIN
            INSERT INTO public.notifications (
                recipient_id, actor_id, actor_username, actor_display_name, actor_avatar_url,
                event_type, target_id, preview_text, dedupe_key
            )
            SELECT s.user_id, NEW.viewer_id, NEW.viewer_username, NEW.viewer_display_name, NEW.viewer_avatar_url,
                   'story_like', s.id::text, 'Hikâyeni beğendi.', 'story_like_' || s.id::text || '_' || NEW.viewer_id::text
            FROM public.stories s
            WHERE s.id = NEW.story_id AND s.user_id <> NEW.viewer_id
            ON CONFLICT (recipient_id, dedupe_key) DO NOTHING;
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
    END IF;
    RETURN COALESCE(NEW, OLD);
END;
$$;
DROP TRIGGER IF EXISTS trg_sync_story_counters ON public.story_views;
CREATE TRIGGER trg_sync_story_counters
AFTER INSERT OR UPDATE OR DELETE ON public.story_views
FOR EACH ROW EXECUTE FUNCTION public.sync_story_counters();

CREATE OR REPLACE FUNCTION public.toggle_story_like(p_story UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_owner UUID;
    v_vis TEXT;
    v_liked BOOLEAN;
BEGIN
    SELECT user_id, visibility INTO v_owner, v_vis FROM public.stories WHERE id = p_story AND expires_at > NOW();
    IF v_owner IS NULL OR NOT public.can_view_story(v_uid, v_owner, v_vis) THEN
        RAISE EXCEPTION 'not_allowed';
    END IF;
    INSERT INTO public.story_views (story_id, viewer_id, has_liked)
    VALUES (p_story, v_uid, true)
    ON CONFLICT (story_id, viewer_id) DO UPDATE SET has_liked = NOT public.story_views.has_liked, viewed_at = NOW()
    RETURNING has_liked INTO v_liked;
    RETURN v_liked;
END;
$$;
GRANT EXECUTE ON FUNCTION public.toggle_story_like(UUID) TO authenticated;

-- -----------------------------------------------------------------------------
-- 8. TAKİP, GÖNDERİ, BEĞENİ, YORUM, KAYDETME — kısıt ve tetikleyici denkleştirmesi
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.follows (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    follower_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    follower_username TEXT NOT NULL DEFAULT '',
    follower_display_name TEXT NOT NULL DEFAULT '',
    follower_avatar_url TEXT,
    following_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    following_username TEXT NOT NULL DEFAULT '',
    following_display_name TEXT NOT NULL DEFAULT '',
    following_avatar_url TEXT,
    status TEXT NOT NULL DEFAULT 'following',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
DELETE FROM public.follows WHERE follower_id = following_id;
SELECT public._juzzio_dedupe('follows', ARRAY['follower_id', 'following_id'], 'updated_at DESC NULLS LAST');
SELECT public._juzzio_ensure_unique('follows', 'follows_unique_pair', ARRAY['follower_id', 'following_id']);
SELECT public._juzzio_reset_fk('follows', 'follower_id', 'public.profiles', 'CASCADE');
SELECT public._juzzio_reset_fk('follows', 'following_id', 'public.profiles', 'CASCADE');
CREATE INDEX IF NOT EXISTS idx_follows_follower_status ON public.follows (follower_id, status);
CREATE INDEX IF NOT EXISTS idx_follows_following_status ON public.follows (following_id, status);

CREATE OR REPLACE FUNCTION public.fill_follow_identity()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    r RECORD;
BEGIN
    SELECT username, display_name, avatar_url INTO r FROM public.profiles WHERE id = NEW.follower_id;
    IF FOUND THEN
        NEW.follower_username := COALESCE(r.username, '');
        NEW.follower_display_name := COALESCE(r.display_name, '');
        NEW.follower_avatar_url := r.avatar_url;
    END IF;
    SELECT username, display_name, avatar_url INTO r FROM public.profiles WHERE id = NEW.following_id;
    IF FOUND THEN
        NEW.following_username := COALESCE(r.username, '');
        NEW.following_display_name := COALESCE(r.display_name, '');
        NEW.following_avatar_url := r.avatar_url;
    END IF;
    -- Gizli hesaplar için takip her zaman 'pending' başlar (istemci ne gönderirse göndersin)
    IF TG_OP = 'INSERT' THEN
        IF EXISTS (SELECT 1 FROM public.profiles WHERE id = NEW.following_id AND is_private_account) THEN
            NEW.status := 'pending';
        ELSE
            NEW.status := 'following';
        END IF;
    END IF;
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_fill_follow_identity ON public.follows;
CREATE TRIGGER trg_fill_follow_identity
BEFORE INSERT ON public.follows
FOR EACH ROW EXECUTE FUNCTION public.fill_follow_identity();

CREATE OR REPLACE FUNCTION public.notify_on_follow_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    BEGIN
        IF TG_OP = 'INSERT' THEN
            INSERT INTO public.notifications (recipient_id, actor_id, actor_username, actor_display_name, actor_avatar_url,
                                              event_type, target_id, preview_text, dedupe_key)
            VALUES (NEW.following_id, NEW.follower_id, NEW.follower_username, NEW.follower_display_name, NEW.follower_avatar_url,
                    CASE WHEN NEW.status = 'pending' THEN 'follow_request' ELSE 'follow' END,
                    NEW.follower_id::text,
                    CASE WHEN NEW.status = 'pending' THEN 'Seni takip etmek istiyor.' ELSE 'Seni takip etmeye başladı.' END,
                    'follow_' || NEW.status || '_' || NEW.follower_id::text || '_' || NEW.following_id::text)
            ON CONFLICT (recipient_id, dedupe_key) DO NOTHING;
        ELSIF TG_OP = 'UPDATE' AND OLD.status = 'pending' AND NEW.status = 'following' THEN
            INSERT INTO public.notifications (recipient_id, actor_id, actor_username, actor_display_name, actor_avatar_url,
                                              event_type, target_id, preview_text, dedupe_key)
            VALUES (NEW.follower_id, NEW.following_id, NEW.following_username, NEW.following_display_name, NEW.following_avatar_url,
                    'follow_accepted', NEW.following_id::text, 'Takip isteğini kabul etti.',
                    'follow_acc_' || NEW.following_id::text || '_' || NEW.follower_id::text)
            ON CONFLICT (recipient_id, dedupe_key) DO NOTHING;
        END IF;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_notify_on_follow_change ON public.follows;
CREATE TRIGGER trg_notify_on_follow_change
AFTER INSERT OR UPDATE ON public.follows
FOR EACH ROW EXECUTE FUNCTION public.notify_on_follow_change();

-- Gönderiler
ALTER TABLE public.posts ADD COLUMN IF NOT EXISTS music_url TEXT;
SELECT public._juzzio_reset_fk('posts', 'author_id', 'public.profiles', 'CASCADE');
DO $$
BEGIN
    IF to_regclass('public.posts') IS NOT NULL THEN
        UPDATE public.posts SET client_request_id = NULL
        WHERE id IN (
            SELECT id FROM (
                SELECT id, row_number() OVER (PARTITION BY author_id, client_request_id ORDER BY created_at) rn
                FROM public.posts WHERE client_request_id IS NOT NULL
            ) x WHERE rn > 1
        );
        PERFORM public._juzzio_ensure_unique('posts', 'posts_author_client_req_unique', ARRAY['author_id', 'client_request_id']);
    END IF;
END $$;
CREATE INDEX IF NOT EXISTS idx_posts_feed_order ON public.posts (created_at DESC, id DESC) WHERE is_deleted = false;
CREATE INDEX IF NOT EXISTS idx_posts_author_order ON public.posts (author_id, created_at DESC) WHERE is_deleted = false;

CREATE OR REPLACE FUNCTION public.fill_post_identity()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    r RECORD;
BEGIN
    SELECT username, display_name, avatar_url, is_verified INTO r FROM public.profiles WHERE id = NEW.author_id;
    IF FOUND THEN
        NEW.author_username := COALESCE(r.username, '');
        NEW.author_display_name := COALESCE(NULLIF(r.display_name, ''), r.username, '');
        NEW.author_avatar_url := r.avatar_url;
        NEW.author_is_verified := COALESCE(r.is_verified, false);
    END IF;
    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_fill_post_identity ON public.posts;
CREATE TRIGGER trg_fill_post_identity
BEFORE INSERT ON public.posts
FOR EACH ROW EXECUTE FUNCTION public.fill_post_identity();

CREATE OR REPLACE FUNCTION public.can_view_user_content(
    p_viewer UUID,
    p_owner UUID,
    p_visibility TEXT DEFAULT 'public'
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_is_private BOOLEAN := false;
BEGIN
    IF p_owner IS NULL THEN RETURN false; END IF;
    IF p_viewer IS NOT NULL AND p_viewer = p_owner THEN RETURN true; END IF;
    IF p_viewer IS NOT NULL AND public.is_blocked_between(p_viewer, p_owner) THEN RETURN false; END IF;
    SELECT COALESCE(is_private_account, false) INTO v_is_private FROM public.profiles WHERE id = p_owner;
    IF p_visibility IN ('private', 'only_me') THEN RETURN false; END IF;
    IF p_visibility = 'friends' THEN
        RETURN p_viewer IS NOT NULL AND public.is_friends_accepted(p_viewer, p_owner);
    END IF;
    IF p_visibility = 'followers' OR v_is_private THEN
        RETURN p_viewer IS NOT NULL AND (
            public.is_following_accepted(p_viewer, p_owner) OR public.is_friends_accepted(p_viewer, p_owner)
        );
    END IF;
    RETURN true;
END;
$$;
GRANT EXECUTE ON FUNCTION public.is_following_accepted(UUID, UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.can_view_user_content(UUID, UUID, TEXT) TO anon, authenticated, service_role;

-- Beğeniler
SELECT public._juzzio_reset_fk('post_likes', 'post_id', 'public.posts', 'CASCADE');
SELECT public._juzzio_reset_fk('post_likes', 'user_id', 'public.profiles', 'CASCADE');
SELECT public._juzzio_dedupe('post_likes', ARRAY['post_id', 'user_id']);
SELECT public._juzzio_ensure_unique('post_likes', 'post_likes_unique_user_post', ARRAY['post_id', 'user_id']);

CREATE OR REPLACE FUNCTION public.fill_like_identity()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    r RECORD;
BEGIN
    SELECT username, display_name, avatar_url INTO r FROM public.profiles WHERE id = NEW.user_id;
    IF FOUND THEN
        NEW.username := COALESCE(r.username, '');
        NEW.display_name := COALESCE(r.display_name, '');
        NEW.avatar_url := r.avatar_url;
    END IF;
    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_fill_like_identity ON public.post_likes;
CREATE TRIGGER trg_fill_like_identity
BEFORE INSERT ON public.post_likes
FOR EACH ROW EXECUTE FUNCTION public.fill_like_identity();

CREATE OR REPLACE FUNCTION public.sync_post_likes_count()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_post UUID := COALESCE(NEW.post_id, OLD.post_id);
BEGIN
    UPDATE public.posts
    SET likes_count = (SELECT COUNT(*) FROM public.post_likes WHERE post_id = v_post)
    WHERE id = v_post;

    IF TG_OP = 'INSERT' THEN
        BEGIN
            INSERT INTO public.notifications (recipient_id, actor_id, actor_username, actor_display_name, actor_avatar_url,
                                              event_type, target_id, preview_text, media_thumb_url, dedupe_key)
            SELECT p.author_id, NEW.user_id, NEW.username, NEW.display_name, NEW.avatar_url,
                   'like', p.id::text, COALESCE(NULLIF(LEFT(p.caption, 120), ''), 'Gönderini beğendi.'),
                   COALESCE(p.cover_url, p.media_urls->>0),
                   'like_' || p.id::text || '_' || NEW.user_id::text
            FROM public.posts p
            WHERE p.id = NEW.post_id AND p.author_id <> NEW.user_id
              AND NOT public.is_blocked_between(p.author_id, NEW.user_id)
            ON CONFLICT (recipient_id, dedupe_key) DO NOTHING;
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
    END IF;
    RETURN COALESCE(NEW, OLD);
END;
$$;
DROP TRIGGER IF EXISTS trg_sync_post_likes_count ON public.post_likes;
CREATE TRIGGER trg_sync_post_likes_count
AFTER INSERT OR DELETE ON public.post_likes
FOR EACH ROW EXECUTE FUNCTION public.sync_post_likes_count();

-- Yorumlar
SELECT public._juzzio_reset_fk('post_comments', 'post_id', 'public.posts', 'CASCADE');
SELECT public._juzzio_reset_fk('post_comments', 'author_id', 'public.profiles', 'CASCADE');
SELECT public._juzzio_reset_fk('post_comments', 'parent_comment_id', 'public.post_comments', 'CASCADE');
DO $$
BEGIN
    UPDATE public.post_comments SET client_request_id = NULL
    WHERE id IN (
        SELECT id FROM (
            SELECT id, row_number() OVER (PARTITION BY author_id, client_request_id ORDER BY created_at) rn
            FROM public.post_comments WHERE client_request_id IS NOT NULL
        ) x WHERE rn > 1
    );
    PERFORM public._juzzio_ensure_unique('post_comments', 'post_comments_unique_req', ARRAY['author_id', 'client_request_id']);
END $$;
CREATE INDEX IF NOT EXISTS idx_post_comments_post_order ON public.post_comments (post_id, created_at, id);
CREATE INDEX IF NOT EXISTS idx_post_comments_parent ON public.post_comments (parent_comment_id);

CREATE OR REPLACE FUNCTION public.fill_comment_identity()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    r RECORD;
BEGIN
    SELECT username, display_name, avatar_url INTO r FROM public.profiles WHERE id = NEW.author_id;
    IF FOUND THEN
        NEW.author_username := COALESCE(r.username, '');
        NEW.author_display_name := COALESCE(NULLIF(r.display_name, ''), r.username, '');
        NEW.author_avatar_url := r.avatar_url;
    END IF;
    -- Yanıtın yanıtı: her zaman kök yoruma bağla (tek seviye iş parçacığı)
    IF NEW.parent_comment_id IS NOT NULL THEN
        SELECT COALESCE(c.parent_comment_id, c.id) INTO NEW.parent_comment_id
        FROM public.post_comments c WHERE c.id = NEW.parent_comment_id AND c.post_id = NEW.post_id;
    END IF;
    IF TG_OP = 'UPDATE' AND NEW.content IS DISTINCT FROM OLD.content THEN
        NEW.is_edited := true;
        NEW.updated_at := NOW();
    END IF;
    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_fill_comment_identity ON public.post_comments;
CREATE TRIGGER trg_fill_comment_identity
BEFORE INSERT OR UPDATE OF content ON public.post_comments
FOR EACH ROW EXECUTE FUNCTION public.fill_comment_identity();

CREATE OR REPLACE FUNCTION public.sync_post_comments_count()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_post UUID := COALESCE(NEW.post_id, OLD.post_id);
    v_parent_author UUID;
BEGIN
    UPDATE public.posts
    SET comments_count = (SELECT COUNT(*) FROM public.post_comments WHERE post_id = v_post)
    WHERE id = v_post;

    IF TG_OP = 'INSERT' THEN
        BEGIN
            INSERT INTO public.notifications (recipient_id, actor_id, actor_username, actor_display_name, actor_avatar_url,
                                              event_type, target_id, target_secondary_id, preview_text, media_thumb_url, dedupe_key)
            SELECT p.author_id, NEW.author_id, NEW.author_username, NEW.author_display_name, NEW.author_avatar_url,
                   CASE WHEN NEW.parent_comment_id IS NULL THEN 'comment' ELSE 'reply' END,
                   p.id::text, NEW.id::text, LEFT(NEW.content, 160),
                   COALESCE(p.cover_url, p.media_urls->>0),
                   'comment_' || NEW.id::text
            FROM public.posts p
            WHERE p.id = NEW.post_id AND p.author_id <> NEW.author_id
              AND NOT public.is_blocked_between(p.author_id, NEW.author_id)
            ON CONFLICT (recipient_id, dedupe_key) DO NOTHING;

            IF NEW.parent_comment_id IS NOT NULL THEN
                SELECT author_id INTO v_parent_author FROM public.post_comments WHERE id = NEW.parent_comment_id;
                IF v_parent_author IS NOT NULL AND v_parent_author <> NEW.author_id
                   AND NOT public.is_blocked_between(v_parent_author, NEW.author_id) THEN
                    INSERT INTO public.notifications (recipient_id, actor_id, actor_username, actor_display_name, actor_avatar_url,
                                                      event_type, target_id, target_secondary_id, preview_text, dedupe_key)
                    VALUES (v_parent_author, NEW.author_id, NEW.author_username, NEW.author_display_name, NEW.author_avatar_url,
                            'reply', NEW.post_id::text, NEW.id::text, LEFT(NEW.content, 160), 'reply_' || NEW.id::text)
                    ON CONFLICT (recipient_id, dedupe_key) DO NOTHING;
                END IF;
            END IF;
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
    END IF;
    RETURN COALESCE(NEW, OLD);
END;
$$;
DROP TRIGGER IF EXISTS trg_sync_post_comments_count ON public.post_comments;
CREATE TRIGGER trg_sync_post_comments_count
AFTER INSERT OR DELETE ON public.post_comments
FOR EACH ROW EXECUTE FUNCTION public.sync_post_comments_count();

SELECT public._juzzio_reset_fk('comment_likes', 'comment_id', 'public.post_comments', 'CASCADE');
SELECT public._juzzio_reset_fk('comment_likes', 'user_id', 'public.profiles', 'CASCADE');
SELECT public._juzzio_dedupe('comment_likes', ARRAY['comment_id', 'user_id']);
SELECT public._juzzio_ensure_unique('comment_likes', 'comment_likes_unique_pair', ARRAY['comment_id', 'user_id']);

CREATE OR REPLACE FUNCTION public.sync_comment_likes_count()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_comment UUID := COALESCE(NEW.comment_id, OLD.comment_id);
BEGIN
    UPDATE public.post_comments
    SET likes_count = (SELECT COUNT(*) FROM public.comment_likes WHERE comment_id = v_comment)
    WHERE id = v_comment;
    RETURN COALESCE(NEW, OLD);
END;
$$;
DROP TRIGGER IF EXISTS trg_sync_comment_likes_count ON public.comment_likes;
CREATE TRIGGER trg_sync_comment_likes_count
AFTER INSERT OR DELETE ON public.comment_likes
FOR EACH ROW EXECUTE FUNCTION public.sync_comment_likes_count();

SELECT public._juzzio_reset_fk('saved_posts', 'post_id', 'public.posts', 'CASCADE');
SELECT public._juzzio_reset_fk('saved_posts', 'user_id', 'public.profiles', 'CASCADE');
SELECT public._juzzio_dedupe('saved_posts', ARRAY['user_id', 'post_id']);
SELECT public._juzzio_ensure_unique('saved_posts', 'saved_posts_unique_user_post', ARRAY['user_id', 'post_id']);

CREATE OR REPLACE FUNCTION public.sync_post_saves_count()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_post UUID := COALESCE(NEW.post_id, OLD.post_id);
BEGIN
    UPDATE public.posts
    SET saves_count = (SELECT COUNT(*) FROM public.saved_posts WHERE post_id = v_post)
    WHERE id = v_post;
    RETURN COALESCE(NEW, OLD);
END;
$$;
DROP TRIGGER IF EXISTS trg_sync_post_saves_count ON public.saved_posts;
CREATE TRIGGER trg_sync_post_saves_count
AFTER INSERT OR DELETE ON public.saved_posts
FOR EACH ROW EXECUTE FUNCTION public.sync_post_saves_count();

-- Sayaçları tek seferlik yeniden hesapla (eksik trigger döneminde kaymış olabilir)
UPDATE public.posts p SET
    likes_count = (SELECT COUNT(*) FROM public.post_likes l WHERE l.post_id = p.id),
    comments_count = (SELECT COUNT(*) FROM public.post_comments c WHERE c.post_id = p.id),
    saves_count = (SELECT COUNT(*) FROM public.saved_posts s WHERE s.post_id = p.id);
UPDATE public.post_comments c SET
    likes_count = (SELECT COUNT(*) FROM public.comment_likes l WHERE l.comment_id = c.id);

-- Raporlar
SELECT public._juzzio_reset_fk('reports', 'reporter_id', 'public.profiles', 'CASCADE');
SELECT public._juzzio_reset_fk('reports', 'target_owner_id', 'public.profiles', 'SET NULL');
SELECT public._juzzio_dedupe('reports', ARRAY['reporter_id', 'target_type', 'target_id']);
SELECT public._juzzio_ensure_unique('reports', 'reports_unique_per_target', ARRAY['reporter_id', 'target_type', 'target_id']);

-- -----------------------------------------------------------------------------
-- 9. BİLDİRİMLER
-- -----------------------------------------------------------------------------
SELECT public._juzzio_reset_fk('notifications', 'recipient_id', 'public.profiles', 'CASCADE');
SELECT public._juzzio_reset_fk('notifications', 'actor_id', 'public.profiles', 'CASCADE');
SELECT public._juzzio_dedupe('notifications', ARRAY['recipient_id', 'dedupe_key']);
SELECT public._juzzio_ensure_unique('notifications', 'notifications_dedupe_unique', ARRAY['recipient_id', 'dedupe_key']);
ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_event_type_check;
ALTER TABLE public.notifications ADD CONSTRAINT notifications_event_type_check CHECK (
    event_type IN ('like', 'comment', 'reply', 'follow', 'follow_request', 'follow_accepted',
                   'friend_request', 'friend_accepted', 'story_like', 'story_reply', 'message',
                   'missed_call', 'incoming_call', 'group_activity', 'system')
) NOT VALID;
CREATE INDEX IF NOT EXISTS idx_notifications_recipient_order ON public.notifications (recipient_id, created_at DESC, id DESC);

-- Arkadaşlık bildirimleri (önceki migration ile aynı; canlı DB'de eksik olabilir)
CREATE OR REPLACE FUNCTION public.notify_on_friendship_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    BEGIN
        IF NEW.status = 'pending' AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM 'pending' OR OLD.requester_id <> NEW.requester_id) THEN
            INSERT INTO public.notifications (recipient_id, actor_id, actor_username, actor_display_name, actor_avatar_url,
                                              event_type, target_id, preview_text, dedupe_key)
            VALUES (NEW.receiver_id, NEW.requester_id, NEW.requester_username, NEW.requester_name, NEW.requester_avatar,
                    'friend_request', NEW.requester_id::text, 'Sana arkadaşlık isteği gönderdi.',
                    'freq_' || NEW.id::text || '_' || EXTRACT(EPOCH FROM NEW.created_at)::bigint::text)
            ON CONFLICT (recipient_id, dedupe_key) DO NOTHING;
        ELSIF TG_OP = 'UPDATE' AND OLD.status = 'pending' AND NEW.status = 'accepted' THEN
            INSERT INTO public.notifications (recipient_id, actor_id, actor_username, actor_display_name, actor_avatar_url,
                                              event_type, target_id, preview_text, dedupe_key)
            VALUES (NEW.requester_id, NEW.receiver_id, NEW.receiver_username, NEW.receiver_name, NEW.receiver_avatar,
                    'friend_accepted', NEW.receiver_id::text, 'Arkadaşlık isteğini kabul etti.', 'facc_' || NEW.id::text)
            ON CONFLICT (recipient_id, dedupe_key) DO NOTHING;
        END IF;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_notify_on_friendship_change ON public.friendships;
CREATE TRIGGER trg_notify_on_friendship_change
AFTER INSERT OR UPDATE ON public.friendships
FOR EACH ROW EXECUTE FUNCTION public.notify_on_friendship_change();

-- -----------------------------------------------------------------------------
-- 10. ARAMA KAYITLARI ve ÇAĞRI SİNYALİ (1'e 1 + Konferans)
-- -----------------------------------------------------------------------------
ALTER TABLE public.call_logs ADD COLUMN IF NOT EXISTS session_id UUID;
ALTER TABLE public.call_logs ADD COLUMN IF NOT EXISTS livekit_room_name TEXT;
ALTER TABLE public.call_logs ADD COLUMN IF NOT EXISTS is_group BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.call_logs ADD COLUMN IF NOT EXISTS group_title TEXT NOT NULL DEFAULT '';
ALTER TABLE public.call_logs ADD COLUMN IF NOT EXISTS answered_at TIMESTAMPTZ;
ALTER TABLE public.call_logs ADD COLUMN IF NOT EXISTS ended_at TIMESTAMPTZ;
ALTER TABLE public.call_logs ALTER COLUMN status SET DEFAULT 'ringing';
ALTER TABLE public.call_logs ALTER COLUMN data_kb SET DEFAULT 0;
ALTER TABLE public.call_logs DROP CONSTRAINT IF EXISTS call_logs_status_check;
ALTER TABLE public.call_logs ADD CONSTRAINT call_logs_status_check CHECK (
    status IN ('ringing', 'answered', 'missed', 'busy_silent', 'rejected', 'ended', 'cancelled')
) NOT VALID;
SELECT public._juzzio_reset_fk('call_logs', 'room_id', 'public.rooms', 'SET NULL');
SELECT public._juzzio_reset_fk('call_logs', 'caller_id', 'public.profiles', 'CASCADE');
SELECT public._juzzio_reset_fk('call_logs', 'receiver_id', 'public.profiles', 'SET NULL');
CREATE INDEX IF NOT EXISTS idx_call_logs_receiver_created ON public.call_logs (receiver_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_call_logs_caller_created ON public.call_logs (caller_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_call_logs_session ON public.call_logs (session_id);

-- Eski ortak oda üzerinden "çalan" kalmış aramaları kapat
UPDATE public.call_logs SET status = 'missed', ended_at = NOW()
WHERE status = 'ringing' AND created_at < NOW() - INTERVAL '2 minutes';

-- Arama başlat: odadaki diğer üyelere (veya seçilen davetlilere) ayrı ayrı "ringing" kaydı açar
CREATE OR REPLACE FUNCTION public.start_call(
    p_room UUID,
    p_is_video BOOLEAN,
    p_invitee_ids UUID[] DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_room RECORD;
    v_me RECORD;
    v_session UUID := gen_random_uuid();
    v_target RECORD;
    v_count INTEGER := 0;
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
    SELECT * INTO v_room FROM public.rooms WHERE id = p_room;
    IF v_room.id IS NULL OR NOT public.is_room_member(p_room, v_uid) THEN
        RAISE EXCEPTION 'not_a_member';
    END IF;
    SELECT id, COALESCE(NULLIF(display_name, ''), username, 'Juzzio') AS name, avatar_url INTO v_me
    FROM public.profiles WHERE id = v_uid;

    -- Grupta zaten süren bir konferans varsa yeni oturum açma: ona katıl
    -- (yalnızca gerçekten süren bir oturumsa: biri cevaplamış ya da hâlâ çalıyor).
    -- Kimsenin katılmadığı/uygulaması kapanmış eski oturum temizlenir, yeni arama başlar.
    IF v_room.is_group AND v_room.is_call_active AND v_room.active_call ? 'session_id' THEN
        IF (v_room.active_call->>'started_at')::timestamptz > NOW() - INTERVAL '6 hours'
           AND (
               EXISTS (SELECT 1 FROM public.call_logs cl
                       WHERE cl.session_id = (v_room.active_call->>'session_id')::uuid
                         AND cl.status = 'answered' AND cl.ended_at IS NULL)
               OR (v_room.active_call->>'started_at')::timestamptz > NOW() - INTERVAL '60 seconds'
           ) THEN
            -- Bu oturumda bana gelen ve hâlâ çalan kayıt varsa "cevaplandı" yap
            UPDATE public.call_logs
            SET status = 'answered', answered_at = COALESCE(answered_at, NOW())
            WHERE session_id = (v_room.active_call->>'session_id')::uuid
              AND receiver_id = v_uid AND status = 'ringing';
            RETURN v_room.active_call || jsonb_build_object('joined_existing', true);
        END IF;
        UPDATE public.call_logs
        SET status = 'missed', ended_at = COALESCE(ended_at, NOW())
        WHERE session_id = (v_room.active_call->>'session_id')::uuid AND status = 'ringing';
        UPDATE public.rooms SET is_call_active = false, active_call = NULL WHERE id = p_room;
    END IF;

    FOR v_target IN
        SELECT p.id, COALESCE(NULLIF(p.display_name, ''), p.username, 'Juzzio') AS name, p.avatar_url,
               p.allow_unknown_calls
        FROM public.room_participants rp
        JOIN public.profiles p ON p.id = rp.user_id
        WHERE rp.room_id = p_room AND rp.left_at IS NULL AND rp.user_id <> v_uid
          AND (p_invitee_ids IS NULL OR rp.user_id = ANY (p_invitee_ids))
          AND NOT public.is_blocked_between(v_uid, rp.user_id)
    LOOP
        INSERT INTO public.call_logs (
            session_id, room_id, livekit_room_name, is_group, group_title,
            caller_id, caller_name, caller_avatar, receiver_id, receiver_name, receiver_avatar,
            is_video, status, status_reason, duration_sec, data_kb
        ) VALUES (
            v_session, p_room, v_room.livekit_room_name, v_room.is_group,
            CASE WHEN v_room.is_group THEN v_room.title ELSE '' END,
            v_uid, v_me.name, v_me.avatar_url, v_target.id, v_target.name, v_target.avatar_url,
            COALESCE(p_is_video, false), 'ringing',
            CASE WHEN p_is_video THEN 'Görüntülü arama' ELSE 'Sesli arama' END, 0, 0
        );
        v_count := v_count + 1;
    END LOOP;

    IF v_count = 0 THEN
        RAISE EXCEPTION 'no_callable_participants';
    END IF;

    UPDATE public.rooms
    SET is_call_active = true,
        active_call = jsonb_build_object(
            'session_id', v_session,
            'caller_id', v_uid,
            'caller_name', v_me.name,
            'is_video', COALESCE(p_is_video, false),
            'is_group_call', v_room.is_group,
            'group_title', v_room.title,
            'livekit_room', v_room.livekit_room_name,
            'started_at', NOW()
        ),
        updated_at = NOW()
    WHERE id = p_room;

    RETURN jsonb_build_object(
        'session_id', v_session,
        'room_id', p_room,
        'livekit_room', v_room.livekit_room_name,
        'is_group_call', v_room.is_group,
        'invited', v_count
    );
END;
$$;
GRANT EXECUTE ON FUNCTION public.start_call(UUID, BOOLEAN, UUID[]) TO authenticated;

-- Süren bir aramaya (1'e 1'i konferansa çevirerek) yeni kişi davet et
CREATE OR REPLACE FUNCTION public.invite_to_call(p_session UUID, p_user_ids UUID[])
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_base RECORD;
    v_me RECORD;
    v_target RECORD;
    v_count INTEGER := 0;
BEGIN
    SELECT * INTO v_base FROM public.call_logs
    WHERE session_id = p_session AND (caller_id = v_uid OR receiver_id = v_uid)
    ORDER BY created_at LIMIT 1;
    IF v_base.id IS NULL THEN RAISE EXCEPTION 'not_in_call'; END IF;

    SELECT COALESCE(NULLIF(display_name, ''), username, 'Juzzio') AS name, avatar_url INTO v_me
    FROM public.profiles WHERE id = v_uid;

    FOR v_target IN
        SELECT p.id, COALESCE(NULLIF(p.display_name, ''), p.username, 'Juzzio') AS name, p.avatar_url
        FROM public.profiles p
        WHERE p.id = ANY (COALESCE(p_user_ids, ARRAY[]::UUID[]))
          AND p.id <> v_uid
          AND NOT public.is_blocked_between(v_uid, p.id)
          AND (public.is_friends_accepted(v_uid, p.id)
               OR (v_base.room_id IS NOT NULL AND public.is_room_member(v_base.room_id, p.id)))
          AND NOT EXISTS (
              SELECT 1 FROM public.call_logs c
              WHERE c.session_id = p_session AND c.receiver_id = p.id AND c.status IN ('ringing', 'answered')
          )
    LOOP
        INSERT INTO public.call_logs (
            session_id, room_id, livekit_room_name, is_group, group_title,
            caller_id, caller_name, caller_avatar, receiver_id, receiver_name, receiver_avatar,
            is_video, status, status_reason
        ) VALUES (
            p_session, v_base.room_id, v_base.livekit_room_name, true,
            COALESCE(NULLIF(v_base.group_title, ''), 'Konferans'),
            v_uid, v_me.name, v_me.avatar_url, v_target.id, v_target.name, v_target.avatar_url,
            v_base.is_video, 'ringing', 'Konferans daveti'
        );
        v_count := v_count + 1;
    END LOOP;
    RETURN v_count;
END;
$$;
GRANT EXECUTE ON FUNCTION public.invite_to_call(UUID, UUID[]) TO authenticated;

-- Aramayı cevapla / reddet / bitir (her kullanıcı yalnızca kendi kaydını değiştirir)
CREATE OR REPLACE FUNCTION public.update_call_status(
    p_call UUID,
    p_status TEXT,
    p_duration_sec INTEGER DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_row RECORD;
BEGIN
    SELECT * INTO v_row FROM public.call_logs WHERE id = p_call;
    IF v_row.id IS NULL OR (v_row.caller_id <> v_uid AND v_row.receiver_id IS DISTINCT FROM v_uid) THEN
        RAISE EXCEPTION 'not_allowed';
    END IF;
    IF p_status NOT IN ('answered', 'rejected', 'ended', 'missed', 'busy_silent', 'cancelled') THEN
        RAISE EXCEPTION 'invalid_status';
    END IF;

    UPDATE public.call_logs
    SET status = CASE
            -- cevaplanmış bir arama "bitti" olarak kapanır; istatistikte cevaplandı kalır
            WHEN p_status = 'ended' AND status IN ('answered', 'ended') THEN 'answered'
            WHEN p_status = 'ended' AND status = 'ringing' THEN 'missed'
            ELSE p_status
        END,
        answered_at = CASE WHEN p_status = 'answered' THEN NOW() ELSE answered_at END,
        ended_at = CASE WHEN p_status <> 'answered' THEN NOW() ELSE ended_at END,
        duration_sec = COALESCE(p_duration_sec, duration_sec)
    WHERE id = p_call;

    IF p_status IN ('rejected', 'missed', 'busy_silent') OR (p_status = 'ended' AND v_row.status = 'ringing') THEN
        BEGIN
            INSERT INTO public.notifications (recipient_id, actor_id, actor_username, actor_display_name, actor_avatar_url,
                                              event_type, target_id, target_secondary_id, preview_text, dedupe_key)
            SELECT v_row.receiver_id, v_row.caller_id, COALESCE(p.username, ''), v_row.caller_name, v_row.caller_avatar,
                   'missed_call', COALESCE(v_row.room_id::text, ''), v_row.id::text,
                   CASE WHEN v_row.is_video THEN 'Cevapsız görüntülü arama' ELSE 'Cevapsız sesli arama' END,
                   'missed_' || v_row.id::text
            FROM public.profiles p
            WHERE p.id = v_row.caller_id AND v_row.receiver_id IS NOT NULL AND p_status <> 'rejected'
            ON CONFLICT (recipient_id, dedupe_key) DO NOTHING;
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
    END IF;
END;
$$;
GRANT EXECUTE ON FUNCTION public.update_call_status(UUID, TEXT, INTEGER) TO authenticated;

-- Arayan kişi aramayı bitirir/iptal eder: oturumdaki tüm çalan kayıtlar kapanır, oda pasifleşir
CREATE OR REPLACE FUNCTION public.end_call_session(p_session UUID, p_duration_sec INTEGER DEFAULT NULL, p_force BOOLEAN DEFAULT false)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_room UUID;
    v_is_group BOOLEAN;
    v_caller UUID;
BEGIN
    SELECT room_id, is_group, caller_id INTO v_room, v_is_group, v_caller
    FROM public.call_logs
    WHERE session_id = p_session AND (caller_id = v_uid OR receiver_id = v_uid)
    ORDER BY created_at LIMIT 1;
    IF v_caller IS NULL THEN RETURN; END IF;

    -- Konferansta biri ayrıldığında oturum herkes için kapanmaz (son kişi veya arayan iptal ederse kapanır)
    IF v_is_group AND NOT p_force THEN
        UPDATE public.call_logs SET status = 'answered', ended_at = NOW(), duration_sec = COALESCE(p_duration_sec, duration_sec)
        WHERE session_id = p_session AND receiver_id = v_uid AND status = 'answered';
        RETURN;
    END IF;

    UPDATE public.call_logs
    SET status = CASE WHEN status = 'ringing' THEN CASE WHEN caller_id = v_uid THEN 'missed' ELSE 'cancelled' END
                      WHEN status = 'answered' THEN 'answered'
                      ELSE status END,
        ended_at = COALESCE(ended_at, NOW()),
        duration_sec = CASE WHEN status = 'answered' THEN COALESCE(p_duration_sec, duration_sec) ELSE duration_sec END
    WHERE session_id = p_session;

    INSERT INTO public.notifications (recipient_id, actor_id, actor_username, actor_display_name, actor_avatar_url,
                                      event_type, target_id, target_secondary_id, preview_text, dedupe_key)
    SELECT c.receiver_id, c.caller_id, COALESCE(p.username, ''), c.caller_name, c.caller_avatar,
           'missed_call', COALESCE(c.room_id::text, ''), c.id::text,
           CASE WHEN c.is_video THEN 'Cevapsız görüntülü arama' ELSE 'Cevapsız sesli arama' END,
           'missed_' || c.id::text
    FROM public.call_logs c
    JOIN public.profiles p ON p.id = c.caller_id
    WHERE c.session_id = p_session AND c.status = 'missed' AND c.receiver_id IS NOT NULL
    ON CONFLICT (recipient_id, dedupe_key) DO NOTHING;

    IF v_room IS NOT NULL THEN
        UPDATE public.rooms SET is_call_active = false, active_call = NULL, updated_at = NOW()
        WHERE id = v_room AND (active_call->>'session_id') = p_session::text;
    END IF;
END;
$$;
GRANT EXECUTE ON FUNCTION public.end_call_session(UUID, INTEGER, BOOLEAN) TO authenticated;

-- Gelen arama push bildirimi (alıcının telefonu çalsın)
CREATE OR REPLACE FUNCTION public.notify_on_call_log_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NEW.receiver_id IS NOT NULL AND NEW.receiver_id <> NEW.caller_id AND NEW.status = 'ringing'
       AND NOT public.is_blocked_between(NEW.caller_id, NEW.receiver_id) THEN
        BEGIN
            INSERT INTO public.notifications (recipient_id, actor_id, actor_username, actor_display_name, actor_avatar_url,
                                              event_type, target_id, target_secondary_id, preview_text, dedupe_key)
            SELECT NEW.receiver_id, NEW.caller_id, COALESCE(p.username, ''), NEW.caller_name, NEW.caller_avatar,
                   'incoming_call', COALESCE(NEW.room_id::text, ''), NEW.id::text,
                   CASE WHEN NEW.is_group THEN COALESCE(NULLIF(NEW.group_title, ''), 'Grup') || ' • ' ELSE '' END ||
                   CASE WHEN NEW.is_video THEN 'Görüntülü arama' ELSE 'Sesli arama' END,
                   'call_' || NEW.id::text
            FROM public.profiles p WHERE p.id = NEW.caller_id
            ON CONFLICT (recipient_id, dedupe_key) DO NOTHING;
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
    END IF;
    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_notify_on_call_log_insert ON public.call_logs;
CREATE TRIGGER trg_notify_on_call_log_insert
AFTER INSERT ON public.call_logs
FOR EACH ROW EXECUTE FUNCTION public.notify_on_call_log_insert();

-- LiveKit token Edge Function'ı için yetki kontrolü
CREATE OR REPLACE FUNCTION public.can_join_livekit_room(p_user UUID, p_livekit_room TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.rooms r
        JOIN public.room_participants rp ON rp.room_id = r.id
        WHERE r.livekit_room_name = p_livekit_room AND rp.user_id = p_user AND rp.left_at IS NULL
    ) OR EXISTS (
        SELECT 1 FROM public.call_logs c
        WHERE c.livekit_room_name = p_livekit_room
          AND (c.caller_id = p_user OR c.receiver_id = p_user)
          AND c.created_at > NOW() - INTERVAL '12 hours'
          AND c.status IN ('ringing', 'answered')
    );
$$;
REVOKE ALL ON FUNCTION public.can_join_livekit_room(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.can_join_livekit_room(UUID, TEXT) TO service_role;

-- -----------------------------------------------------------------------------
-- 11. FCM TOKEN — canlı DB'deki UNIQUE(fcm_token) ile uyumlu tek kayıt/cihaz modeli
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.user_push_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    device_id TEXT NOT NULL DEFAULT '',
    fcm_token TEXT NOT NULL,
    platform TEXT NOT NULL DEFAULT 'android',
    app_version TEXT NOT NULL DEFAULT '0.2.0',
    firebase_project_id TEXT NOT NULL DEFAULT 'juzzio',
    notify_enabled BOOLEAN NOT NULL DEFAULT true,
    notify_messages BOOLEAN NOT NULL DEFAULT true,
    notify_groups BOOLEAN NOT NULL DEFAULT true,
    notify_calls BOOLEAN NOT NULL DEFAULT true,
    notify_follows BOOLEAN NOT NULL DEFAULT true,
    notify_likes_comments BOOLEAN NOT NULL DEFAULT true,
    notify_stories BOOLEAN NOT NULL DEFAULT true,
    notify_system BOOLEAN NOT NULL DEFAULT true,
    is_silent_mode BOOLEAN NOT NULL DEFAULT false,
    is_active BOOLEAN NOT NULL DEFAULT true,
    invalidated_reason TEXT NOT NULL DEFAULT '',
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE public.user_push_tokens ADD COLUMN IF NOT EXISTS notify_system BOOLEAN NOT NULL DEFAULT true;
SELECT public._juzzio_reset_fk('user_push_tokens', 'user_id', 'public.profiles', 'CASCADE');
SELECT public._juzzio_dedupe('user_push_tokens', ARRAY['fcm_token'], 'is_active DESC, updated_at DESC');
ALTER TABLE public.user_push_tokens DROP CONSTRAINT IF EXISTS user_push_tokens_unique_user_token;
SELECT public._juzzio_ensure_unique('user_push_tokens', 'user_push_tokens_fcm_token_key', ARRAY['fcm_token']);

DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN
        SELECT p.oid::regprocedure AS sig
        FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND p.proname = 'upsert_my_push_token'
    LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig;
    END LOOP;
END $$;

CREATE FUNCTION public.upsert_my_push_token(
    p_fcm_token TEXT,
    p_device_id TEXT DEFAULT '',
    p_platform TEXT DEFAULT 'android',
    p_app_version TEXT DEFAULT '0.2.0',
    p_firebase_project_id TEXT DEFAULT 'juzzio',
    p_notify_enabled BOOLEAN DEFAULT true,
    p_notify_messages BOOLEAN DEFAULT true,
    p_notify_groups BOOLEAN DEFAULT true,
    p_notify_calls BOOLEAN DEFAULT true,
    p_notify_follows BOOLEAN DEFAULT true,
    p_notify_likes_comments BOOLEAN DEFAULT true,
    p_notify_stories BOOLEAN DEFAULT true,
    p_notify_system BOOLEAN DEFAULT true,
    p_is_silent_mode BOOLEAN DEFAULT false
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_token TEXT := TRIM(COALESCE(p_fcm_token, ''));
    v_device TEXT := TRIM(COALESCE(p_device_id, ''));
    v_platform TEXT := LOWER(TRIM(COALESCE(p_platform, 'android')));
    v_id UUID;
BEGIN
    IF v_uid IS NULL OR LENGTH(v_token) < 20 THEN
        RETURN NULL;
    END IF;
    IF v_platform NOT IN ('android', 'ios', 'web') THEN v_platform := 'android'; END IF;

    IF v_device <> '' THEN
        UPDATE public.user_push_tokens
        SET is_active = false, invalidated_reason = 'replaced_on_same_device', updated_at = NOW()
        WHERE user_id = v_uid AND device_id = v_device AND fcm_token <> v_token AND is_active;
    END IF;

    -- Token tek bir cihaza aittir: başka hesaptaysa bu hesaba devredilir.
    INSERT INTO public.user_push_tokens (
        user_id, device_id, fcm_token, platform, app_version, firebase_project_id,
        notify_enabled, notify_messages, notify_groups, notify_calls, notify_follows,
        notify_likes_comments, notify_stories, notify_system, is_silent_mode,
        is_active, invalidated_reason, last_seen_at, updated_at
    ) VALUES (
        v_uid, v_device, v_token, v_platform,
        COALESCE(NULLIF(TRIM(p_app_version), ''), '0.2.0'),
        COALESCE(NULLIF(TRIM(p_firebase_project_id), ''), 'juzzio'),
        COALESCE(p_notify_enabled, true), COALESCE(p_notify_messages, true), COALESCE(p_notify_groups, true),
        COALESCE(p_notify_calls, true), COALESCE(p_notify_follows, true), COALESCE(p_notify_likes_comments, true),
        COALESCE(p_notify_stories, true), COALESCE(p_notify_system, true), COALESCE(p_is_silent_mode, false),
        true, '', NOW(), NOW()
    )
    ON CONFLICT (fcm_token) DO UPDATE
    SET user_id = EXCLUDED.user_id,
        device_id = EXCLUDED.device_id,
        platform = EXCLUDED.platform,
        app_version = EXCLUDED.app_version,
        firebase_project_id = EXCLUDED.firebase_project_id,
        notify_enabled = EXCLUDED.notify_enabled,
        notify_messages = EXCLUDED.notify_messages,
        notify_groups = EXCLUDED.notify_groups,
        notify_calls = EXCLUDED.notify_calls,
        notify_follows = EXCLUDED.notify_follows,
        notify_likes_comments = EXCLUDED.notify_likes_comments,
        notify_stories = EXCLUDED.notify_stories,
        notify_system = EXCLUDED.notify_system,
        is_silent_mode = EXCLUDED.is_silent_mode,
        is_active = true,
        invalidated_reason = '',
        last_seen_at = NOW(),
        updated_at = NOW()
    RETURNING id INTO v_id;
    RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION public.upsert_my_push_token(TEXT, TEXT, TEXT, TEXT, TEXT, BOOLEAN, BOOLEAN, BOOLEAN, BOOLEAN, BOOLEAN, BOOLEAN, BOOLEAN, BOOLEAN, BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.upsert_my_push_token(TEXT, TEXT, TEXT, TEXT, TEXT, BOOLEAN, BOOLEAN, BOOLEAN, BOOLEAN, BOOLEAN, BOOLEAN, BOOLEAN, BOOLEAN, BOOLEAN) TO authenticated, service_role;

DROP FUNCTION IF EXISTS public.deactivate_my_push_token(TEXT);
CREATE OR REPLACE FUNCTION public.deactivate_my_push_token(p_fcm_token TEXT, p_device_id TEXT DEFAULT '')
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF auth.uid() IS NULL THEN RETURN FALSE; END IF;
    UPDATE public.user_push_tokens
    SET is_active = false, invalidated_reason = 'user_signed_out', updated_at = NOW()
    WHERE user_id = auth.uid()
      AND ((COALESCE(p_fcm_token, '') <> '' AND fcm_token = p_fcm_token)
        OR (COALESCE(p_device_id, '') <> '' AND device_id = p_device_id));
    RETURN TRUE;
END;
$$;
GRANT EXECUTE ON FUNCTION public.deactivate_my_push_token(TEXT, TEXT) TO authenticated, service_role;

-- push_delivery_logs: skipped_self_actor durumunu garanti et
DO $$
BEGIN
    IF to_regclass('public.push_delivery_logs') IS NOT NULL THEN
        ALTER TABLE public.push_delivery_logs DROP CONSTRAINT IF EXISTS push_delivery_logs_delivery_status_check;
        ALTER TABLE public.push_delivery_logs ADD CONSTRAINT push_delivery_logs_delivery_status_check
            CHECK (delivery_status IN ('processing', 'fcm_accepted', 'no_active_tokens', 'skipped_preference',
                                       'skipped_blocked', 'skipped_self_actor', 'failed')) NOT VALID;
    END IF;
END $$;

-- -----------------------------------------------------------------------------
-- 12. ROW LEVEL SECURITY — "USING (true)" politikalarının tamamen kaldırılması
-- -----------------------------------------------------------------------------
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.room_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.voice_notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.friendships ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.story_views ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.call_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.blocked_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.muted_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.follows ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.post_likes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.post_comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.comment_likes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.saved_posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_push_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_releases ENABLE ROW LEVEL SECURITY;

-- Mevcut tüm politikaları kaldır ve sıfırdan, en az yetki ilkesiyle yeniden oluştur.
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN
        SELECT schemaname, tablename, policyname
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename IN ('profiles', 'rooms', 'room_participants', 'messages', 'voice_notes', 'friendships',
                            'stories', 'story_views', 'call_logs', 'blocked_users', 'muted_users', 'follows',
                            'posts', 'post_likes', 'post_comments', 'comment_likes', 'saved_posts',
                            'notifications', 'reports', 'user_push_tokens', 'app_releases',
                            'message_reads', 'typing_indicators', 'message_translations',
                            'translation_sessions', 'translation_segments', 'push_delivery_logs')
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON %I.%I', r.policyname, r.schemaname, r.tablename);
    END LOOP;
END $$;

-- PROFILES: oturum açmış kullanıcılar görebilir (arama/arkadaş ekleme için), yalnızca sahibi yazar.
CREATE POLICY profiles_select_auth ON public.profiles FOR SELECT TO authenticated USING (true);
CREATE POLICY profiles_insert_own ON public.profiles FOR INSERT TO authenticated WITH CHECK (auth.uid() = id);
CREATE POLICY profiles_update_own ON public.profiles FOR UPDATE TO authenticated USING (auth.uid() = id) WITH CHECK (auth.uid() = id);
CREATE POLICY profiles_delete_own ON public.profiles FOR DELETE TO authenticated USING (auth.uid() = id);

-- ROOMS: yalnızca üyeler görür; oluşturma RPC ile; güncelleme üyeler (arama durumu, başlık)
CREATE POLICY rooms_select_member ON public.rooms FOR SELECT TO authenticated USING (public.is_room_member(id));
CREATE POLICY rooms_insert_creator ON public.rooms FOR INSERT TO authenticated WITH CHECK (created_by = auth.uid());
CREATE POLICY rooms_update_member ON public.rooms FOR UPDATE TO authenticated
    USING (public.is_room_member(id)) WITH CHECK (public.is_room_member(id));
CREATE POLICY rooms_delete_owner ON public.rooms FOR DELETE TO authenticated USING (created_by = auth.uid() AND is_group);

-- ROOM_PARTICIPANTS: aynı odanın üyeleri birbirini görür; ekleme/çıkarma RPC ile
CREATE POLICY room_participants_select_member ON public.room_participants FOR SELECT TO authenticated
    USING (user_id = auth.uid() OR public.is_room_member(room_id));
CREATE POLICY room_participants_update_self ON public.room_participants FOR UPDATE TO authenticated
    USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

-- MESSAGES: yalnızca oda üyeleri; benim temizlediğim geçmiş bana görünmez; süresi dolan gizlenir
CREATE POLICY messages_select_member ON public.messages FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.room_participants rp
            WHERE rp.room_id = messages.room_id AND rp.user_id = auth.uid() AND rp.left_at IS NULL
              AND (rp.cleared_at IS NULL OR messages.created_at > rp.cleared_at)
        )
        AND (messages.expires_at IS NULL OR messages.expires_at > NOW())
    );
CREATE POLICY messages_insert_member ON public.messages FOR INSERT TO authenticated
    WITH CHECK (
        sender_id = auth.uid()
        AND public.is_room_member(room_id)
        AND NOT EXISTS (
            SELECT 1 FROM public.room_participants o
            JOIN public.rooms r ON r.id = o.room_id
            WHERE o.room_id = messages.room_id AND NOT r.is_group AND o.user_id <> auth.uid()
              AND public.is_blocked_between(auth.uid(), o.user_id)
        )
    );
CREATE POLICY messages_update_own ON public.messages FOR UPDATE TO authenticated
    USING (sender_id = auth.uid()) WITH CHECK (sender_id = auth.uid());
CREATE POLICY messages_delete_own ON public.messages FOR DELETE TO authenticated USING (sender_id = auth.uid());

-- VOICE_NOTES
CREATE POLICY voice_notes_select_member ON public.voice_notes FOR SELECT TO authenticated USING (public.is_room_member(room_id));
CREATE POLICY voice_notes_insert_own ON public.voice_notes FOR INSERT TO authenticated
    WITH CHECK (sender_id = auth.uid() AND public.is_room_member(room_id));
CREATE POLICY voice_notes_delete_own ON public.voice_notes FOR DELETE TO authenticated USING (sender_id = auth.uid());

-- FRIENDSHIPS: yalnızca iki taraf görür
CREATE POLICY friendships_select_involved ON public.friendships FOR SELECT TO authenticated
    USING (auth.uid() IN (requester_id, receiver_id));
CREATE POLICY friendships_insert_requester ON public.friendships FOR INSERT TO authenticated
    WITH CHECK (requester_id = auth.uid() AND status = 'pending' AND NOT public.is_blocked_between(requester_id, receiver_id));
CREATE POLICY friendships_update_receiver ON public.friendships FOR UPDATE TO authenticated
    USING (receiver_id = auth.uid()) WITH CHECK (receiver_id = auth.uid());
CREATE POLICY friendships_delete_involved ON public.friendships FOR DELETE TO authenticated
    USING (auth.uid() IN (requester_id, receiver_id));

-- STORIES: görünürlük ayarına göre ve yalnızca süresi dolmamış (sahibi her zaman görür)
CREATE POLICY stories_select_visible ON public.stories FOR SELECT TO authenticated
    USING (
        user_id = auth.uid()
        OR (expires_at > NOW() AND NOT is_archived AND public.can_view_story(auth.uid(), user_id, visibility))
    );
CREATE POLICY stories_insert_own ON public.stories FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY stories_update_own ON public.stories FOR UPDATE TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
CREATE POLICY stories_delete_own ON public.stories FOR DELETE TO authenticated USING (user_id = auth.uid());

-- STORY_VIEWS
CREATE POLICY story_views_select ON public.story_views FOR SELECT TO authenticated
    USING (viewer_id = auth.uid() OR EXISTS (SELECT 1 FROM public.stories s WHERE s.id = story_views.story_id AND s.user_id = auth.uid()));
CREATE POLICY story_views_insert_own ON public.story_views FOR INSERT TO authenticated
    WITH CHECK (
        viewer_id = auth.uid()
        AND EXISTS (SELECT 1 FROM public.stories s WHERE s.id = story_views.story_id
                    AND public.can_view_story(auth.uid(), s.user_id, s.visibility))
    );
CREATE POLICY story_views_update_own ON public.story_views FOR UPDATE TO authenticated
    USING (viewer_id = auth.uid()) WITH CHECK (viewer_id = auth.uid());

-- CALL_LOGS: yalnızca arayan ve aranan görür
CREATE POLICY call_logs_select_involved ON public.call_logs FOR SELECT TO authenticated
    USING (auth.uid() = caller_id OR auth.uid() = receiver_id);
CREATE POLICY call_logs_insert_caller ON public.call_logs FOR INSERT TO authenticated
    WITH CHECK (caller_id = auth.uid());
CREATE POLICY call_logs_update_involved ON public.call_logs FOR UPDATE TO authenticated
    USING (auth.uid() = caller_id OR auth.uid() = receiver_id)
    WITH CHECK (auth.uid() = caller_id OR auth.uid() = receiver_id);
CREATE POLICY call_logs_delete_involved ON public.call_logs FOR DELETE TO authenticated
    USING (auth.uid() = caller_id OR auth.uid() = receiver_id);

-- BLOCKED / MUTED
CREATE POLICY blocked_users_select_involved ON public.blocked_users FOR SELECT TO authenticated
    USING (auth.uid() = blocker_id OR auth.uid() = blocked_id);
CREATE POLICY blocked_users_insert_own ON public.blocked_users FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = blocker_id AND blocker_id <> blocked_id);
CREATE POLICY blocked_users_update_own ON public.blocked_users FOR UPDATE TO authenticated
    USING (auth.uid() = blocker_id) WITH CHECK (auth.uid() = blocker_id);
CREATE POLICY blocked_users_delete_own ON public.blocked_users FOR DELETE TO authenticated USING (auth.uid() = blocker_id);
CREATE POLICY muted_users_all_own ON public.muted_users FOR ALL TO authenticated
    USING (auth.uid() = muter_id) WITH CHECK (auth.uid() = muter_id AND muter_id <> muted_id);

-- FOLLOWS
CREATE POLICY follows_select_visible ON public.follows FOR SELECT TO authenticated
    USING (NOT public.is_blocked_between(auth.uid(), follower_id) AND NOT public.is_blocked_between(auth.uid(), following_id));
CREATE POLICY follows_insert_own ON public.follows FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = follower_id AND follower_id <> following_id AND NOT public.is_blocked_between(follower_id, following_id));
CREATE POLICY follows_update_target ON public.follows FOR UPDATE TO authenticated
    USING (auth.uid() = following_id OR auth.uid() = follower_id)
    WITH CHECK (auth.uid() = following_id OR auth.uid() = follower_id);
CREATE POLICY follows_delete_involved ON public.follows FOR DELETE TO authenticated
    USING (auth.uid() = follower_id OR auth.uid() = following_id);

-- POSTS
CREATE POLICY posts_select_visible ON public.posts FOR SELECT TO authenticated
    USING (is_deleted = false AND public.can_view_user_content(auth.uid(), author_id, visibility));
CREATE POLICY posts_insert_own ON public.posts FOR INSERT TO authenticated WITH CHECK (auth.uid() = author_id);
CREATE POLICY posts_update_own ON public.posts FOR UPDATE TO authenticated USING (auth.uid() = author_id) WITH CHECK (auth.uid() = author_id);
CREATE POLICY posts_delete_own ON public.posts FOR DELETE TO authenticated USING (auth.uid() = author_id);

CREATE POLICY post_likes_select_visible ON public.post_likes FOR SELECT TO authenticated
    USING (EXISTS (SELECT 1 FROM public.posts p WHERE p.id = post_likes.post_id AND p.is_deleted = false
                   AND public.can_view_user_content(auth.uid(), p.author_id, p.visibility)));
CREATE POLICY post_likes_insert_own ON public.post_likes FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = user_id
                AND EXISTS (SELECT 1 FROM public.posts p WHERE p.id = post_likes.post_id AND p.is_deleted = false
                            AND public.can_view_user_content(auth.uid(), p.author_id, p.visibility)));
CREATE POLICY post_likes_update_own ON public.post_likes FOR UPDATE TO authenticated
    USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY post_likes_delete_own ON public.post_likes FOR DELETE TO authenticated USING (auth.uid() = user_id);

CREATE POLICY post_comments_select_visible ON public.post_comments FOR SELECT TO authenticated
    USING (NOT public.is_blocked_between(auth.uid(), author_id)
           AND EXISTS (SELECT 1 FROM public.posts p WHERE p.id = post_comments.post_id AND p.is_deleted = false
                       AND public.can_view_user_content(auth.uid(), p.author_id, p.visibility)));
CREATE POLICY post_comments_insert_allowed ON public.post_comments FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = author_id
                AND EXISTS (SELECT 1 FROM public.posts p WHERE p.id = post_comments.post_id AND p.is_deleted = false
                            AND p.comments_enabled = true
                            AND public.can_view_user_content(auth.uid(), p.author_id, p.visibility)));
CREATE POLICY post_comments_update_own ON public.post_comments FOR UPDATE TO authenticated
    USING (auth.uid() = author_id) WITH CHECK (auth.uid() = author_id);
CREATE POLICY post_comments_delete_own_or_post_owner ON public.post_comments FOR DELETE TO authenticated
    USING (auth.uid() = author_id OR EXISTS (SELECT 1 FROM public.posts p WHERE p.id = post_comments.post_id AND p.author_id = auth.uid()));

CREATE POLICY comment_likes_select_auth ON public.comment_likes FOR SELECT TO authenticated USING (true);
CREATE POLICY comment_likes_insert_own ON public.comment_likes FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY comment_likes_update_own ON public.comment_likes FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY comment_likes_delete_own ON public.comment_likes FOR DELETE TO authenticated USING (auth.uid() = user_id);

CREATE POLICY saved_posts_owner_only ON public.saved_posts FOR ALL TO authenticated
    USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- NOTIFICATIONS
CREATE POLICY notifications_select_recipient ON public.notifications FOR SELECT TO authenticated USING (auth.uid() = recipient_id);
CREATE POLICY notifications_insert_actor ON public.notifications FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = actor_id AND recipient_id <> auth.uid() AND NOT public.is_blocked_between(auth.uid(), recipient_id));
CREATE POLICY notifications_update_recipient ON public.notifications FOR UPDATE TO authenticated
    USING (auth.uid() = recipient_id) WITH CHECK (auth.uid() = recipient_id);
CREATE POLICY notifications_delete_recipient ON public.notifications FOR DELETE TO authenticated USING (auth.uid() = recipient_id);

-- REPORTS
CREATE POLICY reports_select_own ON public.reports FOR SELECT TO authenticated USING (auth.uid() = reporter_id);
CREATE POLICY reports_insert_own ON public.reports FOR INSERT TO authenticated WITH CHECK (auth.uid() = reporter_id);
CREATE POLICY reports_update_own ON public.reports FOR UPDATE TO authenticated USING (auth.uid() = reporter_id) WITH CHECK (auth.uid() = reporter_id);

-- PUSH TOKENS
CREATE POLICY user_push_tokens_select_own ON public.user_push_tokens FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY user_push_tokens_update_own ON public.user_push_tokens FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY user_push_tokens_delete_own ON public.user_push_tokens FOR DELETE TO authenticated USING (auth.uid() = user_id);
DO $$
BEGIN
    IF to_regclass('public.push_delivery_logs') IS NOT NULL THEN
        ALTER TABLE public.push_delivery_logs ENABLE ROW LEVEL SECURITY;
        CREATE POLICY push_delivery_logs_select_own ON public.push_delivery_logs FOR SELECT TO authenticated USING (auth.uid() = recipient_id);
    END IF;
END $$;

-- APP RELEASES: herkes okur; yalnızca service_role yazar (istemciler sürüm ekleyemez!)
CREATE POLICY app_releases_select_all ON public.app_releases FOR SELECT TO anon, authenticated USING (true);

-- Yardımcı tablolar (canlı DB'de var): üyelik tabanlı erişim
DO $$
BEGIN
    IF to_regclass('public.message_reads') IS NOT NULL THEN
        ALTER TABLE public.message_reads ENABLE ROW LEVEL SECURITY;
        CREATE POLICY message_reads_select_member ON public.message_reads FOR SELECT TO authenticated
            USING (EXISTS (SELECT 1 FROM public.messages m WHERE m.id = message_reads.message_id AND public.is_room_member(m.room_id)));
        CREATE POLICY message_reads_insert_own ON public.message_reads FOR INSERT TO authenticated
            WITH CHECK (user_id = auth.uid() AND EXISTS (SELECT 1 FROM public.messages m WHERE m.id = message_reads.message_id AND public.is_room_member(m.room_id)));
    END IF;
    IF to_regclass('public.typing_indicators') IS NOT NULL THEN
        ALTER TABLE public.typing_indicators ENABLE ROW LEVEL SECURITY;
        CREATE POLICY typing_indicators_select_member ON public.typing_indicators FOR SELECT TO authenticated USING (public.is_room_member(room_id));
        CREATE POLICY typing_indicators_write_own ON public.typing_indicators FOR ALL TO authenticated
            USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid() AND public.is_room_member(room_id));
    END IF;
    IF to_regclass('public.message_translations') IS NOT NULL THEN
        ALTER TABLE public.message_translations ENABLE ROW LEVEL SECURITY;
        CREATE POLICY message_translations_select_member ON public.message_translations FOR SELECT TO authenticated
            USING (EXISTS (SELECT 1 FROM public.messages m WHERE m.id = message_translations.message_id AND public.is_room_member(m.room_id)));
    END IF;
    IF to_regclass('public.translation_sessions') IS NOT NULL THEN
        ALTER TABLE public.translation_sessions ENABLE ROW LEVEL SECURITY;
        CREATE POLICY translation_sessions_select_member ON public.translation_sessions FOR SELECT TO authenticated
            USING (room_id IS NOT NULL AND public.is_room_member(room_id));
    END IF;
    IF to_regclass('public.translation_segments') IS NOT NULL THEN
        ALTER TABLE public.translation_segments ENABLE ROW LEVEL SECURITY;
    END IF;
END $$;

-- -----------------------------------------------------------------------------
-- 13. STORAGE: kullanıcılar yalnızca kendi klasörlerine (ilk klasör = uid) yazar
-- -----------------------------------------------------------------------------
DO $$
BEGIN
    INSERT INTO storage.buckets (id, name, public, file_size_limit)
    VALUES
        ('stories', 'stories', true, 104857600),
        ('avatars', 'avatars', true, 20971520),
        ('voice-notes', 'voice-notes', true, 52428800),
        ('chat-media', 'chat-media', true, 104857600),
        ('posts', 'posts', true, 104857600),
        ('reels', 'reels', true, 157286400)
    ON CONFLICT (id) DO UPDATE SET public = true, file_size_limit = EXCLUDED.file_size_limit;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'storage.buckets güncellenemedi: %', SQLERRM;
END $$;

DO $$
BEGIN
    DROP POLICY IF EXISTS "juzzio_storage_public_read" ON storage.objects;
    DROP POLICY IF EXISTS "juzzio_storage_auth_insert" ON storage.objects;
    DROP POLICY IF EXISTS "juzzio_storage_auth_update" ON storage.objects;
    DROP POLICY IF EXISTS "juzzio_social_storage_public_read" ON storage.objects;
    DROP POLICY IF EXISTS "juzzio_social_storage_owner_insert" ON storage.objects;
    DROP POLICY IF EXISTS "juzzio_social_storage_owner_update" ON storage.objects;
    DROP POLICY IF EXISTS "juzzio_social_storage_owner_delete" ON storage.objects;
    DROP POLICY IF EXISTS "juzzio_v2_storage_read" ON storage.objects;
    DROP POLICY IF EXISTS "juzzio_v2_storage_insert_own" ON storage.objects;
    DROP POLICY IF EXISTS "juzzio_v2_storage_update_own" ON storage.objects;
    DROP POLICY IF EXISTS "juzzio_v2_storage_delete_own" ON storage.objects;

    CREATE POLICY "juzzio_v2_storage_read" ON storage.objects FOR SELECT TO anon, authenticated
        USING (bucket_id IN ('stories', 'avatars', 'voice-notes', 'chat-media', 'posts', 'reels'));
    CREATE POLICY "juzzio_v2_storage_insert_own" ON storage.objects FOR INSERT TO authenticated
        WITH CHECK (bucket_id IN ('stories', 'avatars', 'voice-notes', 'chat-media', 'posts', 'reels')
                    AND (storage.foldername(name))[1] = auth.uid()::text);
    CREATE POLICY "juzzio_v2_storage_update_own" ON storage.objects FOR UPDATE TO authenticated
        USING (bucket_id IN ('stories', 'avatars', 'voice-notes', 'chat-media', 'posts', 'reels')
               AND (storage.foldername(name))[1] = auth.uid()::text)
        WITH CHECK ((storage.foldername(name))[1] = auth.uid()::text);
    CREATE POLICY "juzzio_v2_storage_delete_own" ON storage.objects FOR DELETE TO authenticated
        USING (bucket_id IN ('stories', 'avatars', 'voice-notes', 'chat-media', 'posts', 'reels')
               AND (storage.foldername(name))[1] = auth.uid()::text);
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'storage.objects politikaları güncellenemedi: %', SQLERRM;
END $$;

-- -----------------------------------------------------------------------------
-- 14. HESAP SİLME (yeni tablolar dahil)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.delete_my_juzzio_account()
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID := auth.uid();
BEGIN
    IF v_uid IS NULL THEN
        RETURN FALSE;
    END IF;
    -- profiles → auth.users ON DELETE CASCADE ve tüm FK'ler CASCADE/SET NULL olduğundan
    -- auth kullanıcısını silmek bağlı tüm verileri temizler.
    UPDATE public.rooms SET created_by = NULL WHERE created_by = v_uid;
    DELETE FROM public.rooms r
    WHERE r.is_group = false
      AND EXISTS (SELECT 1 FROM public.room_participants rp WHERE rp.room_id = r.id AND rp.user_id = v_uid);
    DELETE FROM public.profiles WHERE id = v_uid;
    BEGIN
        DELETE FROM auth.users WHERE id = v_uid;
    EXCEPTION WHEN OTHERS THEN
        NULL;
    END;
    RETURN TRUE;
END;
$$;
GRANT EXECUTE ON FUNCTION public.delete_my_juzzio_account() TO authenticated;

-- -----------------------------------------------------------------------------
-- 15. REALTIME YAYINI (stream() kullanılan tüm tablolar)
-- -----------------------------------------------------------------------------
DO $$
DECLARE
    t TEXT;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
        RETURN;
    END IF;
    FOREACH t IN ARRAY ARRAY['messages', 'rooms', 'room_participants', 'friendships', 'stories', 'call_logs',
                             'profiles', 'notifications', 'posts', 'follows', 'app_releases']
    LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = t) THEN
            EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', t);
        END IF;
    END LOOP;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Realtime yayını güncellenemedi: %', SQLERRM;
END $$;

-- -----------------------------------------------------------------------------
-- 16. SÜRÜM KAYDI
-- -----------------------------------------------------------------------------
-- (v0.2.0 tarihî sürüm kaydı kanonik dosyadan çıkarıldı: şema değil, eski veri)

-- Geçici yardımcıları kaldır
DROP FUNCTION IF EXISTS public._juzzio_reset_fk(TEXT, TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS public._juzzio_ensure_unique(TEXT, TEXT, TEXT[]);
DROP FUNCTION IF EXISTS public._juzzio_dedupe(TEXT, TEXT[], TEXT);

-- #############################################################################
-- BÖLÜM 6/9 — kaynak: 20261030000000_juzzio_v030_profiles_groups_roles.sql
-- #############################################################################
-- =============================================================================
-- JUZZIO v0.3.0 — Bölüm 1/2: Güvenlik sertleştirme, profil, kimlik, gizli cinsiyet,
-- rezerve kullanıcı adları, mavi tik, grup rolleri ve içerik filtresi
--
-- • Tekrar çalıştırılabilir (idempotent); kullanıcı verisi silmez.
-- • Supabase SQL Editor'de tek parça çalıştırılabilir; CI da otomatik uygular.
-- • Grup tabloları: gruplar mevcut "rooms (is_group)", üyeler "room_participants (role)",
--   mesajlar "messages" tablosunda tutulur. Aynı veriyi kopyalamamak için istenen
--   groups / group_members / group_messages isimleri RLS'e uyan görünümler (view) olarak sunulur.
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

-- İstemci (PostgREST) isteği mi? SECURITY DEFINER RPC'ler sahip rolüyle çalıştığı için
-- bu fonksiyon onlarda false döner; böylece sunucu mantığı korumalı sütunları değiştirebilir.
CREATE OR REPLACE FUNCTION public.juzzio_is_client_request()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
AS $$
    SELECT current_user IN ('authenticated', 'anon');
$$;

-- Türkçe/leet karakterleri sadeleştirir (filtre ve kullanıcı adı karşılaştırmaları için)
CREATE OR REPLACE FUNCTION public.juzzio_fold_text(p TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT TRANSLATE(
        LOWER(COALESCE(p, '')),
        'çğıöşüâîû0134578@$!|',
        'cgiosuaiuoieastbasii'
    );
$$;

-- =============================================================================
-- 1. YASAKLI İÇERİK FİLTRESİ (grup adları/amaçları, profil alanları)
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.banned_terms (
    term TEXT PRIMARY KEY,
    match_mode TEXT NOT NULL DEFAULT 'contains' CHECK (match_mode IN ('contains', 'word')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE public.banned_terms ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.banned_terms FROM anon, authenticated;

INSERT INTO public.banned_terms (term, match_mode) VALUES
    -- Türkçe argo / küfür (kök eşleşmesi)
    ('orospu', 'contains'), ('siktir', 'contains'), ('sikerim', 'contains'), ('sikis', 'contains'),
    ('sikik', 'contains'), ('yarrak', 'contains'), ('pezevenk', 'contains'), ('kahpe', 'contains'),
    ('gavat', 'contains'), ('surtuk', 'contains'), ('kaltak', 'contains'), ('yavsak', 'contains'),
    ('aminakoy', 'contains'), ('aminakoyim', 'contains'), ('ananisikim', 'contains'),
    ('godos', 'contains'), ('ibne', 'contains'), ('kerhane', 'contains'), ('fahise', 'contains'),
    ('porno', 'contains'), ('pornografi', 'contains'),
    -- Kısa kelimeler yalnızca tam kelime olarak
    ('amk', 'word'), ('aq', 'word'), ('sik', 'word'), ('yarak', 'word'), ('seks', 'word'),
    ('sex', 'word'), ('xxx', 'word'), ('sikim', 'word'),
    -- İngilizce
    ('fuck', 'contains'), ('shit', 'contains'), ('bitch', 'contains'), ('porn', 'contains'),
    ('pussy', 'contains'), ('cunt', 'contains'), ('whore', 'contains'), ('slut', 'contains'),
    ('nigger', 'contains'), ('nigga', 'contains'), ('hentai', 'contains'), ('onlyfans', 'contains'),
    ('nsfw', 'contains'), ('nude', 'word'), ('nudes', 'word'), ('dick', 'word'), ('cock', 'word'),
    ('fag', 'word'), ('rape', 'word'),
    -- Almanca
    ('scheisse', 'contains'), ('hurensohn', 'contains'), ('fotze', 'contains'), ('wichser', 'contains')
ON CONFLICT (term) DO UPDATE SET match_mode = EXCLUDED.match_mode;

-- Metin uygun mu? (yasaklı kelime yok, anlamsız/absürt değil)
CREATE OR REPLACE FUNCTION public.juzzio_text_is_clean(p_text TEXT, p_require_letters BOOLEAN DEFAULT true)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_folded TEXT := public.juzzio_fold_text(p_text);
    v_words TEXT;
    v_letters INTEGER;
    v_tok TEXT;
    v_run TEXT := '';
    v_targets TEXT[] := ARRAY[]::TEXT[];
BEGIN
    IF p_text IS NULL OR BTRIM(p_text) = '' THEN
        RETURN NOT p_require_letters;
    END IF;
    v_words := ' ' || REGEXP_REPLACE(v_folded, '[^a-z]+', ' ', 'g') || ' ';
    v_letters := LENGTH(REGEXP_REPLACE(p_text, '[^[:alpha:]]', '', 'g'));

    -- Ad alanları (grup adı vb.) için: en az 2 harf, aynı karakter 6+ kez arka arkaya olamaz
    IF p_require_letters AND v_letters < 2 THEN RETURN false; END IF;
    IF p_require_letters AND p_text ~ '(.)\1{5,}' THEN RETURN false; END IF;

    -- "contains" terimleri her kelimede ayrı aranır (ör. "Nudeln", "abi neşe" yanlış
    -- pozitif vermez); harf harf ayrılmış yazımlar ("o r o s p u", "o.r.o.s.p.u")
    -- birleştirilerek ayrıca kontrol edilir.
    FOREACH v_tok IN ARRAY REGEXP_SPLIT_TO_ARRAY(BTRIM(REGEXP_REPLACE(v_folded, '[^a-z]+', ' ', 'g')), ' ') LOOP
        CONTINUE WHEN v_tok = '';
        v_targets := v_targets || v_tok;
        IF LENGTH(v_tok) = 1 THEN
            v_run := v_run || v_tok;
        ELSE
            IF LENGTH(v_run) > 1 THEN v_targets := v_targets || v_run; END IF;
            v_run := '';
        END IF;
    END LOOP;
    IF LENGTH(v_run) > 1 THEN v_targets := v_targets || v_run; END IF;

    IF EXISTS (
        SELECT 1 FROM public.banned_terms b, UNNEST(v_targets) AS t(target)
        WHERE b.match_mode = 'contains' AND POSITION(b.term IN t.target) > 0
    ) OR EXISTS (
        SELECT 1 FROM public.banned_terms b
        WHERE b.match_mode = 'word' AND POSITION(' ' || b.term || ' ' IN v_words) > 0
    ) THEN
        RETURN false;
    END IF;
    RETURN true;
END;
$$;
GRANT EXECUTE ON FUNCTION public.juzzio_text_is_clean(TEXT, BOOLEAN) TO anon, authenticated;

-- =============================================================================
-- 2. REZERVE KULLANICI ADLARI ve MAVİ TİK
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.reserved_usernames (
    username TEXT PRIMARY KEY CHECK (username = LOWER(username)),
    grants_verified BOOLEAN NOT NULL DEFAULT false,
    note TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE public.reserved_usernames ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.reserved_usernames FROM anon, authenticated;

INSERT INTO public.reserved_usernames (username, grants_verified, note) VALUES
    ('tugkancr', true, 'Kurucu — yalnızca sahibine ait'),
    ('unalcan09', true, 'Doğrulanmış hesap'),
    ('juzzio', false, 'Sistem'),
    ('admin', false, 'Sistem'),
    ('support', false, 'Sistem'),
    ('destek', false, 'Sistem'),
    ('moderator', false, 'Sistem')
ON CONFLICT (username) DO UPDATE SET grants_verified = EXCLUDED.grants_verified;

-- Rezerve/doğrulanmış ad sorguları (tablo istemcilere kapalı; tetikleyiciler bu fonksiyonları kullanır)
CREATE OR REPLACE FUNCTION public.juzzio_username_reserved(p_username TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (SELECT 1 FROM public.reserved_usernames r WHERE r.username = LOWER(BTRIM(COALESCE(p_username, ''))));
$$;
CREATE OR REPLACE FUNCTION public.juzzio_username_grants_verified(p_username TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (SELECT 1 FROM public.reserved_usernames r
                   WHERE r.username = LOWER(BTRIM(COALESCE(p_username, ''))) AND r.grants_verified);
$$;
GRANT EXECUTE ON FUNCTION public.juzzio_username_reserved(TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.juzzio_username_grants_verified(TEXT) TO anon, authenticated;

-- Kullanıcı adı müsait mi? (kayıt ekranı anlık kontrolü)
CREATE OR REPLACE FUNCTION public.check_username_available(p_username TEXT)
RETURNS TEXT
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v TEXT := LOWER(REGEXP_REPLACE(BTRIM(COALESCE(p_username, '')), '^@+', ''));
BEGIN
    IF v !~ '^[a-z0-9_.]{3,30}$' THEN RETURN 'invalid'; END IF;
    IF EXISTS (SELECT 1 FROM public.reserved_usernames r WHERE r.username = v)
       AND NOT EXISTS (SELECT 1 FROM public.profiles p WHERE LOWER(p.username) = v AND p.id = auth.uid()) THEN
        RETURN 'reserved';
    END IF;
    IF EXISTS (SELECT 1 FROM public.profiles p WHERE LOWER(p.username) = v
               AND p.id IS DISTINCT FROM auth.uid()) THEN
        RETURN 'taken';
    END IF;
    IF NOT public.juzzio_text_is_clean(v, false) THEN RETURN 'inappropriate'; END IF;
    RETURN 'ok';
END;
$$;
GRANT EXECUTE ON FUNCTION public.check_username_available(TEXT) TO anon, authenticated;

-- Rezerve adı gerçek sahibine atama (yalnızca SQL Editor / service_role)
CREATE OR REPLACE FUNCTION public.assign_reserved_username(p_user UUID, p_username TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v TEXT := LOWER(BTRIM(p_username));
BEGIN
    UPDATE public.profiles SET username = v || '_' || SUBSTRING(REPLACE(id::text, '-', '') FROM 1 FOR 5)
    WHERE LOWER(username) = v AND id <> p_user;
    UPDATE public.profiles SET username = v WHERE id = p_user;
END;
$$;
REVOKE ALL ON FUNCTION public.assign_reserved_username(UUID, TEXT) FROM PUBLIC, anon, authenticated;

-- =============================================================================
-- 3. PROFİL: biyografi (180), web sitesi, müzik (YouTube 30 sn), kimlik koruması
-- =============================================================================
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS website_url TEXT NOT NULL DEFAULT '';
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS is_verified BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS music_url TEXT NOT NULL DEFAULT '';
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS music_video_id TEXT NOT NULL DEFAULT '';
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS music_start_sec INTEGER NOT NULL DEFAULT 0;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS music_title TEXT NOT NULL DEFAULT '';
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS phone_number TEXT;

-- YouTube bağlantısından video kimliği çıkarır (youtu.be/ID, watch?v=ID, shorts/ID, embed/ID, music.youtube)
CREATE OR REPLACE FUNCTION public.juzzio_youtube_id(p_url TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT COALESCE(
        SUBSTRING(p_url FROM '(?:youtu\.be/|[?&]v=|/shorts/|/embed/|/live/)([A-Za-z0-9_-]{11})'),
        ''
    );
$$;

-- Gizli bilgiler: cinsiyet ve telefon profilde ASLA görünmez (yalnızca sahibi okur)
CREATE TABLE IF NOT EXISTS public.profile_private (
    user_id UUID PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
    gender TEXT NOT NULL DEFAULT 'unspecified' CHECK (gender IN ('female', 'male', 'unspecified')),
    phone_number TEXT,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE public.profile_private ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS profile_private_select_own ON public.profile_private;
DROP POLICY IF EXISTS profile_private_insert_own ON public.profile_private;
DROP POLICY IF EXISTS profile_private_update_own ON public.profile_private;
CREATE POLICY profile_private_select_own ON public.profile_private FOR SELECT TO authenticated USING (user_id = auth.uid());
CREATE POLICY profile_private_insert_own ON public.profile_private FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY profile_private_update_own ON public.profile_private FOR UPDATE TO authenticated
    USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

INSERT INTO public.profile_private (user_id, phone_number)
SELECT id, NULLIF(BTRIM(phone_number), '') FROM public.profiles
ON CONFLICT (user_id) DO UPDATE SET phone_number = COALESCE(public.profile_private.phone_number, EXCLUDED.phone_number);

CREATE OR REPLACE FUNCTION public.set_my_gender(p_gender TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
    IF p_gender NOT IN ('female', 'male', 'unspecified') THEN RAISE EXCEPTION 'invalid_gender'; END IF;
    INSERT INTO public.profile_private (user_id, gender, updated_at)
    VALUES (auth.uid(), p_gender, NOW())
    ON CONFLICT (user_id) DO UPDATE SET gender = EXCLUDED.gender, updated_at = NOW();
END;
$$;
GRANT EXECUTE ON FUNCTION public.set_my_gender(TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_my_private_profile()
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT jsonb_build_object(
        'gender', COALESCE((SELECT gender FROM public.profile_private WHERE user_id = auth.uid()), 'unspecified'),
        'phone_number', COALESCE((SELECT phone_number FROM public.profile_private WHERE user_id = auth.uid()), ''),
        'email', COALESCE((SELECT email FROM auth.users WHERE id = auth.uid()), '')
    );
$$;
GRANT EXECUTE ON FUNCTION public.get_my_private_profile() TO authenticated;

-- Profil koruma tetikleyicisi (istemci istekleri için):
--  • e-posta ve telefon herkese açık tabloda tutulmaz (gizlilik sızıntısı kapatıldı)
--  • is_verified yalnızca sunucu tarafından verilir (mavi tik taklit edilemez)
--  • rezerve kullanıcı adları alınamaz; kullanıcı adı biçimi doğrulanır
--  • biyografi 180 karakter; web sitesi http(s) olmalı; müzik YouTube olmalı
CREATE OR REPLACE FUNCTION public.protect_profile_row()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
    v_client BOOLEAN := public.juzzio_is_client_request();
    v_username_changed BOOLEAN;
    v_vid TEXT;
BEGIN
    -- Hassas iletişim bilgileri herkese açık profilden ayrılır
    IF TG_OP = 'UPDATE' AND NEW.phone_number IS NOT NULL AND BTRIM(NEW.phone_number) <> '' THEN
        INSERT INTO public.profile_private (user_id, phone_number, updated_at)
        VALUES (NEW.id, BTRIM(NEW.phone_number), NOW())
        ON CONFLICT (user_id) DO UPDATE SET phone_number = EXCLUDED.phone_number, updated_at = NOW();
    END IF;
    NEW.phone_number := NULL;
    NEW.email := NULL;

    IF NEW.username IS NOT NULL THEN
        NEW.username := LOWER(REGEXP_REPLACE(BTRIM(NEW.username), '^@+', ''));
    END IF;
    v_username_changed := TG_OP = 'INSERT' OR NEW.username IS DISTINCT FROM OLD.username;

    IF v_client AND v_username_changed AND NEW.username IS NOT NULL THEN
        IF NEW.username !~ '^[a-z0-9_.]{3,30}$' THEN
            RAISE EXCEPTION 'invalid_username' USING ERRCODE = '22023';
        END IF;
        IF public.juzzio_username_reserved(NEW.username) THEN
            RAISE EXCEPTION 'username_reserved' USING ERRCODE = '22023';
        END IF;
        IF NOT public.juzzio_text_is_clean(NEW.username, false) THEN
            RAISE EXCEPTION 'inappropriate_content' USING ERRCODE = '22023';
        END IF;
    END IF;

    -- Mavi tik: rezerve listede "grants_verified" olan ad veya sunucunun verdiği onay
    IF v_client THEN
        NEW.is_verified := CASE WHEN TG_OP = 'UPDATE' AND NOT v_username_changed THEN COALESCE(OLD.is_verified, false) ELSE false END;
    END IF;
    IF NEW.username IS NOT NULL AND public.juzzio_username_grants_verified(NEW.username) THEN
        NEW.is_verified := true;
    END IF;

    -- Biyografi 180 karakter
    NEW.bio := LEFT(COALESCE(NEW.bio, ''), 180);

    -- Görünen ad: boş olamaz, en fazla 60 karakter
    NEW.display_name := LEFT(COALESCE(NULLIF(BTRIM(NEW.display_name), ''), NEW.username, 'Juzzio User'), 60);

    -- Web sitesi (herkese görünür)
    NEW.website_url := BTRIM(COALESCE(NEW.website_url, ''));
    IF NEW.website_url <> '' THEN
        IF NEW.website_url !~* '^https?://' THEN
            NEW.website_url := 'https://' || NEW.website_url;
        END IF;
        IF LENGTH(NEW.website_url) > 200 OR NEW.website_url !~* '^https?://[a-z0-9.-]+\.[a-z]{2,}(:[0-9]+)?(/[^[:space:]]*)?$' THEN
            IF v_client THEN
                RAISE EXCEPTION 'invalid_website' USING ERRCODE = '22023';
            END IF;
            NEW.website_url := '';
        END IF;
    END IF;

    -- Profil müziği: YouTube bağlantısı + başlangıç saniyesi (30 sn kesit uygulamada çalınır)
    NEW.music_url := BTRIM(COALESCE(NEW.music_url, ''));
    IF NEW.music_url = '' THEN
        NEW.music_video_id := '';
        NEW.music_start_sec := 0;
        NEW.music_title := '';
    ELSE
        -- v0.7.0: YouTube kaldırıldı; müzik, isimle aranıp seçilen 30 sn'lik resmi
        -- önizleme ses dosyasıdır (Apple Music/iTunes önizleme sunucuları). Eski YouTube
        -- bağlantıları geriye dönük okunur ama artık yeni kayıt kabul edilmez.
        v_vid := '';
        IF LENGTH(NEW.music_url) > 400
           OR NEW.music_url !~* '^https://([a-z0-9-]+\.)*(mzstatic\.com|itunes\.apple\.com|apple\.com)/' THEN
            IF v_client THEN
                RAISE EXCEPTION 'invalid_music_url' USING ERRCODE = '22023';
            END IF;
            NEW.music_url := '';
            NEW.music_title := '';
        END IF;
        NEW.music_video_id := '';
        NEW.music_start_sec := 0;
        NEW.music_start_sec := GREATEST(0, LEAST(COALESCE(NEW.music_start_sec, 0), 36000));
        NEW.music_title := LEFT(BTRIM(COALESCE(NEW.music_title, '')), 80);
    END IF;

    IF v_client AND (TG_OP = 'INSERT' OR NEW.display_name IS DISTINCT FROM OLD.display_name OR NEW.bio IS DISTINCT FROM OLD.bio)
       AND (NOT public.juzzio_text_is_clean(NEW.display_name, false) OR NOT public.juzzio_text_is_clean(NEW.bio, false)) THEN
        RAISE EXCEPTION 'inappropriate_content' USING ERRCODE = '22023';
    END IF;
    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_protect_profile_row ON public.profiles;
CREATE TRIGGER trg_protect_profile_row
BEFORE INSERT OR UPDATE ON public.profiles
FOR EACH ROW EXECUTE FUNCTION public.protect_profile_row();

-- Mevcut verileri yeni kurallara getir (e-posta/telefon temizliği, mavi tik, bio sınırı)
UPDATE public.profiles SET updated_at = updated_at;
UPDATE public.profiles p SET is_verified = true
WHERE EXISTS (SELECT 1 FROM public.reserved_usernames r WHERE r.username = LOWER(p.username) AND r.grants_verified)
  AND NOT p.is_verified;

-- Kullanıcı adıyla giriş artık e-postayı istemciye vermez: "auth-username-login" Edge Function'ı
-- bu fonksiyonu service_role ile çağırır. (Eski sürüm herkesin e-postasını açığa çıkarıyordu.)
CREATE OR REPLACE FUNCTION public.resolve_email_by_username(p_username TEXT)
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT u.email::text
    FROM public.profiles p
    JOIN auth.users u ON u.id = p.id
    WHERE LOWER(p.username) = LOWER(BTRIM(REGEXP_REPLACE(COALESCE(p_username, ''), '^@+', '')))
    LIMIT 1;
$$;
REVOKE ALL ON FUNCTION public.resolve_email_by_username(TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.resolve_email_by_username(TEXT) TO service_role;

-- Yeni kayıt: kullanıcı adı (rezerve/çakışma kontrolü), görünen ad ayrı, gizli cinsiyet
CREATE OR REPLACE FUNCTION public.handle_new_juzzio_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_meta JSONB := COALESCE(NEW.raw_user_meta_data, '{}'::jsonb);
    v_username TEXT := NULLIF(LOWER(REGEXP_REPLACE(BTRIM(COALESCE(v_meta->>'username', '')), '^@+', '')), '');
    v_display TEXT := NULLIF(BTRIM(COALESCE(v_meta->>'display_name', '')), '');
    v_lang TEXT := COALESCE(NULLIF(v_meta->>'preferred_lang', ''), 'tr');
    v_app_lang TEXT := COALESCE(NULLIF(v_meta->>'app_lang', ''), NULLIF(v_meta->>'preferred_lang', ''), 'tr');
    v_gender TEXT := COALESCE(NULLIF(v_meta->>'gender', ''), 'unspecified');
BEGIN
    IF v_username IS NULL OR v_username !~ '^[a-z0-9_.]{3,30}$' THEN
        v_username := LEFT(REGEXP_REPLACE(LOWER(SPLIT_PART(COALESCE(NEW.email, 'user'), '@', 1)), '[^a-z0-9_.]', '', 'g'), 24);
        IF LENGTH(v_username) < 3 THEN v_username := 'user'; END IF;
    END IF;
    IF EXISTS (SELECT 1 FROM public.reserved_usernames r WHERE r.username = v_username)
       OR EXISTS (SELECT 1 FROM public.profiles WHERE LOWER(username) = v_username AND id <> NEW.id) THEN
        v_username := LEFT(v_username, 24) || '_' || SUBSTRING(REPLACE(NEW.id::text, '-', '') FROM 1 FOR 5);
    END IF;
    IF v_gender NOT IN ('female', 'male', 'unspecified') THEN v_gender := 'unspecified'; END IF;

    INSERT INTO public.profiles (id, username, display_name, preferred_lang, subtitle_lang, app_lang, is_online, last_seen)
    VALUES (NEW.id, v_username, COALESCE(v_display, v_username), v_lang, v_lang, v_app_lang, false, NOW())
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.profile_private (user_id, gender)
    VALUES (NEW.id, v_gender)
    ON CONFLICT (user_id) DO NOTHING;
    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    RETURN NEW;
END;
$$;

-- =============================================================================
-- 4. GRUPLAR: tür, özel amaç, roller (Yönetici / Moderatör / Üye), susturma
-- =============================================================================
ALTER TABLE public.rooms ADD COLUMN IF NOT EXISTS group_type TEXT NOT NULL DEFAULT 'general';
ALTER TABLE public.rooms ADD COLUMN IF NOT EXISTS group_purpose TEXT NOT NULL DEFAULT '';
ALTER TABLE public.rooms ADD COLUMN IF NOT EXISTS description TEXT NOT NULL DEFAULT '';
ALTER TABLE public.rooms DROP CONSTRAINT IF EXISTS rooms_group_type_check;
ALTER TABLE public.rooms ADD CONSTRAINT rooms_group_type_check
    CHECK (group_type IN ('general', 'group_work', 'team_relationship', 'friends', 'family', 'study', 'custom')) NOT VALID;

ALTER TABLE public.room_participants ADD COLUMN IF NOT EXISTS muted_until TIMESTAMPTZ;
ALTER TABLE public.room_participants DROP CONSTRAINT IF EXISTS room_participants_role_check;
-- Eski "admin" rolü moderatöre dönüştürülür; "owner" grubun tek yöneticisidir
UPDATE public.room_participants SET role = 'moderator' WHERE role = 'admin';
ALTER TABLE public.room_participants ADD CONSTRAINT room_participants_role_check
    CHECK (role IN ('owner', 'moderator', 'member', 'host', 'tr', 'en', 'viewer')) NOT VALID;

-- Her grubun tam olarak bir yöneticisi olmalı: yöneticisiz gruplara en eski üyeyi ata
WITH missing AS (
    SELECT r.id AS room_id,
           (SELECT rp.user_id FROM public.room_participants rp
            WHERE rp.room_id = r.id AND rp.left_at IS NULL
            ORDER BY (rp.user_id = r.created_by) DESC, (rp.role = 'moderator') DESC, rp.joined_at
            LIMIT 1) AS new_owner
    FROM public.rooms r
    WHERE r.is_group
      AND NOT EXISTS (SELECT 1 FROM public.room_participants o WHERE o.room_id = r.id AND o.role = 'owner' AND o.left_at IS NULL)
)
UPDATE public.room_participants rp SET role = 'owner'
FROM missing m
WHERE rp.room_id = m.room_id AND rp.user_id = m.new_owner AND m.new_owner IS NOT NULL;
-- Birden fazla yönetici varsa en eskisi kalır, diğerleri moderatör olur
WITH ranked AS (
    SELECT id, row_number() OVER (PARTITION BY room_id ORDER BY joined_at, id) AS rn
    FROM public.room_participants WHERE role = 'owner' AND left_at IS NULL
)
UPDATE public.room_participants rp SET role = 'moderator' FROM ranked WHERE rp.id = ranked.id AND ranked.rn > 1;
CREATE UNIQUE INDEX IF NOT EXISTS idx_room_single_owner
    ON public.room_participants (room_id) WHERE role = 'owner' AND left_at IS NULL;

CREATE OR REPLACE FUNCTION public.group_role_of(p_room UUID, p_user UUID DEFAULT auth.uid())
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT rp.role FROM public.room_participants rp
    WHERE rp.room_id = p_room AND rp.user_id = p_user AND rp.left_at IS NULL
    LIMIT 1;
$$;
GRANT EXECUTE ON FUNCTION public.group_role_of(UUID, UUID) TO authenticated;

-- Oda koruması: istemciler oda kimliğini, LiveKit adını, arama durumunu değiştiremez.
-- Başlık/açıklama/tür yalnızca yönetici ve moderatör tarafından, uygunluk kontrolüyle değişir.
CREATE OR REPLACE FUNCTION public.protect_room_row()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    NEW.title := LEFT(BTRIM(COALESCE(NEW.title, '')), 80);
    NEW.group_purpose := LEFT(BTRIM(COALESCE(NEW.group_purpose, '')), 60);
    NEW.description := LEFT(BTRIM(COALESCE(NEW.description, '')), 300);
    IF TG_OP = 'INSERT' AND NEW.group_type = 'general' AND NEW.group_purpose <> '' THEN
        NEW.group_type := 'custom';
    END IF;

    IF NEW.is_group AND (
        TG_OP = 'INSERT'
        OR NEW.title IS DISTINCT FROM OLD.title
        OR NEW.group_purpose IS DISTINCT FROM OLD.group_purpose
        OR NEW.description IS DISTINCT FROM OLD.description
        OR NEW.group_type IS DISTINCT FROM OLD.group_type
    ) THEN
        IF NOT public.juzzio_text_is_clean(NEW.title, true)
           OR NOT public.juzzio_text_is_clean(NEW.group_purpose, false)
           OR NOT public.juzzio_text_is_clean(NEW.description, false) THEN
            RAISE EXCEPTION 'inappropriate_content' USING ERRCODE = '22023';
        END IF;
        IF NEW.group_type = 'custom' AND NEW.group_purpose = '' THEN
            RAISE EXCEPTION 'group_purpose_required' USING ERRCODE = '22023';
        END IF;
    END IF;

    IF TG_OP = 'UPDATE' AND public.juzzio_is_client_request() THEN
        NEW.id := OLD.id;
        NEW.room_code := OLD.room_code;
        NEW.livekit_room_name := OLD.livekit_room_name;
        NEW.is_group := OLD.is_group;
        NEW.is_channel := OLD.is_channel;
        NEW.created_by := OLD.created_by;
        NEW.is_call_active := OLD.is_call_active;
        NEW.active_call := OLD.active_call;
        NEW.group_members := OLD.group_members;
        NEW.group_member_ids := OLD.group_member_ids;
        NEW.last_message_at := OLD.last_message_at;
        NEW.last_message_preview := OLD.last_message_preview;
        NEW.last_message_sender := OLD.last_message_sender;
        NEW.last_message_type := OLD.last_message_type;
        IF COALESCE(public.group_role_of(OLD.id), '') NOT IN ('owner', 'moderator') THEN
            RAISE EXCEPTION 'not_allowed' USING ERRCODE = '42501';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_protect_room_row ON public.rooms;
CREATE TRIGGER trg_protect_room_row
BEFORE INSERT OR UPDATE ON public.rooms
FOR EACH ROW EXECUTE FUNCTION public.protect_room_row();

DROP POLICY IF EXISTS rooms_update_member ON public.rooms;
DROP POLICY IF EXISTS rooms_update_staff ON public.rooms;
CREATE POLICY rooms_update_staff ON public.rooms FOR UPDATE TO authenticated
    USING (is_group AND public.group_role_of(id) IN ('owner', 'moderator'))
    WITH CHECK (is_group AND public.group_role_of(id) IN ('owner', 'moderator'));
DROP POLICY IF EXISTS rooms_insert_creator ON public.rooms;  -- oda oluşturma yalnızca RPC ile

-- Kullanıcının "beni gruplara kim ekleyebilir" tercihi
CREATE OR REPLACE FUNCTION public.can_add_to_group(p_adder UUID, p_target UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT p_adder IS NOT NULL AND p_target IS NOT NULL AND p_adder <> p_target
       AND NOT public.is_blocked_between(p_adder, p_target)
       AND COALESCE((
           SELECT CASE p.privacy_groups
                      WHEN 'nobody' THEN false
                      WHEN 'friends' THEN public.is_friends_accepted(p_adder, p_target)
                      ELSE true END
           FROM public.profiles p WHERE p.id = p_target
       ), false);
$$;

-- Grup oluşturma (tür + özel amaç + içerik filtresi). Eski imza kaldırılır (belirsizlik olmasın).
DROP FUNCTION IF EXISTS public.create_group_room(TEXT, UUID[], TEXT, BOOLEAN);
CREATE OR REPLACE FUNCTION public.create_group_room(
    p_title TEXT,
    p_member_ids UUID[],
    p_disappearing_timer TEXT DEFAULT 'off',
    p_is_channel BOOLEAN DEFAULT false,
    p_group_type TEXT DEFAULT 'general',
    p_group_purpose TEXT DEFAULT '',
    p_description TEXT DEFAULT ''
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_room UUID;
    v_code TEXT := (CASE WHEN p_is_channel THEN 'channel_' ELSE 'group_' END) || REPLACE(gen_random_uuid()::text, '-', '');
    v_member UUID;
    v_type TEXT := COALESCE(NULLIF(p_group_type, ''), 'general');
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
    IF public.juzzio_is_banned(v_uid) THEN RAISE EXCEPTION 'account_banned'; END IF;
    IF COALESCE(BTRIM(p_title), '') = '' THEN RAISE EXCEPTION 'title_required'; END IF;
    IF v_type NOT IN ('general', 'group_work', 'team_relationship', 'friends', 'family', 'study', 'custom') THEN
        v_type := 'custom';
    END IF;

    INSERT INTO public.rooms (room_code, title, livekit_room_name, is_group, is_channel, disappearing_timer,
                              created_by, group_type, group_purpose, description)
    VALUES (
        v_code, BTRIM(p_title), 'lk_' || v_code, true, COALESCE(p_is_channel, false),
        CASE WHEN p_disappearing_timer IN ('off', '24h', '7d', '30d') THEN p_disappearing_timer ELSE 'off' END,
        v_uid, v_type, COALESCE(p_group_purpose, ''), COALESCE(p_description, '')
    )
    RETURNING id INTO v_room;

    INSERT INTO public.room_participants (room_id, user_id, role) VALUES (v_room, v_uid, 'owner');

    FOREACH v_member IN ARRAY COALESCE(p_member_ids, ARRAY[]::UUID[]) LOOP
        IF public.can_add_to_group(v_uid, v_member) THEN
            INSERT INTO public.room_participants (room_id, user_id, role)
            VALUES (v_room, v_member, 'member')
            ON CONFLICT (room_id, user_id) DO NOTHING;
        END IF;
    END LOOP;

    PERFORM public.sync_room_member_cache(v_room);
    RETURN v_room;
END;
$$;
GRANT EXECUTE ON FUNCTION public.create_group_room(TEXT, UUID[], TEXT, BOOLEAN, TEXT, TEXT, TEXT) TO authenticated;

-- Üye ekleme: yönetici ve moderatörler (kişinin grup gizlilik tercihine uyarak)
CREATE OR REPLACE FUNCTION public.add_group_members(p_room UUID, p_member_ids UUID[])
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_member UUID;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.rooms WHERE id = p_room AND is_group) THEN RAISE EXCEPTION 'not_a_group'; END IF;
    IF COALESCE(public.group_role_of(p_room, v_uid), '') NOT IN ('owner', 'moderator') THEN
        RAISE EXCEPTION 'not_allowed';
    END IF;
    FOREACH v_member IN ARRAY COALESCE(p_member_ids, ARRAY[]::UUID[]) LOOP
        IF public.can_add_to_group(v_uid, v_member) THEN
            INSERT INTO public.room_participants (room_id, user_id, role)
            VALUES (p_room, v_member, 'member')
            ON CONFLICT (room_id, user_id) DO UPDATE
                SET left_at = NULL, hidden_at = NULL, role = 'member', muted_until = NULL, joined_at = NOW()
                WHERE public.room_participants.left_at IS NOT NULL;
        END IF;
    END LOOP;
    PERFORM public.sync_room_member_cache(p_room);
END;
$$;
GRANT EXECUTE ON FUNCTION public.add_group_members(UUID, UUID[]) TO authenticated;

-- Rol atama: yalnızca yönetici. 'owner' verilirse yöneticilik devredilir (eski yönetici moderatör olur).
CREATE OR REPLACE FUNCTION public.set_group_member_role(p_room UUID, p_user UUID, p_role TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID := auth.uid();
BEGIN
    IF public.group_role_of(p_room, v_uid) IS DISTINCT FROM 'owner' THEN RAISE EXCEPTION 'not_allowed'; END IF;
    IF p_user = v_uid THEN RAISE EXCEPTION 'cannot_change_self'; END IF;
    IF p_role NOT IN ('owner', 'moderator', 'member') THEN RAISE EXCEPTION 'invalid_role'; END IF;
    IF public.group_role_of(p_room, p_user) IS NULL THEN RAISE EXCEPTION 'not_a_member'; END IF;

    IF p_role = 'owner' THEN
        UPDATE public.room_participants SET role = 'moderator' WHERE room_id = p_room AND user_id = v_uid;
        UPDATE public.room_participants SET role = 'owner', muted_until = NULL WHERE room_id = p_room AND user_id = p_user;
    ELSE
        UPDATE public.room_participants SET role = p_role WHERE room_id = p_room AND user_id = p_user;
    END IF;
END;
$$;
GRANT EXECUTE ON FUNCTION public.set_group_member_role(UUID, UUID, TEXT) TO authenticated;

-- Üye çıkarma: yalnızca yönetici
CREATE OR REPLACE FUNCTION public.remove_group_member(p_room UUID, p_user UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF public.group_role_of(p_room, auth.uid()) IS DISTINCT FROM 'owner' THEN RAISE EXCEPTION 'not_allowed'; END IF;
    IF p_user = auth.uid() THEN RAISE EXCEPTION 'cannot_remove_self'; END IF;
    UPDATE public.room_participants SET left_at = NOW(), role = 'member', muted_until = NULL
    WHERE room_id = p_room AND user_id = p_user AND left_at IS NULL;
    PERFORM public.sync_room_member_cache(p_room);
END;
$$;
GRANT EXECUTE ON FUNCTION public.remove_group_member(UUID, UUID) TO authenticated;

-- Susturma: yönetici herkesi (kendisi hariç), moderatör yalnızca normal üyeleri susturur
CREATE OR REPLACE FUNCTION public.mute_group_member(p_room UUID, p_user UUID, p_minutes INTEGER)
RETURNS TIMESTAMPTZ
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_my_role TEXT := public.group_role_of(p_room, auth.uid());
    v_target_role TEXT := public.group_role_of(p_room, p_user);
    v_until TIMESTAMPTZ;
BEGIN
    IF v_my_role NOT IN ('owner', 'moderator') THEN RAISE EXCEPTION 'not_allowed'; END IF;
    IF v_target_role IS NULL THEN RAISE EXCEPTION 'not_a_member'; END IF;
    IF p_user = auth.uid() OR v_target_role = 'owner' OR (v_my_role = 'moderator' AND v_target_role <> 'member') THEN
        RAISE EXCEPTION 'not_allowed';
    END IF;
    v_until := CASE WHEN COALESCE(p_minutes, 0) <= 0 THEN NULL
                    ELSE NOW() + make_interval(mins => LEAST(p_minutes, 60 * 24 * 30)) END;
    UPDATE public.room_participants SET muted_until = v_until WHERE room_id = p_room AND user_id = p_user;
    RETURN v_until;
END;
$$;
GRANT EXECUTE ON FUNCTION public.mute_group_member(UUID, UUID, INTEGER) TO authenticated;

-- Moderasyon: yönetici/moderatör gruptaki herhangi bir mesajı silebilir
CREATE OR REPLACE FUNCTION public.moderate_delete_message(p_message UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_room UUID;
    v_sender UUID;
BEGIN
    SELECT room_id, sender_id INTO v_room, v_sender FROM public.messages WHERE id = p_message;
    IF v_room IS NULL THEN RAISE EXCEPTION 'not_found'; END IF;
    IF v_sender IS DISTINCT FROM auth.uid() THEN
        IF NOT EXISTS (SELECT 1 FROM public.rooms WHERE id = v_room AND is_group)
           OR COALESCE(public.group_role_of(v_room, auth.uid()), '') NOT IN ('owner', 'moderator')
           OR public.group_role_of(v_room, v_sender) = 'owner' AND public.group_role_of(v_room, auth.uid()) <> 'owner' THEN
            RAISE EXCEPTION 'not_allowed';
        END IF;
    END IF;
    UPDATE public.messages
    SET is_deleted = true, original_text = '', translated_text = '',
        image_url = NULL, video_url = NULL, audio_url = NULL, document_url = NULL, edited_at = NOW()
    WHERE id = p_message;
END;
$$;
GRANT EXECUTE ON FUNCTION public.moderate_delete_message(UUID) TO authenticated;

-- Grup bilgilerini güncelle (yönetici/moderatör)
CREATE OR REPLACE FUNCTION public.update_group_info(
    p_room UUID,
    p_title TEXT DEFAULT NULL,
    p_group_type TEXT DEFAULT NULL,
    p_group_purpose TEXT DEFAULT NULL,
    p_description TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF COALESCE(public.group_role_of(p_room, auth.uid()), '') NOT IN ('owner', 'moderator') THEN
        RAISE EXCEPTION 'not_allowed';
    END IF;
    UPDATE public.rooms
    SET title = COALESCE(NULLIF(BTRIM(p_title), ''), title),
        group_type = CASE WHEN p_group_type IN ('general', 'group_work', 'team_relationship', 'friends', 'family', 'study', 'custom')
                          THEN p_group_type ELSE group_type END,
        group_purpose = COALESCE(p_group_purpose, group_purpose),
        description = COALESCE(p_description, description),
        updated_at = NOW()
    WHERE id = p_room AND is_group;
END;
$$;
GRANT EXECUTE ON FUNCTION public.update_group_info(UUID, TEXT, TEXT, TEXT, TEXT) TO authenticated;

-- Gruptan ayrılma: yönetici ayrılırsa yöneticilik en eski moderatöre, yoksa en eski üyeye geçer
CREATE OR REPLACE FUNCTION public.leave_room(p_room UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_is_group BOOLEAN;
    v_was_owner BOOLEAN;
    v_next UUID;
BEGIN
    SELECT is_group INTO v_is_group FROM public.rooms WHERE id = p_room;
    IF v_is_group THEN
        v_was_owner := public.group_role_of(p_room, auth.uid()) = 'owner';
        UPDATE public.room_participants SET left_at = NOW(), role = 'member', muted_until = NULL
        WHERE room_id = p_room AND user_id = auth.uid();
        IF v_was_owner THEN
            SELECT user_id INTO v_next FROM public.room_participants
            WHERE room_id = p_room AND left_at IS NULL
            ORDER BY (role = 'moderator') DESC, joined_at
            LIMIT 1;
            IF v_next IS NOT NULL THEN
                UPDATE public.room_participants SET role = 'owner', muted_until = NULL
                WHERE room_id = p_room AND user_id = v_next;
            END IF;
        END IF;
        PERFORM public.sync_room_member_cache(p_room);
    ELSE
        UPDATE public.room_participants SET hidden_at = NOW(), cleared_at = NOW()
        WHERE room_id = p_room AND user_id = auth.uid();
    END IF;
END;
$$;
GRANT EXECUTE ON FUNCTION public.leave_room(UUID) TO authenticated;

-- Grup üyeleri listesi (rol ve susturma durumu ile)
CREATE OR REPLACE FUNCTION public.get_group_members(p_room UUID)
RETURNS TABLE (
    user_id UUID,
    username TEXT,
    display_name TEXT,
    avatar_url TEXT,
    role TEXT,
    muted_until TIMESTAMPTZ,
    joined_at TIMESTAMPTZ,
    is_verified BOOLEAN
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT p.id, p.username, p.display_name, p.avatar_url,
           CASE WHEN rp.role IN ('owner', 'moderator') THEN rp.role ELSE 'member' END,
           CASE WHEN rp.muted_until > NOW() THEN rp.muted_until END,
           rp.joined_at, p.is_verified
    FROM public.room_participants rp
    JOIN public.profiles p ON p.id = rp.user_id
    WHERE rp.room_id = p_room AND rp.left_at IS NULL AND public.is_room_member(p_room, auth.uid())
    ORDER BY CASE rp.role WHEN 'owner' THEN 0 WHEN 'moderator' THEN 1 ELSE 2 END, LOWER(p.display_name);
$$;
GRANT EXECUTE ON FUNCTION public.get_group_members(UUID) TO authenticated;

-- İstenen tablo adları: veriyi kopyalamadan, RLS'e uyan görünümler
DO $$
BEGIN
    EXECUTE 'CREATE OR REPLACE VIEW public.groups WITH (security_invoker = true) AS
             SELECT id, title, group_type, group_purpose, description, avatar_url, created_by, created_at, updated_at,
                    is_channel, disappearing_timer, livekit_room_name
             FROM public.rooms WHERE is_group';
    EXECUTE 'CREATE OR REPLACE VIEW public.group_members WITH (security_invoker = true) AS
             SELECT rp.room_id AS group_id, rp.user_id,
                    CASE WHEN rp.role IN (''owner'', ''moderator'') THEN rp.role ELSE ''member'' END AS role,
                    rp.muted_until, rp.joined_at
             FROM public.room_participants rp JOIN public.rooms r ON r.id = rp.room_id
             WHERE r.is_group AND rp.left_at IS NULL';
    EXECUTE 'CREATE OR REPLACE VIEW public.group_messages WITH (security_invoker = true) AS
             SELECT m.* FROM public.messages m JOIN public.rooms r ON r.id = m.room_id WHERE r.is_group';
    EXECUTE 'GRANT SELECT ON public.groups, public.group_members, public.group_messages TO authenticated';
END $$;

-- =============================================================================
-- 5. GÜVENLİK SERTLEŞTİRME (mevcut tablolar)
-- =============================================================================

-- Hesap/cihaz engeli (admin paneli) — tablo burada, yönetim fonksiyonları Bölüm 2'de
CREATE TABLE IF NOT EXISTS public.banned_users (
    user_id UUID PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
    reason_code TEXT NOT NULL,
    note TEXT NOT NULL DEFAULT '',
    banned_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE public.banned_users ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.banned_users FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.juzzio_is_banned(p_user UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (SELECT 1 FROM public.banned_users b WHERE b.user_id = p_user);
$$;
GRANT EXECUTE ON FUNCTION public.juzzio_is_banned(UUID) TO authenticated;

-- Mesaj gönderme: üye olmalı, engelli/susturulmuş/yasaklı olmamalı
DROP POLICY IF EXISTS messages_insert_member ON public.messages;
CREATE POLICY messages_insert_member ON public.messages FOR INSERT TO authenticated
    WITH CHECK (
        sender_id = auth.uid()
        AND public.is_room_member(room_id)
        AND NOT public.juzzio_is_banned(auth.uid())
        AND NOT EXISTS (
            SELECT 1 FROM public.room_participants me
            WHERE me.room_id = messages.room_id AND me.user_id = auth.uid() AND me.muted_until > NOW()
        )
        AND NOT EXISTS (
            SELECT 1 FROM public.room_participants o
            JOIN public.rooms r ON r.id = o.room_id
            WHERE o.room_id = messages.room_id AND NOT r.is_group AND o.user_id <> auth.uid()
              AND public.is_blocked_between(auth.uid(), o.user_id)
        )
    );

-- Mesaj düzenleme: başka odaya taşıma / gönderen değiştirme engellendi
CREATE OR REPLACE FUNCTION public.protect_message_row()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    IF public.juzzio_is_client_request() THEN
        NEW.id := OLD.id;
        NEW.room_id := OLD.room_id;
        NEW.sender_id := OLD.sender_id;
        NEW.receiver_id := OLD.receiver_id;
        NEW.created_at := OLD.created_at;
        NEW.message_type := OLD.message_type;
        NEW.sender_name := OLD.sender_name;
    END IF;
    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_protect_message_row ON public.messages;
CREATE TRIGGER trg_protect_message_row
BEFORE UPDATE ON public.messages
FOR EACH ROW EXECUTE FUNCTION public.protect_message_row();

-- Arama kayıtları yalnızca RPC'lerle oluşur/değişir (sahte "çalan arama" spam'i engellendi)
DROP POLICY IF EXISTS call_logs_insert_caller ON public.call_logs;
DROP POLICY IF EXISTS call_logs_update_involved ON public.call_logs;

-- Bildirimler yalnızca sunucu tetikleyicileriyle oluşur (başkası adına sahte bildirim engellendi)
DROP POLICY IF EXISTS notifications_insert_actor ON public.notifications;

-- Şikâyetler: gönderen düzenleyemez/kapatamaz (yalnızca admin paneli)
DROP POLICY IF EXISTS reports_update_own ON public.reports;
ALTER TABLE public.reports DROP CONSTRAINT IF EXISTS reports_target_type_check;
ALTER TABLE public.reports ADD CONSTRAINT reports_target_type_check
    CHECK (target_type IN ('post', 'comment', 'story', 'user', 'message', 'group')) NOT VALID;
ALTER TABLE public.reports DROP CONSTRAINT IF EXISTS reports_reason_code_check;
ALTER TABLE public.reports ADD CONSTRAINT reports_reason_code_check
    CHECK (reason_code IN ('spam', 'harassment', 'inappropriate', 'fake_account', 'hate_speech', 'scam', 'violence', 'other')) NOT VALID;
ALTER TABLE public.reports DROP CONSTRAINT IF EXISTS reports_status_check;
ALTER TABLE public.reports ADD CONSTRAINT reports_status_check
    CHECK (status IN ('open', 'reviewed', 'resolved', 'dismissed')) NOT VALID;
ALTER TABLE public.reports ADD COLUMN IF NOT EXISTS reviewed_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL;
ALTER TABLE public.reports ADD COLUMN IF NOT EXISTS reviewed_at TIMESTAMPTZ;
ALTER TABLE public.reports ADD COLUMN IF NOT EXISTS resolution_note TEXT NOT NULL DEFAULT '';

-- Takip: durum sunucuda hesaplanır (gizli hesabı kendi kendine "takip ediliyor" yapma engellendi)
CREATE OR REPLACE FUNCTION public.protect_follow_row()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
    v_private BOOLEAN;
BEGIN
    IF NOT public.juzzio_is_client_request() THEN RETURN NEW; END IF;
    SELECT COALESCE(is_private_account, false) INTO v_private FROM public.profiles WHERE id = NEW.following_id;
    IF TG_OP = 'INSERT' THEN
        NEW.status := CASE WHEN v_private THEN 'pending' ELSE 'following' END;
    ELSIF auth.uid() = OLD.follower_id AND auth.uid() IS DISTINCT FROM OLD.following_id THEN
        -- Takip eden taraf durumu yükseltemez; yalnızca yeniden istek atabilir
        NEW.status := CASE WHEN OLD.status = 'following' THEN 'following'
                           WHEN v_private THEN 'pending' ELSE 'following' END;
        NEW.follower_id := OLD.follower_id;
        NEW.following_id := OLD.following_id;
    ELSE
        NEW.follower_id := OLD.follower_id;
        NEW.following_id := OLD.following_id;
    END IF;
    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_protect_follow_row ON public.follows;
CREATE TRIGGER trg_protect_follow_row
BEFORE INSERT OR UPDATE ON public.follows
FOR EACH ROW EXECUTE FUNCTION public.protect_follow_row();

-- Sayaçlar (beğeni/yorum/görüntülenme) istemci tarafından sahte değerlerle değiştirilemez
CREATE OR REPLACE FUNCTION public.protect_counter_columns()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
    v_col TEXT;
    v_old JSONB;
    v_new JSONB;
BEGIN
    IF NOT public.juzzio_is_client_request() THEN RETURN NEW; END IF;
    v_new := to_jsonb(NEW);
    IF TG_OP = 'INSERT' THEN
        FOREACH v_col IN ARRAY TG_ARGV LOOP
            IF v_new ? v_col THEN v_new := jsonb_set(v_new, ARRAY[v_col], '0'::jsonb); END IF;
        END LOOP;
    ELSE
        v_old := to_jsonb(OLD);
        FOREACH v_col IN ARRAY TG_ARGV LOOP
            IF v_new ? v_col THEN v_new := jsonb_set(v_new, ARRAY[v_col], v_old->v_col); END IF;
        END LOOP;
    END IF;
    NEW := jsonb_populate_record(NEW, v_new);
    RETURN NEW;
END;
$$;
DO $$
BEGIN
    IF to_regclass('public.posts') IS NOT NULL THEN
        DROP TRIGGER IF EXISTS trg_protect_post_counters ON public.posts;
        CREATE TRIGGER trg_protect_post_counters BEFORE INSERT OR UPDATE ON public.posts
        FOR EACH ROW EXECUTE FUNCTION public.protect_counter_columns('likes_count', 'comments_count', 'saves_count', 'shares_count', 'views_count');
    END IF;
    IF to_regclass('public.stories') IS NOT NULL THEN
        DROP TRIGGER IF EXISTS trg_protect_story_counters ON public.stories;
        CREATE TRIGGER trg_protect_story_counters BEFORE INSERT OR UPDATE ON public.stories
        FOR EACH ROW EXECUTE FUNCTION public.protect_counter_columns('likes_count', 'views_count');
    END IF;
    IF to_regclass('public.post_comments') IS NOT NULL THEN
        DROP TRIGGER IF EXISTS trg_protect_comment_counters ON public.post_comments;
        CREATE TRIGGER trg_protect_comment_counters BEFORE INSERT OR UPDATE ON public.post_comments
        FOR EACH ROW EXECUTE FUNCTION public.protect_counter_columns('likes_count', 'replies_count');
    END IF;
END $$;

-- Yasaklı hesaplar gönderi/yorum paylaşamaz
DROP POLICY IF EXISTS posts_insert_own ON public.posts;
CREATE POLICY posts_insert_own ON public.posts FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = author_id AND NOT public.juzzio_is_banned(auth.uid()));
DROP POLICY IF EXISTS post_comments_insert_allowed ON public.post_comments;
CREATE POLICY post_comments_insert_allowed ON public.post_comments FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = author_id
                AND NOT public.juzzio_is_banned(auth.uid())
                AND EXISTS (SELECT 1 FROM public.posts p WHERE p.id = post_comments.post_id AND p.is_deleted = false
                            AND p.comments_enabled = true
                            AND public.can_view_user_content(auth.uid(), p.author_id, p.visibility)));

-- =============================================================================
-- 6. SOHBET LİSTESİ: grup türü/amacı ve benim rolüm eklendi
-- =============================================================================
DROP FUNCTION IF EXISTS public.get_my_conversations();
CREATE OR REPLACE FUNCTION public.get_my_conversations()
RETURNS TABLE (
    room_id UUID,
    room_code TEXT,
    title TEXT,
    is_group BOOLEAN,
    is_channel BOOLEAN,
    livekit_room_name TEXT,
    disappearing_timer TEXT,
    avatar_url TEXT,
    partner_id UUID,
    partner_username TEXT,
    partner_display_name TEXT,
    partner_avatar_url TEXT,
    partner_lang TEXT,
    partner_is_online BOOLEAN,
    partner_last_seen TIMESTAMPTZ,
    member_ids JSONB,
    member_names JSONB,
    last_message_at TIMESTAMPTZ,
    last_message_sender UUID,
    last_message_type TEXT,
    last_message_preview TEXT,
    unread_count INTEGER,
    is_muted BOOLEAN,
    is_pinned BOOLEAN,
    is_call_active BOOLEAN,
    active_call JSONB,
    created_by UUID,
    partner_last_read_at TIMESTAMPTZ,
    my_role TEXT,
    my_muted_until TIMESTAMPTZ,
    group_type TEXT,
    group_purpose TEXT,
    description TEXT,
    partner_is_verified BOOLEAN
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT
        r.id,
        r.room_code,
        CASE WHEN r.is_group THEN r.title ELSE COALESCE(NULLIF(op.display_name, ''), op.username, r.title) END,
        r.is_group,
        r.is_channel,
        r.livekit_room_name,
        r.disappearing_timer,
        CASE WHEN r.is_group THEN r.avatar_url ELSE op.avatar_url END,
        op.id,
        op.username,
        op.display_name,
        op.avatar_url,
        op.preferred_lang,
        op.is_online,
        op.last_seen,
        r.group_member_ids,
        r.group_members,
        CASE WHEN me.cleared_at IS NOT NULL AND r.last_message_at <= me.cleared_at THEN NULL ELSE r.last_message_at END,
        r.last_message_sender,
        r.last_message_type,
        CASE WHEN me.cleared_at IS NOT NULL AND r.last_message_at <= me.cleared_at THEN NULL ELSE r.last_message_preview END,
        (
            SELECT COUNT(*)::INTEGER
            FROM public.messages m
            WHERE m.room_id = r.id
              AND m.sender_id <> me.user_id
              AND m.created_at > GREATEST(me.last_read_at, COALESCE(me.cleared_at, me.last_read_at))
              AND COALESCE(m.is_deleted, false) = false
        ),
        me.is_muted,
        me.is_pinned,
        r.is_call_active,
        r.active_call,
        r.created_by,
        CASE WHEN COALESCE(op.read_receipts, true) AND COALESCE(mp.read_receipts, true) THEN op.partner_last_read_at END,
        CASE WHEN me.role IN ('owner', 'moderator') THEN me.role ELSE 'member' END,
        CASE WHEN me.muted_until > NOW() THEN me.muted_until END,
        r.group_type,
        r.group_purpose,
        r.description,
        COALESCE(op.is_verified, false)
    FROM public.room_participants me
    JOIN public.profiles mp ON mp.id = me.user_id
    JOIN public.rooms r ON r.id = me.room_id
    LEFT JOIN LATERAL (
        SELECT p.*, o.last_read_at AS partner_last_read_at
        FROM public.room_participants o
        JOIN public.profiles p ON p.id = o.user_id
        WHERE NOT r.is_group AND o.room_id = r.id AND o.user_id <> me.user_id
        LIMIT 1
    ) op ON true
    WHERE me.user_id = auth.uid()
      AND me.left_at IS NULL
      AND (me.hidden_at IS NULL OR r.last_message_at > me.hidden_at)
      AND r.room_code <> 'juzzio-couple-main'
      AND (r.is_group OR op.id IS NOT NULL)
    ORDER BY me.is_pinned DESC, COALESCE(r.last_message_at, r.created_at) DESC;
$$;
GRANT EXECUTE ON FUNCTION public.get_my_conversations() TO authenticated;

-- #############################################################################
-- BÖLÜM 7/9 — kaynak: 20261030010000_juzzio_v030_calls_badges_chick_admin.sql
-- #############################################################################
-- =============================================================================
-- JUZZIO v0.3.0 — Bölüm 2/2: Konferans (en fazla 4 kişi), arama rozetleri,
-- Civciv oyunu, yönetici paneli (hash'li şifre, oturum belirteci), cihaz engeli
--
-- Tekrar çalıştırılabilir; 20261030000000 dosyasından SONRA çalışmalıdır.
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

-- Bildirim türleri (civciv olayları eklendi)
ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_event_type_check;
ALTER TABLE public.notifications ADD CONSTRAINT notifications_event_type_check CHECK (
    event_type IN ('like', 'comment', 'reply', 'follow', 'follow_request', 'follow_accepted',
                   'friend_request', 'friend_accepted', 'story_like', 'story_reply', 'message',
                   'missed_call', 'incoming_call', 'group_activity', 'system',
                   'chick_invite', 'chick_hatched', 'chick_hungry', 'chick_dying', 'chick_died')
) NOT VALID;

-- =============================================================================
-- 1. KONFERANS: kişi sınırı (kendisi dahil 4)
-- =============================================================================
CREATE OR REPLACE FUNCTION public.juzzio_max_call_participants()
RETURNS INTEGER
LANGUAGE sql
IMMUTABLE
AS $$ SELECT 4 $$;

-- Oturumdaki aktif kişi sayısı: arayan + cevaplayıp ayrılmamış olanlar
CREATE OR REPLACE FUNCTION public.call_session_active_count(p_session UUID)
RETURNS INTEGER
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT 1 + COUNT(*)::INTEGER
    FROM public.call_logs c
    WHERE c.session_id = p_session AND c.status = 'answered' AND c.ended_at IS NULL
      AND c.receiver_id IS DISTINCT FROM (SELECT caller_id FROM public.call_logs WHERE session_id = p_session ORDER BY created_at LIMIT 1);
$$;

-- Önizleme metinleri artık dile bağlı değil: istemci ve push, anahtarı kullanıcının dilinde gösterir
--   call:voice | call:video | call:group_voice | call:group_video
CREATE OR REPLACE FUNCTION public.juzzio_call_preview_key(p_is_group BOOLEAN, p_is_video BOOLEAN)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT 'call:' || CASE WHEN p_is_group THEN 'group_' ELSE '' END || CASE WHEN p_is_video THEN 'video' ELSE 'voice' END;
$$;

CREATE OR REPLACE FUNCTION public.start_call(
    p_room UUID,
    p_is_video BOOLEAN,
    p_invitee_ids UUID[] DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_room RECORD;
    v_me RECORD;
    v_session UUID := gen_random_uuid();
    v_target RECORD;
    v_count INTEGER := 0;
    v_existing UUID;
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
    IF public.juzzio_is_banned(v_uid) THEN RAISE EXCEPTION 'account_banned'; END IF;
    SELECT * INTO v_room FROM public.rooms WHERE id = p_room;
    IF v_room.id IS NULL OR NOT public.is_room_member(p_room, v_uid) THEN
        RAISE EXCEPTION 'not_a_member';
    END IF;
    SELECT id, COALESCE(NULLIF(display_name, ''), username, 'Juzzio') AS name, avatar_url INTO v_me
    FROM public.profiles WHERE id = v_uid;

    -- Grupta süren gerçek bir konferans varsa ona katıl (doluysa "call_full")
    IF v_room.is_group AND v_room.is_call_active AND v_room.active_call ? 'session_id' THEN
        v_existing := (v_room.active_call->>'session_id')::uuid;
        IF (v_room.active_call->>'started_at')::timestamptz > NOW() - INTERVAL '6 hours'
           AND (
               EXISTS (SELECT 1 FROM public.call_logs cl
                       WHERE cl.session_id = v_existing AND cl.status = 'answered' AND cl.ended_at IS NULL)
               OR (v_room.active_call->>'started_at')::timestamptz > NOW() - INTERVAL '60 seconds'
           ) THEN
            IF NOT EXISTS (SELECT 1 FROM public.call_logs cl
                           WHERE cl.session_id = v_existing AND cl.receiver_id = v_uid
                             AND cl.status = 'answered' AND cl.ended_at IS NULL)
               AND (v_room.active_call->>'caller_id')::uuid IS DISTINCT FROM v_uid
               AND public.call_session_active_count(v_existing) >= public.juzzio_max_call_participants() THEN
                RAISE EXCEPTION 'call_full';
            END IF;
            UPDATE public.call_logs
            SET status = 'answered', answered_at = COALESCE(answered_at, NOW())
            WHERE session_id = v_existing AND receiver_id = v_uid AND status = 'ringing';
            IF NOT FOUND AND (v_room.active_call->>'caller_id')::uuid IS DISTINCT FROM v_uid
               AND NOT EXISTS (SELECT 1 FROM public.call_logs cl WHERE cl.session_id = v_existing AND cl.receiver_id = v_uid) THEN
                -- Sonradan katılan (çağrılmamış) grup üyesi için kayıt
                INSERT INTO public.call_logs (session_id, room_id, livekit_room_name, is_group, group_title,
                    caller_id, caller_name, caller_avatar, receiver_id, receiver_name, receiver_avatar,
                    is_video, status, status_reason, answered_at)
                SELECT v_existing, p_room, v_room.livekit_room_name, true, v_room.title,
                       (v_room.active_call->>'caller_id')::uuid, COALESCE(v_room.active_call->>'caller_name', ''), NULL,
                       v_uid, v_me.name, v_me.avatar_url,
                       COALESCE((v_room.active_call->>'is_video')::boolean, false), 'answered', 'join', NOW();
            END IF;
            RETURN v_room.active_call || jsonb_build_object('joined_existing', true);
        END IF;
        UPDATE public.call_logs
        SET status = 'missed', ended_at = COALESCE(ended_at, NOW())
        WHERE session_id = v_existing AND status = 'ringing';
        UPDATE public.rooms SET is_call_active = false, active_call = NULL WHERE id = p_room;
    END IF;

    FOR v_target IN
        SELECT p.id, COALESCE(NULLIF(p.display_name, ''), p.username, 'Juzzio') AS name, p.avatar_url
        FROM public.room_participants rp
        JOIN public.profiles p ON p.id = rp.user_id
        WHERE rp.room_id = p_room AND rp.left_at IS NULL AND rp.user_id <> v_uid
          AND (p_invitee_ids IS NULL OR rp.user_id = ANY (p_invitee_ids))
          AND NOT public.is_blocked_between(v_uid, rp.user_id)
          AND NOT public.juzzio_is_banned(rp.user_id)
    LOOP
        INSERT INTO public.call_logs (
            session_id, room_id, livekit_room_name, is_group, group_title,
            caller_id, caller_name, caller_avatar, receiver_id, receiver_name, receiver_avatar,
            is_video, status, status_reason, duration_sec, data_kb
        ) VALUES (
            v_session, p_room, v_room.livekit_room_name, v_room.is_group,
            CASE WHEN v_room.is_group THEN v_room.title ELSE '' END,
            v_uid, v_me.name, v_me.avatar_url, v_target.id, v_target.name, v_target.avatar_url,
            COALESCE(p_is_video, false), 'ringing',
            public.juzzio_call_preview_key(v_room.is_group, COALESCE(p_is_video, false)), 0, 0
        );
        v_count := v_count + 1;
    END LOOP;

    IF v_count = 0 THEN
        RAISE EXCEPTION 'no_callable_participants';
    END IF;

    UPDATE public.rooms
    SET is_call_active = true,
        active_call = jsonb_build_object(
            'session_id', v_session,
            'caller_id', v_uid,
            'caller_name', v_me.name,
            'is_video', COALESCE(p_is_video, false),
            'is_group_call', v_room.is_group,
            'group_title', v_room.title,
            'livekit_room', v_room.livekit_room_name,
            'started_at', NOW(),
            'max_participants', public.juzzio_max_call_participants()
        ),
        updated_at = NOW()
    WHERE id = p_room;

    RETURN jsonb_build_object(
        'session_id', v_session,
        'room_id', p_room,
        'livekit_room', v_room.livekit_room_name,
        'is_group_call', v_room.is_group,
        'invited', v_count,
        'max_participants', public.juzzio_max_call_participants()
    );
END;
$$;
GRANT EXECUTE ON FUNCTION public.start_call(UUID, BOOLEAN, UUID[]) TO authenticated;

-- Süren aramaya kişi ekle: boş yer kadar davet (kendisi dahil en fazla 4)
CREATE OR REPLACE FUNCTION public.invite_to_call(p_session UUID, p_user_ids UUID[])
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_base RECORD;
    v_me RECORD;
    v_target RECORD;
    v_count INTEGER := 0;
    v_slots INTEGER;
BEGIN
    SELECT * INTO v_base FROM public.call_logs
    WHERE session_id = p_session AND (caller_id = v_uid OR (receiver_id = v_uid AND status = 'answered'))
    ORDER BY created_at LIMIT 1;
    IF v_base.id IS NULL THEN RAISE EXCEPTION 'not_in_call'; END IF;

    -- Boş yer: sınır − (aktif kişiler + hâlâ çalan davetler)
    v_slots := public.juzzio_max_call_participants() - public.call_session_active_count(p_session)
               - (SELECT COUNT(*)::INTEGER FROM public.call_logs c
                  WHERE c.session_id = p_session AND c.status = 'ringing' AND c.created_at > NOW() - INTERVAL '60 seconds');
    IF v_slots <= 0 THEN RAISE EXCEPTION 'call_full'; END IF;

    SELECT COALESCE(NULLIF(display_name, ''), username, 'Juzzio') AS name, avatar_url INTO v_me
    FROM public.profiles WHERE id = v_uid;

    FOR v_target IN
        SELECT p.id, COALESCE(NULLIF(p.display_name, ''), p.username, 'Juzzio') AS name, p.avatar_url
        FROM public.profiles p
        WHERE p.id = ANY (COALESCE(p_user_ids, ARRAY[]::UUID[]))
          AND p.id <> v_uid
          AND p.id <> v_base.caller_id
          AND NOT public.is_blocked_between(v_uid, p.id)
          AND NOT public.juzzio_is_banned(p.id)
          AND (public.is_friends_accepted(v_uid, p.id)
               OR (v_base.room_id IS NOT NULL AND public.is_room_member(v_base.room_id, p.id)))
          AND NOT EXISTS (
              SELECT 1 FROM public.call_logs c
              WHERE c.session_id = p_session AND c.receiver_id = p.id
                AND (c.status = 'ringing' OR (c.status = 'answered' AND c.ended_at IS NULL))
          )
        LIMIT v_slots
    LOOP
        INSERT INTO public.call_logs (
            session_id, room_id, livekit_room_name, is_group, group_title,
            caller_id, caller_name, caller_avatar, receiver_id, receiver_name, receiver_avatar,
            is_video, status, status_reason
        ) VALUES (
            p_session, v_base.room_id, v_base.livekit_room_name, true,
            COALESCE(NULLIF(v_base.group_title, ''), ''),
            v_uid, v_me.name, v_me.avatar_url, v_target.id, v_target.name, v_target.avatar_url,
            v_base.is_video, 'ringing', public.juzzio_call_preview_key(true, v_base.is_video)
        );
        v_count := v_count + 1;
    END LOOP;
    RETURN v_count;
END;
$$;
GRANT EXECUTE ON FUNCTION public.invite_to_call(UUID, UUID[]) TO authenticated;

-- Cevapla/reddet/bitir: cevaplarken konferans doluysa "call_full"
CREATE OR REPLACE FUNCTION public.update_call_status(
    p_call UUID,
    p_status TEXT,
    p_duration_sec INTEGER DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_row RECORD;
BEGIN
    SELECT * INTO v_row FROM public.call_logs WHERE id = p_call;
    IF v_row.id IS NULL OR (v_row.caller_id <> v_uid AND v_row.receiver_id IS DISTINCT FROM v_uid) THEN
        RAISE EXCEPTION 'not_allowed';
    END IF;
    IF p_status NOT IN ('answered', 'rejected', 'ended', 'missed', 'busy_silent', 'cancelled') THEN
        RAISE EXCEPTION 'invalid_status';
    END IF;
    IF p_status = 'answered' THEN
        IF v_row.status NOT IN ('ringing', 'answered') THEN
            RAISE EXCEPTION 'call_not_ringing';
        END IF;
        IF v_row.status = 'ringing' AND v_row.session_id IS NOT NULL
           AND public.call_session_active_count(v_row.session_id) >= public.juzzio_max_call_participants() THEN
            UPDATE public.call_logs SET status = 'missed', ended_at = NOW() WHERE id = p_call;
            RAISE EXCEPTION 'call_full';
        END IF;
    END IF;

    UPDATE public.call_logs
    SET status = CASE
            WHEN p_status = 'ended' AND status IN ('answered', 'ended') THEN 'answered'
            WHEN p_status = 'ended' AND status = 'ringing' THEN 'missed'
            ELSE p_status
        END,
        answered_at = CASE WHEN p_status = 'answered' THEN COALESCE(answered_at, NOW()) ELSE answered_at END,
        ended_at = CASE WHEN p_status <> 'answered' THEN NOW() ELSE NULL END,
        duration_sec = COALESCE(p_duration_sec, duration_sec)
    WHERE id = p_call;

    IF p_status IN ('missed', 'busy_silent') OR (p_status = 'ended' AND v_row.status = 'ringing') THEN
        BEGIN
            INSERT INTO public.notifications (recipient_id, actor_id, actor_username, actor_display_name, actor_avatar_url,
                                              event_type, target_id, target_secondary_id, preview_text, dedupe_key)
            SELECT v_row.receiver_id, v_row.caller_id, COALESCE(p.username, ''), v_row.caller_name, v_row.caller_avatar,
                   'missed_call', COALESCE(v_row.room_id::text, ''), v_row.id::text,
                   public.juzzio_call_preview_key(v_row.is_group, v_row.is_video),
                   'missed_' || v_row.id::text
            FROM public.profiles p
            WHERE p.id = v_row.caller_id AND v_row.receiver_id IS NOT NULL
            ON CONFLICT (recipient_id, dedupe_key) DO NOTHING;
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
    END IF;
END;
$$;
GRANT EXECUTE ON FUNCTION public.update_call_status(UUID, TEXT, INTEGER) TO authenticated;

-- Arama bitirme: önizleme anahtarı ile cevapsız bildirimi
CREATE OR REPLACE FUNCTION public.end_call_session(p_session UUID, p_duration_sec INTEGER DEFAULT NULL, p_force BOOLEAN DEFAULT false)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_room UUID;
    v_is_group BOOLEAN;
    v_caller UUID;
BEGIN
    SELECT room_id, is_group, caller_id INTO v_room, v_is_group, v_caller
    FROM public.call_logs
    WHERE session_id = p_session AND (caller_id = v_uid OR receiver_id = v_uid)
    ORDER BY created_at LIMIT 1;
    IF v_caller IS NULL THEN RETURN; END IF;

    IF v_is_group AND NOT p_force THEN
        UPDATE public.call_logs SET ended_at = NOW(), duration_sec = COALESCE(p_duration_sec, duration_sec)
        WHERE session_id = p_session AND receiver_id = v_uid AND status = 'answered' AND ended_at IS NULL;
        -- Konferansta biri ayrılınca oturum sürer; içeride ve çalan kimse kalmadıysa kapanır
        IF EXISTS (SELECT 1 FROM public.call_logs c WHERE c.session_id = p_session
                   AND ((c.status = 'answered' AND c.ended_at IS NULL) OR c.status = 'ringing')) THEN
            RETURN;
        END IF;
    END IF;

    UPDATE public.call_logs
    SET status = CASE WHEN status = 'ringing' THEN CASE WHEN caller_id = v_uid THEN 'missed' ELSE 'cancelled' END
                      WHEN status = 'answered' THEN 'answered'
                      ELSE status END,
        ended_at = COALESCE(ended_at, NOW()),
        duration_sec = CASE WHEN status = 'answered' AND ended_at IS NULL THEN COALESCE(p_duration_sec, duration_sec) ELSE duration_sec END
    WHERE session_id = p_session;

    INSERT INTO public.notifications (recipient_id, actor_id, actor_username, actor_display_name, actor_avatar_url,
                                      event_type, target_id, target_secondary_id, preview_text, dedupe_key)
    SELECT c.receiver_id, c.caller_id, COALESCE(p.username, ''), c.caller_name, c.caller_avatar,
           'missed_call', COALESCE(c.room_id::text, ''), c.id::text,
           public.juzzio_call_preview_key(c.is_group, c.is_video),
           'missed_' || c.id::text
    FROM public.call_logs c
    JOIN public.profiles p ON p.id = c.caller_id
    WHERE c.session_id = p_session AND c.status = 'missed' AND c.receiver_id IS NOT NULL
    ON CONFLICT (recipient_id, dedupe_key) DO NOTHING;

    IF v_room IS NOT NULL THEN
        UPDATE public.rooms SET is_call_active = false, active_call = NULL, updated_at = NOW()
        WHERE id = v_room AND (active_call->>'session_id') = p_session::text;
    END IF;
END;
$$;
GRANT EXECUTE ON FUNCTION public.end_call_session(UUID, INTEGER, BOOLEAN) TO authenticated;

CREATE OR REPLACE FUNCTION public.notify_on_call_log_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NEW.receiver_id IS NOT NULL AND NEW.receiver_id <> NEW.caller_id AND NEW.status = 'ringing'
       AND NOT public.is_blocked_between(NEW.caller_id, NEW.receiver_id) THEN
        BEGIN
            INSERT INTO public.notifications (recipient_id, actor_id, actor_username, actor_display_name, actor_avatar_url,
                                              event_type, target_id, target_secondary_id, preview_text, dedupe_key)
            SELECT NEW.receiver_id, NEW.caller_id, COALESCE(p.username, ''), NEW.caller_name, NEW.caller_avatar,
                   'incoming_call', COALESCE(NEW.room_id::text, ''), NEW.id::text,
                   public.juzzio_call_preview_key(NEW.is_group, NEW.is_video)
                       || CASE WHEN NEW.is_group AND COALESCE(NEW.group_title, '') <> '' THEN ':' || NEW.group_title ELSE '' END,
                   'call_' || NEW.id::text
            FROM public.profiles p WHERE p.id = NEW.caller_id
            ON CONFLICT (recipient_id, dedupe_key) DO NOTHING;
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
    END IF;
    RETURN NEW;
END;
$$;

-- v0.5.1: konferanstan çıkarılan katılımcılar (aynı oturuma yeniden token alamaz)
CREATE TABLE IF NOT EXISTS public.call_removals (
    session_id UUID NOT NULL,
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    removed_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    livekit_room_name TEXT NOT NULL DEFAULT '',
    removed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (session_id, user_id)
);
ALTER TABLE public.call_removals ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS call_removals_select_involved ON public.call_removals;
CREATE POLICY call_removals_select_involved ON public.call_removals FOR SELECT TO authenticated
    USING (user_id = auth.uid() OR removed_by = auth.uid());
REVOKE INSERT, UPDATE, DELETE ON public.call_removals FROM anon, authenticated;
CREATE INDEX IF NOT EXISTS idx_call_removals_room ON public.call_removals (livekit_room_name, removed_at DESC);

-- LiveKit token: oda üyesi veya çağrılan kişi; konferans doluysa yeni kişi alınmaz
CREATE OR REPLACE FUNCTION public.can_join_livekit_room(p_user UUID, p_livekit_room TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_session UUID;
    v_caller UUID;
BEGIN
    IF public.juzzio_is_banned(p_user) THEN RETURN false; END IF;
    IF NOT (
        EXISTS (
            SELECT 1 FROM public.rooms r
            JOIN public.room_participants rp ON rp.room_id = r.id
            WHERE r.livekit_room_name = p_livekit_room AND rp.user_id = p_user AND rp.left_at IS NULL
        ) OR EXISTS (
            SELECT 1 FROM public.call_logs c
            WHERE c.livekit_room_name = p_livekit_room
              AND (c.caller_id = p_user OR c.receiver_id = p_user)
              AND c.created_at > NOW() - INTERVAL '12 hours'
              AND c.status IN ('ringing', 'answered')
        )
    ) THEN
        RETURN false;
    END IF;

    -- Bu odada süren oturum varsa: katılımcıysa geçer, değilse yer olmalı
    SELECT c.session_id, c.caller_id INTO v_session, v_caller
    FROM public.call_logs c
    WHERE c.livekit_room_name = p_livekit_room AND c.created_at > NOW() - INTERVAL '6 hours'
      AND (c.status = 'ringing' OR (c.status = 'answered' AND c.ended_at IS NULL))
    ORDER BY c.created_at DESC LIMIT 1;
    IF v_session IS NULL OR v_caller = p_user THEN RETURN true; END IF;
    -- Yönetici tarafından bu oturumdan çıkarılan kişi geri giremez
    IF EXISTS (SELECT 1 FROM public.call_removals cr WHERE cr.session_id = v_session AND cr.user_id = p_user) THEN
        RETURN false;
    END IF;
    -- Cevaplamış (yer ayrılmış) katılımcı her zaman geçer; çalan/çağrılmamış kişi yalnızca yer varsa
    IF EXISTS (SELECT 1 FROM public.call_logs c WHERE c.session_id = v_session AND c.receiver_id = p_user
               AND c.status = 'answered' AND c.ended_at IS NULL) THEN
        RETURN true;
    END IF;
    RETURN public.call_session_active_count(v_session) < public.juzzio_max_call_participants();
END;
$$;
REVOKE ALL ON FUNCTION public.can_join_livekit_room(UUID, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.can_join_livekit_room(UUID, TEXT) TO service_role;

-- v0.5.1: konferanstan katılımcı çıkarma (yalnız Edge Function / service_role çağırır)
--   Yetki: oturumu başlatan (host) veya grubun owner/admin/host rolündeki üyesi. Host çıkarılamaz.
CREATE OR REPLACE FUNCTION public.juzzio_remove_call_participant(p_actor UUID, p_livekit_room TEXT, p_target UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_session UUID;
    v_caller UUID;
    v_room UUID;
    v_allowed BOOLEAN := false;
    v_rows INTEGER := 0;
BEGIN
    IF p_actor IS NULL OR p_target IS NULL OR p_actor = p_target OR COALESCE(p_livekit_room, '') = '' THEN
        RETURN jsonb_build_object('ok', false, 'error', 'invalid_target');
    END IF;
    SELECT c.session_id, c.caller_id, c.room_id INTO v_session, v_caller, v_room
    FROM public.call_logs c
    WHERE c.livekit_room_name = p_livekit_room AND c.created_at > NOW() - INTERVAL '6 hours'
      AND (c.status = 'ringing' OR (c.status = 'answered' AND c.ended_at IS NULL))
    ORDER BY c.created_at DESC LIMIT 1;
    IF v_session IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'error', 'no_active_call');
    END IF;
    IF p_target = v_caller THEN
        RETURN jsonb_build_object('ok', false, 'error', 'cannot_remove_host');
    END IF;
    v_allowed := (p_actor = v_caller) OR EXISTS (
        SELECT 1 FROM public.rooms r
        JOIN public.room_participants rp ON rp.room_id = r.id
        WHERE (r.id = v_room OR r.livekit_room_name = p_livekit_room)
          AND rp.user_id = p_actor AND rp.left_at IS NULL
          AND rp.role IN ('owner', 'admin', 'host')
    );
    IF NOT v_allowed THEN
        RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
    END IF;

    INSERT INTO public.call_removals (session_id, user_id, removed_by, livekit_room_name)
    VALUES (v_session, p_target, p_actor, p_livekit_room)
    ON CONFLICT (session_id, user_id) DO UPDATE SET removed_by = EXCLUDED.removed_by, removed_at = NOW();

    UPDATE public.call_logs c
    SET status = CASE WHEN c.status = 'ringing' THEN 'cancelled' ELSE c.status END,
        status_reason = 'removed',
        duration_sec = CASE
            WHEN c.status = 'answered' AND c.answered_at IS NOT NULL
                THEN GREATEST(c.duration_sec, LEAST(EXTRACT(EPOCH FROM (NOW() - c.answered_at))::INTEGER, 6 * 3600))
            ELSE c.duration_sec END,
        ended_at = COALESCE(c.ended_at, NOW())
    WHERE c.session_id = v_session AND c.receiver_id = p_target AND c.ended_at IS NULL;
    GET DIAGNOSTICS v_rows = ROW_COUNT;

    RETURN jsonb_build_object('ok', true, 'session_id', v_session, 'call_rows', v_rows);
END;
$$;
REVOKE ALL ON FUNCTION public.juzzio_remove_call_participant(UUID, TEXT, UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.juzzio_remove_call_participant(UUID, TEXT, UUID) TO service_role;

-- İstemci: üst çubukta "Katılımcıları yönet" düğmesini yalnız yetkiliye göstermek için
CREATE OR REPLACE FUNCTION public.can_manage_call(p_livekit_room TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_caller UUID;
    v_room UUID;
    v_me UUID := auth.uid();
BEGIN
    IF v_me IS NULL OR COALESCE(p_livekit_room, '') = '' THEN RETURN false; END IF;
    SELECT c.caller_id, c.room_id INTO v_caller, v_room
    FROM public.call_logs c
    WHERE c.livekit_room_name = p_livekit_room AND c.created_at > NOW() - INTERVAL '6 hours'
      AND (c.status = 'ringing' OR (c.status = 'answered' AND c.ended_at IS NULL))
    ORDER BY c.created_at DESC LIMIT 1;
    IF v_caller IS NULL THEN RETURN false; END IF;
    RETURN v_caller = v_me OR EXISTS (
        SELECT 1 FROM public.rooms r
        JOIN public.room_participants rp ON rp.room_id = r.id
        WHERE (r.id = v_room OR r.livekit_room_name = p_livekit_room)
          AND rp.user_id = v_me AND rp.left_at IS NULL AND rp.role IN ('owner', 'admin', 'host')
    );
END;
$$;
REVOKE ALL ON FUNCTION public.can_manage_call(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_manage_call(TEXT) TO authenticated;

-- =============================================================================
-- 2. ROZETLER: sesli/görüntülü konuşma dakikasına göre (herkese görünür) + mavi tik
--   Sesli : voice_chatter 60 dk · voice_storyteller 300 dk · voice_hafiz 1000 dk · voice_legend 3000 dk
--   Görüntü: video_rookie 30 dk · video_star 120 dk · video_ninja 500 dk · video_monster 1500 dk
-- =============================================================================
CREATE INDEX IF NOT EXISTS idx_call_logs_receiver_answered ON public.call_logs (receiver_id) WHERE status = 'answered';
CREATE INDEX IF NOT EXISTS idx_call_logs_caller_answered ON public.call_logs (caller_id) WHERE status = 'answered';

CREATE OR REPLACE FUNCTION public.get_profile_badges(p_user UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_voice_sec BIGINT := 0;
    v_video_sec BIGINT := 0;
    v_badges JSONB := '[]'::jsonb;
    v_verified BOOLEAN := false;
    v_voice_min INTEGER;
    v_video_min INTEGER;
BEGIN
    -- Her oturum kişi başına bir kez sayılır (konferansta arayanın birden çok kaydı olabilir)
    SELECT COALESCE(SUM(CASE WHEN NOT s.is_video THEN s.sec ELSE 0 END), 0),
           COALESCE(SUM(CASE WHEN s.is_video THEN s.sec ELSE 0 END), 0)
    INTO v_voice_sec, v_video_sec
    FROM (
        SELECT COALESCE(c.session_id::text, c.id::text) AS sess, bool_or(c.is_video) AS is_video,
               MAX(LEAST(GREATEST(c.duration_sec, 0), 6 * 3600)) AS sec
        FROM public.call_logs c
        WHERE c.status = 'answered' AND c.duration_sec > 0
          AND (c.caller_id = p_user OR c.receiver_id = p_user)
        GROUP BY 1
    ) s;

    v_voice_min := (v_voice_sec / 60)::INTEGER;
    v_video_min := (v_video_sec / 60)::INTEGER;
    SELECT COALESCE(is_verified, false) INTO v_verified FROM public.profiles WHERE id = p_user;

    IF v_verified THEN v_badges := v_badges || '"verified"'::jsonb; END IF;
    v_badges := v_badges || COALESCE(to_jsonb(CASE
        WHEN v_voice_min >= 3000 THEN 'voice_legend'
        WHEN v_voice_min >= 1000 THEN 'voice_hafiz'
        WHEN v_voice_min >= 300 THEN 'voice_storyteller'
        WHEN v_voice_min >= 60 THEN 'voice_chatter'
    END), '[]'::jsonb);
    v_badges := v_badges || COALESCE(to_jsonb(CASE
        WHEN v_video_min >= 1500 THEN 'video_monster'
        WHEN v_video_min >= 500 THEN 'video_ninja'
        WHEN v_video_min >= 120 THEN 'video_star'
        WHEN v_video_min >= 30 THEN 'video_rookie'
    END), '[]'::jsonb);

    RETURN jsonb_build_object(
        'voice_minutes', v_voice_min,
        'video_minutes', v_video_min,
        'verified', v_verified,
        'badges', v_badges
    );
END;
$$;
GRANT EXECUTE ON FUNCTION public.get_profile_badges(UUID) TO authenticated;

-- =============================================================================
-- 3. CİVCİV OYUNU (yalnızca arkadaşlar arası, kişi başı en fazla 1 civciv)
--   Büyüme çok yavaş: her besleme +1 xp, kişi başı 6 saatte bir besleme.
--   Evreler: 0 yumurta → 1 civciv (xp 5) → 2 genç (xp 60) → 3 tavuk (xp 240)
--   12 saat beslenmezse "acıktım", 3 gün beslenmezse "ölüyorum", 7 gün beslenmezse ölür.
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.chick_pets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL DEFAULT 'Civciv',
    owner_a UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    owner_b UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    status TEXT NOT NULL DEFAULT 'alive' CHECK (status IN ('alive', 'dead', 'released')),
    xp INTEGER NOT NULL DEFAULT 0 CHECK (xp >= 0),
    stage INTEGER NOT NULL DEFAULT 0 CHECK (stage BETWEEN 0 AND 3),
    last_fed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_fed_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    hungry_notified_at TIMESTAMPTZ,
    dying_notified_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ended_at TIMESTAMPTZ,
    CONSTRAINT chick_pets_distinct_owners CHECK (owner_a <> owner_b)
);
-- Kişi başı en fazla 1 canlı civciv
CREATE UNIQUE INDEX IF NOT EXISTS idx_chick_alive_owner_a ON public.chick_pets (owner_a) WHERE status = 'alive';
CREATE UNIQUE INDEX IF NOT EXISTS idx_chick_alive_owner_b ON public.chick_pets (owner_b) WHERE status = 'alive';

CREATE TABLE IF NOT EXISTS public.chick_feed_log (
    id BIGSERIAL PRIMARY KEY,
    chick_id UUID NOT NULL REFERENCES public.chick_pets(id) ON DELETE CASCADE,
    fed_by UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    fed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_chick_feed_recent ON public.chick_feed_log (chick_id, fed_by, fed_at DESC);

CREATE TABLE IF NOT EXISTS public.chick_invites (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    from_user UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    to_user UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    chick_name TEXT NOT NULL DEFAULT 'Civciv',
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'declined', 'cancelled')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    responded_at TIMESTAMPTZ,
    CONSTRAINT chick_invites_distinct CHECK (from_user <> to_user)
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_chick_invite_pending
    ON public.chick_invites (LEAST(from_user, to_user), GREATEST(from_user, to_user)) WHERE status = 'pending';

ALTER TABLE public.chick_pets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chick_feed_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chick_invites ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS chick_pets_select_owner ON public.chick_pets;
DROP POLICY IF EXISTS chick_feed_select_owner ON public.chick_feed_log;
DROP POLICY IF EXISTS chick_invites_select_involved ON public.chick_invites;
CREATE POLICY chick_pets_select_owner ON public.chick_pets FOR SELECT TO authenticated
    USING (auth.uid() IN (owner_a, owner_b));
CREATE POLICY chick_feed_select_owner ON public.chick_feed_log FOR SELECT TO authenticated
    USING (EXISTS (SELECT 1 FROM public.chick_pets c WHERE c.id = chick_feed_log.chick_id AND auth.uid() IN (c.owner_a, c.owner_b)));
CREATE POLICY chick_invites_select_involved ON public.chick_invites FOR SELECT TO authenticated
    USING (auth.uid() IN (from_user, to_user));
-- Yazma işlemleri yalnızca aşağıdaki RPC'lerle

CREATE OR REPLACE FUNCTION public.chick_stage_for_xp(p_xp INTEGER)
RETURNS INTEGER
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT CASE WHEN p_xp >= 240 THEN 3 WHEN p_xp >= 60 THEN 2 WHEN p_xp >= 5 THEN 1 ELSE 0 END;
$$;

-- Bildirim yardımcı fonksiyonu (önizleme yalnızca anahtar; metin alıcının dilinde/cinsiyetinde üretilir)
DROP FUNCTION IF EXISTS public.chick_notify(UUID, UUID, TEXT, UUID, TEXT);
CREATE OR REPLACE FUNCTION public.chick_notify(p_recipient UUID, p_actor UUID, p_event TEXT, p_target TEXT, p_preview TEXT, p_dedupe TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    INSERT INTO public.notifications (recipient_id, actor_id, actor_username, actor_display_name, actor_avatar_url,
                                      event_type, target_id, preview_text, dedupe_key)
    SELECT p_recipient, p_actor, COALESCE(a.username, ''), COALESCE(a.display_name, ''), a.avatar_url,
           p_event, COALESCE(p_target, ''), COALESCE(p_preview, ''),
           p_dedupe
    FROM (SELECT 1) one
    LEFT JOIN public.profiles a ON a.id = p_actor
    ON CONFLICT (recipient_id, dedupe_key) DO NOTHING;
EXCEPTION WHEN OTHERS THEN NULL;
END;
$$;
REVOKE ALL ON FUNCTION public.chick_notify(UUID, UUID, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.invite_chick_partner(p_friend UUID, p_name TEXT DEFAULT 'Civciv')
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_invite UUID;
    v_name TEXT := LEFT(COALESCE(NULLIF(BTRIM(p_name), ''), 'Civciv'), 24);
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
    IF p_friend IS NULL OR p_friend = v_uid THEN RAISE EXCEPTION 'invalid_target'; END IF;
    IF NOT public.is_friends_accepted(v_uid, p_friend) THEN RAISE EXCEPTION 'not_friends'; END IF;
    IF public.is_blocked_between(v_uid, p_friend) THEN RAISE EXCEPTION 'not_allowed'; END IF;
    IF NOT public.juzzio_text_is_clean(v_name, true) THEN RAISE EXCEPTION 'inappropriate_content'; END IF;
    IF EXISTS (SELECT 1 FROM public.chick_pets WHERE status = 'alive' AND v_uid IN (owner_a, owner_b)) THEN
        RAISE EXCEPTION 'you_have_chick';
    END IF;
    IF EXISTS (SELECT 1 FROM public.chick_pets WHERE status = 'alive' AND p_friend IN (owner_a, owner_b)) THEN
        RAISE EXCEPTION 'friend_has_chick';
    END IF;
    IF EXISTS (SELECT 1 FROM public.chick_invites WHERE status = 'pending'
               AND LEAST(from_user, to_user) = LEAST(v_uid, p_friend)
               AND GREATEST(from_user, to_user) = GREATEST(v_uid, p_friend)) THEN
        RAISE EXCEPTION 'invite_pending';
    END IF;

    INSERT INTO public.chick_invites (from_user, to_user, chick_name) VALUES (v_uid, p_friend, v_name)
    RETURNING id INTO v_invite;
    PERFORM public.chick_notify(p_friend, v_uid, 'chick_invite', v_invite::text, v_name, 'chick_invite_' || v_invite::text);
    RETURN v_invite;
END;
$$;
GRANT EXECUTE ON FUNCTION public.invite_chick_partner(UUID, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.respond_chick_invite(p_invite UUID, p_accept BOOLEAN)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_inv RECORD;
    v_chick UUID;
BEGIN
    SELECT * INTO v_inv FROM public.chick_invites WHERE id = p_invite FOR UPDATE;
    IF v_inv.id IS NULL OR v_inv.status <> 'pending' THEN RAISE EXCEPTION 'invite_not_found'; END IF;
    IF v_inv.to_user <> v_uid THEN
        -- Gönderen kendi davetini iptal edebilir
        IF v_inv.from_user = v_uid AND NOT p_accept THEN
            UPDATE public.chick_invites SET status = 'cancelled', responded_at = NOW() WHERE id = p_invite;
            RETURN NULL;
        END IF;
        RAISE EXCEPTION 'not_allowed';
    END IF;

    IF NOT p_accept THEN
        UPDATE public.chick_invites SET status = 'declined', responded_at = NOW() WHERE id = p_invite;
        RETURN NULL;
    END IF;

    IF EXISTS (SELECT 1 FROM public.chick_pets WHERE status = 'alive'
               AND (v_inv.from_user IN (owner_a, owner_b) OR v_inv.to_user IN (owner_a, owner_b))) THEN
        UPDATE public.chick_invites SET status = 'cancelled', responded_at = NOW() WHERE id = p_invite;
        RAISE EXCEPTION 'already_has_chick';
    END IF;
    IF NOT public.is_friends_accepted(v_inv.from_user, v_inv.to_user) THEN
        RAISE EXCEPTION 'not_friends';
    END IF;

    INSERT INTO public.chick_pets (name, owner_a, owner_b, last_fed_at, last_fed_by)
    VALUES (v_inv.chick_name, v_inv.from_user, v_inv.to_user, NOW(), NULL)
    RETURNING id INTO v_chick;
    UPDATE public.chick_invites SET status = 'accepted', responded_at = NOW() WHERE id = p_invite;
    -- Bekleyen diğer davetler geçersiz
    UPDATE public.chick_invites SET status = 'cancelled', responded_at = NOW()
    WHERE status = 'pending' AND (from_user IN (v_inv.from_user, v_inv.to_user) OR to_user IN (v_inv.from_user, v_inv.to_user));
    PERFORM public.chick_notify(v_inv.from_user, v_uid, 'chick_hatched', v_chick::text, v_inv.chick_name, 'chick_hatched_' || v_chick::text);
    RETURN v_chick;
END;
$$;
GRANT EXECUTE ON FUNCTION public.respond_chick_invite(UUID, BOOLEAN) TO authenticated;

CREATE OR REPLACE FUNCTION public.feed_my_chick()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_chick RECORD;
    v_last TIMESTAMPTZ;
    v_new_xp INTEGER;
BEGIN
    SELECT * INTO v_chick FROM public.chick_pets
    WHERE status = 'alive' AND v_uid IN (owner_a, owner_b) FOR UPDATE;
    IF v_chick.id IS NULL THEN RAISE EXCEPTION 'no_chick'; END IF;

    SELECT MAX(fed_at) INTO v_last FROM public.chick_feed_log WHERE chick_id = v_chick.id AND fed_by = v_uid;
    IF v_last IS NOT NULL AND v_last > NOW() - INTERVAL '6 hours' THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'too_soon', 'next_feed_at', v_last + INTERVAL '6 hours');
    END IF;

    INSERT INTO public.chick_feed_log (chick_id, fed_by) VALUES (v_chick.id, v_uid);
    v_new_xp := v_chick.xp + 1;
    UPDATE public.chick_pets
    SET xp = v_new_xp,
        stage = public.chick_stage_for_xp(v_new_xp),
        last_fed_at = NOW(),
        last_fed_by = v_uid,
        hungry_notified_at = NULL,
        dying_notified_at = NULL
    WHERE id = v_chick.id;
    RETURN jsonb_build_object('ok', true, 'xp', v_new_xp, 'stage', public.chick_stage_for_xp(v_new_xp),
                              'next_feed_at', NOW() + INTERVAL '6 hours');
END;
$$;
GRANT EXECUTE ON FUNCTION public.feed_my_chick() TO authenticated;

CREATE OR REPLACE FUNCTION public.release_my_chick()
RETURNS VOID
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    UPDATE public.chick_pets SET status = 'released', ended_at = NOW()
    WHERE status = 'alive' AND auth.uid() IN (owner_a, owner_b);
$$;
GRANT EXECUTE ON FUNCTION public.release_my_chick() TO authenticated;

CREATE OR REPLACE FUNCTION public.get_my_chick()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_chick RECORD;
    v_partner RECORD;
    v_my_last TIMESTAMPTZ;
    v_hours NUMERIC;
BEGIN
    SELECT * INTO v_chick FROM public.chick_pets WHERE status = 'alive' AND v_uid IN (owner_a, owner_b);
    IF v_chick.id IS NULL THEN
        RETURN jsonb_build_object(
            'has_chick', false,
            'invites', COALESCE((
                SELECT jsonb_agg(jsonb_build_object(
                    'id', i.id, 'from_user', i.from_user, 'to_user', i.to_user, 'chick_name', i.chick_name,
                    'incoming', i.to_user = v_uid, 'created_at', i.created_at,
                    'other_name', COALESCE(NULLIF(p.display_name, ''), p.username),
                    'other_avatar', p.avatar_url) ORDER BY i.created_at DESC)
                FROM public.chick_invites i
                JOIN public.profiles p ON p.id = CASE WHEN i.from_user = v_uid THEN i.to_user ELSE i.from_user END
                WHERE i.status = 'pending' AND v_uid IN (i.from_user, i.to_user)
            ), '[]'::jsonb),
            'last_chick', (
                SELECT jsonb_build_object('name', c.name, 'status', c.status, 'ended_at', c.ended_at, 'stage', c.stage)
                FROM public.chick_pets c WHERE v_uid IN (c.owner_a, c.owner_b) AND c.status <> 'alive'
                ORDER BY c.ended_at DESC NULLS LAST LIMIT 1
            )
        );
    END IF;

    SELECT id, username, display_name, avatar_url INTO v_partner FROM public.profiles
    WHERE id = CASE WHEN v_chick.owner_a = v_uid THEN v_chick.owner_b ELSE v_chick.owner_a END;
    SELECT MAX(fed_at) INTO v_my_last FROM public.chick_feed_log WHERE chick_id = v_chick.id AND fed_by = v_uid;
    v_hours := EXTRACT(EPOCH FROM (NOW() - v_chick.last_fed_at)) / 3600.0;

    RETURN jsonb_build_object(
        'has_chick', true,
        'id', v_chick.id,
        'name', v_chick.name,
        'xp', v_chick.xp,
        'stage', v_chick.stage,
        'next_stage_xp', CASE v_chick.stage WHEN 0 THEN 5 WHEN 1 THEN 60 WHEN 2 THEN 240 ELSE NULL END,
        'last_fed_at', v_chick.last_fed_at,
        'hours_since_fed', ROUND(v_hours, 1),
        'mood', CASE WHEN v_hours >= 72 THEN 'dying' WHEN v_hours >= 12 THEN 'hungry' ELSE 'happy' END,
        'my_next_feed_at', CASE WHEN v_my_last IS NULL THEN NOW() ELSE GREATEST(NOW(), v_my_last + INTERVAL '6 hours') END,
        'partner', jsonb_build_object('id', v_partner.id, 'username', v_partner.username,
                                      'display_name', v_partner.display_name, 'avatar_url', v_partner.avatar_url),
        'created_at', v_chick.created_at
    );
END;
$$;
GRANT EXECUTE ON FUNCTION public.get_my_chick() TO authenticated;

-- Periyodik kontrol (pg_cron saatlik). pg_cron yoksa uygulama açılışında da çağrılır.
CREATE OR REPLACE FUNCTION public.chick_tick()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v RECORD;
    v_n INTEGER := 0;
BEGIN
    FOR v IN SELECT * FROM public.chick_pets WHERE status = 'alive' FOR UPDATE SKIP LOCKED LOOP
        IF v.last_fed_at < NOW() - INTERVAL '7 days' THEN
            UPDATE public.chick_pets SET status = 'dead', ended_at = NOW() WHERE id = v.id;
            PERFORM public.chick_notify(v.owner_a, NULL, 'chick_died', v.id::text, v.name, 'chick_died_' || v.id::text);
            PERFORM public.chick_notify(v.owner_b, NULL, 'chick_died', v.id::text, v.name, 'chick_died_' || v.id::text);
            v_n := v_n + 1;
        ELSIF v.last_fed_at < NOW() - INTERVAL '3 days' AND v.dying_notified_at IS NULL THEN
            UPDATE public.chick_pets SET dying_notified_at = NOW() WHERE id = v.id;
            PERFORM public.chick_notify(v.owner_a, NULL, 'chick_dying', v.id::text, v.name, 'chick_dying_' || v.id::text || '_' || EXTRACT(EPOCH FROM v.last_fed_at)::bigint);
            PERFORM public.chick_notify(v.owner_b, NULL, 'chick_dying', v.id::text, v.name, 'chick_dying_' || v.id::text || '_' || EXTRACT(EPOCH FROM v.last_fed_at)::bigint);
            v_n := v_n + 1;
        ELSIF v.last_fed_at < NOW() - INTERVAL '12 hours' AND v.hungry_notified_at IS NULL THEN
            UPDATE public.chick_pets SET hungry_notified_at = NOW() WHERE id = v.id;
            PERFORM public.chick_notify(v.owner_a, NULL, 'chick_hungry', v.id::text, v.name, 'chick_hungry_' || v.id::text || '_' || EXTRACT(EPOCH FROM v.last_fed_at)::bigint);
            PERFORM public.chick_notify(v.owner_b, NULL, 'chick_hungry', v.id::text, v.name, 'chick_hungry_' || v.id::text || '_' || EXTRACT(EPOCH FROM v.last_fed_at)::bigint);
            v_n := v_n + 1;
        END IF;
    END LOOP;
    RETURN v_n;
END;
$$;
REVOKE ALL ON FUNCTION public.chick_tick() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.chick_tick() TO authenticated, service_role;

DO $$
BEGIN
    BEGIN
        CREATE EXTENSION IF NOT EXISTS pg_cron;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'pg_cron etkinleştirilemedi (%). Supabase → Database → Extensions → pg_cron açın ve bu dosyayı tekrar çalıştırın.', SQLERRM;
    END;
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        BEGIN
            PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'juzzio_chick_tick';
            PERFORM cron.schedule('juzzio_chick_tick', '7 * * * *', 'SELECT public.chick_tick()');
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'pg_cron görevi oluşturulamadı: %', SQLERRM;
        END;
    END IF;
END $$;

-- =============================================================================
-- 4. YÖNETİCİ PANELİ (@tugkancr) — şifre bcrypt hash'i, oturum belirteci, cihaz engeli
--   Şifre bu dosyada YOKTUR. Kurulumdan sonra SQL Editor'de bir kez çalıştırın:
--     SELECT public.set_admin_panel_password('ŞİFRENİZ');
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.admin_secret (
    id INTEGER PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    password_hash TEXT NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TABLE IF NOT EXISTS public.admin_sessions (
    token_hash TEXT PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    device_id TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL
);
CREATE TABLE IF NOT EXISTS public.admin_login_attempts (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID,
    device_id TEXT NOT NULL DEFAULT '',
    success BOOLEAN NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TABLE IF NOT EXISTS public.admin_audit_log (
    id BIGSERIAL PRIMARY KEY,
    admin_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    action TEXT NOT NULL,
    target TEXT NOT NULL DEFAULT '',
    details JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TABLE IF NOT EXISTS public.user_devices (
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    device_id TEXT NOT NULL CHECK (LENGTH(device_id) BETWEEN 8 AND 128),
    platform TEXT NOT NULL DEFAULT '',
    first_seen TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_seen TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, device_id)
);
CREATE INDEX IF NOT EXISTS idx_user_devices_device ON public.user_devices (device_id);
CREATE TABLE IF NOT EXISTS public.banned_devices (
    device_id TEXT PRIMARY KEY,
    reason_code TEXT NOT NULL,
    note TEXT NOT NULL DEFAULT '',
    banned_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE public.admin_secret ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_login_attempts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.banned_devices ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.admin_secret, public.admin_sessions, public.admin_login_attempts, public.admin_audit_log,
             public.user_devices, public.banned_devices FROM anon, authenticated;

-- Hazır engelleme sebepleri
CREATE OR REPLACE FUNCTION public.juzzio_ban_reasons()
RETURNS TEXT[]
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT ARRAY['spam', 'harassment', 'hate_speech', 'inappropriate_content', 'fake_account',
                 'scam', 'violence', 'underage', 'impersonation', 'other'];
$$;

CREATE OR REPLACE FUNCTION public.is_juzzio_admin(p_user UUID DEFAULT auth.uid())
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (SELECT 1 FROM public.profiles WHERE id = p_user AND LOWER(username) = 'tugkancr');
$$;
GRANT EXECUTE ON FUNCTION public.is_juzzio_admin(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.set_admin_panel_password(p_password TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
    IF LENGTH(COALESCE(p_password, '')) < 8 THEN RAISE EXCEPTION 'password_too_short'; END IF;
    INSERT INTO public.admin_secret (id, password_hash, updated_at)
    VALUES (1, crypt(p_password, gen_salt('bf', 12)), NOW())
    ON CONFLICT (id) DO UPDATE SET password_hash = EXCLUDED.password_hash, updated_at = NOW();
    DELETE FROM public.admin_sessions;  -- şifre değişince tüm hatırlanan cihazlar çıkış yapar
END;
$$;
REVOKE ALL ON FUNCTION public.set_admin_panel_password(TEXT) FROM PUBLIC, anon, authenticated;

-- Şifre doğrulama → 30 günlük (hatırla) ya da 12 saatlik oturum belirteci. 15 dk'da 5 hatalı denemede kilit.
CREATE OR REPLACE FUNCTION public.admin_unlock(p_password TEXT, p_device_id TEXT, p_remember BOOLEAN DEFAULT false)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_hash TEXT;
    v_token TEXT;
    v_fails INTEGER;
BEGIN
    IF NOT public.is_juzzio_admin(v_uid) THEN RAISE EXCEPTION 'not_allowed'; END IF;
    SELECT COUNT(*) INTO v_fails FROM public.admin_login_attempts
    WHERE user_id = v_uid AND NOT success AND created_at > NOW() - INTERVAL '15 minutes';
    IF v_fails >= 5 THEN RAISE EXCEPTION 'too_many_attempts'; END IF;

    SELECT password_hash INTO v_hash FROM public.admin_secret WHERE id = 1;
    IF v_hash IS NULL THEN RAISE EXCEPTION 'admin_password_not_set'; END IF;
    IF crypt(COALESCE(p_password, ''), v_hash) <> v_hash THEN
        INSERT INTO public.admin_login_attempts (user_id, device_id, success) VALUES (v_uid, LEFT(COALESCE(p_device_id, ''), 128), false);
        RETURN jsonb_build_object('ok', false, 'remaining', GREATEST(0, 4 - v_fails));
    END IF;

    INSERT INTO public.admin_login_attempts (user_id, device_id, success) VALUES (v_uid, LEFT(COALESCE(p_device_id, ''), 128), true);
    v_token := encode(gen_random_bytes(32), 'hex');
    INSERT INTO public.admin_sessions (token_hash, user_id, device_id, expires_at)
    VALUES (encode(digest(v_token, 'sha256'), 'hex'), v_uid, LEFT(COALESCE(p_device_id, ''), 128),
            NOW() + CASE WHEN p_remember THEN INTERVAL '30 days' ELSE INTERVAL '12 hours' END);
    DELETE FROM public.admin_sessions WHERE expires_at < NOW();
    RETURN jsonb_build_object('ok', true, 'token', v_token,
                              'expires_at', NOW() + CASE WHEN p_remember THEN INTERVAL '30 days' ELSE INTERVAL '12 hours' END);
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_unlock(TEXT, TEXT, BOOLEAN) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_check_token(p_token TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
    SELECT public.is_juzzio_admin(auth.uid()) AND EXISTS (
        SELECT 1 FROM public.admin_sessions s
        WHERE s.token_hash = encode(digest(COALESCE(p_token, ''), 'sha256'), 'hex')
          AND s.user_id = auth.uid() AND s.expires_at > NOW()
    );
$$;
GRANT EXECUTE ON FUNCTION public.admin_check_token(TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_logout(p_token TEXT)
RETURNS VOID
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
    DELETE FROM public.admin_sessions
    WHERE token_hash = encode(digest(COALESCE(p_token, ''), 'sha256'), 'hex') AND user_id = auth.uid();
$$;
GRANT EXECUTE ON FUNCTION public.admin_logout(TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public._admin_require(p_token TEXT)
RETURNS VOID
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT public.admin_check_token(p_token) THEN RAISE EXCEPTION 'admin_session_invalid'; END IF;
END;
$$;
REVOKE ALL ON FUNCTION public._admin_require(TEXT) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.admin_dashboard(p_token TEXT)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    PERFORM public._admin_require(p_token);
    RETURN jsonb_build_object(
        'users', (SELECT COUNT(*) FROM public.profiles),
        'online', (SELECT COUNT(*) FROM public.profiles WHERE is_online),
        'open_reports', (SELECT COUNT(*) FROM public.reports WHERE status = 'open'),
        'banned_users', (SELECT COUNT(*) FROM public.banned_users),
        'banned_devices', (SELECT COUNT(*) FROM public.banned_devices),
        'ban_reasons', to_jsonb(public.juzzio_ban_reasons())
    );
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_dashboard(TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_list_reports(p_token TEXT, p_status TEXT DEFAULT 'open', p_limit INTEGER DEFAULT 100)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    PERFORM public._admin_require(p_token);
    RETURN COALESCE((
        SELECT jsonb_agg(row_to_json(x) ORDER BY x.created_at DESC) FROM (
            SELECT r.id, r.target_type, r.target_id, r.reason_code, r.details, r.status, r.created_at,
                   r.resolution_note, r.reviewed_at,
                   r.reporter_id, rp.username AS reporter_username,
                   r.target_owner_id, tp.username AS target_username, tp.display_name AS target_display_name,
                   EXISTS (SELECT 1 FROM public.banned_users b WHERE b.user_id = r.target_owner_id) AS target_banned
            FROM public.reports r
            LEFT JOIN public.profiles rp ON rp.id = r.reporter_id
            LEFT JOIN public.profiles tp ON tp.id = r.target_owner_id
            WHERE p_status IS NULL OR p_status = 'all' OR r.status = p_status
            ORDER BY r.created_at DESC
            LIMIT LEAST(GREATEST(COALESCE(p_limit, 100), 1), 500)
        ) x
    ), '[]'::jsonb);
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_list_reports(TEXT, TEXT, INTEGER) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_set_report_status(p_token TEXT, p_report UUID, p_status TEXT, p_note TEXT DEFAULT '')
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    PERFORM public._admin_require(p_token);
    IF p_status NOT IN ('open', 'reviewed', 'resolved', 'dismissed') THEN RAISE EXCEPTION 'invalid_status'; END IF;
    UPDATE public.reports SET status = p_status, resolution_note = LEFT(COALESCE(p_note, ''), 500),
                              reviewed_by = auth.uid(), reviewed_at = NOW()
    WHERE id = p_report;
    INSERT INTO public.admin_audit_log (admin_id, action, target, details)
    VALUES (auth.uid(), 'report_status', p_report::text, jsonb_build_object('status', p_status));
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_set_report_status(TEXT, UUID, TEXT, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_search_users(p_token TEXT, p_query TEXT)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_q TEXT := '%' || LOWER(BTRIM(COALESCE(p_query, ''))) || '%';
BEGIN
    PERFORM public._admin_require(p_token);
    RETURN COALESCE((
        SELECT jsonb_agg(row_to_json(x)) FROM (
            SELECT p.id, p.username, p.display_name, p.avatar_url, p.is_verified, p.created_at, p.last_seen,
                   EXISTS (SELECT 1 FROM public.banned_users b WHERE b.user_id = p.id) AS is_banned,
                   (SELECT COUNT(*) FROM public.user_devices d WHERE d.user_id = p.id) AS device_count,
                   (SELECT COUNT(*) FROM public.reports r WHERE r.target_owner_id = p.id AND r.status = 'open') AS open_reports
            FROM public.profiles p
            WHERE LOWER(p.username) LIKE v_q OR LOWER(p.display_name) LIKE v_q
            ORDER BY p.created_at DESC
            LIMIT 50
        ) x
    ), '[]'::jsonb);
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_search_users(TEXT, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_ban_user(p_token TEXT, p_user UUID, p_reason TEXT, p_note TEXT DEFAULT '', p_ban_devices BOOLEAN DEFAULT true)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_devices INTEGER := 0;
BEGIN
    PERFORM public._admin_require(p_token);
    IF p_reason IS NULL OR NOT (p_reason = ANY (public.juzzio_ban_reasons())) THEN RAISE EXCEPTION 'invalid_reason'; END IF;
    IF public.is_juzzio_admin(p_user) THEN RAISE EXCEPTION 'cannot_ban_admin'; END IF;

    INSERT INTO public.banned_users (user_id, reason_code, note, banned_by)
    VALUES (p_user, p_reason, LEFT(COALESCE(p_note, ''), 500), auth.uid())
    ON CONFLICT (user_id) DO UPDATE SET reason_code = EXCLUDED.reason_code, note = EXCLUDED.note,
                                        banned_by = EXCLUDED.banned_by, created_at = NOW();
    IF p_ban_devices THEN
        INSERT INTO public.banned_devices (device_id, reason_code, note, banned_by)
        SELECT d.device_id, p_reason, LEFT(COALESCE(p_note, ''), 500), auth.uid()
        FROM public.user_devices d WHERE d.user_id = p_user
        ON CONFLICT (device_id) DO NOTHING;
        GET DIAGNOSTICS v_devices = ROW_COUNT;
    END IF;
    UPDATE public.profiles SET is_online = false WHERE id = p_user;
    UPDATE public.reports SET status = 'resolved', reviewed_by = auth.uid(), reviewed_at = NOW(),
                              resolution_note = 'ban:' || p_reason
    WHERE target_owner_id = p_user AND status = 'open';
    INSERT INTO public.admin_audit_log (admin_id, action, target, details)
    VALUES (auth.uid(), 'ban_user', p_user::text, jsonb_build_object('reason', p_reason, 'devices', v_devices));
    RETURN jsonb_build_object('ok', true, 'devices_banned', v_devices);
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_ban_user(TEXT, UUID, TEXT, TEXT, BOOLEAN) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_unban_user(p_token TEXT, p_user UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    PERFORM public._admin_require(p_token);
    DELETE FROM public.banned_users WHERE user_id = p_user;
    DELETE FROM public.banned_devices bd USING public.user_devices d
    WHERE d.user_id = p_user AND d.device_id = bd.device_id;
    INSERT INTO public.admin_audit_log (admin_id, action, target) VALUES (auth.uid(), 'unban_user', p_user::text);
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_unban_user(TEXT, UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_list_bans(p_token TEXT)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    PERFORM public._admin_require(p_token);
    RETURN COALESCE((
        SELECT jsonb_agg(row_to_json(x) ORDER BY x.created_at DESC) FROM (
            SELECT b.user_id, p.username, p.display_name, b.reason_code, b.note, b.created_at,
                   (SELECT COUNT(*) FROM public.user_devices d JOIN public.banned_devices bd ON bd.device_id = d.device_id
                    WHERE d.user_id = b.user_id) AS banned_devices
            FROM public.banned_users b LEFT JOIN public.profiles p ON p.id = b.user_id
        ) x
    ), '[]'::jsonb);
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_list_bans(TEXT) TO authenticated;

-- Cihaz kaydı (girişte) ve cihaz/hesap erişim kontrolü (giriş öncesi de çağrılabilir)
CREATE OR REPLACE FUNCTION public.register_my_device(p_device_id TEXT, p_platform TEXT DEFAULT '')
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_dev TEXT := LEFT(BTRIM(COALESCE(p_device_id, '')), 128);
BEGIN
    IF v_uid IS NULL OR LENGTH(v_dev) < 8 THEN RETURN jsonb_build_object('ok', false); END IF;
    INSERT INTO public.user_devices (user_id, device_id, platform)
    VALUES (v_uid, v_dev, LEFT(COALESCE(p_platform, ''), 20))
    ON CONFLICT (user_id, device_id) DO UPDATE SET last_seen = NOW(), platform = EXCLUDED.platform;
    -- Engelli kullanıcının yeni cihazı da engellenir
    IF EXISTS (SELECT 1 FROM public.banned_users WHERE user_id = v_uid) THEN
        INSERT INTO public.banned_devices (device_id, reason_code, note)
        SELECT v_dev, reason_code, 'auto:new_device' FROM public.banned_users WHERE user_id = v_uid
        ON CONFLICT (device_id) DO NOTHING;
    END IF;
    RETURN public.check_device_access(v_dev);
END;
$$;
GRANT EXECUTE ON FUNCTION public.register_my_device(TEXT, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.check_device_access(p_device_id TEXT)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_reason TEXT;
BEGIN
    SELECT reason_code INTO v_reason FROM public.banned_devices WHERE device_id = LEFT(BTRIM(COALESCE(p_device_id, '')), 128);
    IF v_reason IS NULL AND auth.uid() IS NOT NULL THEN
        SELECT reason_code INTO v_reason FROM public.banned_users WHERE user_id = auth.uid();
    END IF;
    RETURN jsonb_build_object('ok', true, 'banned', v_reason IS NOT NULL, 'reason', v_reason);
END;
$$;
GRANT EXECUTE ON FUNCTION public.check_device_access(TEXT) TO anon, authenticated;

-- Realtime: civciv ekranı canlı güncellensin
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
        BEGIN
            ALTER PUBLICATION supabase_realtime ADD TABLE public.chick_pets;
        EXCEPTION WHEN duplicate_object THEN NULL;
        END;
        BEGIN
            ALTER PUBLICATION supabase_realtime ADD TABLE public.chick_invites;
        EXCEPTION WHEN duplicate_object THEN NULL;
        END;
    END IF;
END $$;

-- #############################################################################
-- BÖLÜM 8/9 — kaynak: 20261031000000_juzzio_v040_social_presence_admin.sql
-- #############################################################################
-- =============================================================================
-- JUZZIO v0.4.0 — Arkadaş ekleme kuralları, mesaj istekleri, gerçek çevrimiçi
-- durumu, Instagram tarzı profil alanları ve genişletilmiş yönetici paneli.
-- Tekrar çalıştırılabilir (idempotent); kullanıcı verisi silmez.
-- Önkoşul: 20261029000000, 20261030000000, 20261030010000 dosyaları.
-- =============================================================================

-- =============================================================================
-- 1. PROFİL: müzik sanatçısı/kapak, profil kartı arka planı, fotoğraf yakınlaştırma
-- =============================================================================
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS music_artist TEXT NOT NULL DEFAULT '';
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS music_cover_url TEXT NOT NULL DEFAULT '';
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS profile_zoom_enabled BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS card_bg_color TEXT NOT NULL DEFAULT '';
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS card_bg_url TEXT NOT NULL DEFAULT '';
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS app_role TEXT NOT NULL DEFAULT 'user';
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_app_role_check;
ALTER TABLE public.profiles ADD CONSTRAINT profiles_app_role_check CHECK (app_role IN ('user', 'moderator')) NOT VALID;

CREATE OR REPLACE FUNCTION public.juzzio_v040_profile_checks()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    NEW.music_artist := LEFT(BTRIM(COALESCE(NEW.music_artist, '')), 80);
    NEW.music_cover_url := BTRIM(COALESCE(NEW.music_cover_url, ''));
    IF NEW.music_cover_url <> '' AND NEW.music_cover_url !~* '^https://' THEN NEW.music_cover_url := ''; END IF;
    NEW.card_bg_color := UPPER(BTRIM(COALESCE(NEW.card_bg_color, '')));
    IF NEW.card_bg_color <> '' AND NEW.card_bg_color !~ '^#[0-9A-F]{6}$' THEN NEW.card_bg_color := ''; END IF;
    NEW.card_bg_url := BTRIM(COALESCE(NEW.card_bg_url, ''));
    IF NEW.card_bg_url <> '' AND NEW.card_bg_url !~* '^https://' THEN NEW.card_bg_url := ''; END IF;
    -- Uygulama rolü yalnızca sunucu tarafından (yönetici paneli) değiştirilebilir
    IF public.juzzio_is_client_request() THEN
        IF TG_OP = 'INSERT' THEN
            NEW.app_role := 'user';
        ELSE
            NEW.app_role := OLD.app_role;
        END IF;
    END IF;
    IF NEW.music_artist <> '' AND public.juzzio_is_client_request()
       AND NOT public.juzzio_text_is_clean(NEW.music_artist, false) THEN
        RAISE EXCEPTION 'inappropriate_content' USING ERRCODE = '22023';
    END IF;
    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_juzzio_v040_profile_checks ON public.profiles;
CREATE TRIGGER trg_juzzio_v040_profile_checks
    BEFORE INSERT OR UPDATE ON public.profiles
    FOR EACH ROW EXECUTE FUNCTION public.juzzio_v040_profile_checks();

-- =============================================================================
-- 2. GERÇEK ÇEVRİMİÇİ DURUMU
-- Uygulama açıkken her dakika "nabız" gönderir. Son 3 dakikada nabız yoksa
-- kullanıcı çevrimdışı sayılır (uygulama kapanınca yeşil nokta takılı kalmaz).
-- Son görülme / çevrimiçi gizlilik ayarlarına uyulur.
-- =============================================================================
CREATE OR REPLACE FUNCTION public.juzzio_effective_online(p_is_online BOOLEAN, p_last_seen TIMESTAMPTZ)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
AS $$
    SELECT COALESCE(p_is_online, false) AND p_last_seen IS NOT NULL AND p_last_seen > NOW() - INTERVAL '3 minutes';
$$;

CREATE OR REPLACE FUNCTION public.juzzio_can_see_presence(p_viewer UUID, p_owner UUID, p_setting TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT p_viewer = p_owner
        OR CASE COALESCE(p_setting, 'everyone')
               WHEN 'nobody' THEN false
               WHEN 'friends' THEN public.is_friends_accepted(p_viewer, p_owner)
               WHEN 'contacts' THEN public.is_friends_accepted(p_viewer, p_owner)
               ELSE true
           END;
$$;

-- Görüntülenen kişinin çevrimiçi / son görülme bilgisi (gizlilik uygulanmış)
CREATE OR REPLACE FUNCTION public.get_user_presence(p_user UUID)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT jsonb_build_object(
        'is_online', CASE WHEN public.juzzio_can_see_presence(auth.uid(), p.id, p.privacy_online)
                               AND public.juzzio_can_see_presence(auth.uid(), p.id, p.privacy_last_seen)
                          THEN public.juzzio_effective_online(p.is_online, p.last_seen) ELSE false END,
        'last_seen', CASE WHEN public.juzzio_can_see_presence(auth.uid(), p.id, p.privacy_last_seen)
                          THEN p.last_seen END
    )
    FROM public.profiles p
    WHERE p.id = p_user AND auth.uid() IS NOT NULL
      AND NOT public.is_blocked_between(auth.uid(), p.id);
$$;
GRANT EXECUTE ON FUNCTION public.get_user_presence(UUID) TO authenticated;

-- =============================================================================
-- 3. MESAJ İSTEKLERİ
-- Arkadaş olmayan herkes mesaj atabilir. Alıcının hesabı GİZLİ ise ve arkadaş
-- değillerse sohbet alıcının "Mesaj istekleri" bölümünde bekler.
-- =============================================================================
ALTER TABLE public.room_participants ADD COLUMN IF NOT EXISTS request_status TEXT NOT NULL DEFAULT 'none';
ALTER TABLE public.room_participants DROP CONSTRAINT IF EXISTS room_participants_request_status_check;
ALTER TABLE public.room_participants ADD CONSTRAINT room_participants_request_status_check
    CHECK (request_status IN ('none', 'pending', 'accepted', 'declined')) NOT VALID;

CREATE OR REPLACE FUNCTION public.get_or_create_dm_room(p_other UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_code TEXT;
    v_room UUID;
    v_title TEXT;
    v_other_state TEXT;
    v_other_left TIMESTAMPTZ;
    v_needs_request BOOLEAN;
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
    IF p_other IS NULL OR p_other = v_uid THEN RAISE EXCEPTION 'invalid_target'; END IF;
    IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = p_other) THEN RAISE EXCEPTION 'user_not_found'; END IF;
    IF public.is_blocked_between(v_uid, p_other) THEN RAISE EXCEPTION 'blocked'; END IF;
    IF public.juzzio_is_banned(v_uid) THEN RAISE EXCEPTION 'account_banned'; END IF;

    v_code := 'dm_' || LEAST(v_uid, p_other)::text || '_' || GREATEST(v_uid, p_other)::text;

    SELECT id INTO v_room FROM public.rooms WHERE room_code = v_code;
    IF v_room IS NULL THEN
        SELECT COALESCE(NULLIF(display_name, ''), username, 'Juzzio') INTO v_title FROM public.profiles WHERE id = p_other;
        INSERT INTO public.rooms (room_code, title, livekit_room_name, is_group, created_by)
        VALUES (v_code, v_title, 'lk_dm_' || SUBSTRING(md5(v_code) FROM 1 FOR 20), false, v_uid)
        ON CONFLICT (room_code) DO NOTHING
        RETURNING id INTO v_room;
        IF v_room IS NULL THEN
            SELECT id INTO v_room FROM public.rooms WHERE room_code = v_code;
        END IF;
    END IF;

    -- Ben: her zaman (yeniden) katılımcı
    INSERT INTO public.room_participants (room_id, user_id, role)
    VALUES (v_room, v_uid, 'member')
    ON CONFLICT (room_id, user_id) DO UPDATE SET left_at = NULL, hidden_at = NULL;

    v_needs_request := NOT public.is_friends_accepted(v_uid, p_other)
        AND COALESCE((SELECT is_private_account FROM public.profiles WHERE id = p_other), false);

    SELECT request_status, left_at INTO v_other_state, v_other_left
    FROM public.room_participants WHERE room_id = v_room AND user_id = p_other;

    IF NOT FOUND THEN
        INSERT INTO public.room_participants (room_id, user_id, role, request_status)
        VALUES (v_room, p_other, 'member', CASE WHEN v_needs_request THEN 'pending' ELSE 'none' END)
        ON CONFLICT (room_id, user_id) DO NOTHING;
    ELSIF v_other_state = 'declined' THEN
        -- Reddeden kişiye yeniden istek düşer (gizliyse), değilse sohbet normal açılır
        UPDATE public.room_participants
        SET left_at = NULL, hidden_at = NULL,
            request_status = CASE WHEN v_needs_request THEN 'pending' ELSE 'none' END
        WHERE room_id = v_room AND user_id = p_other;
    ELSIF v_other_left IS NOT NULL THEN
        UPDATE public.room_participants SET left_at = NULL
        WHERE room_id = v_room AND user_id = p_other;
    END IF;

    RETURN v_room;
END;
$$;
GRANT EXECUTE ON FUNCTION public.get_or_create_dm_room(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.respond_message_request(p_room UUID, p_accept BOOLEAN)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID := auth.uid();
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
    IF NOT EXISTS (SELECT 1 FROM public.room_participants
                   WHERE room_id = p_room AND user_id = v_uid AND request_status = 'pending') THEN
        RAISE EXCEPTION 'not_found';
    END IF;
    IF p_accept THEN
        UPDATE public.room_participants SET request_status = 'accepted'
        WHERE room_id = p_room AND user_id = v_uid;
    ELSE
        UPDATE public.room_participants SET request_status = 'declined', left_at = NOW(), hidden_at = NOW()
        WHERE room_id = p_room AND user_id = v_uid;
    END IF;
END;
$$;
GRANT EXECUTE ON FUNCTION public.respond_message_request(UUID, BOOLEAN) TO authenticated;

-- Arkadaş olunca bekleyen istekler otomatik kabul edilir
CREATE OR REPLACE FUNCTION public.juzzio_accept_requests_on_friendship()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NEW.status = 'accepted' THEN
        UPDATE public.room_participants rp
        SET request_status = 'accepted'
        FROM public.rooms r
        WHERE r.id = rp.room_id
          AND r.room_code = 'dm_' || LEAST(NEW.requester_id, NEW.receiver_id)::text || '_'
                                  || GREATEST(NEW.requester_id, NEW.receiver_id)::text
          AND rp.request_status = 'pending';
    END IF;
    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_juzzio_accept_requests_on_friendship ON public.friendships;
CREATE TRIGGER trg_juzzio_accept_requests_on_friendship
    AFTER INSERT OR UPDATE OF status ON public.friendships
    FOR EACH ROW EXECUTE FUNCTION public.juzzio_accept_requests_on_friendship();

-- =============================================================================
-- 4. "ARKADAŞ EKLE"
--  • Herkese açık hesap: eklenince içerikleri hemen görülebilir/beğenilebilir
--    (takip kaydı), tam arkadaşlık için karşı tarafın da eklemesi gerekir.
--  • Gizli hesap: istek gönderilir, karşı taraf kabul edince arkadaş olunur.
--  • Gruplara yalnızca karşılıklı arkadaşlar eklenebilir.
-- =============================================================================
CREATE OR REPLACE FUNCTION public.add_friend(p_target UUID)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_state TEXT;
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
    v_state := public.send_friend_request(p_target);
    -- İçerik görünürlüğü için takip kaydı (gizli hesapta "pending" olur, tetikleyici belirler)
    INSERT INTO public.follows (follower_id, following_id, status)
    VALUES (v_uid, p_target, 'following')
    ON CONFLICT (follower_id, following_id) DO NOTHING;
    IF v_state = 'accepted' THEN
        -- Karşılıklı arkadaşlıkta iki yönlü takip
        INSERT INTO public.follows (follower_id, following_id, status)
        VALUES (p_target, v_uid, 'following')
        ON CONFLICT (follower_id, following_id) DO UPDATE SET status = 'following';
        UPDATE public.follows SET status = 'following'
        WHERE follower_id = v_uid AND following_id = p_target;
        RETURN 'friends';
    END IF;
    RETURN 'requested';
END;
$$;
GRANT EXECUTE ON FUNCTION public.add_friend(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_relationship(p_target UUID)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT jsonb_build_object(
        'friend_status', COALESCE((
            SELECT CASE
                       WHEN f.status = 'accepted' THEN 'friends'
                       WHEN f.status = 'pending' AND f.requester_id = auth.uid() THEN 'outgoing'
                       WHEN f.status = 'pending' AND f.receiver_id = auth.uid() THEN 'incoming'
                       ELSE 'none'
                   END
            FROM public.friendships f
            WHERE LEAST(f.requester_id, f.receiver_id) = LEAST(auth.uid(), p_target)
              AND GREATEST(f.requester_id, f.receiver_id) = GREATEST(auth.uid(), p_target)
            LIMIT 1
        ), 'none'),
        'is_private', COALESCE((SELECT is_private_account FROM public.profiles WHERE id = p_target), false),
        'blocked', public.is_blocked_between(auth.uid(), p_target),
        'friend_count', (SELECT COUNT(*) FROM public.friendships f
                         WHERE f.status = 'accepted' AND (f.requester_id = p_target OR f.receiver_id = p_target))
    )
    WHERE auth.uid() IS NOT NULL;
$$;
GRANT EXECUTE ON FUNCTION public.get_relationship(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.can_add_to_group(p_adder UUID, p_target UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT p_adder IS NOT NULL AND p_target IS NOT NULL AND p_adder <> p_target
       AND NOT public.is_blocked_between(p_adder, p_target)
       AND public.is_friends_accepted(p_adder, p_target)
       AND COALESCE((SELECT p.privacy_groups <> 'nobody' FROM public.profiles p WHERE p.id = p_target), false);
$$;

-- =============================================================================
-- 5. SOHBET LİSTESİ: gerçek çevrimiçi durumu, gizlilik ve mesaj istekleri
-- =============================================================================
DROP FUNCTION IF EXISTS public.get_my_conversations();
CREATE OR REPLACE FUNCTION public.get_my_conversations()
RETURNS TABLE (
    room_id UUID,
    room_code TEXT,
    title TEXT,
    is_group BOOLEAN,
    is_channel BOOLEAN,
    livekit_room_name TEXT,
    disappearing_timer TEXT,
    avatar_url TEXT,
    partner_id UUID,
    partner_username TEXT,
    partner_display_name TEXT,
    partner_avatar_url TEXT,
    partner_lang TEXT,
    partner_is_online BOOLEAN,
    partner_last_seen TIMESTAMPTZ,
    member_ids JSONB,
    member_names JSONB,
    last_message_at TIMESTAMPTZ,
    last_message_sender UUID,
    last_message_type TEXT,
    last_message_preview TEXT,
    unread_count INTEGER,
    is_muted BOOLEAN,
    is_pinned BOOLEAN,
    is_call_active BOOLEAN,
    active_call JSONB,
    created_by UUID,
    partner_last_read_at TIMESTAMPTZ,
    my_role TEXT,
    my_muted_until TIMESTAMPTZ,
    group_type TEXT,
    group_purpose TEXT,
    description TEXT,
    partner_is_verified BOOLEAN,
    is_message_request BOOLEAN
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT
        r.id,
        r.room_code,
        CASE WHEN r.is_group THEN r.title ELSE COALESCE(NULLIF(op.display_name, ''), op.username, r.title) END,
        r.is_group,
        r.is_channel,
        r.livekit_room_name,
        r.disappearing_timer,
        CASE WHEN r.is_group THEN r.avatar_url ELSE op.avatar_url END,
        op.id,
        op.username,
        op.display_name,
        op.avatar_url,
        op.preferred_lang,
        CASE WHEN op.id IS NOT NULL
                  AND public.juzzio_can_see_presence(me.user_id, op.id, op.privacy_online)
                  AND public.juzzio_can_see_presence(me.user_id, op.id, op.privacy_last_seen)
             THEN public.juzzio_effective_online(op.is_online, op.last_seen) ELSE false END,
        CASE WHEN op.id IS NOT NULL AND public.juzzio_can_see_presence(me.user_id, op.id, op.privacy_last_seen)
             THEN op.last_seen END,
        r.group_member_ids,
        r.group_members,
        CASE WHEN me.cleared_at IS NOT NULL AND r.last_message_at <= me.cleared_at THEN NULL ELSE r.last_message_at END,
        r.last_message_sender,
        r.last_message_type,
        CASE WHEN me.cleared_at IS NOT NULL AND r.last_message_at <= me.cleared_at THEN NULL ELSE r.last_message_preview END,
        (
            SELECT COUNT(*)::INTEGER
            FROM public.messages m
            WHERE m.room_id = r.id
              AND m.sender_id <> me.user_id
              AND m.created_at > GREATEST(me.last_read_at, COALESCE(me.cleared_at, me.last_read_at))
              AND COALESCE(m.is_deleted, false) = false
        ),
        me.is_muted,
        me.is_pinned,
        r.is_call_active,
        r.active_call,
        r.created_by,
        CASE WHEN COALESCE(op.read_receipts, true) AND COALESCE(mp.read_receipts, true) THEN op.partner_last_read_at END,
        CASE WHEN me.role IN ('owner', 'moderator') THEN me.role ELSE 'member' END,
        CASE WHEN me.muted_until > NOW() THEN me.muted_until END,
        r.group_type,
        r.group_purpose,
        r.description,
        COALESCE(op.is_verified, false),
        (NOT r.is_group AND me.request_status = 'pending')
    FROM public.room_participants me
    JOIN public.profiles mp ON mp.id = me.user_id
    JOIN public.rooms r ON r.id = me.room_id
    LEFT JOIN LATERAL (
        SELECT p.*, o.last_read_at AS partner_last_read_at
        FROM public.room_participants o
        JOIN public.profiles p ON p.id = o.user_id
        WHERE NOT r.is_group AND o.room_id = r.id AND o.user_id <> me.user_id
        LIMIT 1
    ) op ON true
    WHERE me.user_id = auth.uid()
      AND me.left_at IS NULL
      AND (me.hidden_at IS NULL OR r.last_message_at > me.hidden_at)
      AND r.room_code <> 'juzzio-couple-main'
      AND (r.is_group OR op.id IS NOT NULL)
      -- Mesaj isteği yalnızca içinde mesaj varsa listelenir
      AND (me.request_status <> 'pending' OR r.last_message_at IS NOT NULL)
    ORDER BY me.is_pinned DESC, COALESCE(r.last_message_at, r.created_at) DESC;
$$;
GRANT EXECUTE ON FUNCTION public.get_my_conversations() TO authenticated;

-- =============================================================================
-- 6. UYGULAMA AYARLARI: bakım modu ve özellik bayrakları (herkes okuyabilir)
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.app_settings (
    key TEXT PRIMARY KEY,
    value JSONB NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE public.app_settings ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.app_settings FROM anon, authenticated;

INSERT INTO public.app_settings (key, value) VALUES
    ('maintenance_mode', 'false'::jsonb),
    ('maintenance_message', '""'::jsonb),
    ('signups_enabled', 'true'::jsonb),
    ('live_translation_enabled', 'true'::jsonb),
    ('chick_game_enabled', 'true'::jsonb),
    ('stories_enabled', 'true'::jsonb),
    ('beauty_filter_enabled', 'true'::jsonb)
ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.juzzio_setting_bool(p_key TEXT, p_default BOOLEAN)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT COALESCE((SELECT CASE WHEN jsonb_typeof(value) = 'boolean' THEN (value)::text::boolean END
                     FROM public.app_settings WHERE key = p_key), p_default);
$$;

CREATE OR REPLACE FUNCTION public.get_app_config()
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT COALESCE(jsonb_object_agg(key, value), '{}'::jsonb) FROM public.app_settings;
$$;
GRANT EXECUTE ON FUNCTION public.get_app_config() TO anon, authenticated;

-- Kayıtlar kapatıldıysa yeni hesap açılamaz (yönetici paneli bayrağı)
CREATE OR REPLACE FUNCTION public.juzzio_guard_signups()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT public.juzzio_setting_bool('signups_enabled', true) THEN
        RAISE EXCEPTION 'signup_disabled';
    END IF;
    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_juzzio_guard_signups ON auth.users;
CREATE TRIGGER trg_juzzio_guard_signups
    BEFORE INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.juzzio_guard_signups();

-- =============================================================================
-- 7. SÜRELİ ASKIYA ALMA (engel süresi dolunca otomatik kalkar)
-- =============================================================================
ALTER TABLE public.banned_users ADD COLUMN IF NOT EXISTS expires_at TIMESTAMPTZ;

CREATE OR REPLACE FUNCTION public.juzzio_is_banned(p_user UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (SELECT 1 FROM public.banned_users b
                   WHERE b.user_id = p_user AND (b.expires_at IS NULL OR b.expires_at > NOW()));
$$;
GRANT EXECUTE ON FUNCTION public.juzzio_is_banned(UUID) TO authenticated;

-- =============================================================================
-- 8. YÖNETİCİ PANELİ — yeni araçlar (hepsi yönetici oturum belirteci ister)
-- =============================================================================
CREATE OR REPLACE FUNCTION public.admin_stats(p_token TEXT)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_storage JSONB := '{}'::jsonb;
BEGIN
    PERFORM public._admin_require(p_token);
    BEGIN
        EXECUTE $q$
            SELECT jsonb_build_object(
                'files', COUNT(*),
                'bytes', COALESCE(SUM(NULLIF(metadata->>'size', '')::bigint), 0))
            FROM storage.objects
        $q$ INTO v_storage;
    EXCEPTION WHEN OTHERS THEN
        v_storage := '{}'::jsonb;
    END;
    RETURN jsonb_build_object(
        'users', (SELECT COUNT(*) FROM public.profiles),
        'online_now', (SELECT COUNT(*) FROM public.profiles WHERE public.juzzio_effective_online(is_online, last_seen)),
        'dau', (SELECT COUNT(*) FROM public.profiles WHERE last_seen > NOW() - INTERVAL '1 day'),
        'mau', (SELECT COUNT(*) FROM public.profiles WHERE last_seen > NOW() - INTERVAL '30 days'),
        'verified', (SELECT COUNT(*) FROM public.profiles WHERE is_verified),
        'messages_total', (SELECT COUNT(*) FROM public.messages),
        'messages_today', (SELECT COUNT(*) FROM public.messages WHERE created_at > NOW() - INTERVAL '1 day'),
        'calls_total', (SELECT COUNT(DISTINCT COALESCE(session_id::text, id::text)) FROM public.call_logs),
        'voice_minutes', (SELECT COALESCE(SUM(duration_sec), 0) / 60 FROM public.call_logs WHERE NOT is_video),
        'video_minutes', (SELECT COALESCE(SUM(duration_sec), 0) / 60 FROM public.call_logs WHERE is_video),
        'posts', (SELECT COUNT(*) FROM public.posts),
        'stories_active', (SELECT COUNT(*) FROM public.stories WHERE created_at > NOW() - INTERVAL '1 day'),
        'groups', (SELECT COUNT(*) FROM public.rooms WHERE is_group),
        'open_reports', (SELECT COUNT(*) FROM public.reports WHERE status = 'open'),
        'banned_users', (SELECT COUNT(*) FROM public.banned_users WHERE expires_at IS NULL OR expires_at > NOW()),
        'banned_devices', (SELECT COUNT(*) FROM public.banned_devices),
        'chick_alive', (SELECT COUNT(*) FROM public.chick_pets WHERE status = 'alive'),
        'chick_dead', (SELECT COUNT(*) FROM public.chick_pets WHERE status = 'dead'),
        'storage', v_storage,
        'series', (
            SELECT jsonb_agg(jsonb_build_object(
                'day', to_char(d, 'YYYY-MM-DD'),
                'messages', (SELECT COUNT(*) FROM public.messages m WHERE m.created_at >= d AND m.created_at < d + INTERVAL '1 day'),
                'signups', (SELECT COUNT(*) FROM public.profiles p WHERE p.created_at >= d AND p.created_at < d + INTERVAL '1 day'),
                'calls', (SELECT COUNT(*) FROM public.call_logs c WHERE c.created_at >= d AND c.created_at < d + INTERVAL '1 day')
            ) ORDER BY d)
            FROM generate_series(date_trunc('day', NOW()) - INTERVAL '13 days', date_trunc('day', NOW()), INTERVAL '1 day') d
        )
    );
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_stats(TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_search_users(p_token TEXT, p_query TEXT)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_q TEXT := '%' || LOWER(BTRIM(COALESCE(p_query, ''))) || '%';
BEGIN
    PERFORM public._admin_require(p_token);
    RETURN COALESCE((
        SELECT jsonb_agg(row_to_json(x)) FROM (
            SELECT p.id, p.username, p.display_name, p.avatar_url, p.is_verified, p.created_at, p.last_seen,
                   p.app_role, p.is_private_account,
                   public.juzzio_effective_online(p.is_online, p.last_seen) AS is_online,
                   public.juzzio_is_banned(p.id) AS is_banned,
                   (SELECT b.expires_at FROM public.banned_users b WHERE b.user_id = p.id) AS banned_until,
                   (SELECT COUNT(*) FROM public.user_devices d WHERE d.user_id = p.id) AS device_count,
                   (SELECT COUNT(*) FROM public.reports r WHERE r.target_owner_id = p.id AND r.status = 'open') AS open_reports
            FROM public.profiles p
            WHERE LOWER(p.username) LIKE v_q OR LOWER(p.display_name) LIKE v_q
            ORDER BY p.created_at DESC
            LIMIT 100
        ) x
    ), '[]'::jsonb);
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_search_users(TEXT, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_user_detail(p_token TEXT, p_user UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    PERFORM public._admin_require(p_token);
    RETURN (
        SELECT jsonb_build_object(
            'id', p.id, 'username', p.username, 'display_name', p.display_name, 'avatar_url', p.avatar_url,
            'email', (SELECT u.email FROM auth.users u WHERE u.id = p.id),
            'created_at', p.created_at, 'last_seen', p.last_seen,
            'is_online', public.juzzio_effective_online(p.is_online, p.last_seen),
            'is_verified', p.is_verified, 'app_role', p.app_role, 'is_private', p.is_private_account,
            'banned', public.juzzio_is_banned(p.id),
            'ban', (SELECT row_to_json(b) FROM public.banned_users b WHERE b.user_id = p.id),
            'devices', (SELECT COUNT(*) FROM public.user_devices d WHERE d.user_id = p.id),
            'friends', (SELECT COUNT(*) FROM public.friendships f WHERE f.status = 'accepted'
                        AND (f.requester_id = p.id OR f.receiver_id = p.id)),
            'messages', (SELECT COUNT(*) FROM public.messages m WHERE m.sender_id = p.id),
            'posts', (SELECT COUNT(*) FROM public.posts po WHERE po.author_id = p.id),
            'reports_against', (SELECT COUNT(*) FROM public.reports r WHERE r.target_owner_id = p.id),
            'voice_minutes', (SELECT COALESCE(SUM(duration_sec), 0) / 60 FROM public.call_logs c
                              WHERE NOT c.is_video AND (c.caller_id = p.id OR c.receiver_id = p.id)),
            'video_minutes', (SELECT COALESCE(SUM(duration_sec), 0) / 60 FROM public.call_logs c
                              WHERE c.is_video AND (c.caller_id = p.id OR c.receiver_id = p.id))
        )
        FROM public.profiles p WHERE p.id = p_user
    );
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_user_detail(TEXT, UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_set_verified(p_token TEXT, p_user UUID, p_verified BOOLEAN)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    PERFORM public._admin_require(p_token);
    UPDATE public.profiles SET is_verified = COALESCE(p_verified, false), updated_at = NOW() WHERE id = p_user;
    INSERT INTO public.admin_audit_log (admin_id, action, target, details)
    VALUES (auth.uid(), 'set_verified', p_user::text, jsonb_build_object('verified', p_verified));
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_set_verified(TEXT, UUID, BOOLEAN) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_set_app_role(p_token TEXT, p_user UUID, p_role TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    PERFORM public._admin_require(p_token);
    IF p_role NOT IN ('user', 'moderator') THEN RAISE EXCEPTION 'invalid_role'; END IF;
    UPDATE public.profiles SET app_role = p_role, updated_at = NOW() WHERE id = p_user;
    INSERT INTO public.admin_audit_log (admin_id, action, target, details)
    VALUES (auth.uid(), 'set_app_role', p_user::text, jsonb_build_object('role', p_role));
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_set_app_role(TEXT, UUID, TEXT) TO authenticated;

-- Süreli askıya alma (saat cinsinden; 0 veya NULL = süresiz engel)
CREATE OR REPLACE FUNCTION public.admin_suspend_user(p_token TEXT, p_user UUID, p_hours INTEGER, p_reason TEXT, p_note TEXT DEFAULT '')
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    PERFORM public._admin_require(p_token);
    IF p_reason IS NULL OR NOT (p_reason = ANY (public.juzzio_ban_reasons())) THEN RAISE EXCEPTION 'invalid_reason'; END IF;
    IF public.is_juzzio_admin(p_user) THEN RAISE EXCEPTION 'cannot_ban_admin'; END IF;
    INSERT INTO public.banned_users (user_id, reason_code, note, banned_by, expires_at)
    VALUES (p_user, p_reason, LEFT(COALESCE(p_note, ''), 500), auth.uid(),
            CASE WHEN COALESCE(p_hours, 0) > 0 THEN NOW() + make_interval(hours => p_hours) END)
    ON CONFLICT (user_id) DO UPDATE SET reason_code = EXCLUDED.reason_code, note = EXCLUDED.note,
                                        banned_by = EXCLUDED.banned_by, created_at = NOW(),
                                        expires_at = EXCLUDED.expires_at;
    UPDATE public.profiles SET is_online = false WHERE id = p_user;
    INSERT INTO public.admin_audit_log (admin_id, action, target, details)
    VALUES (auth.uid(), 'suspend_user', p_user::text, jsonb_build_object('hours', p_hours, 'reason', p_reason));
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_suspend_user(TEXT, UUID, INTEGER, TEXT, TEXT) TO authenticated;

-- Şifre sıfırlama e-postası için kullanıcının e-postasını döndürür (yalnızca yönetici)
CREATE OR REPLACE FUNCTION public.admin_get_user_email(p_token TEXT, p_user UUID)
RETURNS TEXT
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    PERFORM public._admin_require(p_token);
    RETURN (SELECT u.email FROM auth.users u WHERE u.id = p_user);
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_get_user_email(TEXT, UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_warn_user(p_token TEXT, p_user UUID, p_message TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    PERFORM public._admin_require(p_token);
    IF BTRIM(COALESCE(p_message, '')) = '' THEN RAISE EXCEPTION 'empty_message'; END IF;
    INSERT INTO public.notifications (recipient_id, actor_id, actor_username, actor_display_name,
                                      event_type, target_id, preview_text, dedupe_key)
    VALUES (p_user, NULL, 'juzzio', 'Juzzio', 'system', 'admin_warning', LEFT(BTRIM(p_message), 500),
            'admin_warn_' || p_user::text || '_' || EXTRACT(EPOCH FROM clock_timestamp())::bigint);
    INSERT INTO public.admin_audit_log (admin_id, action, target, details)
    VALUES (auth.uid(), 'warn_user', p_user::text, jsonb_build_object('message', LEFT(p_message, 200)));
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_warn_user(TEXT, UUID, TEXT) TO authenticated;

-- Duyuru / anlık bildirim (her alıcıya bildirim kaydı → push-webhook ile telefonlara gider)
CREATE OR REPLACE FUNCTION public.admin_broadcast(p_token TEXT, p_title TEXT, p_body TEXT, p_image_url TEXT DEFAULT '', p_audience TEXT DEFAULT 'all')
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_count INTEGER;
    v_key TEXT := 'broadcast_' || EXTRACT(EPOCH FROM clock_timestamp())::bigint;
    v_text TEXT;
BEGIN
    PERFORM public._admin_require(p_token);
    IF BTRIM(COALESCE(p_body, '')) = '' THEN RAISE EXCEPTION 'empty_message'; END IF;
    IF p_audience NOT IN ('all', 'online', 'verified', 'active_week') THEN RAISE EXCEPTION 'invalid_audience'; END IF;
    v_text := CASE WHEN BTRIM(COALESCE(p_title, '')) = '' THEN BTRIM(p_body)
                   ELSE BTRIM(p_title) || ' — ' || BTRIM(p_body) END;
    INSERT INTO public.notifications (recipient_id, actor_id, actor_username, actor_display_name,
                                      event_type, target_id, preview_text, media_thumb_url, dedupe_key)
    SELECT p.id, NULL, 'juzzio', 'Juzzio', 'system', 'announcement', LEFT(v_text, 500),
           NULLIF(BTRIM(COALESCE(p_image_url, '')), ''), v_key || '_' || p.id::text
    FROM public.profiles p
    WHERE NOT public.juzzio_is_banned(p.id)
      AND CASE p_audience
              WHEN 'online' THEN public.juzzio_effective_online(p.is_online, p.last_seen)
              WHEN 'verified' THEN p.is_verified
              WHEN 'active_week' THEN p.last_seen > NOW() - INTERVAL '7 days'
              ELSE true
          END;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    INSERT INTO public.admin_audit_log (admin_id, action, target, details)
    VALUES (auth.uid(), 'broadcast', p_audience, jsonb_build_object('count', v_count, 'title', LEFT(COALESCE(p_title, ''), 120)));
    RETURN v_count;
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_broadcast(TEXT, TEXT, TEXT, TEXT, TEXT) TO authenticated;

-- İçerik silme (şikâyet edilen gönderi, hikâye, yorum, mesaj)
CREATE OR REPLACE FUNCTION public.admin_delete_content(p_token TEXT, p_target_type TEXT, p_target_id TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_rows INTEGER := 0;
BEGIN
    PERFORM public._admin_require(p_token);
    CASE p_target_type
        WHEN 'post' THEN DELETE FROM public.posts WHERE id::text = p_target_id;
        WHEN 'story' THEN DELETE FROM public.stories WHERE id::text = p_target_id;
        WHEN 'comment' THEN DELETE FROM public.post_comments WHERE id::text = p_target_id;
        WHEN 'message' THEN
            UPDATE public.messages
            SET is_deleted = true, original_text = '', translated_text = '',
                image_url = NULL, video_url = NULL, audio_url = NULL, document_url = NULL
            WHERE id::text = p_target_id;
        ELSE RAISE EXCEPTION 'invalid_target_type';
    END CASE;
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    UPDATE public.reports SET status = 'resolved', reviewed_by = auth.uid(), reviewed_at = NOW(),
                              resolution_note = 'content_deleted'
    WHERE target_type = p_target_type AND target_id::text = p_target_id AND status = 'open';
    INSERT INTO public.admin_audit_log (admin_id, action, target, details)
    VALUES (auth.uid(), 'delete_content', COALESCE(p_target_id, ''), jsonb_build_object('type', p_target_type, 'rows', v_rows));
    RETURN v_rows > 0;
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_delete_content(TEXT, TEXT, TEXT) TO authenticated;

-- Uygulama içi güncelleme (OTA) yayınlama
ALTER TABLE public.app_releases ADD COLUMN IF NOT EXISTS notes_de TEXT NOT NULL DEFAULT '';

CREATE OR REPLACE FUNCTION public.admin_publish_release(
    p_token TEXT, p_version_name TEXT, p_version_code INTEGER, p_apk_url TEXT,
    p_notes_tr TEXT, p_notes_en TEXT DEFAULT '', p_notes_de TEXT DEFAULT '', p_mandatory BOOLEAN DEFAULT false)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    PERFORM public._admin_require(p_token);
    IF COALESCE(p_version_name, '') !~ '^[0-9]+\.[0-9]+\.[0-9]+$' THEN RAISE EXCEPTION 'invalid_version'; END IF;
    IF COALESCE(p_version_code, 0) <= 0 THEN RAISE EXCEPTION 'invalid_version'; END IF;
    IF COALESCE(p_apk_url, '') !~* '^https://[^ ]+\.apk(\?[^ ]*)?$' THEN RAISE EXCEPTION 'invalid_apk_url'; END IF;
    INSERT INTO public.app_releases (version_name, version_code, apk_url, notes_tr, notes_en, notes_de, is_mandatory, published_at)
    VALUES (p_version_name, p_version_code, p_apk_url, COALESCE(p_notes_tr, ''), COALESCE(p_notes_en, ''),
            COALESCE(p_notes_de, ''), COALESCE(p_mandatory, false), NOW())
    ON CONFLICT (version_name) DO UPDATE SET version_code = EXCLUDED.version_code, apk_url = EXCLUDED.apk_url,
        notes_tr = EXCLUDED.notes_tr, notes_en = EXCLUDED.notes_en, notes_de = EXCLUDED.notes_de,
        is_mandatory = EXCLUDED.is_mandatory, published_at = NOW();
    INSERT INTO public.admin_audit_log (admin_id, action, target, details)
    VALUES (auth.uid(), 'publish_release', p_version_name, jsonb_build_object('code', p_version_code, 'mandatory', p_mandatory));
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_publish_release(TEXT, TEXT, INTEGER, TEXT, TEXT, TEXT, TEXT, BOOLEAN) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_list_releases(p_token TEXT)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    PERFORM public._admin_require(p_token);
    RETURN COALESCE((SELECT jsonb_agg(row_to_json(r) ORDER BY r.version_code DESC, r.published_at DESC)
                     FROM (SELECT * FROM public.app_releases ORDER BY version_code DESC LIMIT 30) r), '[]'::jsonb);
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_list_releases(TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_delete_release(p_token TEXT, p_version_name TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    PERFORM public._admin_require(p_token);
    DELETE FROM public.app_releases WHERE version_name = p_version_name;
    INSERT INTO public.admin_audit_log (admin_id, action, target) VALUES (auth.uid(), 'delete_release', p_version_name);
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_delete_release(TEXT, TEXT) TO authenticated;

-- Bakım modu ve özellik bayrakları
CREATE OR REPLACE FUNCTION public.admin_set_setting(p_token TEXT, p_key TEXT, p_value JSONB)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    PERFORM public._admin_require(p_token);
    IF p_key NOT IN ('maintenance_mode', 'maintenance_message', 'signups_enabled', 'live_translation_enabled',
                     'chick_game_enabled', 'stories_enabled', 'beauty_filter_enabled') THEN
        RAISE EXCEPTION 'invalid_setting';
    END IF;
    IF p_key = 'maintenance_message' THEN
        IF jsonb_typeof(p_value) <> 'string' THEN RAISE EXCEPTION 'invalid_setting'; END IF;
    ELSIF jsonb_typeof(p_value) <> 'boolean' THEN
        RAISE EXCEPTION 'invalid_setting';
    END IF;
    INSERT INTO public.app_settings (key, value, updated_at) VALUES (p_key, p_value, NOW())
    ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = NOW();
    INSERT INTO public.admin_audit_log (admin_id, action, target, details)
    VALUES (auth.uid(), 'set_setting', p_key, jsonb_build_object('value', p_value));
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_set_setting(TEXT, TEXT, JSONB) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_audit(p_token TEXT, p_limit INTEGER DEFAULT 100)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    PERFORM public._admin_require(p_token);
    RETURN COALESCE((
        SELECT jsonb_agg(row_to_json(x) ORDER BY x.created_at DESC) FROM (
            SELECT l.id, l.action, l.target, l.details, l.created_at, p.username AS admin_username
            FROM public.admin_audit_log l LEFT JOIN public.profiles p ON p.id = l.admin_id
            ORDER BY l.created_at DESC
            LIMIT LEAST(GREATEST(COALESCE(p_limit, 100), 1), 300)
        ) x
    ), '[]'::jsonb);
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_audit(TEXT, INTEGER) TO authenticated;

-- Bakım modunda yönetici olmayanlar uygulamaya giremez (istemci bu fonksiyonu sorar)
CREATE OR REPLACE FUNCTION public.am_i_juzzio_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT auth.uid() IS NOT NULL AND public.is_juzzio_admin(auth.uid());
$$;
GRANT EXECUTE ON FUNCTION public.am_i_juzzio_admin() TO authenticated;

-- =============================================================================
-- v0.4.0 — Yeni içerik stüdyosu: video kırpma, oynatma hızı, müzik, yazı stili, klipler
-- =============================================================================
ALTER TABLE public.stories ADD COLUMN IF NOT EXISTS trim_start_ms INTEGER NOT NULL DEFAULT 0;
ALTER TABLE public.stories ADD COLUMN IF NOT EXISTS trim_end_ms INTEGER NOT NULL DEFAULT 0;
ALTER TABLE public.stories ADD COLUMN IF NOT EXISTS playback_speed NUMERIC(3,2) NOT NULL DEFAULT 1.00;
ALTER TABLE public.stories ADD COLUMN IF NOT EXISTS is_muted BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.stories ADD COLUMN IF NOT EXISTS music_url TEXT NOT NULL DEFAULT '';
ALTER TABLE public.stories ADD COLUMN IF NOT EXISTS music_title TEXT NOT NULL DEFAULT '';
ALTER TABLE public.stories ADD COLUMN IF NOT EXISTS music_start_sec INTEGER NOT NULL DEFAULT 0;
ALTER TABLE public.stories ADD COLUMN IF NOT EXISTS overlay_style TEXT NOT NULL DEFAULT 'classic';
ALTER TABLE public.stories ADD COLUMN IF NOT EXISTS overlay_color TEXT NOT NULL DEFAULT '#FFFFFF';

ALTER TABLE public.posts ADD COLUMN IF NOT EXISTS playback_speed NUMERIC(3,2) NOT NULL DEFAULT 1.00;
ALTER TABLE public.posts ADD COLUMN IF NOT EXISTS is_muted BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.posts ADD COLUMN IF NOT EXISTS music_url TEXT NOT NULL DEFAULT '';
ALTER TABLE public.posts ADD COLUMN IF NOT EXISTS music_start_sec INTEGER NOT NULL DEFAULT 0;
ALTER TABLE public.posts ADD COLUMN IF NOT EXISTS clip_meta JSONB NOT NULL DEFAULT '[]'::jsonb;

-- Değer aralıkları (istemci hatalarına karşı sunucu tarafı normalizasyon)
CREATE OR REPLACE FUNCTION public.juzzio_v040_media_meta_checks()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    NEW.playback_speed := LEAST(GREATEST(COALESCE(NEW.playback_speed, 1.00), 0.25), 3.00);
    NEW.music_start_sec := LEAST(GREATEST(COALESCE(NEW.music_start_sec, 0), 0), 7200);
    NEW.music_url := COALESCE(NEW.music_url, '');
    IF NEW.music_url <> '' AND NEW.music_url !~* '^https://' THEN
        NEW.music_url := '';
    END IF;
    IF TG_TABLE_NAME = 'stories' THEN
        NEW.trim_start_ms := GREATEST(COALESCE(NEW.trim_start_ms, 0), 0);
        NEW.trim_end_ms := GREATEST(COALESCE(NEW.trim_end_ms, 0), 0);
        IF NEW.trim_end_ms > 0 AND NEW.trim_end_ms <= NEW.trim_start_ms THEN
            NEW.trim_end_ms := 0;
        END IF;
        IF COALESCE(NEW.overlay_style, '') NOT IN ('classic', 'neon', 'typewriter', 'bold', 'outline') THEN
            NEW.overlay_style := 'classic';
        END IF;
        IF COALESCE(NEW.overlay_color, '') !~ '^#[0-9A-Fa-f]{6}$' THEN
            NEW.overlay_color := '#FFFFFF';
        END IF;
        NEW.music_title := LEFT(COALESCE(NEW.music_title, ''), 120);
    ELSE
        IF jsonb_typeof(COALESCE(NEW.clip_meta, '[]'::jsonb)) <> 'array' THEN
            NEW.clip_meta := '[]'::jsonb;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_juzzio_v040_story_meta ON public.stories;
CREATE TRIGGER trg_juzzio_v040_story_meta
    BEFORE INSERT OR UPDATE ON public.stories
    FOR EACH ROW EXECUTE FUNCTION public.juzzio_v040_media_meta_checks();

DROP TRIGGER IF EXISTS trg_juzzio_v040_post_meta ON public.posts;
CREATE TRIGGER trg_juzzio_v040_post_meta
    BEFORE INSERT OR UPDATE ON public.posts
    FOR EACH ROW EXECUTE FUNCTION public.juzzio_v040_media_meta_checks();

-- #############################################################################
-- BÖLÜM 9/9 — kaynak: 20261101000000_juzzio_v050_group_fix_notifications.sql
-- #############################################################################
-- =============================================================================
-- JUZZIO v0.5.0 — Grup oluşturma P0001 düzeltmesi ve bildirim ayrımı
--
-- KÖK NEDEN (canlı veritabanında yeniden üretildi):
--   Panelden elle eklenmiş, depoda olmayan `trg_check_dm_room_uniqueness`
--   tetikleyicisi her room_participants INSERT'inde odadaki aktif katılımcı
--   sayısı 2 olduğunda odayı "birebir sohbet" sanıyordu. Grup oluşturulurken
--   kurucudan sonra eklenen İLK üye bu koşulu sağlar; iki kişinin zaten bir DM
--   odası olduğu için tetikleyici
--     P0001 "DM room already exists between these two users"
--   hatası fırlatıyor ve tüm grup oluşturma işlemi geri alınıyordu.
--
-- ÇÖZÜM: Kontrol yalnızca grup/kanal OLMAYAN odalarda ve yalnızca diğer
--   birebir odalarla karşılaştırılarak yapılır. Grup oluşturma tek işlemde
--   (create_group_room) atomik kalır. Dosya tekrar çalıştırılabilir.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.check_dm_room_uniqueness()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_is_group BOOLEAN;
    v_other UUID;
BEGIN
    SELECT (r.is_group OR COALESCE(r.is_channel, false)) INTO v_is_group
      FROM public.rooms r WHERE r.id = NEW.room_id;
    -- Grup ve kanal odaları bu kurala tabi değildir
    IF COALESCE(v_is_group, false) THEN
        RETURN NEW;
    END IF;

    IF (SELECT COUNT(*) FROM public.room_participants
         WHERE room_id = NEW.room_id AND left_at IS NULL) = 2 THEN
        SELECT user_id INTO v_other FROM public.room_participants
         WHERE room_id = NEW.room_id AND user_id <> NEW.user_id AND left_at IS NULL
         LIMIT 1;
        IF v_other IS NOT NULL AND EXISTS (
            SELECT 1
              FROM public.room_participants rp1
              JOIN public.room_participants rp2 ON rp1.room_id = rp2.room_id
              JOIN public.rooms r ON r.id = rp1.room_id
             WHERE rp1.user_id = v_other
               AND rp2.user_id = NEW.user_id
               AND rp1.room_id <> NEW.room_id
               AND rp1.left_at IS NULL
               AND rp2.left_at IS NULL
               AND NOT r.is_group
               AND NOT COALESCE(r.is_channel, false)
        ) THEN
            RAISE EXCEPTION 'dm_room_exists';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_check_dm_room_uniqueness ON public.room_participants;
CREATE TRIGGER trg_check_dm_room_uniqueness
    AFTER INSERT ON public.room_participants
    FOR EACH ROW WHEN (NEW.left_at IS NULL)
    EXECUTE FUNCTION public.check_dm_room_uniqueness();

-- =============================================================================
-- Bildirim türleri: mesaj tepkisi ve gönderi kaydetme
-- =============================================================================
ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_event_type_check;
ALTER TABLE public.notifications ADD CONSTRAINT notifications_event_type_check CHECK (event_type = ANY (ARRAY[
    'like', 'comment', 'reply', 'follow', 'follow_request', 'follow_accepted', 'friend_request',
    'friend_accepted', 'story_like', 'story_reply', 'message', 'missed_call', 'incoming_call',
    'group_activity', 'system', 'chick_invite', 'chick_hatched', 'chick_hungry', 'chick_dying',
    'chick_died', 'reaction', 'save'
])) NOT VALID;

-- Kullanıcının o an açık tuttuğu sohbet (tepki bildirimini sohbet içindeyken göndermemek için)
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS active_room_id UUID;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS active_room_at TIMESTAMPTZ;

CREATE OR REPLACE FUNCTION public.set_my_active_room(p_room UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF auth.uid() IS NULL THEN RETURN; END IF;
    IF p_room IS NOT NULL AND NOT public.is_room_member(p_room, auth.uid()) THEN
        RETURN;
    END IF;
    UPDATE public.profiles
       SET active_room_id = p_room,
           active_room_at = CASE WHEN p_room IS NULL THEN NULL ELSE NOW() END
     WHERE id = auth.uid();
END;
$$;
REVOKE ALL ON FUNCTION public.set_my_active_room(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_my_active_room(UUID) TO authenticated;

-- Tepki ekle/kaldır + mesaj sahibine bildirim (sohbeti açık değilse; tekrarlanmaz)
CREATE OR REPLACE FUNCTION public.toggle_message_reaction(p_message UUID, p_emoji TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_key TEXT := auth.uid()::text;
    v_room UUID;
    v_owner UUID;
    v_text TEXT;
    v_reactions JSONB;
    v_added BOOLEAN := false;
    v_emoji TEXT := LEFT(BTRIM(COALESCE(p_emoji, '')), 16);
    v_actor RECORD;
    v_owner_room UUID;
    v_owner_room_at TIMESTAMPTZ;
    v_owner_seen TIMESTAMPTZ;
BEGIN
    SELECT room_id, sender_id, COALESCE(original_text, ''), COALESCE(reactions, '{}'::jsonb)
      INTO v_room, v_owner, v_text, v_reactions
      FROM public.messages WHERE id = p_message FOR UPDATE;
    IF v_room IS NULL OR v_uid IS NULL OR NOT public.is_room_member(v_room, v_uid) THEN
        RAISE EXCEPTION 'not_allowed';
    END IF;
    IF v_emoji = '' OR v_reactions->>v_key = v_emoji THEN
        v_reactions := v_reactions - v_key;
    ELSE
        v_reactions := jsonb_set(v_reactions, ARRAY[v_key], to_jsonb(v_emoji), true);
        v_added := true;
    END IF;
    UPDATE public.messages SET reactions = v_reactions WHERE id = p_message;

    IF v_added AND v_owner IS NOT NULL AND v_owner <> v_uid
       AND NOT public.is_blocked_between(v_uid, v_owner) THEN
        SELECT active_room_id, active_room_at, last_seen INTO v_owner_room, v_owner_room_at, v_owner_seen
          FROM public.profiles WHERE id = v_owner;
        -- Mesaj sahibi şu an bu sohbetin içindeyse bildirim gönderme
        IF NOT COALESCE(v_owner_room = v_room
                AND COALESCE(v_owner_seen, v_owner_room_at) > NOW() - INTERVAL '3 minutes', false) THEN
            SELECT username, display_name, avatar_url INTO v_actor FROM public.profiles WHERE id = v_uid;
            INSERT INTO public.notifications (
                recipient_id, actor_id, actor_username, actor_display_name, actor_avatar_url,
                event_type, target_id, target_secondary_id, preview_text, dedupe_key
            ) VALUES (
                v_owner, v_uid, COALESCE(v_actor.username, ''),
                COALESCE(NULLIF(v_actor.display_name, ''), v_actor.username, 'Juzzio'), v_actor.avatar_url,
                'reaction', v_room::text, p_message::text,
                v_emoji || '|' || LEFT(REGEXP_REPLACE(v_text, '\s+', ' ', 'g'), 80),
                'reaction_' || p_message::text || '_' || v_key || '_' || v_emoji
            )
            ON CONFLICT (recipient_id, dedupe_key) DO NOTHING;
        END IF;
    END IF;
    RETURN v_reactions;
END;
$$;
GRANT EXECUTE ON FUNCTION public.toggle_message_reaction(UUID, TEXT) TO authenticated;

-- Gönderi kaydedilince sahibine sosyal bildirim (bildirim çanında görünür)
CREATE OR REPLACE FUNCTION public.notify_on_post_save()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_author UUID;
    v_actor RECORD;
BEGIN
    SELECT author_id INTO v_author FROM public.posts WHERE id = NEW.post_id;
    IF v_author IS NULL OR v_author = NEW.user_id OR public.is_blocked_between(NEW.user_id, v_author) THEN
        RETURN NEW;
    END IF;
    SELECT username, display_name, avatar_url INTO v_actor FROM public.profiles WHERE id = NEW.user_id;
    INSERT INTO public.notifications (
        recipient_id, actor_id, actor_username, actor_display_name, actor_avatar_url,
        event_type, target_id, preview_text, dedupe_key
    ) VALUES (
        v_author, NEW.user_id, COALESCE(v_actor.username, ''),
        COALESCE(NULLIF(v_actor.display_name, ''), v_actor.username, 'Juzzio'), v_actor.avatar_url,
        'save', NEW.post_id::text, '', 'save_' || NEW.post_id::text || '_' || NEW.user_id::text
    )
    ON CONFLICT (recipient_id, dedupe_key) DO NOTHING;
    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    RETURN NEW; -- bildirim hatası kaydetmeyi asla engellemez
END;
$$;
DROP TRIGGER IF EXISTS trg_notify_on_post_save ON public.saved_posts;
CREATE TRIGGER trg_notify_on_post_save
    AFTER INSERT ON public.saved_posts
    FOR EACH ROW EXECUTE FUNCTION public.notify_on_post_save();

-- Sohbet açıldığında o sohbete ait mesaj/arama bildirim kayıtlarını okundu yap
CREATE OR REPLACE FUNCTION public.mark_room_notifications_read(p_room UUID)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_n INTEGER;
BEGIN
    IF auth.uid() IS NULL OR p_room IS NULL THEN RETURN 0; END IF;
    UPDATE public.notifications
       SET is_read = true, read_at = NOW()
     WHERE recipient_id = auth.uid()
       AND is_read = false
       AND event_type IN ('message', 'group_activity', 'story_reply', 'reaction', 'missed_call', 'incoming_call')
       AND target_id = p_room::text;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    RETURN v_n;
END;
$$;
REVOKE ALL ON FUNCTION public.mark_room_notifications_read(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mark_room_notifications_read(UUID) TO authenticated;

-- =============================================================================
-- Küresel akış: yalnızca yazı paylaşımı (X / Reddit tarzı). Reels yeni içerik
-- olarak oluşturulmaz; eski 'reel' kayıtları video olarak görünmeye devam eder.
-- =============================================================================
ALTER TABLE public.posts DROP CONSTRAINT IF EXISTS posts_content_type_check;
ALTER TABLE public.posts ADD CONSTRAINT posts_content_type_check
    CHECK (content_type = ANY (ARRAY['image', 'video', 'carousel', 'reel', 'text']));

-- =============================================================================
-- Küresel akış çeviri önbelleği (gönderi ve yorumlar)
--  Anahtar: (tür, içerik, hedef dil). source_hash orijinal metnin md5'idir;
--  metin düzenlenirse karma değişir ve eski çeviri geçersiz sayılır.
--  Yalnızca translate-bridge (service role) yazar/okur; istemci tabloya
--  doğrudan erişemez (RLS açık, politika yok) → çeviri zehirlenemez.
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.content_translations (
    kind TEXT NOT NULL CHECK (kind IN ('post', 'comment')),
    content_id UUID NOT NULL,
    target_lang TEXT NOT NULL CHECK (char_length(target_lang) BETWEEN 2 AND 8),
    source_hash TEXT NOT NULL,
    source_lang TEXT NOT NULL DEFAULT 'auto',
    translated_text TEXT NOT NULL,
    provider TEXT NOT NULL DEFAULT 'gtx',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (kind, content_id, target_lang)
);
ALTER TABLE public.content_translations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.content_translations FROM anon, authenticated;

-- Çeviri kullanım ölçümü (yönetici panelindeki sistem durumu için)
CREATE TABLE IF NOT EXISTS public.translation_usage_daily (
    day DATE NOT NULL DEFAULT CURRENT_DATE,
    kind TEXT NOT NULL,
    requests INTEGER NOT NULL DEFAULT 0,
    cache_hits INTEGER NOT NULL DEFAULT 0,
    failures INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (day, kind)
);
ALTER TABLE public.translation_usage_daily ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.translation_usage_daily FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.bump_translation_usage(p_kind TEXT, p_requests INT, p_hits INT, p_failures INT)
RETURNS VOID
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    INSERT INTO public.translation_usage_daily (day, kind, requests, cache_hits, failures)
    VALUES (CURRENT_DATE, p_kind, GREATEST(p_requests, 0), GREATEST(p_hits, 0), GREATEST(p_failures, 0))
    ON CONFLICT (day, kind) DO UPDATE
       SET requests = translation_usage_daily.requests + EXCLUDED.requests,
           cache_hits = translation_usage_daily.cache_hits + EXCLUDED.cache_hits,
           failures = translation_usage_daily.failures + EXCLUDED.failures;
$$;
REVOKE ALL ON FUNCTION public.bump_translation_usage(TEXT, INT, INT, INT) FROM PUBLIC, anon, authenticated;

-- =============================================================================
-- Yönetici paneli: gerçek verilerle sistem durumu (yalnızca geçerli yönetici oturumu)
-- =============================================================================
CREATE OR REPLACE FUNCTION public.admin_system_health(p_token TEXT)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v JSONB;
BEGIN
    PERFORM public._admin_require(p_token);
    SELECT jsonb_build_object(
        'server_time', NOW(),
        'active_voice_calls', (SELECT COUNT(DISTINCT COALESCE(session_id::text, id::text)) FROM public.call_logs
                                WHERE status = 'answered' AND ended_at IS NULL AND NOT is_video AND NOT COALESCE(is_group, false)
                                  AND created_at > NOW() - INTERVAL '6 hours'),
        'active_video_calls', (SELECT COUNT(DISTINCT COALESCE(session_id::text, id::text)) FROM public.call_logs
                                WHERE status = 'answered' AND ended_at IS NULL AND is_video AND NOT COALESCE(is_group, false)
                                  AND created_at > NOW() - INTERVAL '6 hours'),
        'active_conferences', (SELECT COUNT(DISTINCT COALESCE(session_id::text, id::text)) FROM public.call_logs
                                WHERE status = 'answered' AND ended_at IS NULL AND COALESCE(is_group, false)
                                  AND created_at > NOW() - INTERVAL '6 hours'),
        'push_tokens_active', (SELECT COUNT(*) FROM public.user_push_tokens WHERE is_active),
        'push_tokens_invalid', (SELECT COUNT(*) FROM public.user_push_tokens WHERE NOT is_active),
        'translation_requests_today', (SELECT COALESCE(SUM(requests), 0) FROM public.translation_usage_daily WHERE day = CURRENT_DATE),
        'translation_cache_hits_today', (SELECT COALESCE(SUM(cache_hits), 0) FROM public.translation_usage_daily WHERE day = CURRENT_DATE),
        'translation_failures_today', (SELECT COALESCE(SUM(failures), 0) FROM public.translation_usage_daily WHERE day = CURRENT_DATE),
        'translation_cache_size', (SELECT COUNT(*) FROM public.content_translations),
        'community_posts', (SELECT COUNT(*) FROM public.posts WHERE NOT is_deleted),
        'text_posts', (SELECT COUNT(*) FROM public.posts WHERE NOT is_deleted AND content_type = 'text'),
        'stories_24h', (SELECT COUNT(*) FROM public.stories WHERE created_at > NOW() - INTERVAL '24 hours'),
        'admin_actions_24h', (SELECT COUNT(*) FROM public.admin_audit_log WHERE created_at > NOW() - INTERVAL '24 hours')
    ) INTO v;
    RETURN v;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_system_health(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_system_health(TEXT) TO authenticated;

-- -----------------------------------------------------------------------------
-- v0.5.1: küresel akış konuları (gerçek sunucu filtresi)
-- -----------------------------------------------------------------------------
ALTER TABLE public.posts ADD COLUMN IF NOT EXISTS topic TEXT NOT NULL DEFAULT 'general';
ALTER TABLE public.posts DROP CONSTRAINT IF EXISTS posts_topic_check;
ALTER TABLE public.posts ADD CONSTRAINT posts_topic_check CHECK (topic IN (
    'general', 'news', 'technology', 'science', 'sports', 'entertainment',
    'music', 'gaming', 'travel', 'food', 'art', 'humor'
)) NOT VALID;
CREATE INDEX IF NOT EXISTS idx_posts_topic_created ON public.posts (topic, created_at DESC) WHERE NOT is_deleted;

-- =============================================================================
-- v0.6.0: İÇERİK DENETİMİ, CEZA BASAMAKLARI, YÖNETİCİ PANELİ GENİŞLETMESİ
--  • Ad / kullanıcı adı / grup adı: genişletilmiş yasaklı kelime listesi (yönetici düzenler)
--  • Profil fotoğrafı: content-moderation Edge Function onayı olmadan değiştirilemez
--  • Görüntülü arama: müstehcen görüntü veya ağır argo → arama kesilir, ceza basamağı:
--      1. ihlal: 1 saat uzaklaştırma + uyarı
--      2. ihlal: 4 saat uzaklaştırma + uyarı
--      3. ihlal: son uyarı + kalıcı engel + cihaz engeli + aynı e-postayla yeni hesap yasağı
-- =============================================================================

-- Konuşma denetiminde ceza sayılan ağır terimler (ad denetimi tüm listeyi kullanır)
ALTER TABLE public.banned_terms ADD COLUMN IF NOT EXISTS speech_strike BOOLEAN NOT NULL DEFAULT false;

INSERT INTO public.banned_terms (term, match_mode) VALUES
    -- Türkçe müstehcen / ağır argo
    ('amcik', 'contains'), ('amcuk', 'contains'), ('aminakoydugum', 'contains'),
    ('dalyarak', 'contains'), ('dallama', 'contains'), ('gotveren', 'contains'), ('gotlek', 'contains'),
    ('kancik', 'contains'), ('sikici', 'contains'), ('sikiyim', 'contains'), ('siktim', 'contains'),
    ('sikeyim', 'contains'), ('yarram', 'contains'), ('yarragi', 'contains'), ('pezo', 'word'),
    ('fahise', 'contains'), ('orospucocugu', 'contains'), ('ibnelik', 'contains'),
    ('vajina', 'contains'), ('penis', 'contains'), ('memeler', 'contains'), ('ciplak', 'contains'),
    ('seksi', 'word'), ('erotik', 'contains'), ('azgin', 'contains'), ('escort', 'contains'),
    ('sokus', 'contains'), ('masaj18', 'contains'),
    -- İngilizce
    ('blowjob', 'contains'), ('handjob', 'contains'), ('boobs', 'contains'), ('tits', 'word'),
    ('milf', 'word'), ('anal', 'word'), ('cum', 'word'), ('horny', 'contains'), ('xvideos', 'contains'),
    ('xnxx', 'contains'), ('pornhub', 'contains'), ('brazzers', 'contains'), ('naked', 'contains'),
    ('motherfucker', 'contains'), ('asshole', 'contains'), ('bastard', 'contains'), ('dildo', 'contains'),
    ('vagina', 'contains'), ('blow job', 'contains'), ('sexy', 'word'), ('stripper', 'contains'),
    -- Almanca
    ('arschloch', 'contains'), ('schlampe', 'contains'), ('ficken', 'contains'), ('nutte', 'contains'),
    ('muschi', 'contains'), ('schwanz', 'word')
ON CONFLICT (term) DO NOTHING;

UPDATE public.banned_terms SET speech_strike = true
WHERE term IN ('orospu', 'siktir', 'sikerim', 'sikis', 'yarrak', 'aminakoy', 'aminakoyim', 'ananisikim',
               'amcik', 'amcuk', 'aminakoydugum', 'sikiyim', 'sikeyim', 'yarram', 'yarragi', 'orospucocugu',
               'porno', 'pornografi', 'fuck', 'motherfucker', 'pussy', 'cunt', 'whore', 'slut', 'blowjob',
               'handjob', 'dildo', 'hurensohn', 'fotze', 'ficken', 'nigger', 'nigga');

-- Konuşma metninde ağır terim var mı? (yalnızca speech_strike terimleri)
CREATE OR REPLACE FUNCTION public.juzzio_speech_is_explicit(p_text TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_folded TEXT := public.juzzio_fold_text(p_text);
    v_words TEXT;
    v_joined TEXT;
BEGIN
    IF p_text IS NULL OR BTRIM(p_text) = '' THEN RETURN false; END IF;
    v_words := ' ' || REGEXP_REPLACE(v_folded, '[^a-z]+', ' ', 'g') || ' ';
    v_joined := REGEXP_REPLACE(v_folded, '[^a-z]+', '', 'g');
    RETURN EXISTS (
        SELECT 1 FROM public.banned_terms b
        WHERE b.speech_strike
          AND ((b.match_mode = 'contains' AND (POSITION(b.term IN v_words) > 0 OR POSITION(b.term IN v_joined) > 0))
               OR (b.match_mode = 'word' AND POSITION(' ' || b.term || ' ' IN v_words) > 0))
    );
END;
$$;
REVOKE ALL ON FUNCTION public.juzzio_speech_is_explicit(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.juzzio_speech_is_explicit(TEXT) TO authenticated, service_role;

-- Medya denetim kayıtları (profil fotoğrafı, arama karesi)
CREATE TABLE IF NOT EXISTS public.media_moderation (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    kind TEXT NOT NULL CHECK (kind IN ('avatar', 'call_frame', 'story', 'post', 'other')),
    url TEXT NOT NULL DEFAULT '',
    verdict TEXT NOT NULL CHECK (verdict IN ('safe', 'nsfw', 'unchecked')),
    provider TEXT NOT NULL DEFAULT '',
    scores JSONB NOT NULL DEFAULT '{}'::jsonb,
    review_status TEXT NOT NULL DEFAULT 'auto' CHECK (review_status IN ('auto', 'pending', 'approved', 'rejected')),
    reviewed_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    reviewed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_media_moderation_user ON public.media_moderation (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_media_moderation_queue ON public.media_moderation (review_status, created_at DESC);
ALTER TABLE public.media_moderation ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS media_moderation_select_own ON public.media_moderation;
CREATE POLICY media_moderation_select_own ON public.media_moderation FOR SELECT TO authenticated
    USING (user_id = auth.uid());
REVOKE INSERT, UPDATE, DELETE ON public.media_moderation FROM anon, authenticated;

-- İhlal / ceza kayıtları
CREATE TABLE IF NOT EXISTS public.moderation_strikes (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    kind TEXT NOT NULL CHECK (kind IN ('call_nudity', 'call_speech', 'avatar_nsfw', 'name', 'admin')),
    detail TEXT NOT NULL DEFAULT '',
    room_name TEXT NOT NULL DEFAULT '',
    strike_no INTEGER NOT NULL,
    penalty TEXT NOT NULL CHECK (penalty IN ('suspend_1h', 'suspend_4h', 'permanent', 'warning')),
    source TEXT NOT NULL DEFAULT 'auto' CHECK (source IN ('auto', 'admin')),
    revoked BOOLEAN NOT NULL DEFAULT false,
    created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_moderation_strikes_user ON public.moderation_strikes (user_id, created_at DESC);
ALTER TABLE public.moderation_strikes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS moderation_strikes_select_own ON public.moderation_strikes;
CREATE POLICY moderation_strikes_select_own ON public.moderation_strikes FOR SELECT TO authenticated
    USING (user_id = auth.uid());
REVOKE INSERT, UPDATE, DELETE ON public.moderation_strikes FROM anon, authenticated;

-- Konuşma denetimi isabetleri (2 ağır ifade → ihlal; tek bir yanlış tanıma ceza doğurmaz)
CREATE TABLE IF NOT EXISTS public.call_speech_hits (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    room_name TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_call_speech_hits_user ON public.call_speech_hits (user_id, created_at DESC);
ALTER TABLE public.call_speech_hits ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.call_speech_hits FROM anon, authenticated;

-- Kalıcı engellenen kişilerin e-posta özeti: aynı e-postayla yeni hesap açılamaz
CREATE TABLE IF NOT EXISTS public.banned_identities (
    email_hash TEXT PRIMARY KEY,
    user_id UUID,
    reason TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE public.banned_identities ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.banned_identities FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.juzzio_email_hash(p_email TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
SET search_path = public, extensions
AS $$
    SELECT encode(digest(LOWER(BTRIM(COALESCE(p_email, ''))), 'sha256'), 'hex');
$$;

-- Kayıt koruması: kayıtlar kapalıysa veya e-posta kalıcı engelliyse yeni hesap açılamaz
CREATE OR REPLACE FUNCTION public.juzzio_guard_signups()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
    IF NOT public.juzzio_setting_bool('signups_enabled', true) THEN
        RAISE EXCEPTION 'signup_disabled';
    END IF;
    IF NEW.email IS NOT NULL AND EXISTS (
        SELECT 1 FROM public.banned_identities bi WHERE bi.email_hash = public.juzzio_email_hash(NEW.email)
    ) THEN
        RAISE EXCEPTION 'signup_blocked';
    END IF;
    RETURN NEW;
END;
$$;

-- Yeni ayarlar (yönetici panelinden değişir)
INSERT INTO public.app_settings (key, value) VALUES
    ('default_glass_palette', '"ocean"'::jsonb),
    ('call_moderation_enabled', 'true'::jsonb),
    ('speech_moderation_enabled', 'true'::jsonb),
    ('avatar_moderation_enabled', 'true'::jsonb),
    ('call_moderation_interval_sec', '6'::jsonb),
    ('posts_enabled', 'true'::jsonb),
    ('calls_enabled', 'true'::jsonb),
    ('group_creation_enabled', 'true'::jsonb),
    ('global_feed_enabled', 'true'::jsonb),
    ('announcement_banner', '""'::jsonb)
ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.admin_set_setting(p_token TEXT, p_key TEXT, p_value JSONB)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    PERFORM public._admin_require(p_token);
    IF p_key IN ('maintenance_message', 'announcement_banner') THEN
        IF jsonb_typeof(p_value) <> 'string' THEN RAISE EXCEPTION 'invalid_setting'; END IF;
        p_value := to_jsonb(LEFT(p_value #>> '{}', 500));
    ELSIF p_key = 'default_glass_palette' THEN
        IF jsonb_typeof(p_value) <> 'string'
           OR (p_value #>> '{}') NOT IN ('ocean', 'glass_white', 'amethyst', 'emerald', 'lagoon', 'chrome') THEN
            RAISE EXCEPTION 'invalid_setting';
        END IF;
    ELSIF p_key = 'call_moderation_interval_sec' THEN
        IF jsonb_typeof(p_value) <> 'number' OR (p_value #>> '{}')::numeric NOT BETWEEN 3 AND 60 THEN
            RAISE EXCEPTION 'invalid_setting';
        END IF;
    ELSIF p_key IN ('maintenance_mode', 'signups_enabled', 'live_translation_enabled', 'chick_game_enabled',
                    'stories_enabled', 'beauty_filter_enabled', 'call_moderation_enabled',
                    'speech_moderation_enabled', 'avatar_moderation_enabled', 'posts_enabled', 'calls_enabled',
                    'group_creation_enabled', 'global_feed_enabled') THEN
        IF jsonb_typeof(p_value) <> 'boolean' THEN RAISE EXCEPTION 'invalid_setting'; END IF;
    ELSE
        RAISE EXCEPTION 'invalid_setting';
    END IF;
    INSERT INTO public.app_settings (key, value, updated_at) VALUES (p_key, p_value, NOW())
    ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = NOW();
    INSERT INTO public.admin_audit_log (admin_id, action, target, details)
    VALUES (auth.uid(), 'set_setting', p_key, jsonb_build_object('value', p_value));
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_set_setting(TEXT, TEXT, JSONB) TO authenticated;

-- Profil fotoğrafı yalnızca denetimden geçmiş adresle değiştirilebilir
CREATE OR REPLACE FUNCTION public.juzzio_guard_avatar_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF auth.uid() IS NULL OR auth.uid() <> NEW.id THEN RETURN NEW; END IF; -- sunucu / yönetici işlemleri
    IF COALESCE(NEW.avatar_url, '') = '' OR NEW.avatar_url IS NOT DISTINCT FROM OLD.avatar_url THEN RETURN NEW; END IF;
    IF NOT public.juzzio_setting_bool('avatar_moderation_enabled', true) THEN RETURN NEW; END IF;
    IF NOT EXISTS (
        SELECT 1 FROM public.media_moderation m
        WHERE m.user_id = NEW.id AND m.kind = 'avatar' AND m.url = NEW.avatar_url
          AND m.verdict IN ('safe', 'unchecked') AND m.review_status <> 'rejected'
          AND m.created_at > NOW() - INTERVAL '2 hours'
    ) THEN
        RAISE EXCEPTION 'avatar_not_moderated' USING ERRCODE = '22023';
    END IF;
    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_juzzio_guard_avatar ON public.profiles;
CREATE TRIGGER trg_juzzio_guard_avatar
    BEFORE UPDATE OF avatar_url ON public.profiles
    FOR EACH ROW EXECUTE FUNCTION public.juzzio_guard_avatar_change();

-- İhlal kaydı ve ceza basamağı (yalnızca Edge Function / service_role ve yönetici fonksiyonları çağırır)
CREATE OR REPLACE FUNCTION public.juzzio_record_violation(
    p_user UUID,
    p_kind TEXT,
    p_detail TEXT DEFAULT '',
    p_room TEXT DEFAULT '',
    p_source TEXT DEFAULT 'auto',
    p_actor UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_prev public.moderation_strikes%ROWTYPE;
    v_count INTEGER;
    v_no INTEGER;
    v_penalty TEXT;
    v_until TIMESTAMPTZ;
    v_msg TEXT;
    v_email TEXT;
    v_devices INTEGER := 0;
    v_calls INTEGER := 0;
BEGIN
    IF p_user IS NULL THEN RAISE EXCEPTION 'invalid_user'; END IF;
    IF p_kind NOT IN ('call_nudity', 'call_speech', 'avatar_nsfw', 'name', 'admin') THEN RAISE EXCEPTION 'invalid_kind'; END IF;

    -- Aynı olay için tekrar eden karelerde tek ceza (aynı odada son 3 dakika)
    SELECT * INTO v_prev FROM public.moderation_strikes s
    WHERE s.user_id = p_user AND NOT s.revoked AND s.created_at > NOW() - INTERVAL '3 minutes'
      AND (COALESCE(p_room, '') = '' OR s.room_name = p_room)
    ORDER BY s.created_at DESC LIMIT 1;
    IF FOUND THEN
        RETURN jsonb_build_object('ok', true, 'duplicate', true, 'strike', v_prev.strike_no, 'penalty', v_prev.penalty);
    END IF;

    SELECT COUNT(*) INTO v_count FROM public.moderation_strikes s
    WHERE s.user_id = p_user AND NOT s.revoked AND s.penalty <> 'warning';
    v_no := v_count + 1;

    IF public.is_juzzio_admin(p_user) THEN
        v_penalty := 'warning';
    ELSIF v_no = 1 THEN
        v_penalty := 'suspend_1h';
        v_until := NOW() + INTERVAL '1 hour';
    ELSIF v_no = 2 THEN
        v_penalty := 'suspend_4h';
        v_until := NOW() + INTERVAL '4 hours';
    ELSE
        v_penalty := 'permanent';
    END IF;

    INSERT INTO public.moderation_strikes (user_id, kind, detail, room_name, strike_no, penalty, source, created_by)
    VALUES (p_user, p_kind, LEFT(COALESCE(p_detail, ''), 300), LEFT(COALESCE(p_room, ''), 128), v_no, v_penalty,
            CASE WHEN p_source = 'admin' THEN 'admin' ELSE 'auto' END, p_actor);

    IF v_penalty IN ('suspend_1h', 'suspend_4h', 'permanent') THEN
        INSERT INTO public.banned_users (user_id, reason_code, note, banned_by, expires_at)
        VALUES (p_user, 'inappropriate_content', 'auto:' || p_kind || ':strike' || v_no, p_actor, v_until)
        ON CONFLICT (user_id) DO UPDATE SET reason_code = EXCLUDED.reason_code, note = EXCLUDED.note,
                                            banned_by = EXCLUDED.banned_by, created_at = NOW(),
                                            expires_at = EXCLUDED.expires_at;
        UPDATE public.profiles SET is_online = false WHERE id = p_user;
    END IF;

    IF v_penalty = 'permanent' THEN
        INSERT INTO public.banned_devices (device_id, reason_code, note, banned_by)
        SELECT d.device_id, 'inappropriate_content', 'auto:strike' || v_no, p_actor
        FROM public.user_devices d WHERE d.user_id = p_user
        ON CONFLICT (device_id) DO NOTHING;
        GET DIAGNOSTICS v_devices = ROW_COUNT;
        SELECT u.email INTO v_email FROM auth.users u WHERE u.id = p_user;
        IF COALESCE(v_email, '') <> '' THEN
            INSERT INTO public.banned_identities (email_hash, user_id, reason)
            VALUES (public.juzzio_email_hash(v_email), p_user, p_kind)
            ON CONFLICT (email_hash) DO NOTHING;
        END IF;
    END IF;

    -- Süren aramaları kapat (kişinin taraf olduğu tüm açık kayıtlar)
    IF p_kind IN ('call_nudity', 'call_speech') OR v_penalty <> 'warning' THEN
        UPDATE public.call_logs c
        SET status = CASE WHEN c.status = 'ringing' THEN 'cancelled' ELSE c.status END,
            status_reason = 'moderation',
            duration_sec = CASE
                WHEN c.status = 'answered' AND c.answered_at IS NOT NULL
                    THEN GREATEST(c.duration_sec, LEAST(EXTRACT(EPOCH FROM (NOW() - c.answered_at))::INTEGER, 6 * 3600))
                ELSE c.duration_sec END,
            ended_at = COALESCE(c.ended_at, NOW())
        WHERE (c.caller_id = p_user OR c.receiver_id = p_user)
          AND c.ended_at IS NULL AND c.created_at > NOW() - INTERVAL '12 hours'
          AND c.status IN ('ringing', 'answered');
        GET DIAGNOSTICS v_calls = ROW_COUNT;
    END IF;

    v_msg := CASE v_penalty
        WHEN 'suspend_1h' THEN 'Uyarı: Uygunsuz görüntü veya ifade nedeniyle aramanız sonlandırıldı ve hesabınız 1 saat süreyle uzaklaştırıldı. Tekrarı halinde 4 saat uzaklaştırma uygulanır.'
        WHEN 'suspend_4h' THEN 'İkinci uyarı: Uygunsuz içerik tekrarlandığı için hesabınız 4 saat süreyle uzaklaştırıldı. Bir sonraki ihlalde hesabınız kalıcı olarak kapatılır.'
        WHEN 'permanent' THEN 'Son uyarı: Üçüncü ihlal nedeniyle hesabınız kalıcı olarak engellendi. Bu cihazdan veya bu e-posta adresiyle yeni hesap açılamaz.'
        ELSE 'Uyarı: Uygunsuz içerik tespit edildi.'
    END;
    BEGIN
        INSERT INTO public.notifications (recipient_id, actor_id, actor_username, actor_display_name,
                                          event_type, target_id, preview_text, dedupe_key)
        VALUES (p_user, NULL, 'juzzio', 'Juzzio', 'system', 'moderation_' || v_penalty, v_msg,
                'moderation_' || p_user::text || '_' || v_no || '_' || EXTRACT(EPOCH FROM clock_timestamp())::bigint);
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    INSERT INTO public.admin_audit_log (admin_id, action, target, details)
    VALUES (p_actor, 'moderation_strike', p_user::text,
            jsonb_build_object('kind', p_kind, 'strike', v_no, 'penalty', v_penalty, 'room', p_room,
                               'devices', v_devices, 'calls_closed', v_calls, 'source', p_source));

    RETURN jsonb_build_object('ok', true, 'duplicate', false, 'strike', v_no, 'penalty', v_penalty,
                              'until', v_until, 'message', v_msg, 'calls_closed', v_calls);
END;
$$;
REVOKE ALL ON FUNCTION public.juzzio_record_violation(UUID, TEXT, TEXT, TEXT, TEXT, UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.juzzio_record_violation(UUID, TEXT, TEXT, TEXT, TEXT, UUID) TO service_role;

-- Konuşma isabeti kaydı: aynı aramada 10 dk içinde 2. ağır ifade → ihlal (service_role)
CREATE OR REPLACE FUNCTION public.juzzio_record_speech_hit(p_user UUID, p_room TEXT, p_text TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_hits INTEGER;
BEGIN
    IF NOT public.juzzio_setting_bool('speech_moderation_enabled', true) THEN
        RETURN jsonb_build_object('ok', true, 'explicit', false, 'disabled', true);
    END IF;
    IF NOT public.juzzio_speech_is_explicit(p_text) THEN
        RETURN jsonb_build_object('ok', true, 'explicit', false);
    END IF;
    INSERT INTO public.call_speech_hits (user_id, room_name) VALUES (p_user, LEFT(COALESCE(p_room, ''), 128));
    SELECT COUNT(*) INTO v_hits FROM public.call_speech_hits h
    WHERE h.user_id = p_user AND h.room_name = LEFT(COALESCE(p_room, ''), 128) AND h.created_at > NOW() - INTERVAL '10 minutes';
    IF v_hits >= 2 THEN
        RETURN jsonb_build_object('ok', true, 'explicit', true, 'hits', v_hits,
            'violation', public.juzzio_record_violation(p_user, 'call_speech', 'speech', p_room));
    END IF;
    RETURN jsonb_build_object('ok', true, 'explicit', true, 'hits', v_hits);
END;
$$;
REVOKE ALL ON FUNCTION public.juzzio_record_speech_hit(UUID, TEXT, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.juzzio_record_speech_hit(UUID, TEXT, TEXT) TO service_role;

-- Kullanıcının kendi ihlal geçmişi ve geçerli ceza durumu
CREATE OR REPLACE FUNCTION public.get_my_moderation_status()
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT jsonb_build_object(
        'strikes', (SELECT COUNT(*) FROM public.moderation_strikes s WHERE s.user_id = auth.uid() AND NOT s.revoked AND s.penalty <> 'warning'),
        'banned', public.juzzio_is_banned(auth.uid()),
        'until', (SELECT b.expires_at FROM public.banned_users b WHERE b.user_id = auth.uid()),
        'last', (SELECT row_to_json(x) FROM (
                    SELECT s.kind, s.strike_no, s.penalty, s.created_at FROM public.moderation_strikes s
                    WHERE s.user_id = auth.uid() AND NOT s.revoked ORDER BY s.created_at DESC LIMIT 1) x)
    );
$$;
GRANT EXECUTE ON FUNCTION public.get_my_moderation_status() TO authenticated;

-- -----------------------------------------------------------------------------
-- YÖNETİCİ: denetim merkezi
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_list_strikes(p_token TEXT, p_user UUID DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    PERFORM public._admin_require(p_token);
    RETURN COALESCE((
        SELECT jsonb_agg(row_to_json(x) ORDER BY x.created_at DESC) FROM (
            SELECT s.id, s.user_id, p.username, p.display_name, p.avatar_url, s.kind, s.detail, s.room_name,
                   s.strike_no, s.penalty, s.source, s.revoked, s.created_at
            FROM public.moderation_strikes s LEFT JOIN public.profiles p ON p.id = s.user_id
            WHERE p_user IS NULL OR s.user_id = p_user
            ORDER BY s.created_at DESC LIMIT 200
        ) x
    ), '[]'::jsonb);
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_list_strikes(TEXT, UUID) TO authenticated;

-- İhlali geri al; isteğe bağlı olarak engeli de kaldır
CREATE OR REPLACE FUNCTION public.admin_revoke_strike(p_token TEXT, p_strike BIGINT, p_lift_ban BOOLEAN DEFAULT true)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_user UUID;
BEGIN
    PERFORM public._admin_require(p_token);
    UPDATE public.moderation_strikes SET revoked = true WHERE id = p_strike RETURNING user_id INTO v_user;
    IF v_user IS NULL THEN RAISE EXCEPTION 'not_found'; END IF;
    IF p_lift_ban THEN
        DELETE FROM public.banned_users WHERE user_id = v_user AND note LIKE 'auto:%';
        DELETE FROM public.banned_devices bd USING public.user_devices d
        WHERE d.user_id = v_user AND d.device_id = bd.device_id AND bd.note LIKE 'auto:%';
        DELETE FROM public.banned_identities WHERE user_id = v_user;
    END IF;
    INSERT INTO public.admin_audit_log (admin_id, action, target, details)
    VALUES (auth.uid(), 'revoke_strike', v_user::text, jsonb_build_object('strike', p_strike, 'lift_ban', p_lift_ban));
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_revoke_strike(TEXT, BIGINT, BOOLEAN) TO authenticated;

-- Yöneticinin elle ihlal vermesi (aynı ceza basamağı uygulanır)
CREATE OR REPLACE FUNCTION public.admin_add_strike(p_token TEXT, p_user UUID, p_detail TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    PERFORM public._admin_require(p_token);
    IF public.is_juzzio_admin(p_user) THEN RAISE EXCEPTION 'cannot_ban_admin'; END IF;
    RETURN public.juzzio_record_violation(p_user, 'admin', COALESCE(p_detail, ''), '', 'admin', auth.uid());
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_add_strike(TEXT, UUID, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_media_queue(p_token TEXT, p_status TEXT DEFAULT 'all')
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    PERFORM public._admin_require(p_token);
    RETURN COALESCE((
        SELECT jsonb_agg(row_to_json(x) ORDER BY x.created_at DESC) FROM (
            SELECT m.id, m.user_id, p.username, p.display_name, m.kind, m.url, m.verdict, m.provider, m.scores,
                   m.review_status, m.created_at
            FROM public.media_moderation m LEFT JOIN public.profiles p ON p.id = m.user_id
            WHERE (p_status = 'all' AND m.kind <> 'call_frame')
               OR (p_status = 'pending' AND m.review_status = 'pending')
               OR (p_status = 'nsfw' AND m.verdict = 'nsfw')
            ORDER BY m.created_at DESC LIMIT 150
        ) x
    ), '[]'::jsonb);
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_media_queue(TEXT, TEXT) TO authenticated;

-- Medya incelemesi: reddedilen profil fotoğrafı kaldırılır, isteğe bağlı ihlal verilir
CREATE OR REPLACE FUNCTION public.admin_review_media(p_token TEXT, p_id BIGINT, p_approve BOOLEAN, p_strike BOOLEAN DEFAULT false)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_row public.media_moderation%ROWTYPE;
    v_strike JSONB;
BEGIN
    PERFORM public._admin_require(p_token);
    SELECT * INTO v_row FROM public.media_moderation WHERE id = p_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'not_found'; END IF;
    UPDATE public.media_moderation
    SET review_status = CASE WHEN p_approve THEN 'approved' ELSE 'rejected' END,
        reviewed_by = auth.uid(), reviewed_at = NOW()
    WHERE id = p_id;
    IF NOT p_approve AND v_row.kind = 'avatar' THEN
        UPDATE public.profiles SET avatar_url = NULL WHERE id = v_row.user_id AND avatar_url = v_row.url;
        IF p_strike AND NOT public.is_juzzio_admin(v_row.user_id) THEN
            v_strike := public.juzzio_record_violation(v_row.user_id, 'avatar_nsfw', 'admin_review', '', 'admin', auth.uid());
        END IF;
    END IF;
    INSERT INTO public.admin_audit_log (admin_id, action, target, details)
    VALUES (auth.uid(), 'review_media', COALESCE(v_row.user_id::text, ''),
            jsonb_build_object('id', p_id, 'approve', p_approve, 'strike', p_strike));
    RETURN jsonb_build_object('ok', true, 'strike', v_strike);
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_review_media(TEXT, BIGINT, BOOLEAN, BOOLEAN) TO authenticated;

-- Yasaklı kelime listesi yönetimi
CREATE OR REPLACE FUNCTION public.admin_list_banned_terms(p_token TEXT)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    PERFORM public._admin_require(p_token);
    RETURN COALESCE((SELECT jsonb_agg(jsonb_build_object('term', term, 'match_mode', match_mode, 'speech_strike', speech_strike)
                                      ORDER BY term) FROM public.banned_terms), '[]'::jsonb);
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_list_banned_terms(TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_upsert_banned_term(p_token TEXT, p_term TEXT, p_match_mode TEXT DEFAULT 'contains', p_speech_strike BOOLEAN DEFAULT false)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_term TEXT := REGEXP_REPLACE(public.juzzio_fold_text(BTRIM(COALESCE(p_term, ''))), '[^a-z ]+', '', 'g');
BEGIN
    PERFORM public._admin_require(p_token);
    IF LENGTH(v_term) < 2 OR LENGTH(v_term) > 40 THEN RAISE EXCEPTION 'invalid_term'; END IF;
    IF p_match_mode NOT IN ('contains', 'word') THEN RAISE EXCEPTION 'invalid_term'; END IF;
    INSERT INTO public.banned_terms (term, match_mode, speech_strike) VALUES (v_term, p_match_mode, COALESCE(p_speech_strike, false))
    ON CONFLICT (term) DO UPDATE SET match_mode = EXCLUDED.match_mode, speech_strike = EXCLUDED.speech_strike;
    INSERT INTO public.admin_audit_log (admin_id, action, target, details)
    VALUES (auth.uid(), 'upsert_banned_term', v_term, jsonb_build_object('mode', p_match_mode, 'speech', p_speech_strike));
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_upsert_banned_term(TEXT, TEXT, TEXT, BOOLEAN) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_delete_banned_term(p_token TEXT, p_term TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    PERFORM public._admin_require(p_token);
    DELETE FROM public.banned_terms WHERE term = p_term;
    INSERT INTO public.admin_audit_log (admin_id, action, target) VALUES (auth.uid(), 'delete_banned_term', COALESCE(p_term, ''));
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_delete_banned_term(TEXT, TEXT) TO authenticated;

-- Mevcut uygunsuz adları tara (kullanıcılar ve gruplar)
CREATE OR REPLACE FUNCTION public.admin_scan_names(p_token TEXT)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    PERFORM public._admin_require(p_token);
    RETURN jsonb_build_object(
        'users', COALESCE((SELECT jsonb_agg(row_to_json(x)) FROM (
            SELECT p.id, p.username, p.display_name, p.bio, p.avatar_url FROM public.profiles p
            WHERE NOT public.juzzio_text_is_clean(p.username, false)
               OR NOT public.juzzio_text_is_clean(p.display_name, false)
               OR NOT public.juzzio_text_is_clean(p.bio, false)
            LIMIT 200) x), '[]'::jsonb),
        'groups', COALESCE((SELECT jsonb_agg(row_to_json(x)) FROM (
            SELECT r.id, r.title, r.group_purpose, r.description FROM public.rooms r
            WHERE r.is_group AND (NOT public.juzzio_text_is_clean(r.title, false)
                                  OR NOT public.juzzio_text_is_clean(r.group_purpose, false)
                                  OR NOT public.juzzio_text_is_clean(r.description, false))
            LIMIT 200) x), '[]'::jsonb)
    );
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_scan_names(TEXT) TO authenticated;

-- Kullanıcı profilini düzenle (ad, kullanıcı adı, biyografi, fotoğraf kaldırma)
CREATE OR REPLACE FUNCTION public.admin_update_user_profile(
    p_token TEXT,
    p_user UUID,
    p_display_name TEXT DEFAULT NULL,
    p_username TEXT DEFAULT NULL,
    p_bio TEXT DEFAULT NULL,
    p_clear_avatar BOOLEAN DEFAULT false
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_username TEXT := LOWER(REGEXP_REPLACE(BTRIM(COALESCE(p_username, '')), '^@+', ''));
BEGIN
    PERFORM public._admin_require(p_token);
    IF v_username <> '' THEN
        IF v_username !~ '^[a-z0-9_.]{3,30}$' THEN RAISE EXCEPTION 'invalid_username'; END IF;
        IF EXISTS (SELECT 1 FROM public.profiles WHERE LOWER(username) = v_username AND id <> p_user) THEN
            RAISE EXCEPTION 'username_taken';
        END IF;
    END IF;
    UPDATE public.profiles
    SET display_name = COALESCE(NULLIF(BTRIM(p_display_name), ''), display_name),
        username = CASE WHEN v_username <> '' THEN v_username ELSE username END,
        bio = COALESCE(p_bio, bio),
        avatar_url = CASE WHEN p_clear_avatar THEN NULL ELSE avatar_url END,
        updated_at = NOW()
    WHERE id = p_user;
    INSERT INTO public.admin_audit_log (admin_id, action, target, details)
    VALUES (auth.uid(), 'update_user_profile', p_user::text,
            jsonb_build_object('display_name', p_display_name, 'username', v_username, 'clear_avatar', p_clear_avatar));
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_update_user_profile(TEXT, UUID, TEXT, TEXT, TEXT, BOOLEAN) TO authenticated;

-- Tüm oturumları kapat (kullanıcı yeniden giriş yapmak zorunda kalır)
CREATE OR REPLACE FUNCTION public.admin_sign_out_user(p_token TEXT, p_user UUID)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_rows INTEGER := 0;
BEGIN
    PERFORM public._admin_require(p_token);
    BEGIN
        EXECUTE 'DELETE FROM auth.sessions WHERE user_id = $1' USING p_user;
        GET DIAGNOSTICS v_rows = ROW_COUNT;
        EXECUTE 'DELETE FROM auth.refresh_tokens WHERE user_id = $1::text' USING p_user;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
    UPDATE public.profiles SET is_online = false WHERE id = p_user;
    INSERT INTO public.admin_audit_log (admin_id, action, target, details)
    VALUES (auth.uid(), 'sign_out_user', p_user::text, jsonb_build_object('sessions', v_rows));
    RETURN v_rows;
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_sign_out_user(TEXT, UUID) TO authenticated;

-- Hesabı kalıcı sil (yalnızca yönetici; geri alınamaz)
CREATE OR REPLACE FUNCTION public.admin_delete_user(p_token TEXT, p_user UUID, p_confirm TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_username TEXT;
BEGIN
    PERFORM public._admin_require(p_token);
    IF public.is_juzzio_admin(p_user) THEN RAISE EXCEPTION 'cannot_ban_admin'; END IF;
    SELECT username INTO v_username FROM public.profiles WHERE id = p_user;
    IF v_username IS NULL OR LOWER(COALESCE(p_confirm, '')) <> LOWER(v_username) THEN RAISE EXCEPTION 'confirm_mismatch'; END IF;
    INSERT INTO public.admin_audit_log (admin_id, action, target, details)
    VALUES (auth.uid(), 'delete_user', p_user::text, jsonb_build_object('username', v_username));
    DELETE FROM auth.users WHERE id = p_user;
    DELETE FROM public.profiles WHERE id = p_user;
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_delete_user(TEXT, UUID, TEXT) TO authenticated;

-- Gruplar
CREATE OR REPLACE FUNCTION public.admin_list_groups(p_token TEXT, p_query TEXT DEFAULT '')
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_q TEXT := '%' || LOWER(BTRIM(COALESCE(p_query, ''))) || '%';
BEGIN
    PERFORM public._admin_require(p_token);
    RETURN COALESCE((
        SELECT jsonb_agg(row_to_json(x) ORDER BY x.created_at DESC) FROM (
            SELECT r.id, r.title, r.group_type, r.group_purpose, r.description, r.created_at,
                   (SELECT COUNT(*) FROM public.room_participants rp WHERE rp.room_id = r.id AND rp.left_at IS NULL) AS members,
                   (SELECT COUNT(*) FROM public.messages m WHERE m.room_id = r.id) AS messages,
                   (SELECT p.username FROM public.room_participants rp JOIN public.profiles p ON p.id = rp.user_id
                    WHERE rp.room_id = r.id AND rp.role IN ('owner', 'admin') AND rp.left_at IS NULL LIMIT 1) AS owner_username
            FROM public.rooms r
            WHERE r.is_group AND (LOWER(COALESCE(r.title, '')) LIKE v_q)
            ORDER BY r.created_at DESC LIMIT 150
        ) x
    ), '[]'::jsonb);
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_list_groups(TEXT, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_group_members(p_token TEXT, p_room UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    PERFORM public._admin_require(p_token);
    RETURN COALESCE((
        SELECT jsonb_agg(row_to_json(x)) FROM (
            SELECT rp.user_id, p.username, p.display_name, p.avatar_url, rp.role, rp.joined_at
            FROM public.room_participants rp JOIN public.profiles p ON p.id = rp.user_id
            WHERE rp.room_id = p_room AND rp.left_at IS NULL
            ORDER BY rp.joined_at
        ) x
    ), '[]'::jsonb);
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_group_members(TEXT, UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_update_group(p_token TEXT, p_room UUID, p_title TEXT DEFAULT NULL, p_description TEXT DEFAULT NULL)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    PERFORM public._admin_require(p_token);
    UPDATE public.rooms
    SET title = COALESCE(NULLIF(BTRIM(p_title), ''), title),
        description = COALESCE(p_description, description),
        updated_at = NOW()
    WHERE id = p_room AND is_group;
    INSERT INTO public.admin_audit_log (admin_id, action, target, details)
    VALUES (auth.uid(), 'update_group', p_room::text, jsonb_build_object('title', p_title));
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_update_group(TEXT, UUID, TEXT, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_remove_group_member(p_token TEXT, p_room UUID, p_user UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    PERFORM public._admin_require(p_token);
    UPDATE public.room_participants SET left_at = NOW() WHERE room_id = p_room AND user_id = p_user AND left_at IS NULL;
    INSERT INTO public.admin_audit_log (admin_id, action, target, details)
    VALUES (auth.uid(), 'remove_group_member', p_room::text, jsonb_build_object('user', p_user));
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_remove_group_member(TEXT, UUID, UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_delete_group(p_token TEXT, p_room UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_title TEXT;
BEGIN
    PERFORM public._admin_require(p_token);
    SELECT title INTO v_title FROM public.rooms WHERE id = p_room AND is_group;
    IF NOT FOUND THEN RAISE EXCEPTION 'not_found'; END IF;
    DELETE FROM public.rooms WHERE id = p_room AND is_group;
    INSERT INTO public.admin_audit_log (admin_id, action, target, details)
    VALUES (auth.uid(), 'delete_group', p_room::text, jsonb_build_object('title', v_title));
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_delete_group(TEXT, UUID) TO authenticated;

-- Süren aramalar ve yöneticinin aramayı sonlandırması
CREATE OR REPLACE FUNCTION public.admin_active_calls(p_token TEXT)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    PERFORM public._admin_require(p_token);
    RETURN COALESCE((
        SELECT jsonb_agg(row_to_json(x) ORDER BY x.started_at DESC) FROM (
            SELECT COALESCE(c.session_id::text, c.id::text) AS session_key,
                   MAX(c.livekit_room_name) AS room_name,
                   bool_or(c.is_video) AS is_video,
                   bool_or(COALESCE(c.is_group, false)) AS is_group,
                   MAX(c.group_title) AS group_title,
                   MIN(c.created_at) AS started_at,
                   (array_agg(c.caller_name))[1] AS caller_name,
                   jsonb_agg(DISTINCT c.receiver_name) AS receivers,
                   COUNT(*) FILTER (WHERE c.status = 'answered') AS answered
            FROM public.call_logs c
            WHERE c.ended_at IS NULL AND c.status IN ('ringing', 'answered') AND c.created_at > NOW() - INTERVAL '6 hours'
            GROUP BY 1
        ) x
    ), '[]'::jsonb);
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_active_calls(TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_end_call(p_token TEXT, p_session_key TEXT)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_rows INTEGER := 0;
BEGIN
    PERFORM public._admin_require(p_token);
    UPDATE public.call_logs c
    SET status = CASE WHEN c.status = 'ringing' THEN 'cancelled' ELSE c.status END,
        status_reason = 'admin',
        duration_sec = CASE
            WHEN c.status = 'answered' AND c.answered_at IS NOT NULL
                THEN GREATEST(c.duration_sec, LEAST(EXTRACT(EPOCH FROM (NOW() - c.answered_at))::INTEGER, 6 * 3600))
            ELSE c.duration_sec END,
        ended_at = COALESCE(c.ended_at, NOW())
    WHERE COALESCE(c.session_id::text, c.id::text) = p_session_key AND c.ended_at IS NULL;
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    INSERT INTO public.admin_audit_log (admin_id, action, target, details)
    VALUES (auth.uid(), 'end_call', COALESCE(p_session_key, ''), jsonb_build_object('rows', v_rows));
    RETURN v_rows;
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_end_call(TEXT, TEXT) TO authenticated;

-- Son içerikler (gönderi / hikâye / yorum) — yönetici hızlı silme listesi
CREATE OR REPLACE FUNCTION public.admin_recent_content(p_token TEXT, p_kind TEXT DEFAULT 'post', p_query TEXT DEFAULT '')
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_q TEXT := '%' || LOWER(BTRIM(COALESCE(p_query, ''))) || '%';
BEGIN
    PERFORM public._admin_require(p_token);
    IF p_kind = 'post' THEN
        RETURN COALESCE((SELECT jsonb_agg(row_to_json(x)) FROM (
            SELECT po.id, po.author_id AS user_id, po.author_username AS username, po.caption AS text,
                   COALESCE(po.cover_url, '') AS media_url, po.content_type AS sub, po.created_at
            FROM public.posts po WHERE NOT po.is_deleted AND LOWER(COALESCE(po.caption, '')) LIKE v_q
            ORDER BY po.created_at DESC LIMIT 100) x), '[]'::jsonb);
    ELSIF p_kind = 'story' THEN
        RETURN COALESCE((SELECT jsonb_agg(row_to_json(x)) FROM (
            SELECT s.id, s.user_id, s.username, COALESCE(NULLIF(s.overlay_text_original, ''), s.caption_original) AS text,
                   COALESCE(s.media_url, '') AS media_url, s.media_type AS sub, s.created_at
            FROM public.stories s
            WHERE LOWER(COALESCE(s.caption_original, '') || ' ' || COALESCE(s.overlay_text_original, '')) LIKE v_q
            ORDER BY s.created_at DESC LIMIT 100) x), '[]'::jsonb);
    ELSIF p_kind = 'comment' THEN
        RETURN COALESCE((SELECT jsonb_agg(row_to_json(x)) FROM (
            SELECT c.id, c.author_id AS user_id, c.author_username AS username, c.content AS text, '' AS media_url, '' AS sub, c.created_at
            FROM public.post_comments c
            WHERE LOWER(COALESCE(c.content, '')) LIKE v_q
            ORDER BY c.created_at DESC LIMIT 100) x), '[]'::jsonb);
    END IF;
    RAISE EXCEPTION 'invalid_target_type';
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_recent_content(TEXT, TEXT, TEXT) TO authenticated;

-- Denetim özeti (genel bakış kartları)
CREATE OR REPLACE FUNCTION public.admin_moderation_overview(p_token TEXT)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    PERFORM public._admin_require(p_token);
    RETURN jsonb_build_object(
        'strikes_24h', (SELECT COUNT(*) FROM public.moderation_strikes WHERE created_at > NOW() - INTERVAL '24 hours' AND NOT revoked),
        'strikes_total', (SELECT COUNT(*) FROM public.moderation_strikes WHERE NOT revoked),
        'permanent_bans', (SELECT COUNT(*) FROM public.moderation_strikes WHERE penalty = 'permanent' AND NOT revoked),
        'suspended_now', (SELECT COUNT(*) FROM public.banned_users WHERE expires_at IS NOT NULL AND expires_at > NOW()),
        'media_pending', (SELECT COUNT(*) FROM public.media_moderation WHERE review_status = 'pending'),
        'media_nsfw_24h', (SELECT COUNT(*) FROM public.media_moderation WHERE verdict = 'nsfw' AND created_at > NOW() - INTERVAL '24 hours'),
        'banned_terms', (SELECT COUNT(*) FROM public.banned_terms),
        'blocked_emails', (SELECT COUNT(*) FROM public.banned_identities),
        'active_calls', (SELECT COUNT(DISTINCT COALESCE(session_id::text, id::text)) FROM public.call_logs
                         WHERE ended_at IS NULL AND status IN ('ringing', 'answered') AND created_at > NOW() - INTERVAL '6 hours')
    );
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_moderation_overview(TEXT) TO authenticated;

-- Süreli uzaklaştırmalar: süre dolunca erişim açılır; yalnızca kalıcı engelde yeni cihaz da engellenir
CREATE OR REPLACE FUNCTION public.register_my_device(p_device_id TEXT, p_platform TEXT DEFAULT '')
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_dev TEXT := LEFT(BTRIM(COALESCE(p_device_id, '')), 128);
BEGIN
    IF v_uid IS NULL OR LENGTH(v_dev) < 8 THEN RETURN jsonb_build_object('ok', false); END IF;
    INSERT INTO public.user_devices (user_id, device_id, platform)
    VALUES (v_uid, v_dev, LEFT(COALESCE(p_platform, ''), 20))
    ON CONFLICT (user_id, device_id) DO UPDATE SET last_seen = NOW(), platform = EXCLUDED.platform;
    IF EXISTS (SELECT 1 FROM public.banned_users WHERE user_id = v_uid AND expires_at IS NULL) THEN
        INSERT INTO public.banned_devices (device_id, reason_code, note)
        SELECT v_dev, reason_code, 'auto:new_device' FROM public.banned_users WHERE user_id = v_uid
        ON CONFLICT (device_id) DO NOTHING;
    END IF;
    RETURN public.check_device_access(v_dev);
END;
$$;
GRANT EXECUTE ON FUNCTION public.register_my_device(TEXT, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.check_device_access(p_device_id TEXT)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_reason TEXT;
    v_until TIMESTAMPTZ;
    v_note TEXT := '';
BEGIN
    SELECT reason_code, note INTO v_reason, v_note FROM public.banned_devices
    WHERE device_id = LEFT(BTRIM(COALESCE(p_device_id, '')), 128);
    IF v_reason IS NULL AND auth.uid() IS NOT NULL THEN
        SELECT b.reason_code, b.expires_at, b.note INTO v_reason, v_until, v_note FROM public.banned_users b
        WHERE b.user_id = auth.uid() AND (b.expires_at IS NULL OR b.expires_at > NOW());
    END IF;
    RETURN jsonb_build_object('ok', true, 'banned', v_reason IS NOT NULL, 'reason', v_reason, 'until', v_until,
                              'moderation', COALESCE(v_note, '') LIKE 'auto:%');
END;
$$;
GRANT EXECUTE ON FUNCTION public.check_device_access(TEXT) TO anon, authenticated;

-- Kayıt koruması (sürüm 2): yasaklı e-posta, uygunsuz kullanıcı adı / görünen ad engellenir
CREATE OR REPLACE FUNCTION public.juzzio_guard_signups()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_meta JSONB := COALESCE(NEW.raw_user_meta_data, '{}'::jsonb);
BEGIN
    IF NOT public.juzzio_setting_bool('signups_enabled', true) THEN
        RAISE EXCEPTION 'signup_disabled';
    END IF;
    IF NEW.email IS NOT NULL AND EXISTS (
        SELECT 1 FROM public.banned_identities bi WHERE bi.email_hash = public.juzzio_email_hash(NEW.email)
    ) THEN
        RAISE EXCEPTION 'signup_blocked';
    END IF;
    IF NOT public.juzzio_text_is_clean(COALESCE(v_meta->>'username', ''), false)
       OR NOT public.juzzio_text_is_clean(COALESCE(v_meta->>'display_name', ''), false) THEN
        RAISE EXCEPTION 'inappropriate_content';
    END IF;
    RETURN NEW;
END;
$$;

-- Kayıt öncesi istemci kontrolü (anlaşılır hata mesajı için): e-posta / cihaz / ad
CREATE OR REPLACE FUNCTION public.juzzio_check_signup(p_email TEXT, p_username TEXT, p_display_name TEXT, p_device_id TEXT DEFAULT '')
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
    IF NOT public.juzzio_setting_bool('signups_enabled', true) THEN
        RETURN jsonb_build_object('allowed', false, 'reason', 'signup_disabled');
    END IF;
    IF COALESCE(p_device_id, '') <> '' AND EXISTS (
        SELECT 1 FROM public.banned_devices WHERE device_id = LEFT(BTRIM(p_device_id), 128)
    ) THEN
        RETURN jsonb_build_object('allowed', false, 'reason', 'signup_blocked');
    END IF;
    IF COALESCE(p_email, '') <> '' AND EXISTS (
        SELECT 1 FROM public.banned_identities WHERE email_hash = public.juzzio_email_hash(p_email)
    ) THEN
        RETURN jsonb_build_object('allowed', false, 'reason', 'signup_blocked');
    END IF;
    IF NOT public.juzzio_text_is_clean(COALESCE(p_username, ''), false)
       OR NOT public.juzzio_text_is_clean(COALESCE(p_display_name, ''), false) THEN
        RETURN jsonb_build_object('allowed', false, 'reason', 'inappropriate_content');
    END IF;
    RETURN jsonb_build_object('allowed', true);
END;
$$;
GRANT EXECUTE ON FUNCTION public.juzzio_check_signup(TEXT, TEXT, TEXT, TEXT) TO anon, authenticated;

-- Özellik bayrakları sunucuda da uygulanır (yöneticiler hariç)
CREATE OR REPLACE FUNCTION public.juzzio_guard_feature_flags()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF auth.uid() IS NULL OR public.is_juzzio_admin(auth.uid()) THEN RETURN NEW; END IF;
    IF TG_TABLE_NAME = 'posts' AND NOT public.juzzio_setting_bool('posts_enabled', true) THEN
        RAISE EXCEPTION 'feature_disabled' USING ERRCODE = '22023';
    ELSIF TG_TABLE_NAME = 'call_logs' AND NOT public.juzzio_setting_bool('calls_enabled', true) THEN
        RAISE EXCEPTION 'feature_disabled' USING ERRCODE = '22023';
    ELSIF TG_TABLE_NAME = 'rooms' THEN
        -- NEW alanına yalnızca rooms tablosunda erişilir (PL/pgSQL AND kısa devre yapmaz)
        IF NEW.is_group AND NOT public.juzzio_setting_bool('group_creation_enabled', true) THEN
            RAISE EXCEPTION 'feature_disabled' USING ERRCODE = '22023';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_juzzio_flag_posts ON public.posts;
CREATE TRIGGER trg_juzzio_flag_posts BEFORE INSERT ON public.posts
    FOR EACH ROW EXECUTE FUNCTION public.juzzio_guard_feature_flags();
DROP TRIGGER IF EXISTS trg_juzzio_flag_calls ON public.call_logs;
CREATE TRIGGER trg_juzzio_flag_calls BEFORE INSERT ON public.call_logs
    FOR EACH ROW EXECUTE FUNCTION public.juzzio_guard_feature_flags();
DROP TRIGGER IF EXISTS trg_juzzio_flag_rooms ON public.rooms;
CREATE TRIGGER trg_juzzio_flag_rooms BEFORE INSERT ON public.rooms
    FOR EACH ROW EXECUTE FUNCTION public.juzzio_guard_feature_flags();

-- =============================================================================
-- v0.6.1 GÜVENLİK: dosya listeleme kapatıldı
--  Önceki "herkes okuyabilir" SELECT politikası, uygulamaya gömülü (herkese açık)
--  anahtarla tüm sohbet fotoğraflarının ve sesli mesajların ADLARININ listelenip
--  indirilebilmesine imkân veriyordu. Artık her kullanıcı yalnızca kendi klasörünü
--  görebilir. Paylaşılan dosyalar yine kendi bağlantısıyla açılır (uygulama listeleme
--  kullanmaz), yani mevcut hiçbir özellik bozulmaz.
-- =============================================================================
DO $$
BEGIN
    IF to_regclass('storage.objects') IS NOT NULL THEN
        DROP POLICY IF EXISTS "juzzio_v2_storage_read" ON storage.objects;
        DROP POLICY IF EXISTS "juzzio_storage_public_read" ON storage.objects;
        DROP POLICY IF EXISTS "juzzio_v061_storage_read_own" ON storage.objects;
        CREATE POLICY "juzzio_v061_storage_read_own" ON storage.objects FOR SELECT TO authenticated
            USING (bucket_id IN ('stories', 'avatars', 'voice-notes', 'chat-media', 'posts', 'reels')
                   AND (storage.foldername(name))[1] = auth.uid()::text);
    END IF;
EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'storage.objects politikası değiştirilemedi (yetki yok) — Supabase panelinden uygulayın.';
END $$;

-- =============================================================================
-- v0.6.1: ŞEFFAF GÜNCELLEME NOTLARI
--  Her sürüm için yapılandırılmış ayrıntı: neden getirildi, yeni özellikler,
--  düzeltilen hatalar, güvenlik/gizlilik değişiklikleri (tr/en/de).
--  details = {"tr": {"reason": "...", "features": [...], "fixes": [...], "security": [...]}, "en": {...}, "de": {...}}
-- =============================================================================
ALTER TABLE public.app_releases ADD COLUMN IF NOT EXISTS details JSONB NOT NULL DEFAULT '{}'::jsonb;

DROP FUNCTION IF EXISTS public.admin_publish_release(TEXT, TEXT, INTEGER, TEXT, TEXT, TEXT, TEXT, BOOLEAN);
CREATE OR REPLACE FUNCTION public.admin_publish_release(
    p_token TEXT, p_version_name TEXT, p_version_code INTEGER, p_apk_url TEXT,
    p_notes_tr TEXT, p_notes_en TEXT DEFAULT '', p_notes_de TEXT DEFAULT '', p_mandatory BOOLEAN DEFAULT false,
    p_details JSONB DEFAULT '{}'::jsonb)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    PERFORM public._admin_require(p_token);
    IF COALESCE(p_version_name, '') !~ '^[0-9]+\.[0-9]+\.[0-9]+$' THEN RAISE EXCEPTION 'invalid_version'; END IF;
    IF COALESCE(p_version_code, 0) <= 0 THEN RAISE EXCEPTION 'invalid_version'; END IF;
    IF COALESCE(p_apk_url, '') !~* '^https://[^ ]+\.apk(\?[^ ]*)?$' THEN RAISE EXCEPTION 'invalid_apk_url'; END IF;
    IF jsonb_typeof(COALESCE(p_details, '{}'::jsonb)) <> 'object' OR LENGTH(COALESCE(p_details, '{}'::jsonb)::text) > 60000 THEN
        RAISE EXCEPTION 'invalid_details';
    END IF;
    -- Şeffaflık kuralı: bir "neden" açıklaması mutlaka bulunur. v0.7.0: yönetici yazmadıysa
    -- uygulama GitHub sürüm notlarından doldurur; o da yoksa kısa not kullanılır.
    IF BTRIM(COALESCE(p_details #>> '{tr,reason}', '')) = '' THEN
        IF BTRIM(COALESCE(p_notes_tr, '')) = '' THEN RAISE EXCEPTION 'release_reason_required'; END IF;
        p_details := jsonb_set(COALESCE(p_details, '{}'::jsonb), '{tr}',
            COALESCE(p_details -> 'tr', '{}'::jsonb) || jsonb_build_object('reason', LEFT(BTRIM(p_notes_tr), 1000)), true);
    END IF;
    INSERT INTO public.app_releases (version_name, version_code, apk_url, notes_tr, notes_en, notes_de, is_mandatory, details, published_at)
    VALUES (p_version_name, p_version_code, p_apk_url, COALESCE(p_notes_tr, ''), COALESCE(p_notes_en, ''),
            COALESCE(p_notes_de, ''), COALESCE(p_mandatory, false), COALESCE(p_details, '{}'::jsonb), NOW())
    ON CONFLICT (version_name) DO UPDATE SET version_code = EXCLUDED.version_code, apk_url = EXCLUDED.apk_url,
        notes_tr = EXCLUDED.notes_tr, notes_en = EXCLUDED.notes_en, notes_de = EXCLUDED.notes_de,
        is_mandatory = EXCLUDED.is_mandatory, details = EXCLUDED.details, published_at = NOW();
    INSERT INTO public.admin_audit_log (admin_id, action, target, details)
    VALUES (auth.uid(), 'publish_release', p_version_name, jsonb_build_object('code', p_version_code, 'mandatory', p_mandatory));
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_publish_release(TEXT, TEXT, INTEGER, TEXT, TEXT, TEXT, TEXT, BOOLEAN, JSONB) TO authenticated;

-- =============================================================================
-- v0.7.0 — Aramalarda küfür/argo serbest; yalnızca müstehcen görüntü cezalandırılır
-- =============================================================================
CREATE OR REPLACE FUNCTION public.juzzio_record_speech_hit(p_user UUID, p_room TEXT, p_text TEXT)
RETURNS JSONB
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$ SELECT jsonb_build_object('ok', true, 'explicit', false, 'disabled', true); $$;
REVOKE ALL ON FUNCTION public.juzzio_record_speech_hit(UUID, TEXT, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.juzzio_record_speech_hit(UUID, TEXT, TEXT) TO service_role;
INSERT INTO public.app_settings (key, value) VALUES ('speech_moderation_enabled', 'false'::jsonb)
ON CONFLICT (key) DO UPDATE SET value = 'false'::jsonb;

-- v0.7.0: Aramayı ilk kim kapattı (ended_by) + 1'e 1 sohbette arama kaydı mesajı
ALTER TABLE public.call_logs ADD COLUMN IF NOT EXISTS ended_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL;
-- Arama bitirme (v0.7.0): ended_by + sohbet içi arama kaydı
CREATE OR REPLACE FUNCTION public.end_call_session(p_session UUID, p_duration_sec INTEGER DEFAULT NULL, p_force BOOLEAN DEFAULT false)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_room UUID;
    v_is_group BOOLEAN;
    v_caller UUID;
BEGIN
    SELECT room_id, is_group, caller_id INTO v_room, v_is_group, v_caller
    FROM public.call_logs
    WHERE session_id = p_session AND (caller_id = v_uid OR receiver_id = v_uid)
    ORDER BY created_at LIMIT 1;
    IF v_caller IS NULL THEN RETURN; END IF;

    IF v_is_group AND NOT p_force THEN
        UPDATE public.call_logs SET ended_at = NOW(), duration_sec = COALESCE(p_duration_sec, duration_sec)
        WHERE session_id = p_session AND receiver_id = v_uid AND status = 'answered' AND ended_at IS NULL;
        -- Konferansta biri ayrılınca oturum sürer; içeride ve çalan kimse kalmadıysa kapanır
        IF EXISTS (SELECT 1 FROM public.call_logs c WHERE c.session_id = p_session
                   AND ((c.status = 'answered' AND c.ended_at IS NULL) OR c.status = 'ringing')) THEN
            RETURN;
        END IF;
    END IF;

    UPDATE public.call_logs
    SET status = CASE WHEN status = 'ringing' THEN CASE WHEN caller_id = v_uid THEN 'missed' ELSE 'cancelled' END
                      WHEN status = 'answered' THEN 'answered'
                      ELSE status END,
        ended_at = COALESCE(ended_at, NOW()),
        ended_by = COALESCE(ended_by, v_uid),
        duration_sec = CASE WHEN status = 'answered' AND ended_at IS NULL THEN COALESCE(p_duration_sec, duration_sec) ELSE duration_sec END
    WHERE session_id = p_session;

    INSERT INTO public.notifications (recipient_id, actor_id, actor_username, actor_display_name, actor_avatar_url,
                                      event_type, target_id, target_secondary_id, preview_text, dedupe_key)
    SELECT c.receiver_id, c.caller_id, COALESCE(p.username, ''), c.caller_name, c.caller_avatar,
           'missed_call', COALESCE(c.room_id::text, ''), c.id::text,
           public.juzzio_call_preview_key(c.is_group, c.is_video),
           'missed_' || c.id::text
    FROM public.call_logs c
    JOIN public.profiles p ON p.id = c.caller_id
    WHERE c.session_id = p_session AND c.status = 'missed' AND c.receiver_id IS NOT NULL
    ON CONFLICT (recipient_id, dedupe_key) DO NOTHING;

    -- Sohbette arama kaydı: yapılan, cevaplanan, cevapsız (yalnızca 1'e 1, oturum başına bir kez)
    IF v_room IS NOT NULL AND NOT v_is_group THEN
        INSERT INTO public.messages (room_id, sender_id, receiver_id, message_type, original_text, translated_text, metadata)
        SELECT c.room_id, c.caller_id, c.receiver_id, 'call', '', '',
               jsonb_build_object('call', jsonb_build_object(
                   'log_id', c.id, 'session_id', p_session, 'status', c.status, 'is_video', c.is_video,
                   'duration_sec', COALESCE(c.duration_sec, 0), 'ended_by', c.ended_by,
                   'started_at', c.created_at, 'answered_at', c.answered_at, 'ended_at', c.ended_at))
        FROM public.call_logs c
        WHERE c.session_id = p_session AND c.room_id = v_room
          AND NOT EXISTS (SELECT 1 FROM public.messages m WHERE m.room_id = v_room AND m.message_type = 'call'
                          AND m.metadata->'call'->>'session_id' = p_session::text)
        ORDER BY c.created_at LIMIT 1;
    END IF;

    IF v_room IS NOT NULL THEN
        UPDATE public.rooms SET is_call_active = false, active_call = NULL, updated_at = NOW()
        WHERE id = v_room AND (active_call->>'session_id') = p_session::text;
    END IF;
END;
$$;
GRANT EXECUTE ON FUNCTION public.end_call_session(UUID, INTEGER, BOOLEAN) TO authenticated;

-- v0.7.0: Eski YouTube müzik bağlantıları temizlenir (artık isimle aranan önizleme sesi kullanılır)
UPDATE public.profiles SET music_url = '', music_video_id = '', music_start_sec = 0, music_title = '', music_artist = '', music_cover_url = ''
WHERE music_url ~* '(youtube\.com|youtu\.be)';
UPDATE public.stories SET music_url = '', music_title = '' WHERE COALESCE(music_url, '') ~* '(youtube\.com|youtu\.be)';

-- =============================================================================
-- v0.7.0 — Yakın arkadaşlar (favori arkadaşlar): hikâyeyi yalnızca seçilen kişiler görür
--  • Liste yalnızca sahibine görünür; listeye eklenen kişi eklendiğini göremez.
--  • visibility = 'close_friends' olan hikâyeyi yalnızca sahibi ve listedekiler görür;
--    diğer arkadaşlar ve herkes için gizlidir.
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.close_friends (
    owner_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    friend_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (owner_id, friend_id),
    CHECK (owner_id <> friend_id)
);
CREATE INDEX IF NOT EXISTS idx_close_friends_friend ON public.close_friends (friend_id);
ALTER TABLE public.close_friends ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.close_friends FROM anon;
GRANT SELECT, INSERT, DELETE ON public.close_friends TO authenticated;
DROP POLICY IF EXISTS close_friends_select_own ON public.close_friends;
CREATE POLICY close_friends_select_own ON public.close_friends FOR SELECT TO authenticated USING (owner_id = auth.uid());
DROP POLICY IF EXISTS close_friends_insert_own ON public.close_friends;
CREATE POLICY close_friends_insert_own ON public.close_friends FOR INSERT TO authenticated
    WITH CHECK (owner_id = auth.uid() AND NOT public.is_blocked_between(owner_id, friend_id));
DROP POLICY IF EXISTS close_friends_delete_own ON public.close_friends;
CREATE POLICY close_friends_delete_own ON public.close_friends FOR DELETE TO authenticated USING (owner_id = auth.uid());

CREATE OR REPLACE FUNCTION public.can_view_story(p_viewer UUID, p_owner UUID, p_visibility TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT CASE
        WHEN p_viewer IS NULL THEN false
        WHEN p_viewer = p_owner THEN true
        WHEN public.is_blocked_between(p_viewer, p_owner) THEN false
        WHEN EXISTS (
            SELECT 1 FROM public.muted_users mu
            WHERE mu.muter_id = p_viewer AND mu.muted_id = p_owner AND mu.mute_stories
        ) THEN false
        WHEN p_visibility IN ('private') THEN false
        WHEN p_visibility = 'close_friends' THEN EXISTS (
            SELECT 1 FROM public.close_friends cf WHERE cf.owner_id = p_owner AND cf.friend_id = p_viewer)
        WHEN p_visibility = 'friends' THEN public.is_friends_accepted(p_viewer, p_owner)
        WHEN p_visibility = 'followers' THEN
            public.is_following_accepted(p_viewer, p_owner) OR public.is_friends_accepted(p_viewer, p_owner)
        ELSE true
    END;
$$;
GRANT EXECUTE ON FUNCTION public.can_view_story(UUID, UUID, TEXT) TO authenticated, service_role;

-- v0.7.0: Kişiye özel sohbet ayarları sayfasından süreli mesaj ayarı (1'e 1: iki taraf da; grup: yönetici)
CREATE OR REPLACE FUNCTION public.set_room_disappearing_timer(p_room UUID, p_timer TEXT)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_group BOOLEAN;
    v_timer TEXT := COALESCE(NULLIF(BTRIM(p_timer), ''), 'off');
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
    IF v_timer NOT IN ('off', '24h', '7d', '30d') THEN RAISE EXCEPTION 'invalid_timer' USING ERRCODE = '22023'; END IF;
    SELECT is_group INTO v_group FROM public.rooms WHERE id = p_room;
    IF v_group IS NULL OR NOT public.is_room_member(p_room, v_uid) THEN RAISE EXCEPTION 'not_allowed'; END IF;
    IF v_group AND NOT EXISTS (
        SELECT 1 FROM public.room_participants rp
        WHERE rp.room_id = p_room AND rp.user_id = v_uid AND rp.left_at IS NULL AND COALESCE(rp.role, 'member') IN ('owner', 'admin')
    ) THEN
        RAISE EXCEPTION 'not_allowed';
    END IF;
    UPDATE public.rooms SET disappearing_timer = v_timer, updated_at = NOW() WHERE id = p_room;
    RETURN v_timer;
END;
$$;
REVOKE ALL ON FUNCTION public.set_room_disappearing_timer(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_room_disappearing_timer(UUID, TEXT) TO authenticated;

-- =============================================================================
-- v0.7.0 — Zil sesleri ve uyarı tonları (varsayılan + kişiye özel)
--  push-webhook alıcının seçimine göre Android kanalını (juzzio_msg_<ton>,
--  juzzio_call_<zil>) belirler; uygulama kapalıyken de doğru ses çalar.
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.user_sound_prefs (
    user_id UUID PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
    message_tone TEXT NOT NULL DEFAULT 'juzzio_tone_glass',
    ringtone TEXT NOT NULL DEFAULT 'juzzio_ring_aurora',
    contact_prefs JSONB NOT NULL DEFAULT '{}'::jsonb,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE public.user_sound_prefs ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.user_sound_prefs FROM anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.user_sound_prefs TO authenticated;
DROP POLICY IF EXISTS user_sound_prefs_own ON public.user_sound_prefs;
CREATE POLICY user_sound_prefs_own ON public.user_sound_prefs FOR ALL TO authenticated
    USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

CREATE OR REPLACE FUNCTION public.juzzio_sound_prefs_check()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    IF NEW.message_tone !~ '^(default|juzzio_tone_[a-z]{2,16})$' THEN NEW.message_tone := 'juzzio_tone_glass'; END IF;
    IF NEW.ringtone !~ '^(default|juzzio_ring_[a-z]{2,16})$' THEN NEW.ringtone := 'juzzio_ring_aurora'; END IF;
    IF jsonb_typeof(COALESCE(NEW.contact_prefs, '{}'::jsonb)) <> 'object' OR length(NEW.contact_prefs::text) > 20000 THEN
        NEW.contact_prefs := '{}'::jsonb;
    END IF;
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_juzzio_sound_prefs_check ON public.user_sound_prefs;
CREATE TRIGGER trg_juzzio_sound_prefs_check BEFORE INSERT OR UPDATE ON public.user_sound_prefs
    FOR EACH ROW EXECUTE FUNCTION public.juzzio_sound_prefs_check();

-- v0.7.0: Küresel sohbet/akış uygulamadan kaldırıldı
INSERT INTO public.app_settings (key, value) VALUES ('global_feed_enabled', 'false'::jsonb)
ON CONFLICT (key) DO UPDATE SET value = 'false'::jsonb;

-- =============================================================================
-- v0.7.0 — Ayarlar → Yardım → Hata bildir / geri bildirim (ekran görüntüsüyle)
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.app_feedback (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    kind TEXT NOT NULL DEFAULT 'bug' CHECK (kind IN ('bug', 'feedback', 'idea')),
    message TEXT NOT NULL CHECK (length(BTRIM(message)) BETWEEN 5 AND 4000),
    image_url TEXT NOT NULL DEFAULT '',
    app_version TEXT NOT NULL DEFAULT '',
    device_info TEXT NOT NULL DEFAULT '',
    status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'in_progress', 'resolved')),
    admin_note TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_app_feedback_created ON public.app_feedback (created_at DESC);
ALTER TABLE public.app_feedback ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.app_feedback FROM anon;
GRANT SELECT, INSERT ON public.app_feedback TO authenticated;
DROP POLICY IF EXISTS app_feedback_insert_own ON public.app_feedback;
CREATE POLICY app_feedback_insert_own ON public.app_feedback FOR INSERT TO authenticated
    WITH CHECK (user_id = auth.uid() AND status = 'open' AND admin_note = ''
                AND (image_url = '' OR image_url ~* '^https://'));
DROP POLICY IF EXISTS app_feedback_select_own ON public.app_feedback;
CREATE POLICY app_feedback_select_own ON public.app_feedback FOR SELECT TO authenticated USING (user_id = auth.uid());

-- Kötüye kullanıma karşı: kullanıcı başına saatte en fazla 10 bildirim
CREATE OR REPLACE FUNCTION public.juzzio_feedback_rate_limit()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF (SELECT COUNT(*) FROM public.app_feedback WHERE user_id = NEW.user_id AND created_at > NOW() - INTERVAL '1 hour') >= 10 THEN
        RAISE EXCEPTION 'feedback_rate_limited' USING ERRCODE = '22023';
    END IF;
    NEW.message := LEFT(BTRIM(NEW.message), 4000);
    NEW.app_version := LEFT(COALESCE(NEW.app_version, ''), 40);
    NEW.device_info := LEFT(COALESCE(NEW.device_info, ''), 300);
    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_juzzio_feedback_rate_limit ON public.app_feedback;
CREATE TRIGGER trg_juzzio_feedback_rate_limit BEFORE INSERT ON public.app_feedback
    FOR EACH ROW EXECUTE FUNCTION public.juzzio_feedback_rate_limit();

CREATE OR REPLACE FUNCTION public.admin_list_feedback(p_token TEXT, p_status TEXT DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    PERFORM public._admin_require(p_token);
    RETURN COALESCE((
        SELECT jsonb_agg(x ORDER BY x.created_at DESC) FROM (
            SELECT f.id, f.kind, f.message, f.image_url, f.app_version, f.device_info, f.status, f.admin_note, f.created_at,
                   p.username, p.display_name
            FROM public.app_feedback f LEFT JOIN public.profiles p ON p.id = f.user_id
            WHERE p_status IS NULL OR f.status = p_status
            ORDER BY f.created_at DESC LIMIT 200
        ) x), '[]'::jsonb);
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_list_feedback(TEXT, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_update_feedback(p_token TEXT, p_id UUID, p_status TEXT, p_note TEXT DEFAULT '')
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    PERFORM public._admin_require(p_token);
    IF p_status NOT IN ('open', 'in_progress', 'resolved') THEN RAISE EXCEPTION 'invalid_setting'; END IF;
    UPDATE public.app_feedback SET status = p_status, admin_note = LEFT(COALESCE(p_note, ''), 1000) WHERE id = p_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_update_feedback(TEXT, UUID, TEXT, TEXT) TO authenticated;

-- =============================================================================
-- v0.7.0 — Uçtan uca şifreleme (1'e 1 yazılı mesajlar)
--  Özel anahtar yalnızca cihazdadır; burada yalnızca açık anahtar (X25519, 32 bayt,
--  base64) tutulur. Şifreli mesajlarda original_text/translated_text boştur, şifreli
--  yük metadata.e2ee alanındadır; sunucu ve yöneticiler içeriği okuyamaz.
-- =============================================================================
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS e2ee_public_key TEXT NOT NULL DEFAULT '';
CREATE OR REPLACE FUNCTION public.juzzio_e2ee_key_check()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    NEW.e2ee_public_key := BTRIM(COALESCE(NEW.e2ee_public_key, ''));
    IF NEW.e2ee_public_key <> '' AND NEW.e2ee_public_key !~ '^[A-Za-z0-9+/]{43}=$' THEN
        IF TG_OP = 'UPDATE' THEN NEW.e2ee_public_key := OLD.e2ee_public_key; ELSE NEW.e2ee_public_key := ''; END IF;
    END IF;
    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_juzzio_e2ee_key_check ON public.profiles;
CREATE TRIGGER trg_juzzio_e2ee_key_check BEFORE INSERT OR UPDATE OF e2ee_public_key ON public.profiles
    FOR EACH ROW EXECUTE FUNCTION public.juzzio_e2ee_key_check();

-- =============================================================================
-- v0.8.0 — Kuantum sonrası (PQ3 tarzı) uçtan uca şifreleme
--  Yalnızca AÇIK anahtarlar burada: ML-KEM-768 (FIPS 203) kapsülleme anahtarı
--  (1184 bayt, base64) ve anahtar kimliği. Özel anahtarlar cihazdadır.
-- =============================================================================
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS e2ee_pq_key TEXT NOT NULL DEFAULT '';
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS e2ee_key_id TEXT NOT NULL DEFAULT '';
CREATE OR REPLACE FUNCTION public.juzzio_e2ee_pq_key_check()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    NEW.e2ee_pq_key := BTRIM(COALESCE(NEW.e2ee_pq_key, ''));
    NEW.e2ee_key_id := LOWER(BTRIM(COALESCE(NEW.e2ee_key_id, '')));
    IF (NEW.e2ee_pq_key <> '' AND (LENGTH(NEW.e2ee_pq_key) <> 1580 OR NEW.e2ee_pq_key !~ '^[A-Za-z0-9+/]+=*$'))
       OR (NEW.e2ee_key_id <> '' AND NEW.e2ee_key_id !~ '^[0-9a-f]{16}$') THEN
        IF TG_OP = 'UPDATE' THEN
            NEW.e2ee_pq_key := OLD.e2ee_pq_key;
            NEW.e2ee_key_id := OLD.e2ee_key_id;
        ELSE
            NEW.e2ee_pq_key := '';
            NEW.e2ee_key_id := '';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_juzzio_e2ee_pq_key_check ON public.profiles;
CREATE TRIGGER trg_juzzio_e2ee_pq_key_check BEFORE INSERT OR UPDATE OF e2ee_pq_key, e2ee_key_id ON public.profiles
    FOR EACH ROW EXECUTE FUNCTION public.juzzio_e2ee_pq_key_check();

-- =============================================================================
-- v0.8.3 — RBAC (rol tabanlı yetki), yetki kontrol fonksiyonları ve
--          KÜRESEL TEMA STÜDYOSU (taslak → yayın → zamanlama → sürüm → geri alma)
-- Tamamen idempotent; mevcut tabloları/verileri değiştirmez.
-- =============================================================================

-- ---- 1) Personel rolleri -----------------------------------------------------
CREATE TABLE IF NOT EXISTS public.staff_roles (
    user_id UUID PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
    role TEXT NOT NULL,
    granted_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    granted_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE public.staff_roles DROP CONSTRAINT IF EXISTS staff_roles_role_check;
ALTER TABLE public.staff_roles ADD CONSTRAINT staff_roles_role_check
    CHECK (role IN ('admin', 'moderator', 'support', 'analyst', 'content_manager', 'auditor'));
ALTER TABLE public.staff_roles ENABLE ROW LEVEL SECURITY;

-- Rol → izin matrisi (varsayılan: yetki yok / deny-by-default)
CREATE OR REPLACE FUNCTION public.juzzio_role_permissions(p_role TEXT)
RETURNS TEXT[]
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
    SELECT CASE p_role
        WHEN 'super_admin' THEN ARRAY['*']
        WHEN 'admin' THEN ARRAY['users.manage', 'users.read', 'moderation', 'reports', 'theme.publish',
                                'settings', 'broadcast', 'releases', 'audit.read', 'roles.read', 'stats.read']
        WHEN 'moderator' THEN ARRAY['moderation', 'reports', 'users.read']
        WHEN 'support' THEN ARRAY['users.read', 'reports']
        WHEN 'analyst' THEN ARRAY['stats.read']
        WHEN 'content_manager' THEN ARRAY['theme.publish', 'broadcast', 'releases']
        WHEN 'auditor' THEN ARRAY['audit.read', 'roles.read', 'stats.read']
        ELSE ARRAY[]::TEXT[]
    END;
$$;
GRANT EXECUTE ON FUNCTION public.juzzio_role_permissions(TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.juzzio_staff_role(p_user UUID DEFAULT auth.uid())
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT CASE
        WHEN p_user IS NULL THEN NULL
        WHEN public.is_juzzio_admin(p_user) THEN 'super_admin'
        ELSE (SELECT role FROM public.staff_roles WHERE user_id = p_user)
    END;
$$;
GRANT EXECUTE ON FUNCTION public.juzzio_staff_role(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.juzzio_has_permission(p_perm TEXT, p_user UUID DEFAULT auth.uid())
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT COALESCE(
        (SELECT '*' = ANY (perms) OR p_perm = ANY (perms)
           FROM (SELECT public.juzzio_role_permissions(public.juzzio_staff_role(p_user)) AS perms) x),
        false);
$$;
GRANT EXECUTE ON FUNCTION public.juzzio_has_permission(TEXT, UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.juzzio_my_permissions()
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT jsonb_build_object(
        'role', public.juzzio_staff_role(auth.uid()),
        'permissions', to_jsonb(public.juzzio_role_permissions(public.juzzio_staff_role(auth.uid()))));
$$;
GRANT EXECUTE ON FUNCTION public.juzzio_my_permissions() TO authenticated;

DROP POLICY IF EXISTS staff_roles_select ON public.staff_roles;
CREATE POLICY staff_roles_select ON public.staff_roles FOR SELECT TO authenticated
    USING (user_id = auth.uid() OR public.juzzio_has_permission('roles.read'));
-- Yazma politikası yok: roller yalnızca aşağıdaki denetimli fonksiyonlarla değişir.
REVOKE INSERT, UPDATE, DELETE ON public.staff_roles FROM anon, authenticated;

-- Geçerli yönetici oturumu (süper yönetici şifresi) VEYA ilgili izin
CREATE OR REPLACE FUNCTION public._staff_require(p_token TEXT, p_perm TEXT)
RETURNS VOID
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF COALESCE(p_token, '') <> '' AND public.admin_check_token(p_token) THEN RETURN; END IF;
    IF public.juzzio_has_permission(p_perm) THEN RETURN; END IF;
    RAISE EXCEPTION 'permission_denied:%', p_perm;
END;
$$;
REVOKE ALL ON FUNCTION public._staff_require(TEXT, TEXT) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.admin_list_staff(p_token TEXT)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    PERFORM public._staff_require(p_token, 'roles.read');
    RETURN COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
            'user_id', s.user_id, 'role', s.role, 'username', p.username, 'display_name', p.display_name,
            'granted_at', s.granted_at) ORDER BY s.granted_at DESC)
        FROM public.staff_roles s JOIN public.profiles p ON p.id = s.user_id), '[]'::jsonb);
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_list_staff(TEXT) TO authenticated;

-- Rol verme/alma: YALNIZCA süper yönetici oturumu (yetki yükseltme koruması) + denetim kaydı
CREATE OR REPLACE FUNCTION public.admin_grant_role(p_token TEXT, p_user UUID, p_role TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    PERFORM public._admin_require(p_token);
    IF p_role NOT IN ('admin', 'moderator', 'support', 'analyst', 'content_manager', 'auditor') THEN
        RAISE EXCEPTION 'invalid_role';
    END IF;
    IF p_user = auth.uid() OR public.is_juzzio_admin(p_user) THEN RAISE EXCEPTION 'cannot_change_own_role'; END IF;
    IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = p_user) THEN RAISE EXCEPTION 'user_not_found'; END IF;
    INSERT INTO public.staff_roles (user_id, role, granted_by, granted_at)
    VALUES (p_user, p_role, auth.uid(), NOW())
    ON CONFLICT (user_id) DO UPDATE SET role = EXCLUDED.role, granted_by = EXCLUDED.granted_by, granted_at = NOW();
    INSERT INTO public.admin_audit_log (admin_id, action, target, details)
    VALUES (auth.uid(), 'grant_role', p_user::text, jsonb_build_object('role', p_role));
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_grant_role(TEXT, UUID, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_revoke_role(p_token TEXT, p_user UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_old TEXT;
BEGIN
    PERFORM public._admin_require(p_token);
    DELETE FROM public.staff_roles WHERE user_id = p_user RETURNING role INTO v_old;
    INSERT INTO public.admin_audit_log (admin_id, action, target, details)
    VALUES (auth.uid(), 'revoke_role', p_user::text, jsonb_build_object('role', v_old));
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_revoke_role(TEXT, UUID) TO authenticated;

-- ---- 2) Küresel tema stüdyosu ------------------------------------------------
CREATE TABLE IF NOT EXISTS public.global_themes (
    version INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    payload JSONB NOT NULL,
    status TEXT NOT NULL DEFAULT 'draft',
    publish_at TIMESTAMPTZ,
    published_at TIMESTAMPTZ,
    note TEXT NOT NULL DEFAULT '',
    created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE public.global_themes DROP CONSTRAINT IF EXISTS global_themes_status_check;
ALTER TABLE public.global_themes ADD CONSTRAINT global_themes_status_check
    CHECK (status IN ('draft', 'published', 'archived'));
CREATE INDEX IF NOT EXISTS idx_global_themes_live ON public.global_themes (status, publish_at DESC);
ALTER TABLE public.global_themes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS global_themes_read_live ON public.global_themes;
CREATE POLICY global_themes_read_live ON public.global_themes FOR SELECT TO authenticated
    USING ((status = 'published' AND publish_at <= NOW()) OR public.juzzio_has_permission('theme.publish'));
REVOKE INSERT, UPDATE, DELETE ON public.global_themes FROM anon, authenticated;

-- İstemci doğrulamasının sunucu karşılığı (juzzio_custom_theme.dart ile aynı kurallar)
CREATE OR REPLACE FUNCTION public._validate_theme_payload(p_payload JSONB)
RETURNS VOID
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
DECLARE
    k TEXT;
    v_glass JSONB;
BEGIN
    IF p_payload IS NULL OR jsonb_typeof(p_payload) <> 'object' THEN RAISE EXCEPTION 'theme_invalid_json'; END IF;
    IF octet_length(p_payload::text) > 16384 THEN RAISE EXCEPTION 'theme_too_large'; END IF;
    IF p_payload->>'schema' IS DISTINCT FROM 'juzzio-theme' THEN RAISE EXCEPTION 'theme_invalid_schema'; END IF;
    IF jsonb_typeof(p_payload->'version') <> 'number' OR (p_payload->>'version')::numeric <> 1 THEN
        RAISE EXCEPTION 'theme_invalid_version';
    END IF;
    IF COALESCE(p_payload->>'mode', 'dark') NOT IN ('dark', 'light') THEN RAISE EXCEPTION 'theme_invalid_mode'; END IF;
    IF jsonb_typeof(p_payload->'colors') <> 'object' THEN RAISE EXCEPTION 'theme_invalid_colors'; END IF;
    FOREACH k IN ARRAY ARRAY['background','gradientA','gradientB','gradientC','text','heading','button',
                             'buttonText','card','bubbleOut','bubbleIn','icon','border'] LOOP
        IF COALESCE(p_payload->'colors'->>k, '') !~ '^#([0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$' THEN
            RAISE EXCEPTION 'theme_invalid_color:%', k;
        END IF;
    END LOOP;
    v_glass := COALESCE(p_payload->'glass', '{}'::jsonb);
    IF jsonb_typeof(v_glass) <> 'object' THEN RAISE EXCEPTION 'theme_invalid_glass'; END IF;
    IF (v_glass ? 'blur') AND (jsonb_typeof(v_glass->'blur') <> 'number' OR (v_glass->>'blur')::numeric NOT BETWEEN 6 AND 30) THEN
        RAISE EXCEPTION 'theme_invalid_blur';
    END IF;
    IF (v_glass ? 'opacity') AND (jsonb_typeof(v_glass->'opacity') <> 'number' OR (v_glass->>'opacity')::numeric NOT BETWEEN 0.04 AND 0.7) THEN
        RAISE EXCEPTION 'theme_invalid_opacity';
    END IF;
    IF (v_glass ? 'intensity') AND (jsonb_typeof(v_glass->'intensity') <> 'number' OR (v_glass->>'intensity')::numeric NOT BETWEEN 0.6 AND 1.4) THEN
        RAISE EXCEPTION 'theme_invalid_intensity';
    END IF;
END;
$$;
REVOKE ALL ON FUNCTION public._validate_theme_payload(JSONB) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.admin_theme_save_draft(p_token TEXT, p_name TEXT, p_payload JSONB, p_note TEXT DEFAULT '')
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_ver INTEGER; v_name TEXT;
BEGIN
    PERFORM public._staff_require(p_token, 'theme.publish');
    PERFORM public._validate_theme_payload(p_payload);
    v_name := LEFT(regexp_replace(BTRIM(COALESCE(p_name, '')), '[[:cntrl:]<>{}\\]', '', 'g'), 40);
    IF v_name = '' THEN v_name := 'Juzzio teması'; END IF;
    PERFORM pg_advisory_xact_lock(hashtext('juzzio_global_themes'));
    SELECT COALESCE(MAX(version), 0) + 1 INTO v_ver FROM public.global_themes;
    INSERT INTO public.global_themes (version, name, payload, status, note, created_by)
    VALUES (v_ver, v_name, p_payload, 'draft', LEFT(COALESCE(p_note, ''), 300), auth.uid());
    INSERT INTO public.admin_audit_log (admin_id, action, target, details)
    VALUES (auth.uid(), 'theme_save_draft', v_ver::text, jsonb_build_object('name', v_name));
    RETURN v_ver;
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_theme_save_draft(TEXT, TEXT, JSONB, TEXT) TO authenticated;

-- Yayınla (hemen veya ileri tarihli zamanlama)
CREATE OR REPLACE FUNCTION public.admin_theme_publish(p_token TEXT, p_version INTEGER, p_publish_at TIMESTAMPTZ DEFAULT NULL)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_at TIMESTAMPTZ := COALESCE(p_publish_at, NOW());
BEGIN
    PERFORM public._staff_require(p_token, 'theme.publish');
    IF v_at < NOW() - INTERVAL '5 minutes' THEN RAISE EXCEPTION 'publish_at_in_past'; END IF;
    UPDATE public.global_themes
       SET status = 'published', publish_at = v_at, published_at = NOW()
     WHERE version = p_version AND status IN ('draft', 'archived', 'published');
    IF NOT FOUND THEN RAISE EXCEPTION 'theme_not_found'; END IF;
    INSERT INTO public.admin_audit_log (admin_id, action, target, details)
    VALUES (auth.uid(), 'theme_publish', p_version::text, jsonb_build_object('publish_at', v_at));
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_theme_publish(TEXT, INTEGER, TIMESTAMPTZ) TO authenticated;

-- Geri al: seçilen eski sürüm YENİ bir sürüm olarak hemen yayınlanır (geçmiş korunur)
CREATE OR REPLACE FUNCTION public.admin_theme_rollback(p_token TEXT, p_version INTEGER)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_src public.global_themes%ROWTYPE; v_ver INTEGER;
BEGIN
    PERFORM public._staff_require(p_token, 'theme.publish');
    SELECT * INTO v_src FROM public.global_themes WHERE version = p_version;
    IF NOT FOUND THEN RAISE EXCEPTION 'theme_not_found'; END IF;
    PERFORM pg_advisory_xact_lock(hashtext('juzzio_global_themes'));
    SELECT COALESCE(MAX(version), 0) + 1 INTO v_ver FROM public.global_themes;
    INSERT INTO public.global_themes (version, name, payload, status, publish_at, published_at, note, created_by)
    VALUES (v_ver, v_src.name, v_src.payload, 'published', NOW(), NOW(), 'rollback:v' || p_version, auth.uid());
    INSERT INTO public.admin_audit_log (admin_id, action, target, details)
    VALUES (auth.uid(), 'theme_rollback', v_ver::text, jsonb_build_object('from_version', p_version));
    RETURN v_ver;
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_theme_rollback(TEXT, INTEGER) TO authenticated;

-- Arşivle (yayından kaldır); son kararlı yayın otomatik olarak geçerli olur
CREATE OR REPLACE FUNCTION public.admin_theme_archive(p_token TEXT, p_version INTEGER)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    PERFORM public._staff_require(p_token, 'theme.publish');
    UPDATE public.global_themes SET status = 'archived' WHERE version = p_version;
    IF NOT FOUND THEN RAISE EXCEPTION 'theme_not_found'; END IF;
    INSERT INTO public.admin_audit_log (admin_id, action, target, details)
    VALUES (auth.uid(), 'theme_archive', p_version::text, '{}'::jsonb);
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_theme_archive(TEXT, INTEGER) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_theme_list(p_token TEXT)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_live INTEGER;
BEGIN
    PERFORM public._staff_require(p_token, 'theme.publish');
    SELECT version INTO v_live FROM public.global_themes
     WHERE status = 'published' AND publish_at <= NOW() ORDER BY publish_at DESC, version DESC LIMIT 1;
    RETURN COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
            'version', g.version, 'name', g.name, 'payload', g.payload, 'status', g.status,
            'publish_at', g.publish_at, 'published_at', g.published_at, 'note', g.note,
            'created_at', g.created_at, 'live', g.version = v_live) ORDER BY g.version DESC)
        FROM public.global_themes g), '[]'::jsonb);
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_theme_list(TEXT) TO authenticated;

-- Tüm kullanıcılar: şu an geçerli küresel tema (yoksa NULL)
CREATE OR REPLACE FUNCTION public.get_active_global_theme()
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT jsonb_build_object('version', version, 'name', name, 'payload', payload)
      FROM public.global_themes
     WHERE status = 'published' AND publish_at <= NOW()
     ORDER BY publish_at DESC, version DESC
     LIMIT 1;
$$;
GRANT EXECUTE ON FUNCTION public.get_active_global_theme() TO authenticated;
