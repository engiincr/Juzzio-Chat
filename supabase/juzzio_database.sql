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

-- v1.0.0: v0.1'in geniş storage politikaları burada artık OLUŞTURULMAZ. Aynı transaction'ın
-- ilerisinde (sıkılaştırma bölümü) zaten kaldırılıyorlardı; oluştur-sil adımı canlı
-- dağıtımda storage.objects üzerinde gereksiz ACCESS EXCLUSIVE kilit alıp uygulamanın
-- dosya sorgularıyla kilitlenmeye (deadlock) yol açıyordu. Sonuç şema aynıdır.

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
        -- v0.9.0: süreli sohbet sessize alma (notif_muted_until, Bölüm 10.15) de uygulanır
        SELECT user_id, is_muted, notif_muted_until FROM public.room_participants
        WHERE room_id = NEW.room_id AND user_id <> NEW.sender_id AND left_at IS NULL
    LOOP
        IF rp.is_muted OR COALESCE(rp.notif_muted_until > NOW(), false)
           OR public.is_blocked_between(NEW.sender_id, rp.user_id) THEN
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
-- v0.9.4: rol listesine yanlışlıkla karışmış dil kodları ('tr', 'en') kaldırıldı
UPDATE public.room_participants SET role = 'member' WHERE role IN ('tr', 'en');
ALTER TABLE public.room_participants ADD CONSTRAINT room_participants_role_check
    CHECK (role IN ('owner', 'moderator', 'member', 'host', 'viewer')) NOT VALID;

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
    PERFORM public._staff_require(p_token, 'stats.read');
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
    PERFORM public._staff_require(p_token, 'reports');
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
    PERFORM public._staff_require(p_token, 'reports.resolve');
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
    PERFORM public._staff_require(p_token, 'users.ban');
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
    PERFORM public._staff_require(p_token, 'users.ban');
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
    PERFORM public._staff_require(p_token, 'users.read');
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
    PERFORM public._staff_require(p_token, 'stats.read');
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
    PERFORM public._staff_require(p_token, 'users.read');
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
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    PERFORM public._staff_require(p_token, 'users.read');
    -- v0.9.0: ayrıcalıklı okuma da denetim kaydına yazılır
    INSERT INTO public.admin_audit_log (admin_id, action, target, details)
    VALUES (auth.uid(), 'view_user_detail', p_user::text, jsonb_build_object('pii', public._staff_has(p_token, 'users.pii')));
    RETURN (
        SELECT jsonb_build_object(
            'id', p.id, 'username', p.username, 'display_name', p.display_name, 'avatar_url', p.avatar_url,
            -- v0.9.0: e-posta yalnızca 'users.pii' iznine açık (destek görevlisi göremez)
            'email', CASE WHEN public._staff_has(p_token, 'users.pii') THEN (SELECT u.email FROM auth.users u WHERE u.id = p.id) END,
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
    PERFORM public._staff_require(p_token, 'users.manage');
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
    PERFORM public._staff_require(p_token, 'roles.manage');
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
    PERFORM public._staff_require(p_token, 'users.ban');
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
    PERFORM public._staff_require(p_token, 'users.pii');
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
    PERFORM public._staff_require(p_token, 'users.warn');
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
    PERFORM public._staff_require(p_token, 'broadcast');
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
    PERFORM public._staff_require(p_token, 'content.delete');
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
    PERFORM public._staff_require(p_token, 'releases');
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
    PERFORM public._staff_require(p_token, 'releases');
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
    PERFORM public._staff_require(p_token, 'audit.read');
    RETURN COALESCE((
        SELECT jsonb_agg(row_to_json(x) ORDER BY x.created_at DESC) FROM (
            -- v1.0.0: hedef kimliği okunur hâle getirilir (kullanıcı adı / grup adı)
            SELECT l.id, l.action, l.target, l.details, l.created_at, p.username AS admin_username,
                   tp.username AS target_username, COALESCE(tp.display_name, tr.title) AS target_name
            FROM public.admin_audit_log l
            LEFT JOIN public.profiles p ON p.id = l.admin_id
            LEFT JOIN public.profiles tp ON tp.id::text = l.target
            LEFT JOIN public.rooms tr ON tr.id::text = l.target
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
    PERFORM public._staff_require(p_token, 'stats.read');
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
    PERFORM public._staff_require(p_token, 'settings');
    IF p_key IN ('maintenance_message', 'announcement_banner') THEN
        IF jsonb_typeof(p_value) <> 'string' THEN RAISE EXCEPTION 'invalid_setting'; END IF;
        p_value := to_jsonb(LEFT(p_value #>> '{}', 500));
    ELSIF p_key = 'default_glass_palette' THEN
        IF jsonb_typeof(p_value) <> 'string'
           -- v0.9.5: istemcideki TÜM cam temaları (önceden 6 temayla sınırlıydı → diğerlerini seçince
           -- yönetici panelinde "geçersiz ayar" hatası alınıyordu; varsayılan juzzio_liquid bile reddediliyordu)
           OR (p_value #>> '{}') NOT IN ('juzzio_liquid', 'ocean', 'glass_white', 'amethyst', 'emerald', 'lagoon', 'chrome',
                                        'obsidian_oled', 'lavender_mist', 'rose_quartz', 'cyber_neon', 'high_contrast') THEN
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
    PERFORM public._staff_require(p_token, 'users.read');
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
    PERFORM public._staff_require(p_token, 'users.warn');
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
    PERFORM public._staff_require(p_token, 'users.warn');
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
    PERFORM public._staff_require(p_token, 'moderation');
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
    PERFORM public._staff_require(p_token, 'moderation');
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
    PERFORM public._staff_require(p_token, 'moderation');
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
    PERFORM public._staff_require(p_token, 'moderation.config');
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
    PERFORM public._staff_require(p_token, 'moderation.config');
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
    PERFORM public._staff_require(p_token, 'moderation');
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
    PERFORM public._staff_require(p_token, 'users.manage');
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
    PERFORM public._staff_require(p_token, 'users.manage');
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
    PERFORM public._staff_require(p_token, 'users.delete');
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
    PERFORM public._staff_require(p_token, 'groups.read');
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
    PERFORM public._staff_require(p_token, 'groups.read');
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
    PERFORM public._staff_require(p_token, 'groups.manage');
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
    PERFORM public._staff_require(p_token, 'groups.manage');
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
    PERFORM public._staff_require(p_token, 'groups.manage');
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
    PERFORM public._staff_require(p_token, 'calls.manage');
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
    PERFORM public._staff_require(p_token, 'calls.manage');
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
    PERFORM public._staff_require(p_token, 'moderation');
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
    PERFORM public._staff_require(p_token, 'moderation');
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
    PERFORM public._staff_require(p_token, 'releases');
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
    PERFORM public._staff_require(p_token, 'feedback.manage');
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
    PERFORM public._staff_require(p_token, 'feedback.manage');
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
    -- v0.9.0: Süper yönetici ('*') YALNIZCA şifreyle açılmış oturum belirteciyle geçer
    -- (belirteçsiz '*' yetkisi bir zayıflama olurdu). Personel rolleri kendi izinleriyle geçer.
    IF COALESCE(public.juzzio_staff_role(auth.uid()), '') <> 'super_admin'
       AND public.juzzio_has_permission(p_perm) THEN
        RETURN;
    END IF;
    -- Geriye uyumluluk: belirteç verilip geçersizse istemci şifre ekranını yeniden açar
    IF COALESCE(p_token, '') <> '' THEN RAISE EXCEPTION 'admin_session_invalid'; END IF;
    RAISE EXCEPTION 'permission_denied:%', p_perm;
END;
$$;
REVOKE ALL ON FUNCTION public._staff_require(TEXT, TEXT) FROM PUBLIC, anon, authenticated;

-- v0.9.0: izin VAR MI (istisna fırlatmadan) — alan bazlı maskeleme için (ör. e-posta)
CREATE OR REPLACE FUNCTION public._staff_has(p_token TEXT, p_perm TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF COALESCE(p_token, '') <> '' AND public.admin_check_token(p_token) THEN RETURN true; END IF;
    RETURN COALESCE(public.juzzio_staff_role(auth.uid()), '') <> 'super_admin' AND public.juzzio_has_permission(p_perm);
END;
$$;
REVOKE ALL ON FUNCTION public._staff_has(TEXT, TEXT) FROM PUBLIC, anon, authenticated;

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
    PERFORM public._staff_require(p_token, 'roles.manage');
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
    PERFORM public._staff_require(p_token, 'roles.manage');
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


-- #############################################################################
-- BÖLÜM 10 — v0.9.0 GÜVENLİK SERTLEŞTİRMESİ (kaynak denetimi: Gemini + ChatGPT bulguları)
--   10.1 LiveKit token: biten/çıkarılan katılımcı yeniden token alamaz (G01)
--   10.2 Aktif çağrı katılımcısı kontrolü — content-moderation geri dönüşü (G02)
--   10.3 invite_to_call: davet eden yasaklı/çıkarılmış olamaz (G06)
--   10.4 Canlı altyazı (Deepgram) yalnızca aktif çağrıda ve yasaklı değilse (G05)
--   10.5 Sesli mesaj transkripsiyonu: oda üyeliği + hız sınırı (G04)
--   10.6 Push teslim kilidi: askıda kalan "processing" kaydı güvenle devralınır (G08)
--   10.7 Storage gizliliği: özel sohbet/hikâye/gönderi medyası artık herkese açık DEĞİL
-- Tümü idempotent; veri silmez. Testler: supabase/tests/juzzio_database_tests.sql (v0.9.0 bloğu)
-- #############################################################################

-- 10.0 Yardımcı: metni güvenle UUID'ye çevir (geçersizse NULL, istisna fırlatmaz)
CREATE OR REPLACE FUNCTION public.juzzio_try_uuid(p_text TEXT)
RETURNS UUID
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
    IF p_text IS NULL OR p_text !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
        RETURN NULL;
    END IF;
    RETURN p_text::uuid;
END;
$$;
GRANT EXECUTE ON FUNCTION public.juzzio_try_uuid(TEXT) TO authenticated, service_role;

-- 10.1 LiveKit token yetkisi.
--  Önceki sürüm (Bölüm 7) yasak ve call_removals kontrolünü zaten yapıyordu; kalan açık:
--  "answered" durumundaki BİTMİŞ bir çağrı kaydı 12 saat boyunca token almaya yetiyordu.
--  Artık yalnızca çalan veya bitmemiş (ended_at IS NULL) çağrı ile oda dışı katılım mümkün.
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
    IF p_user IS NULL OR COALESCE(p_livekit_room, '') = '' THEN RETURN false; END IF;
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
              AND (c.status = 'ringing' OR (c.status = 'answered' AND c.ended_at IS NULL))
        )
    ) THEN
        RETURN false;
    END IF;

    SELECT c.session_id, c.caller_id INTO v_session, v_caller
    FROM public.call_logs c
    WHERE c.livekit_room_name = p_livekit_room AND c.created_at > NOW() - INTERVAL '6 hours'
      AND (c.status = 'ringing' OR (c.status = 'answered' AND c.ended_at IS NULL))
    ORDER BY c.created_at DESC LIMIT 1;
    IF v_session IS NULL OR v_caller = p_user THEN RETURN true; END IF;
    IF EXISTS (SELECT 1 FROM public.call_removals cr WHERE cr.session_id = v_session AND cr.user_id = p_user) THEN
        RETURN false;
    END IF;
    IF EXISTS (SELECT 1 FROM public.call_logs c WHERE c.session_id = v_session AND c.receiver_id = p_user
               AND c.status = 'answered' AND c.ended_at IS NULL) THEN
        RETURN true;
    END IF;
    RETURN public.call_session_active_count(v_session) < public.juzzio_max_call_participants();
END;
$$;
REVOKE ALL ON FUNCTION public.can_join_livekit_room(UUID, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.can_join_livekit_room(UUID, TEXT) TO service_role;

-- 10.2 Kişi şu anda bu LiveKit odasındaki bir çağrının ETKİN katılımcısı mı?
--  (yasaklı olsa bile — görüntü denetimi süren çağrıda devam etmeli; ama bitmiş veya
--   çıkarılmış katılımcı ASLA sayılmaz → odayı kapatma/DoS açığı kapanır)
CREATE OR REPLACE FUNCTION public.juzzio_is_active_call_participant(p_user UUID, p_livekit_room TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT p_user IS NOT NULL AND COALESCE(p_livekit_room, '') <> '' AND EXISTS (
        SELECT 1 FROM public.call_logs c
        WHERE c.livekit_room_name = p_livekit_room
          AND c.created_at > NOW() - INTERVAL '6 hours'
          AND c.ended_at IS NULL
          AND (
                (c.caller_id = p_user AND c.status IN ('ringing', 'answered'))
             OR (c.receiver_id = p_user AND c.status = 'answered')
          )
          AND NOT EXISTS (
              SELECT 1 FROM public.call_removals cr
              WHERE cr.session_id = c.session_id AND cr.user_id = p_user
          )
    );
$$;
REVOKE ALL ON FUNCTION public.juzzio_is_active_call_participant(UUID, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.juzzio_is_active_call_participant(UUID, TEXT) TO service_role;

-- 10.3 Çağrıya davet: davet eden yasaklı olamaz; yalnızca ETKİN (bitmemiş, çıkarılmamış)
--      katılımcı davet edebilir; dört kişilik sınır korunur.
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
    IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
    IF public.juzzio_is_banned(v_uid) THEN RAISE EXCEPTION 'account_banned'; END IF;
    IF COALESCE(array_length(p_user_ids, 1), 0) > 16 THEN RAISE EXCEPTION 'too_many_invites'; END IF;

    SELECT * INTO v_base FROM public.call_logs
    WHERE session_id = p_session
      AND ended_at IS NULL
      AND ((caller_id = v_uid AND status IN ('ringing', 'answered'))
           OR (receiver_id = v_uid AND status = 'answered'))
    ORDER BY created_at LIMIT 1;
    IF v_base.id IS NULL THEN RAISE EXCEPTION 'not_in_call'; END IF;
    IF EXISTS (SELECT 1 FROM public.call_removals cr WHERE cr.session_id = p_session AND cr.user_id = v_uid) THEN
        RAISE EXCEPTION 'not_in_call';
    END IF;

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
          AND NOT EXISTS (SELECT 1 FROM public.call_removals cr WHERE cr.session_id = p_session AND cr.user_id = p.id)
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
REVOKE ALL ON FUNCTION public.invite_to_call(UUID, UUID[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.invite_to_call(UUID, UUID[]) TO authenticated;

-- 10.4/10.5 Genel amaçlı hız sınırlayıcı (yalnız service_role; Edge Function'lar kullanır)
CREATE TABLE IF NOT EXISTS public.juzzio_rate_events (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID NOT NULL,
    action TEXT NOT NULL CHECK (char_length(action) BETWEEN 1 AND 64),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_juzzio_rate_events_lookup ON public.juzzio_rate_events (user_id, action, created_at DESC);
ALTER TABLE public.juzzio_rate_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.juzzio_rate_events FROM anon, authenticated;

-- true → izin verildi (olay kaydedildi); false → sınır aşıldı. Eski olaylar kendiliğinden budanır.
CREATE OR REPLACE FUNCTION public.juzzio_rate_check(p_user UUID, p_action TEXT, p_limit INTEGER, p_window_seconds INTEGER)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_count INTEGER;
BEGIN
    IF p_user IS NULL OR COALESCE(p_action, '') = '' OR p_limit < 1 OR p_window_seconds < 1 THEN
        RETURN false;
    END IF;
    -- Aynı kullanıcı+eylem için eşzamanlı çağrılar sırayla sayılır
    PERFORM pg_advisory_xact_lock(hashtextextended(p_user::text || ':' || p_action, 0));
    SELECT COUNT(*) INTO v_count FROM public.juzzio_rate_events
     WHERE user_id = p_user AND action = p_action
       AND created_at > NOW() - make_interval(secs => p_window_seconds);
    IF v_count >= p_limit THEN RETURN false; END IF;
    INSERT INTO public.juzzio_rate_events (user_id, action) VALUES (p_user, p_action);
    DELETE FROM public.juzzio_rate_events
     WHERE user_id = p_user AND action = p_action AND created_at < NOW() - INTERVAL '2 days';
    RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION public.juzzio_rate_check(UUID, TEXT, INTEGER, INTEGER) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.juzzio_rate_check(UUID, TEXT, INTEGER, INTEGER) TO service_role;

-- 10.4 Canlı altyazı token'ı: yasaklı değil + şu an etkin bir çağrının katılımcısı
CREATE OR REPLACE FUNCTION public.juzzio_can_use_live_captions(p_user UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT p_user IS NOT NULL
       AND NOT public.juzzio_is_banned(p_user)
       AND EXISTS (
           SELECT 1 FROM public.call_logs c
           WHERE c.created_at > NOW() - INTERVAL '6 hours'
             AND c.ended_at IS NULL
             AND ((c.caller_id = p_user AND c.status IN ('ringing', 'answered'))
                  OR (c.receiver_id = p_user AND c.status = 'answered'))
             AND NOT EXISTS (SELECT 1 FROM public.call_removals cr
                             WHERE cr.session_id = c.session_id AND cr.user_id = p_user)
       );
$$;
REVOKE ALL ON FUNCTION public.juzzio_can_use_live_captions(UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.juzzio_can_use_live_captions(UUID) TO service_role;

-- 10.5 Sesli mesaj transkripsiyonu için nesne çözümü.
--  İstemci URL'si yetki DEĞİLDİR. Kayıt, kimlik (voice note / mesaj id) veya depolama yolu
--  ile veritabanından bulunur; çağıranın o odada ETKİN üye olması, yasaklı olmaması ve
--  gönderenle arasında engel bulunmaması gerekir. Dönüş: {ok, bucket, storage_path, mime_type}
--  veya {ok:false, error}. Yalnızca service_role (translate-bridge) çağırır.
CREATE OR REPLACE FUNCTION public.juzzio_voice_note_for_transcription(
    p_user UUID, p_voice_note UUID DEFAULT NULL, p_message UUID DEFAULT NULL, p_storage_path TEXT DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v RECORD;
    v_path TEXT := NULLIF(BTRIM(COALESCE(p_storage_path, '')), '');
BEGIN
    IF p_user IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'unauthorized'); END IF;
    IF public.juzzio_is_banned(p_user) THEN RETURN jsonb_build_object('ok', false, 'error', 'account_banned'); END IF;
    IF v_path IS NOT NULL AND (v_path LIKE '%..%' OR v_path LIKE '/%' OR char_length(v_path) > 512) THEN
        RETURN jsonb_build_object('ok', false, 'error', 'invalid_path');
    END IF;
    SELECT vn.id, vn.room_id, vn.sender_id, vn.storage_path, vn.mime_type INTO v
      FROM public.voice_notes vn
     WHERE (p_voice_note IS NOT NULL AND vn.id = p_voice_note)
        OR (p_message IS NOT NULL AND vn.message_id = p_message)
        OR (v_path IS NOT NULL AND vn.storage_path = v_path)
     ORDER BY vn.created_at DESC
     LIMIT 1;
    IF v.id IS NULL THEN
        -- Henüz kaydı oluşmamış KENDİ yüklemesi: yol <uid>/<oda>/... ve kişi o odanın üyesi
        IF v_path IS NOT NULL AND split_part(v_path, '/', 1) = p_user::text
           AND public.is_room_member(public.juzzio_try_uuid(split_part(v_path, '/', 2)), p_user) THEN
            RETURN jsonb_build_object('ok', true, 'bucket', 'voice-notes', 'storage_path', v_path,
                                      'mime_type', 'audio/mp4', 'pending_owner_upload', true);
        END IF;
        RETURN jsonb_build_object('ok', false, 'error', 'not_found');
    END IF;
    IF NOT public.is_room_member(v.room_id, p_user) THEN
        RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
    END IF;
    IF v.sender_id <> p_user AND public.is_blocked_between(p_user, v.sender_id) THEN
        RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
    END IF;
    RETURN jsonb_build_object('ok', true, 'bucket', 'voice-notes', 'storage_path', v.storage_path,
                              'mime_type', COALESCE(NULLIF(v.mime_type, ''), 'audio/mp4'),
                              'voice_note_id', v.id, 'room_id', v.room_id);
END;
$$;
REVOKE ALL ON FUNCTION public.juzzio_voice_note_for_transcription(UUID, UUID, UUID, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.juzzio_voice_note_for_transcription(UUID, UUID, UUID, TEXT) TO service_role;

-- 10.6 Push teslim kilidi: aynı idempotency anahtarı için "processing" kaydı 2 dakikadan
--  eskiyse (ilk çalışma zaman aşımına uğramış) tek bir çağıran kilidi atomik olarak devralır.
--  Dönüş: devralınan kaydın id'si veya NULL (kayıt güncel/sonuçlanmış → tekrar gönderme yok).
CREATE OR REPLACE FUNCTION public.juzzio_claim_stale_push_delivery(p_idempotency_key TEXT, p_stale_seconds INTEGER DEFAULT 120)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_id UUID;
BEGIN
    UPDATE public.push_delivery_logs
       SET created_at = NOW(),
           fcm_error_code = 'stale_lock_reclaimed'
     WHERE id = (
            SELECT id FROM public.push_delivery_logs
             WHERE idempotency_key = p_idempotency_key
               AND delivery_status = 'processing'
               AND created_at < NOW() - make_interval(secs => GREATEST(p_stale_seconds, 30))
             FOR UPDATE SKIP LOCKED
             LIMIT 1)
    RETURNING id INTO v_id;
    RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION public.juzzio_claim_stale_push_delivery(TEXT, INTEGER) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.juzzio_claim_stale_push_delivery(TEXT, INTEGER) TO service_role;

-- 10.7 STORAGE GİZLİLİĞİ (denetim bulgusu C — P0/P1)
--  Önce: 6 bucket'ın tamamı public=true idi. Herkese açık bucket'ta nesne, OKUMA RLS'i
--  atlanarak /object/public/... adresinden indirilebilir; v0.6.1'deki "yalnız kendi klasörü"
--  politikası yalnızca LİSTELEMEYİ engelliyordu, özel sohbet fotoğrafı/sesli mesajı değil.
--  Şimdi:
--   • avatars          → herkese açık kalır (ürün gereği: profil fotoğrafı)
--   • chat-media, voice-notes → ÖZEL; okuma: yol <yükleyen>/<oda>/... ve okuyan o odanın üyesi
--   • stories          → ÖZEL; okuma: hikâye satırını RLS ile görebilen (görünürlük, yakın
--                         arkadaş, engel, süre dolumu) — politika çağıranın yetkisiyle çalışır
--   • posts, reels     → ÖZEL; okuma: media_storage_paths içinde bu nesne bulunan ve RLS ile
--                         görülebilen gönderi (public/followers/friends/private kuralları)
--  Nesneler TAŞINMAZ ve silinmez (veri kaybı yok); yalnızca erişim yolu değişir. v0.9.0
--  istemcisi bu bucket'lar için kısa ömürlü imzalı URL (createSignedUrl) kullanır.
--  ÖNEMLİ: Daha önce herkese açık bağlantıyla indirilmiş kopyalar geri alınamaz.
DO $$
BEGIN
    IF to_regclass('storage.buckets') IS NOT NULL THEN
        UPDATE storage.buckets SET public = false
         WHERE id IN ('chat-media', 'voice-notes', 'stories', 'posts', 'reels') AND public IS DISTINCT FROM false;
        UPDATE storage.buckets SET public = true WHERE id = 'avatars' AND public IS DISTINCT FROM true;
    END IF;
EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'storage.buckets güncellenemedi (yetki yok) — Supabase panelinden bucket''ları özel yapın.';
END $$;

-- posts.media_storage_paths ("bucket:yol" dizisi) üzerinde hızlı arama
CREATE INDEX IF NOT EXISTS idx_posts_media_storage_paths ON public.posts USING GIN (media_storage_paths);

-- Sohbet medyası okuma yetkisi (yol: <yükleyen_uid>/<oda_id>/<dosya>)
CREATE OR REPLACE FUNCTION public.juzzio_can_read_room_object(p_name TEXT, p_user UUID DEFAULT auth.uid())
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT p_user IS NOT NULL
       AND COALESCE(p_name, '') NOT LIKE '%..%'
       AND public.is_room_member(public.juzzio_try_uuid(split_part(p_name, '/', 2)), p_user)
       AND NOT public.juzzio_is_banned(p_user);
$$;
REVOKE ALL ON FUNCTION public.juzzio_can_read_room_object(TEXT, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.juzzio_can_read_room_object(TEXT, UUID) TO authenticated, service_role;

DO $$
BEGIN
    IF to_regclass('storage.objects') IS NOT NULL THEN
        DROP POLICY IF EXISTS "juzzio_v061_storage_read_own" ON storage.objects;
        DROP POLICY IF EXISTS "juzzio_v090_storage_read" ON storage.objects;
        -- Not: stories/posts alt sorguları ÇAĞIRANIN yetkisiyle çalışır; böylece hikâye ve
        -- gönderi görünürlük kuralları (RLS) depolama erişimine birebir yansır.
        CREATE POLICY "juzzio_v090_storage_read" ON storage.objects FOR SELECT TO authenticated
            USING (
                (bucket_id IN ('stories', 'avatars', 'voice-notes', 'chat-media', 'posts', 'reels')
                 AND (storage.foldername(name))[1] = auth.uid()::text)
             OR bucket_id = 'avatars'
             OR (bucket_id IN ('chat-media', 'voice-notes') AND public.juzzio_can_read_room_object(name))
             -- Personel (en az yetki): geri bildirim ekran görüntüleri yalnız 'feedback.manage';
             -- hikâye/gönderi/reels medyası yalnız 'moderation' (şikâyet incelemesi). Özel sohbet
             -- medyası ve sesli mesajlar personele AÇILMAZ.
             OR (bucket_id = 'chat-media' AND split_part(name, '/', 2) = 'feedback'
                 AND public.juzzio_has_permission('feedback.manage'))
             OR (bucket_id IN ('stories', 'posts', 'reels') AND public.juzzio_has_permission('moderation'))
             OR (bucket_id = 'stories' AND EXISTS (
                    SELECT 1 FROM public.stories s
                     WHERE s.media_url IS NOT NULL
                       AND right(s.media_url, char_length('/stories/' || name)) = '/stories/' || name))
             OR (bucket_id IN ('posts', 'reels') AND EXISTS (
                    SELECT 1 FROM public.posts p
                     WHERE p.media_storage_paths ? (bucket_id || ':' || name)
                        OR (p.cover_url IS NOT NULL
                            AND right(p.cover_url, char_length('/' || bucket_id || '/' || name)) = '/' || bucket_id || '/' || name)))
            );
    END IF;
EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'storage.objects okuma politikası değiştirilemedi (yetki yok) — Supabase panelinden uygulayın.';
END $$;

-- 10.8 Arayüz dil paketi önbelleği (translate-bridge "batch_ui" modu — G12)
--  Önceden her telefon 1.231 arayüz metnini 6 paralel kolla doğrudan resmi olmayan
--  translate.googleapis.com uç noktasına gönderiyordu (HTTP 429 / IP engeli riski).
--  Artık her (dil, metin) çifti SUNUCUDA bir kez çevrilir ve herkes için önbellekten gelir.
--  Yalnızca service_role erişir; satırlar kişisel veri içermez (yalnızca uygulama metinleri).
CREATE TABLE IF NOT EXISTS public.ui_translations (
    target_lang TEXT NOT NULL CHECK (target_lang ~ '^[a-z]{2,3}(-[a-z0-9]{2,4})?$'),
    source_hash TEXT NOT NULL CHECK (source_hash ~ '^[0-9a-f]{64}$'),
    translated_text TEXT NOT NULL CHECK (char_length(translated_text) <= 2000),
    provider TEXT NOT NULL DEFAULT 'gtx',
    review_status TEXT NOT NULL DEFAULT 'machine' CHECK (review_status IN ('machine', 'reviewed')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (target_lang, source_hash)
);
ALTER TABLE public.ui_translations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.ui_translations FROM anon, authenticated;

-- 10.9 RBAC — en az yetki izin matrisi (G20/G21)
--  Tüm admin_* RPC'leri artık _admin_require (yalnız süper yönetici) yerine
--  _staff_require(p_token, '<izin>') kullanır. Süper yönetici yine şifreli oturum ister.
--  Görev ayrımı: hesap silme ve rol yönetimi YALNIZCA süper yöneticide ('*').
--  Destek görevlisi e-posta (users.pii) göremez; denetçi salt okunurdur.
--  İzinler her çağrıda staff_roles'tan canlı okunur → rol geri alındığı anda etkisizdir.
CREATE OR REPLACE FUNCTION public.juzzio_role_permissions(p_role TEXT)
RETURNS TEXT[]
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
    SELECT CASE p_role
        WHEN 'super_admin' THEN ARRAY['*']
        WHEN 'admin' THEN ARRAY['users.read', 'users.manage', 'users.warn', 'users.ban', 'users.pii',
                                'moderation', 'moderation.config', 'content.delete', 'reports', 'reports.resolve',
                                'groups.read', 'groups.manage', 'calls.manage', 'feedback.manage',
                                'theme.publish', 'settings', 'broadcast', 'releases',
                                'audit.read', 'roles.read', 'stats.read',
                                -- v0.9.0 Business: başvuru/hesap yönetimi ve hukuki metin yayını
                                'business.read', 'business.manage', 'legal.publish']
        WHEN 'moderator' THEN ARRAY['users.read', 'users.warn', 'moderation', 'content.delete', 'reports',
                                    'reports.resolve', 'groups.read', 'calls.manage', 'business.read']
        WHEN 'support' THEN ARRAY['users.read', 'reports', 'feedback.manage', 'groups.read', 'business.read']
        WHEN 'analyst' THEN ARRAY['stats.read']
        WHEN 'content_manager' THEN ARRAY['theme.publish', 'broadcast', 'releases']
        WHEN 'auditor' THEN ARRAY['audit.read', 'roles.read', 'stats.read']
        ELSE ARRAY[]::TEXT[]
    END;
$$;
GRANT EXECUTE ON FUNCTION public.juzzio_role_permissions(TEXT) TO authenticated;

-- 10.10 STORAGE TEMİZLİĞİ (G22)
--  Supabase, storage.objects satırlarının SQL ile silinmesine izin vermez (nesne diskte
--  kalır). Bu yüzden silinecek nesneler bir KUYRUĞA yazılır; `storage-cleanup` Edge
--  Function'ı kuyruğu Storage API ile boşaltır (GitHub Actions bakım iş akışı saatlik
--  tetikler; yönetici panelinden de tetiklenebilir).
--  Kaynaklar: gönderi silme (yumuşak/sert), hikâye silme, mesaj silme veya "herkesten sil"
--  (URL alanları temizlenince), süreli mesajın süresinin dolması, hesap silme (kullanıcı
--  klasörlerinin tamamı). Süresi dolan hikâyeler sahibinin arşivi için 30 gün tutulur.
CREATE TABLE IF NOT EXISTS public.juzzio_storage_cleanup_queue (
    id BIGSERIAL PRIMARY KEY,
    bucket TEXT NOT NULL CHECK (bucket IN ('stories', 'avatars', 'voice-notes', 'chat-media', 'posts', 'reels')),
    object_name TEXT NOT NULL CHECK (char_length(object_name) BETWEEN 1 AND 512 AND object_name NOT LIKE '%..%'),
    is_prefix BOOLEAN NOT NULL DEFAULT false,
    reason TEXT NOT NULL DEFAULT '',
    enqueued_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    attempts INTEGER NOT NULL DEFAULT 0,
    last_error TEXT NOT NULL DEFAULT '',
    processed_at TIMESTAMPTZ
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_juzzio_storage_cleanup_pending
    ON public.juzzio_storage_cleanup_queue (bucket, object_name, is_prefix) WHERE processed_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_juzzio_storage_cleanup_due
    ON public.juzzio_storage_cleanup_queue (enqueued_at) WHERE processed_at IS NULL;
ALTER TABLE public.juzzio_storage_cleanup_queue ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.juzzio_storage_cleanup_queue FROM anon, authenticated;

-- Storage URL'sinden (public / sign / authenticated) bucket + nesne yolu çıkarır
CREATE OR REPLACE FUNCTION public.juzzio_storage_ref_from_url(p_url TEXT)
RETURNS TABLE (bucket TEXT, object_name TEXT)
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT m[2], m[3]
      FROM (SELECT regexp_match(COALESCE(p_url, ''),
                   '/storage/v1/object/(public|sign|authenticated)/([a-z0-9-]+)/([^?#]+)') AS m) x
     WHERE m IS NOT NULL
$$;

CREATE OR REPLACE FUNCTION public.juzzio_enqueue_storage_cleanup(p_bucket TEXT, p_name TEXT, p_reason TEXT, p_prefix BOOLEAN DEFAULT false)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF p_bucket IS NULL OR COALESCE(p_name, '') = ''
       OR p_bucket NOT IN ('stories', 'avatars', 'voice-notes', 'chat-media', 'posts', 'reels')
       OR p_name LIKE '%..%' OR p_name LIKE '/%' OR char_length(p_name) > 512 THEN
        RETURN;
    END IF;
    INSERT INTO public.juzzio_storage_cleanup_queue (bucket, object_name, is_prefix, reason)
    VALUES (p_bucket, p_name, COALESCE(p_prefix, false), LEFT(COALESCE(p_reason, ''), 64))
    ON CONFLICT (bucket, object_name, is_prefix) WHERE processed_at IS NULL DO NOTHING;
END;
$$;
REVOKE ALL ON FUNCTION public.juzzio_enqueue_storage_cleanup(TEXT, TEXT, TEXT, BOOLEAN) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.juzzio_enqueue_url_cleanup(p_url TEXT, p_reason TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE r RECORD;
BEGIN
    FOR r IN SELECT * FROM public.juzzio_storage_ref_from_url(p_url) LOOP
        PERFORM public.juzzio_enqueue_storage_cleanup(r.bucket, r.object_name, p_reason);
    END LOOP;
END;
$$;
REVOKE ALL ON FUNCTION public.juzzio_enqueue_url_cleanup(TEXT, TEXT) FROM PUBLIC, anon, authenticated;

-- Gönderi: sert silme veya yumuşak silme (is_deleted=true) → medya + kapak
CREATE OR REPLACE FUNCTION public.juzzio_trg_post_storage_cleanup()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_ref TEXT;
BEGIN
    IF TG_OP = 'UPDATE' AND NOT (COALESCE(NEW.is_deleted, false) AND NOT COALESCE(OLD.is_deleted, false)) THEN
        RETURN NEW;
    END IF;
    FOR v_ref IN SELECT jsonb_array_elements_text(COALESCE(OLD.media_storage_paths, '[]'::jsonb)) LOOP
        IF position(':' IN v_ref) > 0 THEN
            PERFORM public.juzzio_enqueue_storage_cleanup(split_part(v_ref, ':', 1), substr(v_ref, position(':' IN v_ref) + 1), 'post_deleted');
        END IF;
    END LOOP;
    PERFORM public.juzzio_enqueue_url_cleanup(OLD.cover_url, 'post_deleted');
    RETURN COALESCE(NEW, OLD);
END;
$$;
DROP TRIGGER IF EXISTS trg_juzzio_post_storage_cleanup ON public.posts;
CREATE TRIGGER trg_juzzio_post_storage_cleanup AFTER DELETE OR UPDATE OF is_deleted ON public.posts
    FOR EACH ROW EXECUTE FUNCTION public.juzzio_trg_post_storage_cleanup();

-- Hikâye silindiğinde medya
CREATE OR REPLACE FUNCTION public.juzzio_trg_story_storage_cleanup()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    PERFORM public.juzzio_enqueue_url_cleanup(OLD.media_url, 'story_deleted');
    RETURN OLD;
END;
$$;
DROP TRIGGER IF EXISTS trg_juzzio_story_storage_cleanup ON public.stories;
CREATE TRIGGER trg_juzzio_story_storage_cleanup AFTER DELETE ON public.stories
    FOR EACH ROW EXECUTE FUNCTION public.juzzio_trg_story_storage_cleanup();

-- Mesaj: sert silme veya medya alanlarının temizlenmesi ("herkesten sil")
CREATE OR REPLACE FUNCTION public.juzzio_trg_message_storage_cleanup()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF TG_OP = 'DELETE' OR NEW.image_url IS DISTINCT FROM OLD.image_url THEN
        PERFORM public.juzzio_enqueue_url_cleanup(OLD.image_url, 'message_deleted');
    END IF;
    IF TG_OP = 'DELETE' OR NEW.video_url IS DISTINCT FROM OLD.video_url THEN
        PERFORM public.juzzio_enqueue_url_cleanup(OLD.video_url, 'message_deleted');
    END IF;
    IF TG_OP = 'DELETE' OR NEW.document_url IS DISTINCT FROM OLD.document_url THEN
        PERFORM public.juzzio_enqueue_url_cleanup(OLD.document_url, 'message_deleted');
    END IF;
    IF TG_OP = 'DELETE' OR NEW.audio_url IS DISTINCT FROM OLD.audio_url THEN
        PERFORM public.juzzio_enqueue_url_cleanup(OLD.audio_url, 'message_deleted');
    END IF;
    -- Herkesten silinen sesli mesajın kaydı ve dosyası da kaldırılır
    IF TG_OP = 'UPDATE' AND COALESCE(NEW.is_deleted, false) AND NOT COALESCE(OLD.is_deleted, false) THEN
        DELETE FROM public.voice_notes WHERE message_id = OLD.id;
    END IF;
    RETURN COALESCE(NEW, OLD);
END;
$$;
DROP TRIGGER IF EXISTS trg_juzzio_message_storage_cleanup ON public.messages;
CREATE TRIGGER trg_juzzio_message_storage_cleanup
    AFTER DELETE OR UPDATE OF image_url, video_url, document_url, audio_url, is_deleted ON public.messages
    FOR EACH ROW EXECUTE FUNCTION public.juzzio_trg_message_storage_cleanup();

-- Sesli mesaj kaydı silinince dosyası
CREATE OR REPLACE FUNCTION public.juzzio_trg_voice_note_storage_cleanup()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    PERFORM public.juzzio_enqueue_storage_cleanup('voice-notes', OLD.storage_path, 'voice_note_deleted');
    RETURN OLD;
END;
$$;
DROP TRIGGER IF EXISTS trg_juzzio_voice_note_storage_cleanup ON public.voice_notes;
CREATE TRIGGER trg_juzzio_voice_note_storage_cleanup AFTER DELETE ON public.voice_notes
    FOR EACH ROW EXECUTE FUNCTION public.juzzio_trg_voice_note_storage_cleanup();

-- Hesap silme: kullanıcının tüm bucket'lardaki klasörü (<uid>/) — öksüz dosyalar dahil
CREATE OR REPLACE FUNCTION public.juzzio_trg_profile_storage_cleanup()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE b TEXT;
BEGIN
    FOREACH b IN ARRAY ARRAY['stories', 'avatars', 'voice-notes', 'chat-media', 'posts', 'reels'] LOOP
        PERFORM public.juzzio_enqueue_storage_cleanup(b, OLD.id::text || '/', 'account_deleted', true);
    END LOOP;
    RETURN OLD;
END;
$$;
DROP TRIGGER IF EXISTS trg_juzzio_profile_storage_cleanup ON public.profiles;
CREATE TRIGGER trg_juzzio_profile_storage_cleanup AFTER DELETE ON public.profiles
    FOR EACH ROW EXECUTE FUNCTION public.juzzio_trg_profile_storage_cleanup();

-- Süresi dolan içerik: süreli mesajlar (1 saat tolerans) ve 30 günü geçen biten hikâyeler
CREATE OR REPLACE FUNCTION public.juzzio_purge_expired_content()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_msgs INTEGER; v_stories INTEGER;
BEGIN
    DELETE FROM public.messages WHERE expires_at IS NOT NULL AND expires_at < NOW() - INTERVAL '1 hour';
    GET DIAGNOSTICS v_msgs = ROW_COUNT;
    DELETE FROM public.stories WHERE expires_at < NOW() - INTERVAL '30 days';
    GET DIAGNOSTICS v_stories = ROW_COUNT;
    RETURN jsonb_build_object('messages', v_msgs, 'stories', v_stories);
END;
$$;
REVOKE ALL ON FUNCTION public.juzzio_purge_expired_content() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.juzzio_purge_expired_content() TO service_role;

-- Edge Function için: işlenecek kuyruk kalemleri (kilitli, eşzamanlı işçiler çakışmaz)
CREATE OR REPLACE FUNCTION public.juzzio_storage_cleanup_claim(p_limit INTEGER DEFAULT 100)
RETURNS TABLE (id BIGINT, bucket TEXT, object_name TEXT, is_prefix BOOLEAN)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    UPDATE public.juzzio_storage_cleanup_queue q
       SET attempts = q.attempts + 1
     WHERE q.id IN (
            SELECT x.id FROM public.juzzio_storage_cleanup_queue x
             WHERE x.processed_at IS NULL AND x.attempts < 8
             ORDER BY x.enqueued_at
             FOR UPDATE SKIP LOCKED
             LIMIT LEAST(GREATEST(p_limit, 1), 500))
    RETURNING q.id, q.bucket, q.object_name, q.is_prefix;
END;
$$;
REVOKE ALL ON FUNCTION public.juzzio_storage_cleanup_claim(INTEGER) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.juzzio_storage_cleanup_claim(INTEGER) TO service_role;

CREATE OR REPLACE FUNCTION public.juzzio_storage_cleanup_done(p_ids BIGINT[], p_error TEXT DEFAULT '')
RETURNS VOID
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    UPDATE public.juzzio_storage_cleanup_queue
       SET processed_at = CASE WHEN COALESCE(p_error, '') = '' THEN NOW() ELSE NULL END,
           last_error = LEFT(COALESCE(p_error, ''), 200)
     WHERE id = ANY (p_ids);
$$;
REVOKE ALL ON FUNCTION public.juzzio_storage_cleanup_done(BIGINT[], TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.juzzio_storage_cleanup_done(BIGINT[], TEXT) TO service_role;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        BEGIN
            PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'juzzio_purge_expired_content';
            PERFORM cron.schedule('juzzio_purge_expired_content', '17 * * * *', 'SELECT public.juzzio_purge_expired_content()');
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'pg_cron görevi (juzzio_purge_expired_content) oluşturulamadı: %', SQLERRM;
        END;
    END IF;
END $$;

-- 10.11 Mesaj gönderim idempotency'si (çevrimdışı kuyruk, bildirimden hızlı yanıt, ağ tekrarları)
--  İstemci her gönderim için benzersiz client_msg_id üretir; aynı gönderen + aynı kimlik
--  ikinci kez eklenemez (23505) → istemci bunu "zaten gönderildi" olarak kabul eder.
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS client_msg_id TEXT;
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'messages_client_msg_id_len') THEN
        ALTER TABLE public.messages ADD CONSTRAINT messages_client_msg_id_len
            CHECK (client_msg_id IS NULL OR client_msg_id ~ '^[A-Za-z0-9_-]{8,80}$') NOT VALID;
    END IF;
END $$;
CREATE UNIQUE INDEX IF NOT EXISTS uq_messages_sender_client_msg
    ON public.messages (sender_id, client_msg_id) WHERE client_msg_id IS NOT NULL;

-- 10.12 Sohbet etkinlik durumu: "Yazıyor..." / "Ses kaydediliyor.." (ek paket N-A)
--  Taşıma: Supabase Realtime ÖZEL yayın kanalı 'room-activity:<oda_uuid>'. İçerik yalnızca
--  {state: typing|recording|idle, ts} — mesaj metni ASLA gönderilmez, veritabanına yazılmaz.
--  Yetki (realtime.messages RLS):
--   • Yalnızca odanın etkin üyesi dinleyebilir/gönderebilir.
--   • Birebir odada taraflar arasında engel varsa iki yön de kapalı.
--   • Gönderen çevrimiçi gizliliğini 'nobody' yaptıysa yayın yapamaz; birebir odada karşı
--     taraf gönderenin çevrimiçi durumunu göremiyorsa (yalnız arkadaşlar vb.) yayın yapamaz.
CREATE OR REPLACE FUNCTION public.juzzio_can_room_activity(p_room UUID, p_user UUID, p_sending BOOLEAN)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_is_group BOOLEAN;
    v_other UUID;
    v_privacy TEXT;
BEGIN
    IF p_room IS NULL OR p_user IS NULL OR NOT public.is_room_member(p_room, p_user) THEN
        RETURN false;
    END IF;
    SELECT r.is_group INTO v_is_group FROM public.rooms r WHERE r.id = p_room;
    IF v_is_group IS NULL THEN
        RETURN false;
    END IF;
    IF NOT v_is_group THEN
        SELECT rp.user_id INTO v_other
        FROM public.room_participants rp
        WHERE rp.room_id = p_room AND rp.user_id <> p_user
        LIMIT 1;
        IF v_other IS NOT NULL AND public.is_blocked_between(p_user, v_other) THEN
            RETURN false;
        END IF;
    END IF;
    IF p_sending THEN
        SELECT p.privacy_online INTO v_privacy FROM public.profiles p WHERE p.id = p_user;
        IF COALESCE(v_privacy, 'everyone') = 'nobody' THEN
            RETURN false;
        END IF;
        IF NOT v_is_group AND v_other IS NOT NULL
           AND NOT public.juzzio_can_see_presence(v_other, p_user, COALESCE(v_privacy, 'everyone')) THEN
            RETURN false;
        END IF;
    END IF;
    RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION public.juzzio_can_room_activity(UUID, UUID, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.juzzio_can_room_activity(UUID, UUID, BOOLEAN) TO authenticated, service_role;

DO $$
BEGIN
    IF to_regclass('realtime.messages') IS NULL THEN
        RAISE NOTICE 'realtime.messages yok — oda etkinlik politikaları atlandı';
        RETURN;
    END IF;
    EXECUTE 'DROP POLICY IF EXISTS juzzio_room_activity_read ON realtime.messages';
    EXECUTE 'DROP POLICY IF EXISTS juzzio_room_activity_send ON realtime.messages';
    EXECUTE $p$
        CREATE POLICY juzzio_room_activity_read ON realtime.messages
        FOR SELECT TO authenticated
        USING (
            realtime.messages.extension = 'broadcast'
            AND realtime.topic() LIKE 'room-activity:%'
            AND public.juzzio_can_room_activity(
                    public.juzzio_try_uuid(split_part(realtime.topic(), ':', 2)), auth.uid(), false)
        )
    $p$;
    EXECUTE $p$
        CREATE POLICY juzzio_room_activity_send ON realtime.messages
        FOR INSERT TO authenticated
        WITH CHECK (
            realtime.messages.extension = 'broadcast'
            AND realtime.topic() LIKE 'room-activity:%'
            AND public.juzzio_can_room_activity(
                    public.juzzio_try_uuid(split_part(realtime.topic(), ':', 2)), auth.uid(), true)
        )
    $p$;
END $$;

-- 10.13 Bildirim önizleme kipleri (ek paket N-D) + şifreli içerik sızıntı koruması
--  Cihaz başına kip: 'full' (cihaz mesajı kendisi çözer ve gösterir), 'sender' (yalnız gönderen
--  adı + "yeni mesaj"), 'hidden' (gönderen adı da yok: "Juzzio — Yeni mesaj"). Sunucu FCM'e
--  HİÇBİR kipte mesaj metni koymaz; 'hidden' kipte gönderen adını da koymaz.
ALTER TABLE public.user_push_tokens ADD COLUMN IF NOT EXISTS notify_preview TEXT NOT NULL DEFAULT 'full';
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'user_push_tokens_notify_preview_check') THEN
        ALTER TABLE public.user_push_tokens ADD CONSTRAINT user_push_tokens_notify_preview_check
            CHECK (notify_preview IN ('full', 'sender', 'hidden')) NOT VALID;
    END IF;
END $$;

CREATE OR REPLACE FUNCTION public.set_my_push_preview(p_fcm_token TEXT, p_mode TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_mode TEXT := LOWER(BTRIM(COALESCE(p_mode, '')));
    v_n INT;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'not_authenticated';
    END IF;
    IF v_mode NOT IN ('full', 'sender', 'hidden') THEN
        RAISE EXCEPTION 'invalid_preview_mode';
    END IF;
    -- Yalnız kendi (etkin) cihaz kaydı değişir
    UPDATE public.user_push_tokens
       SET notify_preview = v_mode, updated_at = NOW()
     WHERE user_id = v_uid AND fcm_token = BTRIM(COALESCE(p_fcm_token, ''));
    GET DIAGNOSTICS v_n = ROW_COUNT;
    RETURN v_n > 0;
END;
$$;
REVOKE ALL ON FUNCTION public.set_my_push_preview(TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_my_push_preview(TEXT, TEXT) TO authenticated;

--  Şifreli mesaj gövdesi (juzzio_e2ee_…) hiçbir bildirim önizlemesine girmez. Eski tepki
--  bildirimleri şifreli metnin ilk 80 karakterini önizleme olarak kopyalıyordu (anlamsız şifre
--  metni bildirim çanında ve push gövdesinde görünüyordu). Tüm ekleme yollarını tek noktada keser.
CREATE OR REPLACE FUNCTION public.juzzio_sanitize_notification_preview()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    IF NEW.preview_text IS NOT NULL AND NEW.preview_text ~* 'juzzio_e2ee_' THEN
        IF NEW.event_type = 'reaction' AND position('|' IN NEW.preview_text) > 0 THEN
            NEW.preview_text := split_part(NEW.preview_text, '|', 1) || '|🔒';
        ELSE
            NEW.preview_text := '🔒';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_juzzio_sanitize_notification_preview ON public.notifications;
CREATE TRIGGER trg_juzzio_sanitize_notification_preview
BEFORE INSERT OR UPDATE OF preview_text ON public.notifications
FOR EACH ROW EXECUTE FUNCTION public.juzzio_sanitize_notification_preview();
-- Var olan kayıtlar (idempotent; yalnızca şifreli metin içerenler)
UPDATE public.notifications SET preview_text = preview_text WHERE preview_text ~* 'juzzio_e2ee_';

-- 10.14 Gelen arama bildiriminden Reddet (ek paket N-F)
--  update_call_status genel amaçlıdır (arayan/aranan, birçok durum). Bildirimdeki Reddet düğmesi
--  için dar ve denetimli bir RPC: yalnız ARANAN kişi, yalnız hâlâ ÇALAN arama reddedilebilir;
--  tekrar basma idempotenttir (zaten reddedildiyse 'rejected' döner, başka durum değişmez).
CREATE OR REPLACE FUNCTION public.juzzio_decline_call(p_call UUID)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_row RECORD;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'not_authenticated';
    END IF;
    SELECT id, receiver_id, status INTO v_row FROM public.call_logs WHERE id = p_call FOR UPDATE;
    IF v_row.id IS NULL OR v_row.receiver_id IS DISTINCT FROM v_uid THEN
        RAISE EXCEPTION 'not_allowed';
    END IF;
    IF v_row.status = 'rejected' THEN
        RETURN 'rejected';
    END IF;
    IF v_row.status <> 'ringing' THEN
        RETURN v_row.status; -- bitmiş/cevaplanmış arama değiştirilmez
    END IF;
    UPDATE public.call_logs SET status = 'rejected', ended_at = NOW() WHERE id = p_call;
    RETURN 'rejected';
END;
$$;
REVOKE ALL ON FUNCTION public.juzzio_decline_call(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.juzzio_decline_call(UUID) TO authenticated;

-- 10.15 Sohbet bazlı bildirim ayarları (son talimat §6.4: Sohbet Bilgileri > Bildirimleri Özelleştir)
--  Kişiye özel, yalnız kendi katılım satırı: süreli sessize alma, önizleme (cihaz kipinden daha
--  sıkı olabilir, daha gevşek olamaz), titreşim. Ses: mevcut kişiye özel ton (contact_prefs) kullanılır.
--  (Not: room_participants.muted_until grup moderasyonudur — yazma kısıtı; bununla karıştırılmaz.)
ALTER TABLE public.room_participants ADD COLUMN IF NOT EXISTS notif_muted_until TIMESTAMPTZ;
ALTER TABLE public.room_participants ADD COLUMN IF NOT EXISTS notif_preview TEXT;
ALTER TABLE public.room_participants ADD COLUMN IF NOT EXISTS notif_vibrate BOOLEAN NOT NULL DEFAULT true;
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'room_participants_notif_preview_check') THEN
        ALTER TABLE public.room_participants ADD CONSTRAINT room_participants_notif_preview_check
            CHECK (notif_preview IS NULL OR notif_preview IN ('full', 'sender', 'hidden')) NOT VALID;
    END IF;
END $$;

-- p_mute_minutes: NULL = değiştirme, 0 = sessizi kaldır, -1 = süresiz (100 yıl), >0 dakika (≤ 1 yıl)
-- p_preview: NULL = değiştirme, 'inherit' = cihaz ayarı, full|sender|hidden
CREATE OR REPLACE FUNCTION public.set_room_notification_prefs(
    p_room UUID,
    p_mute_minutes INTEGER DEFAULT NULL,
    p_preview TEXT DEFAULT NULL,
    p_vibrate BOOLEAN DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_preview TEXT := LOWER(BTRIM(COALESCE(p_preview, '')));
    v_row RECORD;
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
    IF NOT public.is_room_member(p_room, v_uid) THEN RAISE EXCEPTION 'not_allowed'; END IF;
    IF p_preview IS NOT NULL AND v_preview NOT IN ('inherit', 'full', 'sender', 'hidden') THEN
        RAISE EXCEPTION 'invalid_preview_mode';
    END IF;
    IF p_mute_minutes IS NOT NULL AND (p_mute_minutes < -1 OR p_mute_minutes > 525600) THEN
        RAISE EXCEPTION 'invalid_mute_duration';
    END IF;
    UPDATE public.room_participants SET
        notif_muted_until = CASE
            WHEN p_mute_minutes IS NULL THEN notif_muted_until
            WHEN p_mute_minutes = 0 THEN NULL
            WHEN p_mute_minutes = -1 THEN NOW() + INTERVAL '100 years'
            ELSE NOW() + make_interval(mins => p_mute_minutes) END,
        notif_preview = CASE
            WHEN p_preview IS NULL THEN notif_preview
            WHEN v_preview = 'inherit' THEN NULL
            ELSE v_preview END,
        notif_vibrate = COALESCE(p_vibrate, notif_vibrate)
    WHERE room_id = p_room AND user_id = v_uid AND left_at IS NULL
    RETURNING notif_muted_until, notif_preview, notif_vibrate INTO v_row;
    RETURN jsonb_build_object(
        'muted_until', v_row.notif_muted_until,
        'preview', COALESCE(v_row.notif_preview, 'inherit'),
        'vibrate', v_row.notif_vibrate);
END;
$$;
REVOKE ALL ON FUNCTION public.set_room_notification_prefs(UUID, INTEGER, TEXT, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_room_notification_prefs(UUID, INTEGER, TEXT, BOOLEAN) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_room_notification_prefs(p_room UUID)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT jsonb_build_object(
        'muted_until', CASE WHEN rp.notif_muted_until > NOW() THEN rp.notif_muted_until END,
        'preview', COALESCE(rp.notif_preview, 'inherit'),
        'vibrate', rp.notif_vibrate)
    FROM public.room_participants rp
    WHERE rp.room_id = p_room AND rp.user_id = auth.uid() AND rp.left_at IS NULL;
$$;
REVOKE ALL ON FUNCTION public.get_room_notification_prefs(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_room_notification_prefs(UUID) TO authenticated;

-- 10.16 Kaydetme bildirimi isteğe bağlı (ek paket N-C: "kaydetme bildirimi varsayılan KAPALI")
--  Gönderi sahibi açıkça açmadıkça kimin kaydettiği bildirilmez (kaydetme özel bir eylemdir).
--  Tercih profile_private'ta (yalnız sahibi okur/yazar); sayaç (saves_count) etkilenmez.
ALTER TABLE public.profile_private ADD COLUMN IF NOT EXISTS notify_post_saves BOOLEAN NOT NULL DEFAULT false;

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
    IF NOT COALESCE((SELECT pp.notify_post_saves FROM public.profile_private pp WHERE pp.user_id = v_author), false) THEN
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

CREATE OR REPLACE FUNCTION public.set_my_save_notifications(p_enabled BOOLEAN)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID := auth.uid();
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
    INSERT INTO public.profile_private (user_id, notify_post_saves, updated_at)
    VALUES (v_uid, COALESCE(p_enabled, false), NOW())
    ON CONFLICT (user_id) DO UPDATE SET notify_post_saves = EXCLUDED.notify_post_saves, updated_at = NOW();
    RETURN COALESCE(p_enabled, false);
END;
$$;
REVOKE ALL ON FUNCTION public.set_my_save_notifications(BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_my_save_notifications(BOOLEAN) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_my_save_notifications()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT COALESCE((SELECT notify_post_saves FROM public.profile_private WHERE user_id = auth.uid()), false);
$$;
REVOKE ALL ON FUNCTION public.get_my_save_notifications() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_save_notifications() TO authenticated;

-- 10.17 @etiketleme (ek paket N-B; son talimat §3.1 Keşfet)
--  Gönderi açıklaması, yorum/yanıt ve hikâye metnindeki @kullanıcıadı belirteçleri SUNUCUDA
--  ayrıştırılır (istemciye güvenilmez). Her etiket için:
--   • etiketlenen hesap var olmalı, taraflar arasında engel olmamalı,
--   • etiketlenenin tercihi (privacy_mentions: everyone | friends | nobody) izin vermeli,
--   • etiketlenen içeriği GÖREBİLMELİ (görünürlük) — göremediği içerik için bildirim yok,
--   • içerik başına en fazla 10 etiket, yazar başına saatte 60 etiket bildirimi (spam sınırı).
--  Bildirimler idempotent (dedupe_key); içerik düzenlenince yalnız YENİ etiketler bildirilir.
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS privacy_mentions TEXT NOT NULL DEFAULT 'everyone';
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'profiles_privacy_mentions_check') THEN
        ALTER TABLE public.profiles ADD CONSTRAINT profiles_privacy_mentions_check
            CHECK (privacy_mentions IN ('everyone', 'friends', 'nobody')) NOT VALID;
    END IF;
END $$;

ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_event_type_check;
ALTER TABLE public.notifications ADD CONSTRAINT notifications_event_type_check CHECK (event_type = ANY (ARRAY[
    'like', 'comment', 'reply', 'follow', 'follow_request', 'follow_accepted', 'friend_request',
    'friend_accepted', 'story_like', 'story_reply', 'message', 'missed_call', 'incoming_call',
    'group_activity', 'system', 'chick_invite', 'chick_hatched', 'chick_hungry', 'chick_dying',
    'chick_died', 'reaction', 'save', 'mention'
])) NOT VALID;

CREATE TABLE IF NOT EXISTS public.content_mentions (
    id BIGSERIAL PRIMARY KEY,
    content_type TEXT NOT NULL CHECK (content_type IN ('post', 'comment', 'story')),
    content_id UUID NOT NULL,
    post_id UUID,
    author_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    mentioned_user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (content_type, content_id, mentioned_user_id)
);
CREATE INDEX IF NOT EXISTS idx_content_mentions_user ON public.content_mentions (mentioned_user_id, created_at DESC);
ALTER TABLE public.content_mentions ENABLE ROW LEVEL SECURITY;
REVOKE INSERT, UPDATE, DELETE ON public.content_mentions FROM anon, authenticated;
DROP POLICY IF EXISTS content_mentions_select_party ON public.content_mentions;
CREATE POLICY content_mentions_select_party ON public.content_mentions FOR SELECT TO authenticated
    USING (author_id = auth.uid() OR mentioned_user_id = auth.uid());

-- Saf ayrıştırıcı: küçük harf, tekil, en fazla 10, e-posta içindeki @ yok sayılır
CREATE OR REPLACE FUNCTION public.juzzio_extract_mentions(p_text TEXT)
RETURNS TEXT[]
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT COALESCE(ARRAY(
        SELECT u FROM (
            SELECT lower(rtrim(m[1], '.')) AS u, min(ord) AS first_pos
            FROM regexp_matches(COALESCE(p_text, ''), '(?:^|[^A-Za-z0-9_.@])@([A-Za-z0-9_.]{3,30})(?![A-Za-z0-9_.])', 'g')
                 WITH ORDINALITY AS t(m, ord)
            GROUP BY 1
        ) x
        WHERE length(u) >= 3
        ORDER BY first_pos
        LIMIT 10
    ), ARRAY[]::TEXT[]);
$$;
GRANT EXECUTE ON FUNCTION public.juzzio_extract_mentions(TEXT) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.juzzio_can_mention(p_actor UUID, p_target UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT p_actor IS NOT NULL AND p_target IS NOT NULL AND p_actor <> p_target
       AND NOT public.is_blocked_between(p_actor, p_target)
       AND EXISTS (
           SELECT 1 FROM public.profiles t
           WHERE t.id = p_target
             AND public.juzzio_can_see_presence(p_actor, p_target, t.privacy_mentions));
$$;
GRANT EXECUTE ON FUNCTION public.juzzio_can_mention(UUID, UUID) TO authenticated, service_role;

-- Ortak işleyici: etiketleri kaydeder + bildirir. p_can_view: etiketlenen içeriği görebilir mi?
CREATE OR REPLACE FUNCTION public.juzzio_process_mentions(
    p_type TEXT, p_content UUID, p_post UUID, p_author UUID, p_text TEXT, p_visibility_owner UUID, p_visibility TEXT
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_name TEXT;
    v_target UUID;
    v_actor RECORD;
    v_n INTEGER := 0;
    v_visible BOOLEAN;
BEGIN
    SELECT username, display_name, avatar_url INTO v_actor FROM public.profiles WHERE id = p_author;
    FOREACH v_name IN ARRAY public.juzzio_extract_mentions(p_text) LOOP
        SELECT id INTO v_target FROM public.profiles WHERE lower(username) = v_name LIMIT 1;
        CONTINUE WHEN v_target IS NULL OR NOT public.juzzio_can_mention(p_author, v_target);
        v_visible := CASE p_type
            WHEN 'story' THEN public.can_view_story(v_target, p_visibility_owner, p_visibility)
            ELSE public.can_view_user_content(v_target, p_visibility_owner, p_visibility) END;
        CONTINUE WHEN NOT COALESCE(v_visible, false);
        INSERT INTO public.content_mentions (content_type, content_id, post_id, author_id, mentioned_user_id)
        VALUES (p_type, p_content, p_post, p_author, v_target)
        ON CONFLICT (content_type, content_id, mentioned_user_id) DO NOTHING;
        CONTINUE WHEN NOT FOUND; -- zaten etiketliydi (düzenleme) → yeniden bildirme
        v_n := v_n + 1;
        -- spam sınırı: yazar başına saatte 60 etiket bildirimi (kayıt yine tutulur)
        CONTINUE WHEN NOT public.juzzio_rate_check(p_author, 'mention_notify', 60, 3600);
        INSERT INTO public.notifications (
            recipient_id, actor_id, actor_username, actor_display_name, actor_avatar_url,
            event_type, target_id, target_secondary_id, preview_text, dedupe_key
        ) VALUES (
            v_target, p_author, COALESCE(v_actor.username, ''),
            COALESCE(NULLIF(v_actor.display_name, ''), v_actor.username, 'Juzzio'), v_actor.avatar_url,
            'mention', COALESCE(p_post, p_content)::text, p_content::text,
            p_type || '|' || LEFT(REGEXP_REPLACE(COALESCE(p_text, ''), '\s+', ' ', 'g'), 120),
            'mention_' || p_type || '_' || p_content::text || '_' || v_target::text
        )
        ON CONFLICT (recipient_id, dedupe_key) DO NOTHING;
    END LOOP;
    RETURN v_n;
END;
$$;
REVOKE ALL ON FUNCTION public.juzzio_process_mentions(TEXT, UUID, UUID, UUID, TEXT, UUID, TEXT) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.juzzio_mentions_on_post()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF NEW.is_deleted THEN RETURN NEW; END IF;
    IF TG_OP = 'UPDATE' AND NEW.caption IS NOT DISTINCT FROM OLD.caption AND NEW.visibility IS NOT DISTINCT FROM OLD.visibility THEN
        RETURN NEW;
    END IF;
    PERFORM public.juzzio_process_mentions('post', NEW.id, NEW.id, NEW.author_id, NEW.caption, NEW.author_id, NEW.visibility);
    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    RETURN NEW; -- etiket hatası paylaşımı asla engellemez
END $$;
DROP TRIGGER IF EXISTS trg_juzzio_mentions_post ON public.posts;
CREATE TRIGGER trg_juzzio_mentions_post AFTER INSERT OR UPDATE OF caption, visibility, is_deleted ON public.posts
    FOR EACH ROW EXECUTE FUNCTION public.juzzio_mentions_on_post();

CREATE OR REPLACE FUNCTION public.juzzio_mentions_on_comment()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_post RECORD;
BEGIN
    IF TG_OP = 'UPDATE' AND NEW.content IS NOT DISTINCT FROM OLD.content THEN RETURN NEW; END IF;
    SELECT author_id, visibility, is_deleted INTO v_post FROM public.posts WHERE id = NEW.post_id;
    IF v_post.author_id IS NULL OR v_post.is_deleted THEN RETURN NEW; END IF;
    PERFORM public.juzzio_process_mentions('comment', NEW.id, NEW.post_id, NEW.author_id, NEW.content, v_post.author_id, v_post.visibility);
    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_juzzio_mentions_comment ON public.post_comments;
CREATE TRIGGER trg_juzzio_mentions_comment AFTER INSERT OR UPDATE OF content ON public.post_comments
    FOR EACH ROW EXECUTE FUNCTION public.juzzio_mentions_on_comment();

CREATE OR REPLACE FUNCTION public.juzzio_mentions_on_story()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF TG_OP = 'UPDATE' AND NEW.caption_original IS NOT DISTINCT FROM OLD.caption_original
       AND NEW.overlay_text_original IS NOT DISTINCT FROM OLD.overlay_text_original THEN
        RETURN NEW;
    END IF;
    PERFORM public.juzzio_process_mentions('story', NEW.id, NULL, NEW.user_id,
        COALESCE(NEW.caption_original, '') || ' ' || COALESCE(NEW.overlay_text_original, ''), NEW.user_id, NEW.visibility);
    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_juzzio_mentions_story ON public.stories;
CREATE TRIGGER trg_juzzio_mentions_story AFTER INSERT OR UPDATE OF caption_original, overlay_text_original ON public.stories
    FOR EACH ROW EXECUTE FUNCTION public.juzzio_mentions_on_story();

-- Öneri: etiketlenebilir kişiler (önce arkadaşlar), engelliler ve 'nobody' hariç
CREATE OR REPLACE FUNCTION public.suggest_mentions(p_query TEXT, p_limit INTEGER DEFAULT 8)
RETURNS TABLE (user_id UUID, username TEXT, display_name TEXT, avatar_url TEXT, is_friend BOOLEAN)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    WITH q AS (SELECT lower(regexp_replace(BTRIM(COALESCE(p_query, '')), '[%_\\]', '', 'g')) AS v)
    SELECT p.id, p.username, p.display_name, p.avatar_url, public.is_friends_accepted(auth.uid(), p.id) AS is_friend
    FROM public.profiles p, q
    WHERE auth.uid() IS NOT NULL
      AND p.id <> auth.uid()
      AND p.username IS NOT NULL
      AND LENGTH(q.v) BETWEEN 1 AND 30
      AND (lower(p.username) LIKE q.v || '%' OR lower(COALESCE(p.display_name, '')) LIKE q.v || '%')
      AND public.juzzio_can_mention(auth.uid(), p.id)
    ORDER BY is_friend DESC, lower(p.username)
    LIMIT LEAST(GREATEST(COALESCE(p_limit, 8), 1), 20);
$$;
REVOKE ALL ON FUNCTION public.suggest_mentions(TEXT, INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.suggest_mentions(TEXT, INTEGER) TO authenticated;

CREATE OR REPLACE FUNCTION public.set_my_mention_privacy(p_mode TEXT)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_mode TEXT := LOWER(BTRIM(COALESCE(p_mode, '')));
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
    IF v_mode NOT IN ('everyone', 'friends', 'nobody') THEN RAISE EXCEPTION 'invalid_mention_privacy'; END IF;
    UPDATE public.profiles SET privacy_mentions = v_mode WHERE id = auth.uid();
    RETURN v_mode;
END;
$$;
REVOKE ALL ON FUNCTION public.set_my_mention_privacy(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_my_mention_privacy(TEXT) TO authenticated;

-- 10.18 Personal: Yaşam Merkezi (görev + hatırlatma), mesaja hatırlatıcı, kayıtlı mesajlar
--  (son talimat §4.1–§4.3). Tek tablo: life_tasks (kind = task | message_reminder) — ikinci bir
--  hatırlatma sistemi kurulmaz. Yalnız sahibi okur/yazar (RLS). Mesaja bağlı kayıtlarda kullanıcı
--  o odanın ETKİN üyesi olmalıdır (tetikleyici). Mesaj metni KOPYALANMAZ (E2EE içeriği sunucuya
--  açık yazılmaz) — yalnız mesaj/oda kimliği tutulur, metin cihazda çözülerek gösterilir.
CREATE TABLE IF NOT EXISTS public.life_tasks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    kind TEXT NOT NULL DEFAULT 'task' CHECK (kind IN ('task', 'message_reminder')),
    title TEXT NOT NULL DEFAULT '' CHECK (LENGTH(title) <= 200),
    description TEXT NOT NULL DEFAULT '' CHECK (LENGTH(description) <= 2000),
    due_at TIMESTAMPTZ,
    remind_at TIMESTAMPTZ,
    reminded_at TIMESTAMPTZ,
    done_at TIMESTAMPTZ,
    room_id UUID REFERENCES public.rooms(id) ON DELETE CASCADE,
    message_id UUID REFERENCES public.messages(id) ON DELETE CASCADE,
    client_request_id TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT life_tasks_title_or_message CHECK (kind = 'message_reminder' OR LENGTH(BTRIM(title)) > 0),
    CONSTRAINT life_tasks_message_needs_ids CHECK (kind = 'task' OR (message_id IS NOT NULL AND room_id IS NOT NULL AND remind_at IS NOT NULL)),
    CONSTRAINT life_tasks_unique_req UNIQUE (user_id, client_request_id)
);
ALTER TABLE public.life_tasks ALTER COLUMN user_id SET DEFAULT auth.uid();
CREATE INDEX IF NOT EXISTS idx_life_tasks_user_due ON public.life_tasks (user_id, done_at, due_at);
CREATE INDEX IF NOT EXISTS idx_life_tasks_remind ON public.life_tasks (remind_at) WHERE reminded_at IS NULL AND done_at IS NULL;
ALTER TABLE public.life_tasks ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS life_tasks_own ON public.life_tasks;
CREATE POLICY life_tasks_own ON public.life_tasks FOR ALL TO authenticated
    USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
GRANT SELECT, INSERT, UPDATE, DELETE ON public.life_tasks TO authenticated;

CREATE OR REPLACE FUNCTION public.juzzio_life_task_guard()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_room UUID;
BEGIN
    NEW.title := BTRIM(COALESCE(NEW.title, ''));
    NEW.description := BTRIM(COALESCE(NEW.description, ''));
    NEW.updated_at := NOW();
    IF TG_OP = 'UPDATE' THEN
        -- sahiplik ve bağlam değiştirilemez
        NEW.user_id := OLD.user_id;
        NEW.kind := OLD.kind;
        NEW.message_id := OLD.message_id;
        NEW.room_id := OLD.room_id;
        NEW.created_at := OLD.created_at;
        -- hatırlatma zamanı değişirse yeniden hatırlatılabilir
        IF NEW.remind_at IS DISTINCT FROM OLD.remind_at THEN NEW.reminded_at := NULL; END IF;
    END IF;
    IF NEW.kind = 'message_reminder' THEN
        SELECT room_id INTO v_room FROM public.messages WHERE id = NEW.message_id;
        IF v_room IS NULL OR v_room IS DISTINCT FROM NEW.room_id OR NOT public.is_room_member(NEW.room_id, NEW.user_id) THEN
            RAISE EXCEPTION 'not_allowed';
        END IF;
    END IF;
    -- kullanıcı başına makul üst sınır (kötüye kullanım)
    IF TG_OP = 'INSERT' AND (SELECT count(*) FROM public.life_tasks WHERE user_id = NEW.user_id AND done_at IS NULL) >= 2000 THEN
        RAISE EXCEPTION 'too_many_tasks';
    END IF;
    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_juzzio_life_task_guard ON public.life_tasks;
CREATE TRIGGER trg_juzzio_life_task_guard BEFORE INSERT OR UPDATE ON public.life_tasks
    FOR EACH ROW EXECUTE FUNCTION public.juzzio_life_task_guard();

CREATE TABLE IF NOT EXISTS public.saved_messages (
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    message_id UUID NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
    room_id UUID NOT NULL REFERENCES public.rooms(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, message_id)
);
ALTER TABLE public.saved_messages ALTER COLUMN user_id SET DEFAULT auth.uid();
CREATE INDEX IF NOT EXISTS idx_saved_messages_user ON public.saved_messages (user_id, created_at DESC);
ALTER TABLE public.saved_messages ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS saved_messages_own_select ON public.saved_messages;
DROP POLICY IF EXISTS saved_messages_own_insert ON public.saved_messages;
DROP POLICY IF EXISTS saved_messages_own_delete ON public.saved_messages;
CREATE POLICY saved_messages_own_select ON public.saved_messages FOR SELECT TO authenticated USING (user_id = auth.uid());
CREATE POLICY saved_messages_own_insert ON public.saved_messages FOR INSERT TO authenticated
    WITH CHECK (user_id = auth.uid() AND public.is_room_member(room_id, auth.uid())
                AND EXISTS (SELECT 1 FROM public.messages m WHERE m.id = message_id AND m.room_id = saved_messages.room_id));
CREATE POLICY saved_messages_own_delete ON public.saved_messages FOR DELETE TO authenticated USING (user_id = auth.uid());
GRANT SELECT, INSERT, DELETE ON public.saved_messages TO authenticated;
-- Kaydetme karşı tarafa BİLDİRİLMEZ (tetikleyici/bildirim yok — talimat §4.3).

ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_event_type_check;
ALTER TABLE public.notifications ADD CONSTRAINT notifications_event_type_check CHECK (event_type = ANY (ARRAY[
    'like', 'comment', 'reply', 'follow', 'follow_request', 'follow_accepted', 'friend_request',
    'friend_accepted', 'story_like', 'story_reply', 'message', 'missed_call', 'incoming_call',
    'group_activity', 'system', 'chick_invite', 'chick_hatched', 'chick_hungry', 'chick_dying',
    'chick_died', 'reaction', 'save', 'mention', 'reminder'
])) NOT VALID;

-- Zamanı gelen hatırlatmalar → kendi bildirimi (push-webhook FCM'e iletir). Atomik, idempotent.
CREATE OR REPLACE FUNCTION public.juzzio_fire_due_reminders(p_limit INTEGER DEFAULT 500)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    r RECORD;
    v_n INTEGER := 0;
BEGIN
    FOR r IN
        SELECT t.id, t.user_id, t.kind, t.title, t.room_id, t.message_id
        FROM public.life_tasks t
        WHERE t.remind_at IS NOT NULL AND t.remind_at <= NOW()
          AND t.reminded_at IS NULL AND t.done_at IS NULL
        ORDER BY t.remind_at
        LIMIT LEAST(GREATEST(COALESCE(p_limit, 500), 1), 2000)
        FOR UPDATE SKIP LOCKED
    LOOP
        UPDATE public.life_tasks SET reminded_at = NOW() WHERE id = r.id;
        -- mesaj hatırlatıcısında artık üye değilse sessizce atlanır
        CONTINUE WHEN r.kind = 'message_reminder' AND NOT public.is_room_member(r.room_id, r.user_id);
        INSERT INTO public.notifications (recipient_id, actor_id, actor_username, actor_display_name,
                                          event_type, target_id, target_secondary_id, preview_text, dedupe_key)
        VALUES (r.user_id, NULL, '', 'Juzzio', 'reminder',
                COALESCE(r.room_id::text, r.id::text), COALESCE(r.message_id::text, r.id::text),
                CASE WHEN r.kind = 'message_reminder' THEN 'message|' ELSE 'task|' || LEFT(r.title, 120) END,
                'reminder_' || r.id::text || '_' || extract(epoch FROM NOW())::bigint::text)
        ON CONFLICT (recipient_id, dedupe_key) DO NOTHING;
        v_n := v_n + 1;
    END LOOP;
    RETURN v_n;
END;
$$;
REVOKE ALL ON FUNCTION public.juzzio_fire_due_reminders(INTEGER) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.juzzio_fire_due_reminders(INTEGER) TO service_role;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        BEGIN
            PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'juzzio_fire_due_reminders';
            PERFORM cron.schedule('juzzio_fire_due_reminders', '* * * * *', 'SELECT public.juzzio_fire_due_reminders()');
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'pg_cron görevi (juzzio_fire_due_reminders) oluşturulamadı: %', SQLERRM;
        END;
    END IF;
END $$;

-- 10.19 Mesaj düzenleme + düzenleme geçmişi (son talimat §4.5)
--  Politika: yalnız gönderen, yalnız 'text' mesajı, gönderimden sonra 15 dk içinde, en fazla 10 kez.
--  Geçmiş: önceki sürüm (düz metin YA DA E2EE zarfı — sunucu şifreli içeriği AÇMAZ, olduğu gibi
--  saklar) yalnız oda üyelerine görünür; 30 gün saklanır; mesaj silinince geçmişi de silinir.
CREATE TABLE IF NOT EXISTS public.message_edits (
    id BIGSERIAL PRIMARY KEY,
    message_id UUID NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
    room_id UUID NOT NULL REFERENCES public.rooms(id) ON DELETE CASCADE,
    editor_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    prev_text TEXT NOT NULL DEFAULT '',
    prev_metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    prev_edited_at TIMESTAMPTZ,
    edited_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_message_edits_msg ON public.message_edits (message_id, edited_at DESC);
ALTER TABLE public.message_edits ENABLE ROW LEVEL SECURITY;
REVOKE INSERT, UPDATE, DELETE ON public.message_edits FROM anon, authenticated;
GRANT SELECT ON public.message_edits TO authenticated;
DROP POLICY IF EXISTS message_edits_member_read ON public.message_edits;
CREATE POLICY message_edits_member_read ON public.message_edits FOR SELECT TO authenticated
    USING (public.is_room_member(room_id, auth.uid()) AND edited_at > NOW() - INTERVAL '30 days');

CREATE OR REPLACE FUNCTION public.juzzio_message_edit_guard()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Silme (yumuşak) düzenleme sayılmaz; geçmiş temizlenir
    IF NEW.is_deleted AND NOT OLD.is_deleted THEN
        DELETE FROM public.message_edits WHERE message_id = OLD.id;
        RETURN NEW;
    END IF;
    IF NEW.original_text IS NOT DISTINCT FROM OLD.original_text
       AND (NEW.metadata -> 'e2ee') IS NOT DISTINCT FROM (OLD.metadata -> 'e2ee') THEN
        RETURN NEW; -- içerik değişmedi (tepki, sabitleme, çeviri vb.)
    END IF;
    -- Sistem/servis güncellemeleri (ör. sesli not dökümü) bu kurala tabi değildir
    IF auth.uid() IS NULL THEN RETURN NEW; END IF;
    IF OLD.is_deleted OR OLD.message_type <> 'text' OR OLD.sender_id IS DISTINCT FROM auth.uid() THEN
        RAISE EXCEPTION 'edit_not_allowed';
    END IF;
    IF OLD.created_at < NOW() - INTERVAL '15 minutes' THEN
        RAISE EXCEPTION 'edit_window_expired';
    END IF;
    IF (SELECT count(*) FROM public.message_edits WHERE message_id = OLD.id) >= 10 THEN
        RAISE EXCEPTION 'edit_limit_reached';
    END IF;
    IF LENGTH(BTRIM(COALESCE(NEW.original_text, ''))) = 0 AND NOT (COALESCE(NEW.metadata, '{}'::jsonb) ? 'e2ee') THEN
        RAISE EXCEPTION 'edit_empty';
    END IF;
    INSERT INTO public.message_edits (message_id, room_id, editor_id, prev_text, prev_metadata, prev_edited_at)
    VALUES (OLD.id, OLD.room_id, auth.uid(), COALESCE(OLD.original_text, ''),
            CASE WHEN COALESCE(OLD.metadata, '{}'::jsonb) ? 'e2ee'
                 THEN jsonb_build_object('e2ee', OLD.metadata -> 'e2ee') ELSE '{}'::jsonb END,
            OLD.edited_at);
    NEW.edited_at := NOW();
    -- eski çeviri yeni metne ait değildir
    IF NOT (COALESCE(NEW.metadata, '{}'::jsonb) ? 'e2ee') AND NEW.translated_text IS NOT DISTINCT FROM OLD.translated_text THEN
        NEW.translated_text := '';
    END IF;
    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_juzzio_message_edit_guard ON public.messages;
CREATE TRIGGER trg_juzzio_message_edit_guard BEFORE UPDATE OF original_text, metadata, is_deleted ON public.messages
    FOR EACH ROW EXECUTE FUNCTION public.juzzio_message_edit_guard();

CREATE OR REPLACE FUNCTION public.juzzio_purge_old_message_edits()
RETURNS INTEGER
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    WITH d AS (DELETE FROM public.message_edits WHERE edited_at < NOW() - INTERVAL '30 days' RETURNING 1)
    SELECT count(*)::int FROM d;
$$;
REVOKE ALL ON FUNCTION public.juzzio_purge_old_message_edits() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.juzzio_purge_old_message_edits() TO service_role;
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        BEGIN
            PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'juzzio_purge_old_message_edits';
            PERFORM cron.schedule('juzzio_purge_old_message_edits', '41 3 * * *', 'SELECT public.juzzio_purge_old_message_edits()');
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'pg_cron görevi (juzzio_purge_old_message_edits) oluşturulamadı: %', SQLERRM;
        END;
    END IF;
END $$;

-- =============================================================================
-- 10.20 JUZZIO BUSINESS — hesap modu, durum makinesi, hukuki onaylar, kurulum adımları
--  (Business eki §1–§4, §9, §15–§16; son talimat §2). Tek kimlik: business hesabı kullanıcının
--  kendi profiline bağlıdır (business_id = sahibin kullanıcı kimliği). Ayrı kullanıcı sistemi YOK.
--  İstemci durum alanını ASLA doğrudan yazamaz: tablolar istemciye yalnız okunur, tüm geçişler
--  SECURITY DEFINER RPC'lerde doğrulanır ve business_status_events'e (değiştirilemez) yazılır.
--  E2EE'ye dokunulmaz: geçiş anahtarları, sohbetleri ve mesajları değiştirmez/kopyalamaz.
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.business_accounts (
    id UUID PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
    status TEXT NOT NULL DEFAULT 'personal' CHECK (status IN (
        'personal', 'business_application_started', 'business_terms_pending', 'business_preparing',
        'business_active', 'business_rejected', 'business_cancelled', 'business_suspended', 'business_reverting',
        'business_paused')),
    profile_type TEXT NOT NULL DEFAULT 'individual_professional' CHECK (profile_type IN (
        'individual_professional', 'creator', 'business', 'organization', 'community_operator', 'service_provider')),
    display_name TEXT NOT NULL DEFAULT '' CHECK (LENGTH(display_name) <= 80),
    professional_title TEXT NOT NULL DEFAULT '' CHECK (LENGTH(professional_title) <= 80),
    description TEXT NOT NULL DEFAULT '' CHECK (LENGTH(description) <= 1000),
    logo_url TEXT,
    cover_url TEXT,
    website TEXT NOT NULL DEFAULT '' CHECK (LENGTH(website) <= 200),
    contact_email TEXT NOT NULL DEFAULT '' CHECK (LENGTH(contact_email) <= 200),
    contact_phone TEXT NOT NULL DEFAULT '' CHECK (LENGTH(contact_phone) <= 40),
    working_hours JSONB NOT NULL DEFAULT '{}'::jsonb,
    timezone TEXT NOT NULL DEFAULT 'Europe/Istanbul',
    categories TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    location TEXT NOT NULL DEFAULT '' CHECK (LENGTH(location) <= 120),
    social_links JSONB NOT NULL DEFAULT '{}'::jsonb,
    is_verified BOOLEAN NOT NULL DEFAULT false,
    active_view TEXT NOT NULL DEFAULT 'personal' CHECK (active_view IN ('personal', 'business')),
    status_reason TEXT NOT NULL DEFAULT '',
    application_request_id TEXT,
    activated_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE public.business_accounts ENABLE ROW LEVEL SECURITY;
REVOKE INSERT, UPDATE, DELETE ON public.business_accounts FROM anon, authenticated;
GRANT SELECT ON public.business_accounts TO authenticated;
DROP POLICY IF EXISTS business_accounts_read ON public.business_accounts;
-- Sahibi her şeyi; diğerleri yalnız AKTİF işletme profilini görür (herkese açık işletme sayfası)
CREATE POLICY business_accounts_read ON public.business_accounts FOR SELECT TO authenticated
    USING (id = auth.uid() OR (status = 'business_active' AND NOT public.is_blocked_between(auth.uid(), id)));

CREATE TABLE IF NOT EXISTS public.business_status_events (
    id BIGSERIAL PRIMARY KEY,
    business_id UUID NOT NULL REFERENCES public.business_accounts(id) ON DELETE CASCADE,
    from_status TEXT NOT NULL,
    to_status TEXT NOT NULL,
    actor_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    actor_kind TEXT NOT NULL DEFAULT 'owner' CHECK (actor_kind IN ('owner', 'system', 'staff')),
    reason TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE public.business_status_events ENABLE ROW LEVEL SECURITY;
REVOKE INSERT, UPDATE, DELETE ON public.business_status_events FROM anon, authenticated;
GRANT SELECT ON public.business_status_events TO authenticated;
DROP POLICY IF EXISTS business_status_events_owner ON public.business_status_events;
CREATE POLICY business_status_events_owner ON public.business_status_events FOR SELECT TO authenticated
    USING (business_id = auth.uid());

-- İzin verilen geçişler (tek doğruluk kaynağı). İstemci yalnız 'owner' satırlarını tetikleyebilir.
CREATE OR REPLACE FUNCTION public.juzzio_business_transition_allowed(p_from TEXT, p_to TEXT, p_kind TEXT)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT (p_kind, p_from, p_to) IN (
        ('owner', 'personal', 'business_application_started'),
        ('owner', 'business_cancelled', 'business_application_started'),
        ('owner', 'business_rejected', 'business_application_started'),
        ('owner', 'business_application_started', 'business_terms_pending'),
        ('owner', 'business_terms_pending', 'business_preparing'),
        ('owner', 'business_application_started', 'business_cancelled'),
        ('owner', 'business_terms_pending', 'business_cancelled'),
        ('system', 'business_preparing', 'business_active'),
        ('owner', 'business_active', 'business_paused'),
        ('owner', 'business_paused', 'business_active'),
        ('owner', 'business_active', 'business_reverting'),
        ('owner', 'business_paused', 'business_reverting'),
        ('system', 'business_reverting', 'business_cancelled'),
        ('staff', 'business_preparing', 'business_rejected'),
        ('staff', 'business_active', 'business_suspended'),
        ('staff', 'business_paused', 'business_suspended'),
        ('staff', 'business_suspended', 'business_active'),
        ('staff', 'business_application_started', 'business_rejected'),
        ('staff', 'business_terms_pending', 'business_rejected')
    );
$$;

CREATE OR REPLACE FUNCTION public.juzzio_business_set_status(p_business UUID, p_to TEXT, p_kind TEXT, p_reason TEXT DEFAULT '')
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_from TEXT;
BEGIN
    SELECT status INTO v_from FROM public.business_accounts WHERE id = p_business FOR UPDATE;
    IF v_from IS NULL THEN RAISE EXCEPTION 'business_not_found'; END IF;
    IF v_from = p_to THEN RETURN v_from; END IF; -- idempotent
    IF NOT public.juzzio_business_transition_allowed(v_from, p_to, p_kind) THEN
        RAISE EXCEPTION 'invalid_transition:%->%', v_from, p_to;
    END IF;
    UPDATE public.business_accounts
       SET status = p_to, status_reason = LEFT(COALESCE(p_reason, ''), 300), updated_at = NOW(),
           activated_at = CASE WHEN p_to = 'business_active' THEN COALESCE(activated_at, NOW()) ELSE activated_at END,
           active_view = CASE WHEN p_to IN ('business_active') THEN active_view ELSE 'personal' END
     WHERE id = p_business;
    INSERT INTO public.business_status_events (business_id, from_status, to_status, actor_id, actor_kind, reason)
    VALUES (p_business, v_from, p_to, auth.uid(), p_kind, LEFT(COALESCE(p_reason, ''), 300));
    RETURN p_to;
END;
$$;
REVOKE ALL ON FUNCTION public.juzzio_business_set_status(UUID, TEXT, TEXT, TEXT) FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Hukuki metinler ve onaylar (Business eki §3). Metinler TASLAKTIR: hukuk incelemesi olmadan
-- 'published' yapılamaz (yalnız legal.publish yetkili personel, inceleme notuyla).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.legal_documents (
    id BIGSERIAL PRIMARY KEY,
    doc_key TEXT NOT NULL CHECK (doc_key ~ '^[a-z0-9_]{3,60}$'),
    version INTEGER NOT NULL CHECK (version > 0),
    locale TEXT NOT NULL DEFAULT 'tr',
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    consent_type TEXT NOT NULL CHECK (consent_type IN ('contract', 'information', 'explicit_consent', 'marketing')),
    required_for_business BOOLEAN NOT NULL DEFAULT false,
    review_status TEXT NOT NULL DEFAULT 'DRAFT - LEGAL REVIEW REQUIRED'
        CHECK (review_status IN ('DRAFT - LEGAL REVIEW REQUIRED', 'LEGAL REVIEWED')),
    review_note TEXT NOT NULL DEFAULT '',
    effective_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    policy_hash TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (doc_key, version, locale)
);
ALTER TABLE public.legal_documents ENABLE ROW LEVEL SECURITY;
REVOKE INSERT, UPDATE, DELETE ON public.legal_documents FROM anon, authenticated;
GRANT SELECT ON public.legal_documents TO anon, authenticated;
DROP POLICY IF EXISTS legal_documents_read ON public.legal_documents;
CREATE POLICY legal_documents_read ON public.legal_documents FOR SELECT TO anon, authenticated USING (true);

CREATE OR REPLACE FUNCTION public.juzzio_legal_hash()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = public, extensions AS $$
BEGIN
    NEW.policy_hash := encode(digest(convert_to(NEW.doc_key || '|' || NEW.version || '|' || NEW.locale || '|' || NEW.title || '|' || NEW.body, 'UTF8'), 'sha256'), 'hex');
    RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_juzzio_legal_hash ON public.legal_documents;
CREATE TRIGGER trg_juzzio_legal_hash BEFORE INSERT OR UPDATE OF title, body, version, locale ON public.legal_documents
    FOR EACH ROW EXECUTE FUNCTION public.juzzio_legal_hash();

-- Onaylar yalnız EKLENİR (değiştirilemez denetim geçmişi). Geri alma = yeni 'withdraw' satırı.
CREATE TABLE IF NOT EXISTS public.user_consents (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    document_id BIGINT NOT NULL REFERENCES public.legal_documents(id),
    doc_key TEXT NOT NULL,
    document_version INTEGER NOT NULL,
    consent_type TEXT NOT NULL,
    action TEXT NOT NULL CHECK (action IN ('accept', 'withdraw')),
    locale TEXT NOT NULL DEFAULT 'tr',
    policy_hash TEXT NOT NULL,
    client_info TEXT NOT NULL DEFAULT '' CHECK (LENGTH(client_info) <= 120), -- yalnız uygulama sürümü (minimizasyon)
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_user_consents_user ON public.user_consents (user_id, doc_key, created_at DESC);
ALTER TABLE public.user_consents ENABLE ROW LEVEL SECURITY;
REVOKE INSERT, UPDATE, DELETE ON public.user_consents FROM anon, authenticated;
GRANT SELECT ON public.user_consents TO authenticated;
DROP POLICY IF EXISTS user_consents_own ON public.user_consents;
CREATE POLICY user_consents_own ON public.user_consents FOR SELECT TO authenticated USING (user_id = auth.uid());

-- Bir belgenin güncel sürümü (dil yoksa tr)
CREATE OR REPLACE FUNCTION public.juzzio_current_legal_doc(p_key TEXT, p_locale TEXT DEFAULT 'tr')
RETURNS public.legal_documents
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT d.* FROM public.legal_documents d
    WHERE d.doc_key = p_key AND d.locale IN (COALESCE(p_locale, 'tr'), 'tr') AND d.effective_at <= NOW()
    ORDER BY (d.locale = COALESCE(p_locale, 'tr')) DESC, d.version DESC
    LIMIT 1;
$$;

-- Kullanıcının bir belgenin GÜNCEL sürümünü geçerli olarak kabul etmiş olup olmadığı
CREATE OR REPLACE FUNCTION public.juzzio_has_current_consent(p_user UUID, p_key TEXT)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT COALESCE((
        SELECT c.action = 'accept'
        FROM public.user_consents c
        WHERE c.user_id = p_user AND c.doc_key = p_key
          AND c.document_version = (SELECT max(version) FROM public.legal_documents WHERE doc_key = p_key AND effective_at <= NOW())
        ORDER BY c.created_at DESC, c.id DESC
        LIMIT 1), false);
$$;

CREATE OR REPLACE FUNCTION public.record_consent(p_doc_key TEXT, p_accept BOOLEAN, p_locale TEXT DEFAULT 'tr', p_client_info TEXT DEFAULT '')
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_doc public.legal_documents;
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
    SELECT * INTO v_doc FROM public.juzzio_current_legal_doc(p_doc_key, p_locale);
    IF v_doc.id IS NULL THEN RAISE EXCEPTION 'document_not_found'; END IF;
    IF NOT public.juzzio_rate_check(v_uid, 'consent', 60, 3600) THEN RAISE EXCEPTION 'rate_limited'; END IF;
    INSERT INTO public.user_consents (user_id, document_id, doc_key, document_version, consent_type, action, locale, policy_hash, client_info)
    VALUES (v_uid, v_doc.id, v_doc.doc_key, v_doc.version, v_doc.consent_type,
            CASE WHEN p_accept THEN 'accept' ELSE 'withdraw' END, v_doc.locale, v_doc.policy_hash,
            LEFT(regexp_replace(COALESCE(p_client_info, ''), '[^A-Za-z0-9 ._+-]', '', 'g'), 120));
    RETURN jsonb_build_object('doc_key', v_doc.doc_key, 'version', v_doc.version, 'accepted', p_accept, 'policy_hash', v_doc.policy_hash);
END;
$$;
REVOKE ALL ON FUNCTION public.record_consent(TEXT, BOOLEAN, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_consent(TEXT, BOOLEAN, TEXT, TEXT) TO authenticated;

-- Kullanıcıya gösterilecek Business belgeleri + onay durumu (önceden İŞARETLİ kutu yok: durum gerçek kayıttan)
CREATE OR REPLACE FUNCTION public.get_business_legal_documents(p_locale TEXT DEFAULT 'tr')
RETURNS JSONB
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'doc_key', d.doc_key, 'version', d.version, 'locale', d.locale, 'title', d.title, 'body', d.body,
        'consent_type', d.consent_type, 'required', d.required_for_business, 'review_status', d.review_status,
        'effective_at', d.effective_at, 'policy_hash', d.policy_hash,
        'accepted', public.juzzio_has_current_consent(auth.uid(), d.doc_key)) ORDER BY d.required_for_business DESC, d.doc_key), '[]'::jsonb)
    FROM (SELECT DISTINCT ON (doc_key) * FROM public.legal_documents
          WHERE effective_at <= NOW() AND locale IN (COALESCE(p_locale, 'tr'), 'tr') AND doc_key LIKE 'business_%'
          ORDER BY doc_key, (locale = COALESCE(p_locale, 'tr')) DESC, version DESC) d;
$$;
REVOKE ALL ON FUNCTION public.get_business_legal_documents(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_business_legal_documents(TEXT) TO authenticated;

-- Taslak belgeler (14 madde, Business eki §3). İçerik KISA TASLAKTIR ve öyle etiketlidir.
INSERT INTO public.legal_documents (doc_key, version, locale, title, body, consent_type, required_for_business)
SELECT k, 1, 'tr', t, '⚠ DRAFT - LEGAL REVIEW REQUIRED — Bu metin taslaktır; hukuk incelemesi tamamlanmadan hukuki geçerlilik veya KVKK uyumluluğu garantisi vermez.' || E'\n\n' || b, c, r
FROM (VALUES
  ('business_terms_of_use', 'Juzzio Business Kullanım Koşulları', 'Juzzio Business özelliklerinin kullanım kuralları, hesabın amacı, yasaklı kullanımlar ve hesap kısıtlama koşulları burada yer alacaktır.', 'contract', true),
  ('business_service_terms', 'Juzzio Business Hizmet Şartları', 'Hizmetin kapsamı, ücretsiz Business hesap türü ile ayrı yönetilen ücretli planların ayrımı, hizmet seviyesi ve sorumluluk sınırları.', 'contract', true),
  ('business_kvkk_notice', 'KVKK Aydınlatma Metni', 'Veri sorumlusu, işlenen kişisel veri kategorileri, işleme amaçları, hukuki sebepler, aktarım alıcıları ve ilgili kişi hakları (KVKK m.10–11).', 'information', true),
  ('business_data_processing_info', 'Kişisel Verilerin İşlenmesine İlişkin Bilgilendirme', 'Müşteri iletişim kayıtları, ekip erişimi ve saklama süreleri hakkında bilgilendirme. Uçtan uca şifreli kişisel sohbetler Business paneline aktarılmaz.', 'information', true),
  ('business_explicit_consent_analytics', 'Açık Rıza — Gelişmiş Analitik', 'İsteğe bağlıdır; vermemeniz Business hesabını kullanmanıza engel değildir. Dilediğiniz zaman geri alabilirsiniz.', 'explicit_consent', false),
  ('business_commercial_messages', 'Ticari Elektronik İleti Tercihleri', 'Juzzio''nun size kampanya/tanıtım iletisi göndermesi için izin. İsteğe bağlıdır; hizmet kullanımının şartı değildir.', 'marketing', false),
  ('business_ai_voice_notice', 'Yapay Zekâ ve Yapay Ses Üretimi Bilgilendirmesi', 'AI özelliklerinin hangi veriyi işlediği, üçüncü taraf hizmetleri ve maliyet/kota sınırları.', 'information', false),
  ('business_voice_identity_consent', 'Ses Kimliği Oluşturma ve Kullanma İzni', 'Biyometrik nitelikte veri; ayrı açık rıza gerektirir. Bu sürümde ses kimliği özelliği etkin değildir.', 'explicit_consent', false),
  ('business_third_party_transfer', 'Üçüncü Taraf Entegrasyon ve Veri Aktarımı', 'Entegrasyonlar ayrı ayrı yetkilendirilir; yurt dışı aktarım mekanizmaları değerlendirilmeden aktarım yapılmaz.', 'information', false),
  ('business_content_rights', 'İçerik Hakları ve Kullanıcı Sorumlulukları', 'Paylaşılan içeriklerin hakları, lisans ve ihlal bildirimi süreci.', 'contract', true),
  ('business_customer_comm_duties', 'İşletme ve Müşteri İletişimi Sorumlulukları', 'Müşteri verisinin yalnız hizmet amacıyla kullanılması, ekip erişim yetkileri ve otomatik yanıtların işaretlenmesi.', 'contract', true),
  ('business_moderator_duties', 'Topluluk Yöneticisi ve Moderatör Sorumlulukları', 'Moderasyon yetkilerinin kötüye kullanılmaması ve denetim kayıtları.', 'information', false),
  ('business_abuse_policy', 'Güvenlik, Kötüye Kullanım ve Hesap Kısıtlama Politikası', 'Spam, taklit, dolandırıcılık ve yetkisiz erişim durumlarında uygulanacak kısıtlamalar.', 'contract', true),
  ('business_closure_retention', 'İşletme Hesabının Kapatılması ve Verilerin Saklanması/Silinmesi', 'Personal görünüme geçmek, geçici devre dışı bırakmak ve hesabı kapatmak farklı işlemlerdir; kapatmada verilerin saklama ve silme süreleri.', 'information', true)
) AS v(k, t, b, c, r)
ON CONFLICT (doc_key, version, locale) DO NOTHING;

-- Personel: yeni sürüm yayınla (önemli değişiklik → kullanıcıdan yeniden onay istenir, çünkü
-- juzzio_has_current_consent yalnız EN YENİ sürümü sayar). 'LEGAL REVIEWED' ancak inceleme notuyla.
CREATE OR REPLACE FUNCTION public.admin_publish_legal_document(p_token TEXT, p_doc_key TEXT, p_locale TEXT, p_title TEXT, p_body TEXT,
                                                               p_consent_type TEXT, p_required BOOLEAN, p_reviewed BOOLEAN, p_review_note TEXT)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_next INTEGER;
BEGIN
    PERFORM public._staff_require(p_token, 'legal.publish');
    IF p_reviewed AND LENGTH(BTRIM(COALESCE(p_review_note, ''))) < 10 THEN RAISE EXCEPTION 'review_note_required'; END IF;
    SELECT COALESCE(max(version), 0) + 1 INTO v_next FROM public.legal_documents WHERE doc_key = p_doc_key;
    INSERT INTO public.legal_documents (doc_key, version, locale, title, body, consent_type, required_for_business, review_status, review_note)
    VALUES (p_doc_key, v_next, COALESCE(p_locale, 'tr'), p_title, p_body, p_consent_type, COALESCE(p_required, false),
            CASE WHEN p_reviewed THEN 'LEGAL REVIEWED' ELSE 'DRAFT - LEGAL REVIEW REQUIRED' END, COALESCE(p_review_note, ''));
    INSERT INTO public.admin_audit_log (admin_id, action, target, details)
    VALUES (auth.uid(), 'legal_publish', p_doc_key, jsonb_build_object('version', v_next, 'reviewed', p_reviewed));
    RETURN v_next;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_publish_legal_document(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, BOOLEAN, BOOLEAN, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_publish_legal_document(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, BOOLEAN, BOOLEAN, TEXT) TO authenticated;

-- ---------------------------------------------------------------------------
-- Ekip (Business eki §10): Owner, Admin, Manager, Support Agent, Content Manager, Moderator, Analyst.
-- Uygulama personeli rolleriyle (staff_roles) KARIŞMAZ: bu roller yalnız ilgili işletme içindir.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.business_members (
    business_id UUID NOT NULL REFERENCES public.business_accounts(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    role TEXT NOT NULL CHECK (role IN ('owner', 'admin', 'manager', 'support_agent', 'content_manager', 'moderator', 'analyst')),
    status TEXT NOT NULL DEFAULT 'invited' CHECK (status IN ('invited', 'active', 'removed', 'declined')),
    invited_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (business_id, user_id)
);
ALTER TABLE public.business_members ENABLE ROW LEVEL SECURITY;
REVOKE INSERT, UPDATE, DELETE ON public.business_members FROM anon, authenticated;
GRANT SELECT ON public.business_members TO authenticated;

CREATE OR REPLACE FUNCTION public.juzzio_business_role(p_business UUID, p_user UUID DEFAULT auth.uid())
RETURNS TEXT
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT CASE
        WHEN p_user IS NULL OR p_business IS NULL THEN NULL
        WHEN NOT EXISTS (SELECT 1 FROM public.business_accounts b WHERE b.id = p_business AND b.status IN ('business_active', 'business_paused')) THEN
            CASE WHEN p_business = p_user THEN 'owner_inactive' END
        WHEN p_business = p_user THEN 'owner'
        ELSE (SELECT m.role FROM public.business_members m WHERE m.business_id = p_business AND m.user_id = p_user AND m.status = 'active')
    END;
$$;

-- İşletme içi yetki matrisi (backend'de uygulanır; arayüzde gizlemek yeterli değildir)
CREATE OR REPLACE FUNCTION public.juzzio_business_role_perms(p_role TEXT)
RETURNS TEXT[]
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE p_role
        WHEN 'owner' THEN ARRAY['*']
        WHEN 'admin' THEN ARRAY['inbox.read', 'inbox.assign', 'inbox.reply', 'customers.read', 'customers.write',
                                'appointments.read', 'appointments.write', 'tasks.read', 'tasks.write', 'team.read',
                                'team.manage', 'analytics.read', 'automation.manage', 'profile.manage', 'services.manage']
        WHEN 'manager' THEN ARRAY['inbox.read', 'inbox.assign', 'inbox.reply', 'customers.read', 'customers.write',
                                  'appointments.read', 'appointments.write', 'tasks.read', 'tasks.write', 'team.read',
                                  'analytics.read', 'services.manage']
        WHEN 'support_agent' THEN ARRAY['inbox.read', 'inbox.reply', 'customers.read', 'customers.write',
                                        'appointments.read', 'appointments.write', 'tasks.read', 'tasks.write']
        WHEN 'content_manager' THEN ARRAY['analytics.read', 'tasks.read', 'tasks.write']
        WHEN 'moderator' THEN ARRAY['inbox.read', 'customers.read', 'tasks.read']
        WHEN 'analyst' THEN ARRAY['analytics.read', 'customers.read']
        ELSE ARRAY[]::TEXT[]
    END;
$$;

CREATE OR REPLACE FUNCTION public.juzzio_business_can(p_business UUID, p_perm TEXT, p_user UUID DEFAULT auth.uid())
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT COALESCE((
        SELECT '*' = ANY (perms) OR p_perm = ANY (perms)
        FROM (SELECT public.juzzio_business_role_perms(public.juzzio_business_role(p_business, p_user)) AS perms) x), false);
$$;
GRANT EXECUTE ON FUNCTION public.juzzio_business_can(UUID, TEXT, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.juzzio_business_role(UUID, UUID) TO authenticated;

DROP POLICY IF EXISTS business_members_read ON public.business_members;
CREATE POLICY business_members_read ON public.business_members FOR SELECT TO authenticated
    USING (user_id = auth.uid() OR public.juzzio_business_can(business_id, 'team.read'));

-- ---------------------------------------------------------------------------
-- Başvuru ve kurulum (Business eki §2, §4): gerçek adımlar, kaldığı yerden devam, idempotent.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.business_setup_steps (
    business_id UUID NOT NULL REFERENCES public.business_accounts(id) ON DELETE CASCADE,
    step TEXT NOT NULL CHECK (step IN ('profile', 'workspace', 'security', 'modules', 'final')),
    done_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    detail JSONB NOT NULL DEFAULT '{}'::jsonb,
    PRIMARY KEY (business_id, step)
);
ALTER TABLE public.business_setup_steps ENABLE ROW LEVEL SECURITY;
REVOKE INSERT, UPDATE, DELETE ON public.business_setup_steps FROM anon, authenticated;
GRANT SELECT ON public.business_setup_steps TO authenticated;
DROP POLICY IF EXISTS business_setup_steps_owner ON public.business_setup_steps;
CREATE POLICY business_setup_steps_owner ON public.business_setup_steps FOR SELECT TO authenticated USING (business_id = auth.uid());

CREATE TABLE IF NOT EXISTS public.business_module_prefs (
    business_id UUID PRIMARY KEY REFERENCES public.business_accounts(id) ON DELETE CASCADE,
    enabled_modules TEXT[] NOT NULL DEFAULT ARRAY['overview', 'inbox', 'customers', 'appointments', 'team', 'tasks', 'analytics', 'automation']::TEXT[],
    dashboard_widgets TEXT[] NOT NULL DEFAULT ARRAY['today_messages', 'awaiting_reply', 'appointments', 'tasks', 'followups']::TEXT[],
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE public.business_module_prefs ENABLE ROW LEVEL SECURITY;
REVOKE INSERT, UPDATE, DELETE ON public.business_module_prefs FROM anon, authenticated;
GRANT SELECT ON public.business_module_prefs TO authenticated;
DROP POLICY IF EXISTS business_module_prefs_read ON public.business_module_prefs;
CREATE POLICY business_module_prefs_read ON public.business_module_prefs FOR SELECT TO authenticated
    USING (public.juzzio_business_role(business_id) IS NOT NULL);

CREATE OR REPLACE FUNCTION public.business_get_state()
RETURNS JSONB
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT jsonb_build_object(
        'status', COALESCE(b.status, 'personal'),
        'active_view', COALESCE(b.active_view, 'personal'),
        'profile_type', b.profile_type,
        'display_name', b.display_name,
        'reason', b.status_reason,
        'steps', COALESCE((SELECT jsonb_agg(s.step ORDER BY s.done_at) FROM public.business_setup_steps s WHERE s.business_id = auth.uid()), '[]'::jsonb),
        'missing_consents', COALESCE((
            SELECT jsonb_agg(d.doc_key ORDER BY d.doc_key)
            FROM (SELECT DISTINCT doc_key FROM public.legal_documents WHERE required_for_business AND doc_key LIKE 'business_%') d
            WHERE NOT public.juzzio_has_current_consent(auth.uid(), d.doc_key)), '[]'::jsonb),
        'memberships', COALESCE((
            SELECT jsonb_agg(jsonb_build_object('business_id', m.business_id, 'role', m.role, 'status', m.status,
                                                'name', (SELECT display_name FROM public.business_accounts WHERE id = m.business_id)))
            FROM public.business_members m WHERE m.user_id = auth.uid() AND m.status IN ('invited', 'active')), '[]'::jsonb))
    FROM (SELECT 1) one
    LEFT JOIN public.business_accounts b ON b.id = auth.uid()
    WHERE auth.uid() IS NOT NULL;
$$;
REVOKE ALL ON FUNCTION public.business_get_state() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.business_get_state() TO authenticated;

CREATE OR REPLACE FUNCTION public.business_start_application(p_profile_type TEXT, p_display_name TEXT, p_request_id TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_row public.business_accounts;
    v_name TEXT := BTRIM(COALESCE(p_display_name, ''));
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
    IF p_profile_type NOT IN ('individual_professional', 'creator', 'business', 'organization', 'community_operator', 'service_provider') THEN
        RAISE EXCEPTION 'invalid_profile_type';
    END IF;
    IF LENGTH(v_name) NOT BETWEEN 2 AND 80 THEN RAISE EXCEPTION 'invalid_display_name'; END IF;
    IF COALESCE(p_request_id, '') !~ '^[A-Za-z0-9_-]{8,80}$' THEN RAISE EXCEPTION 'invalid_request_id'; END IF;
    IF public.juzzio_is_banned(v_uid) THEN RAISE EXCEPTION 'account_banned'; END IF;
    INSERT INTO public.business_accounts (id) VALUES (v_uid) ON CONFLICT (id) DO NOTHING;
    SELECT * INTO v_row FROM public.business_accounts WHERE id = v_uid FOR UPDATE;
    -- Aynı istek tekrarı veya süren başvuru: aynı kayıt döner (çift başvuru yok)
    IF v_row.status IN ('business_application_started', 'business_terms_pending', 'business_preparing', 'business_active', 'business_paused') THEN
        RETURN public.business_get_state();
    END IF;
    IF v_row.status = 'business_suspended' THEN RAISE EXCEPTION 'business_suspended'; END IF;
    UPDATE public.business_accounts SET profile_type = p_profile_type, display_name = v_name, application_request_id = p_request_id
     WHERE id = v_uid;
    PERFORM public.juzzio_business_set_status(v_uid, 'business_application_started', 'owner', 'application');
    PERFORM public.juzzio_business_set_status(v_uid, 'business_terms_pending', 'owner', 'awaiting_consents');
    RETURN public.business_get_state();
END;
$$;
REVOKE ALL ON FUNCTION public.business_start_application(TEXT, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.business_start_application(TEXT, TEXT, TEXT) TO authenticated;

-- Onaylar tamamsa hazırlığa geç. Zorunlu sözleşme/bilgilendirme onayı eksikse ilerlemez.
CREATE OR REPLACE FUNCTION public.business_submit_consents()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_missing JSONB;
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
    v_missing := public.business_get_state() -> 'missing_consents';
    IF jsonb_array_length(COALESCE(v_missing, '[]'::jsonb)) > 0 THEN
        RAISE EXCEPTION 'consents_missing:%', v_missing::text;
    END IF;
    PERFORM public.juzzio_business_set_status(v_uid, 'business_preparing', 'owner', 'consents_complete');
    RETURN public.business_get_state();
END;
$$;
REVOKE ALL ON FUNCTION public.business_submit_consents() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.business_submit_consents() TO authenticated;

-- Hazırlık adımı: GERÇEK işi yapar ve kaydeder; tekrar çağrı idempotent. Sıra zorunlu.
CREATE OR REPLACE FUNCTION public.business_run_setup_step(p_step TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_status TEXT;
    v_order TEXT[] := ARRAY['profile', 'workspace', 'security', 'modules', 'final'];
    v_idx INTEGER := array_position(ARRAY['profile', 'workspace', 'security', 'modules', 'final'], p_step);
    v_detail JSONB := '{}'::jsonb;
    v_prof RECORD;
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
    IF v_idx IS NULL THEN RAISE EXCEPTION 'invalid_step'; END IF;
    SELECT status INTO v_status FROM public.business_accounts WHERE id = v_uid FOR UPDATE;
    IF EXISTS (SELECT 1 FROM public.business_setup_steps WHERE business_id = v_uid AND step = p_step) THEN
        RETURN public.business_get_state(); -- zaten yapıldı
    END IF;
    IF v_status IS DISTINCT FROM 'business_preparing' THEN RAISE EXCEPTION 'not_preparing'; END IF;
    IF v_idx > 1 AND NOT EXISTS (SELECT 1 FROM public.business_setup_steps WHERE business_id = v_uid AND step = v_order[v_idx - 1]) THEN
        RAISE EXCEPTION 'previous_step_missing:%', v_order[v_idx - 1];
    END IF;
    CASE p_step
        WHEN 'profile' THEN
            -- Kişisel profil KORUNUR; eksik işletme alanları kişisel profilden önerilir (üzerine yazmaz)
            SELECT avatar_url, bio INTO v_prof FROM public.profiles WHERE id = v_uid;
            UPDATE public.business_accounts
               SET logo_url = COALESCE(logo_url, v_prof.avatar_url),
                   description = CASE WHEN description = '' THEN LEFT(COALESCE(v_prof.bio, ''), 1000) ELSE description END
             WHERE id = v_uid;
            v_detail := jsonb_build_object('logo_from_avatar', v_prof.avatar_url IS NOT NULL);
        WHEN 'workspace' THEN
            INSERT INTO public.business_members (business_id, user_id, role, status, invited_by)
            VALUES (v_uid, v_uid, 'owner', 'active', v_uid)
            ON CONFLICT (business_id, user_id) DO UPDATE SET role = 'owner', status = 'active', updated_at = NOW();
        WHEN 'security' THEN
            -- Doğrulama: sahip üyeliği ve RLS'in açık olduğu (yalnız kontrol; E2EE'ye dokunulmaz)
            IF NOT EXISTS (SELECT 1 FROM public.business_members WHERE business_id = v_uid AND user_id = v_uid AND role = 'owner' AND status = 'active') THEN
                RAISE EXCEPTION 'owner_membership_missing';
            END IF;
            IF EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
                       WHERE n.nspname = 'public' AND c.relname IN ('business_accounts', 'business_members', 'business_customers', 'business_conversations')
                         AND NOT c.relrowsecurity) THEN
                RAISE EXCEPTION 'rls_disabled';
            END IF;
            v_detail := jsonb_build_object('rls', true, 'e2ee_unchanged', true);
        WHEN 'modules' THEN
            INSERT INTO public.business_module_prefs (business_id) VALUES (v_uid) ON CONFLICT (business_id) DO NOTHING;
        WHEN 'final' THEN
            PERFORM public.juzzio_business_set_status(v_uid, 'business_active', 'system', 'setup_complete');
    END CASE;
    INSERT INTO public.business_setup_steps (business_id, step, detail) VALUES (v_uid, p_step, v_detail)
    ON CONFLICT (business_id, step) DO NOTHING;
    RETURN public.business_get_state();
END;
$$;
REVOKE ALL ON FUNCTION public.business_run_setup_step(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.business_run_setup_step(TEXT) TO authenticated;

-- Görünüm geçişi (Personal ↔ Business) — veri değişmez, yalnız arayüz tercihi
CREATE OR REPLACE FUNCTION public.business_set_view(p_view TEXT)
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF p_view NOT IN ('personal', 'business') THEN RAISE EXCEPTION 'invalid_view'; END IF;
    IF p_view = 'business' AND NOT EXISTS (SELECT 1 FROM public.business_accounts WHERE id = auth.uid() AND status = 'business_active') THEN
        RAISE EXCEPTION 'business_not_active';
    END IF;
    UPDATE public.business_accounts SET active_view = p_view, updated_at = NOW() WHERE id = auth.uid();
    RETURN p_view;
END $$;
REVOKE ALL ON FUNCTION public.business_set_view(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.business_set_view(TEXT) TO authenticated;

-- Sahip eylemleri: geçici devre dışı / devam / kapat (§15: kapatma ≠ görünüm geçişi; veri SİLİNMEZ)
CREATE OR REPLACE FUNCTION public.business_owner_action(p_action TEXT, p_reason TEXT DEFAULT '')
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_uid UUID := auth.uid();
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
    CASE p_action
        WHEN 'pause' THEN PERFORM public.juzzio_business_set_status(v_uid, 'business_paused', 'owner', p_reason);
        WHEN 'resume' THEN PERFORM public.juzzio_business_set_status(v_uid, 'business_active', 'owner', p_reason);
        WHEN 'close' THEN
            PERFORM public.juzzio_business_set_status(v_uid, 'business_reverting', 'owner', p_reason);
            -- ekip erişimi kapanır (kayıtlar korunur), sahip personal'a döner
            UPDATE public.business_members SET status = 'removed', updated_at = NOW()
             WHERE business_id = v_uid AND user_id <> v_uid AND status IN ('active', 'invited');
            PERFORM public.juzzio_business_set_status(v_uid, 'business_cancelled', 'system', 'closed_by_owner');
        WHEN 'cancel_application' THEN PERFORM public.juzzio_business_set_status(v_uid, 'business_cancelled', 'owner', p_reason);
        ELSE RAISE EXCEPTION 'invalid_action';
    END CASE;
    RETURN public.business_get_state();
END $$;
REVOKE ALL ON FUNCTION public.business_owner_action(TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.business_owner_action(TEXT, TEXT) TO authenticated;

-- İşletme profili güncelle (doğrulama rozeti İSTEMCİDEN değişmez)
CREATE OR REPLACE FUNCTION public.business_update_profile(p_patch JSONB)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_biz UUID := COALESCE(NULLIF(p_patch->>'business_id', '')::uuid, auth.uid());
BEGIN
    IF NOT public.juzzio_business_can(v_biz, 'profile.manage') THEN RAISE EXCEPTION 'not_allowed'; END IF;
    UPDATE public.business_accounts SET
        display_name = COALESCE(LEFT(NULLIF(BTRIM(p_patch->>'display_name'), ''), 80), display_name),
        professional_title = COALESCE(LEFT(p_patch->>'professional_title', 80), professional_title),
        description = COALESCE(LEFT(p_patch->>'description', 1000), description),
        website = COALESCE(LEFT(p_patch->>'website', 200), website),
        contact_email = COALESCE(LEFT(p_patch->>'contact_email', 200), contact_email),
        contact_phone = COALESCE(LEFT(p_patch->>'contact_phone', 40), contact_phone),
        location = COALESCE(LEFT(p_patch->>'location', 120), location),
        working_hours = COALESCE(CASE WHEN jsonb_typeof(p_patch->'working_hours') = 'object' THEN p_patch->'working_hours' END, working_hours),
        categories = COALESCE((SELECT array_agg(LEFT(x, 40)) FROM jsonb_array_elements_text(CASE WHEN jsonb_typeof(p_patch->'categories') = 'array' THEN p_patch->'categories' END) x), categories),
        logo_url = COALESCE(p_patch->>'logo_url', logo_url),
        updated_at = NOW()
    WHERE id = v_biz;
    RETURN (SELECT to_jsonb(b) - 'application_request_id' FROM public.business_accounts b WHERE id = v_biz);
END $$;
REVOKE ALL ON FUNCTION public.business_update_profile(JSONB) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.business_update_profile(JSONB) TO authenticated;

-- Ekip: davet / kabul / rol / erişim kaldır
CREATE OR REPLACE FUNCTION public.business_invite_member(p_business UUID, p_username TEXT, p_role TEXT)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_target UUID;
BEGIN
    IF NOT public.juzzio_business_can(p_business, 'team.manage') THEN RAISE EXCEPTION 'not_allowed'; END IF;
    IF p_role NOT IN ('admin', 'manager', 'support_agent', 'content_manager', 'moderator', 'analyst') THEN RAISE EXCEPTION 'invalid_role'; END IF;
    -- yalnız sahip 'admin' atayabilir
    IF p_role = 'admin' AND public.juzzio_business_role(p_business) <> 'owner' THEN RAISE EXCEPTION 'not_allowed'; END IF;
    SELECT id INTO v_target FROM public.profiles WHERE lower(username) = lower(BTRIM(p_username)) LIMIT 1;
    IF v_target IS NULL THEN RAISE EXCEPTION 'user_not_found'; END IF;
    IF v_target = p_business THEN RAISE EXCEPTION 'already_owner'; END IF;
    IF public.is_blocked_between(v_target, auth.uid()) THEN RAISE EXCEPTION 'not_allowed'; END IF;
    IF NOT public.juzzio_rate_check(auth.uid(), 'business_invite', 30, 3600) THEN RAISE EXCEPTION 'rate_limited'; END IF;
    INSERT INTO public.business_members (business_id, user_id, role, status, invited_by)
    VALUES (p_business, v_target, p_role, 'invited', auth.uid())
    ON CONFLICT (business_id, user_id) DO UPDATE
        SET role = EXCLUDED.role, status = CASE WHEN business_members.status = 'active' THEN 'active' ELSE 'invited' END,
            invited_by = EXCLUDED.invited_by, updated_at = NOW();
    INSERT INTO public.notifications (recipient_id, actor_id, actor_username, actor_display_name, event_type, target_id, preview_text, dedupe_key)
    SELECT v_target, auth.uid(), COALESCE(p.username, ''), COALESCE((SELECT display_name FROM public.business_accounts WHERE id = p_business), 'Juzzio'),
           'system', p_business::text, 'business_invite|' || p_role, 'biz_invite_' || p_business::text || '_' || v_target::text || '_' || p_role
    FROM public.profiles p WHERE p.id = auth.uid()
    ON CONFLICT (recipient_id, dedupe_key) DO NOTHING;
    RETURN jsonb_build_object('user_id', v_target, 'role', p_role, 'status', 'invited');
END $$;
REVOKE ALL ON FUNCTION public.business_invite_member(UUID, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.business_invite_member(UUID, TEXT, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.business_respond_invite(p_business UUID, p_accept BOOLEAN)
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_new TEXT := CASE WHEN p_accept THEN 'active' ELSE 'declined' END;
BEGIN
    UPDATE public.business_members SET status = v_new, updated_at = NOW()
     WHERE business_id = p_business AND user_id = auth.uid() AND status = 'invited';
    IF NOT FOUND THEN RAISE EXCEPTION 'invite_not_found'; END IF;
    RETURN v_new;
END $$;
REVOKE ALL ON FUNCTION public.business_respond_invite(UUID, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.business_respond_invite(UUID, BOOLEAN) TO authenticated;

CREATE OR REPLACE FUNCTION public.business_set_member(p_business UUID, p_user UUID, p_role TEXT, p_remove BOOLEAN DEFAULT false)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_my TEXT := public.juzzio_business_role(p_business);
    v_their TEXT;
BEGIN
    IF NOT public.juzzio_business_can(p_business, 'team.manage') THEN RAISE EXCEPTION 'not_allowed'; END IF;
    SELECT role INTO v_their FROM public.business_members WHERE business_id = p_business AND user_id = p_user;
    IF v_their IS NULL THEN RAISE EXCEPTION 'not_a_member'; END IF;
    -- sahip değiştirilemez; admin yalnız sahip tarafından yönetilir
    IF v_their = 'owner' OR ((v_their = 'admin' OR p_role = 'admin') AND v_my <> 'owner') THEN RAISE EXCEPTION 'not_allowed'; END IF;
    IF p_remove THEN
        UPDATE public.business_members SET status = 'removed', updated_at = NOW() WHERE business_id = p_business AND user_id = p_user;
        -- açık atamalar sahibine döner (veri silinmez)
        UPDATE public.business_conversations SET assignee_id = NULL WHERE business_id = p_business AND assignee_id = p_user;
    ELSE
        IF p_role NOT IN ('admin', 'manager', 'support_agent', 'content_manager', 'moderator', 'analyst') THEN RAISE EXCEPTION 'invalid_role'; END IF;
        UPDATE public.business_members SET role = p_role, updated_at = NOW() WHERE business_id = p_business AND user_id = p_user;
    END IF;
    INSERT INTO public.business_audit_log (business_id, actor_id, action, target, details)
    VALUES (p_business, auth.uid(), CASE WHEN p_remove THEN 'member_remove' ELSE 'member_role' END, p_user::text,
            jsonb_build_object('from', v_their, 'to', CASE WHEN p_remove THEN 'removed' ELSE p_role END));
    RETURN jsonb_build_object('user_id', p_user, 'role', CASE WHEN p_remove THEN v_their ELSE p_role END, 'removed', p_remove);
END $$;
REVOKE ALL ON FUNCTION public.business_set_member(UUID, UUID, TEXT, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.business_set_member(UUID, UUID, TEXT, BOOLEAN) TO authenticated;

-- İşletme denetim kaydı (yalnız ekleme; okuma: sahip/admin)
CREATE TABLE IF NOT EXISTS public.business_audit_log (
    id BIGSERIAL PRIMARY KEY,
    business_id UUID NOT NULL REFERENCES public.business_accounts(id) ON DELETE CASCADE,
    actor_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    action TEXT NOT NULL,
    target TEXT NOT NULL DEFAULT '',
    details JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE public.business_audit_log ENABLE ROW LEVEL SECURITY;
REVOKE INSERT, UPDATE, DELETE ON public.business_audit_log FROM anon, authenticated;
GRANT SELECT ON public.business_audit_log TO authenticated;
DROP POLICY IF EXISTS business_audit_log_read ON public.business_audit_log;
CREATE POLICY business_audit_log_read ON public.business_audit_log FOR SELECT TO authenticated
    USING (public.juzzio_business_can(business_id, 'team.manage'));

-- Personel: başvuru/hesap durumu (red, askıya alma, geri açma) — denetimli
CREATE OR REPLACE FUNCTION public.admin_business_set_status(p_token TEXT, p_business UUID, p_status TEXT, p_reason TEXT)
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    PERFORM public._staff_require(p_token, 'business.manage');
    IF LENGTH(BTRIM(COALESCE(p_reason, ''))) < 3 THEN RAISE EXCEPTION 'reason_required'; END IF;
    PERFORM public.juzzio_business_set_status(p_business, p_status, 'staff', p_reason);
    INSERT INTO public.admin_audit_log (admin_id, action, target, details)
    VALUES (auth.uid(), 'business_status', p_business::text, jsonb_build_object('status', p_status, 'reason', p_reason));
    RETURN p_status;
END $$;
REVOKE ALL ON FUNCTION public.admin_business_set_status(TEXT, UUID, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_business_set_status(TEXT, UUID, TEXT, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_list_business_accounts(p_token TEXT, p_status TEXT DEFAULT NULL, p_limit INTEGER DEFAULT 100)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    PERFORM public._staff_require(p_token, 'business.read');
    RETURN COALESCE((SELECT jsonb_agg(jsonb_build_object('id', b.id, 'status', b.status, 'profile_type', b.profile_type,
                                                         'display_name', b.display_name, 'is_verified', b.is_verified,
                                                         'created_at', b.created_at, 'updated_at', b.updated_at) ORDER BY b.updated_at DESC)
                     FROM (SELECT * FROM public.business_accounts WHERE status <> 'personal' AND (p_status IS NULL OR status = p_status)
                           ORDER BY updated_at DESC LIMIT LEAST(GREATEST(COALESCE(p_limit, 100), 1), 500)) b), '[]'::jsonb);
END $$;
REVOKE ALL ON FUNCTION public.admin_list_business_accounts(TEXT, TEXT, INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_business_accounts(TEXT, TEXT, INTEGER) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_set_business_verified(p_token TEXT, p_business UUID, p_verified BOOLEAN, p_reason TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    PERFORM public._staff_require(p_token, 'business.manage');
    UPDATE public.business_accounts SET is_verified = COALESCE(p_verified, false), updated_at = NOW() WHERE id = p_business;
    INSERT INTO public.admin_audit_log (admin_id, action, target, details)
    VALUES (auth.uid(), 'business_verify', p_business::text, jsonb_build_object('verified', p_verified, 'reason', p_reason));
    RETURN COALESCE(p_verified, false);
END $$;
REVOKE ALL ON FUNCTION public.admin_set_business_verified(TEXT, UUID, BOOLEAN, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_business_verified(TEXT, UUID, BOOLEAN, TEXT) TO authenticated;

-- ---------------------------------------------------------------------------
-- 10.21 Business iş verileri: müşteriler (CRM), notlar, takipler, gelen kutusu kayıtları,
-- randevular, hizmetler, görevler, otomatik yanıtlar, analiz (son talimat §5).
-- Kiracı izolasyonu: her satır business_id taşır; RLS = juzzio_business_can(business_id, izin).
-- E2EE: gelen kutusu yalnız KONUŞMA BİLGİSİ tutar (oda bağlantısı, atama, durum, öncelik,
-- etiket). Mesaj içeriği kopyalanmaz; kişisel sohbet otomatik eklenmez (sahip açıkça işaretler).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.business_customers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL REFERENCES public.business_accounts(id) ON DELETE CASCADE,
    customer_user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    name TEXT NOT NULL CHECK (LENGTH(BTRIM(name)) BETWEEN 1 AND 120),
    email TEXT NOT NULL DEFAULT '' CHECK (LENGTH(email) <= 200),
    phone TEXT NOT NULL DEFAULT '' CHECK (LENGTH(phone) <= 40),
    tags TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    follow_status TEXT NOT NULL DEFAULT 'none' CHECK (follow_status IN ('none', 'pending', 'done')),
    last_contact_at TIMESTAMPTZ,
    created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (business_id, customer_user_id)
);
CREATE INDEX IF NOT EXISTS idx_business_customers_biz ON public.business_customers (business_id, updated_at DESC);

CREATE TABLE IF NOT EXISTS public.business_customer_notes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL REFERENCES public.business_accounts(id) ON DELETE CASCADE,
    customer_id UUID NOT NULL REFERENCES public.business_customers(id) ON DELETE CASCADE,
    author_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL DEFAULT auth.uid(),
    body TEXT NOT NULL CHECK (LENGTH(BTRIM(body)) BETWEEN 1 AND 4000),
    is_internal BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.business_followups (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL REFERENCES public.business_accounts(id) ON DELETE CASCADE,
    customer_id UUID NOT NULL REFERENCES public.business_customers(id) ON DELETE CASCADE,
    title TEXT NOT NULL CHECK (LENGTH(BTRIM(title)) BETWEEN 1 AND 200),
    description TEXT NOT NULL DEFAULT '' CHECK (LENGTH(description) <= 2000),
    due_at TIMESTAMPTZ NOT NULL,
    assignee_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    done_at TIMESTAMPTZ,
    reminded_at TIMESTAMPTZ,
    created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL DEFAULT auth.uid(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_business_followups_due ON public.business_followups (due_at) WHERE done_at IS NULL AND reminded_at IS NULL;

CREATE TABLE IF NOT EXISTS public.business_conversations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL REFERENCES public.business_accounts(id) ON DELETE CASCADE,
    room_id UUID NOT NULL REFERENCES public.rooms(id) ON DELETE CASCADE,
    customer_id UUID REFERENCES public.business_customers(id) ON DELETE SET NULL,
    assignee_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'pending', 'resolved')),
    priority TEXT NOT NULL DEFAULT 'normal' CHECK (priority IN ('low', 'normal', 'high', 'urgent')),
    labels TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    assign_reason TEXT NOT NULL DEFAULT '' CHECK (LENGTH(assign_reason) <= 300),
    last_activity_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (business_id, room_id)
);

CREATE TABLE IF NOT EXISTS public.business_services (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL REFERENCES public.business_accounts(id) ON DELETE CASCADE,
    name TEXT NOT NULL CHECK (LENGTH(BTRIM(name)) BETWEEN 1 AND 120),
    description TEXT NOT NULL DEFAULT '' CHECK (LENGTH(description) <= 1000),
    duration_min INTEGER NOT NULL DEFAULT 30 CHECK (duration_min BETWEEN 5 AND 1440),
    price_text TEXT NOT NULL DEFAULT '' CHECK (LENGTH(price_text) <= 40),
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.business_appointments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL REFERENCES public.business_accounts(id) ON DELETE CASCADE,
    customer_id UUID REFERENCES public.business_customers(id) ON DELETE SET NULL,
    service_id UUID REFERENCES public.business_services(id) ON DELETE SET NULL,
    starts_at TIMESTAMPTZ NOT NULL,
    ends_at TIMESTAMPTZ NOT NULL,
    assignee_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    description TEXT NOT NULL DEFAULT '' CHECK (LENGTH(description) <= 2000),
    status TEXT NOT NULL DEFAULT 'scheduled' CHECK (status IN ('scheduled', 'completed', 'cancelled', 'no_show')),
    remind_minutes_before INTEGER NOT NULL DEFAULT 60 CHECK (remind_minutes_before BETWEEN 0 AND 10080),
    reminded_at TIMESTAMPTZ,
    created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL DEFAULT auth.uid(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT business_appointments_order CHECK (ends_at > starts_at)
);
CREATE INDEX IF NOT EXISTS idx_business_appointments_time ON public.business_appointments (business_id, starts_at);

CREATE TABLE IF NOT EXISTS public.business_tasks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL REFERENCES public.business_accounts(id) ON DELETE CASCADE,
    title TEXT NOT NULL CHECK (LENGTH(BTRIM(title)) BETWEEN 1 AND 200),
    description TEXT NOT NULL DEFAULT '' CHECK (LENGTH(description) <= 2000),
    assignee_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    customer_id UUID REFERENCES public.business_customers(id) ON DELETE SET NULL,
    due_at TIMESTAMPTZ,
    done_at TIMESTAMPTZ,
    created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL DEFAULT auth.uid(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.business_auto_replies (
    business_id UUID NOT NULL REFERENCES public.business_accounts(id) ON DELETE CASCADE,
    kind TEXT NOT NULL CHECK (kind IN ('welcome', 'away')),
    enabled BOOLEAN NOT NULL DEFAULT false,
    body TEXT NOT NULL DEFAULT '' CHECK (LENGTH(body) <= 1000),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (business_id, kind)
);
CREATE TABLE IF NOT EXISTS public.business_auto_reply_log (
    id BIGSERIAL PRIMARY KEY,
    business_id UUID NOT NULL REFERENCES public.business_accounts(id) ON DELETE CASCADE,
    room_id UUID NOT NULL,
    customer_user_id UUID NOT NULL,
    kind TEXT NOT NULL,
    message_id UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_business_auto_reply_log ON public.business_auto_reply_log (business_id, customer_user_id, created_at DESC);

-- RLS: aynı desen, izin anahtarına göre
DO $$
DECLARE
    t RECORD;
BEGIN
    FOR t IN SELECT * FROM (VALUES
        ('business_customers', 'customers.read', 'customers.write'),
        ('business_customer_notes', 'customers.read', 'customers.write'),
        ('business_followups', 'customers.read', 'customers.write'),
        ('business_conversations', 'inbox.read', 'inbox.assign'),
        ('business_services', 'appointments.read', 'services.manage'),
        ('business_appointments', 'appointments.read', 'appointments.write'),
        ('business_tasks', 'tasks.read', 'tasks.write'),
        ('business_auto_replies', 'inbox.read', 'automation.manage'),
        ('business_auto_reply_log', 'inbox.read', 'automation.manage')
    ) AS v(tbl, rperm, wperm) LOOP
        EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t.tbl);
        EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON public.%I TO authenticated', t.tbl);
        EXECUTE format('REVOKE ALL ON public.%I FROM anon', t.tbl);
        EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t.tbl || '_read', t.tbl);
        EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t.tbl || '_write', t.tbl);
        EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t.tbl || '_update', t.tbl);
        EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t.tbl || '_delete', t.tbl);
        EXECUTE format('CREATE POLICY %I ON public.%I FOR SELECT TO authenticated USING (public.juzzio_business_can(business_id, %L))',
                       t.tbl || '_read', t.tbl, t.rperm);
        EXECUTE format('CREATE POLICY %I ON public.%I FOR INSERT TO authenticated WITH CHECK (public.juzzio_business_can(business_id, %L))',
                       t.tbl || '_write', t.tbl, t.wperm);
        EXECUTE format('CREATE POLICY %I ON public.%I FOR UPDATE TO authenticated USING (public.juzzio_business_can(business_id, %L)) WITH CHECK (public.juzzio_business_can(business_id, %L))',
                       t.tbl || '_update', t.tbl, t.wperm, t.wperm);
        EXECUTE format('CREATE POLICY %I ON public.%I FOR DELETE TO authenticated USING (public.juzzio_business_can(business_id, %L))',
                       t.tbl || '_delete', t.tbl, t.wperm);
    END LOOP;
END $$;
-- Otomatik yanıt kaydı yalnız sunucu yazar
REVOKE INSERT, UPDATE, DELETE ON public.business_auto_reply_log FROM authenticated;

-- Tutarlılık: bağlı kayıtlar aynı işletmeye ait olmalı; atanan kişi ekip üyesi olmalı; kişisel
-- sohbet ancak sahip/üye o odanın katılımcısıysa gelen kutusuna eklenebilir.
CREATE OR REPLACE FUNCTION public.juzzio_business_row_guard()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_cust UUID;
    v_assignee UUID;
BEGIN
    IF TG_OP = 'UPDATE' AND NEW.business_id IS DISTINCT FROM OLD.business_id THEN RAISE EXCEPTION 'not_allowed'; END IF;
    v_cust := CASE WHEN TG_TABLE_NAME IN ('business_customer_notes', 'business_followups', 'business_conversations', 'business_appointments', 'business_tasks')
                   THEN (to_jsonb(NEW) ->> 'customer_id')::uuid END;
    IF v_cust IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.business_customers c WHERE c.id = v_cust AND c.business_id = NEW.business_id) THEN
        RAISE EXCEPTION 'customer_not_in_business';
    END IF;
    v_assignee := CASE WHEN TG_TABLE_NAME IN ('business_followups', 'business_conversations', 'business_appointments', 'business_tasks')
                       THEN (to_jsonb(NEW) ->> 'assignee_id')::uuid END;
    IF v_assignee IS NOT NULL AND public.juzzio_business_role(NEW.business_id, v_assignee) IS NULL THEN
        RAISE EXCEPTION 'assignee_not_member';
    END IF;
    IF TG_TABLE_NAME = 'business_appointments' AND (to_jsonb(NEW) ->> 'service_id') IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM public.business_services s WHERE s.id = (to_jsonb(NEW) ->> 'service_id')::uuid AND s.business_id = NEW.business_id) THEN
        RAISE EXCEPTION 'service_not_in_business';
    END IF;
    IF TG_TABLE_NAME = 'business_conversations' AND TG_OP = 'INSERT'
       AND NOT public.is_room_member((to_jsonb(NEW) ->> 'room_id')::uuid, auth.uid()) THEN
        RAISE EXCEPTION 'not_a_room_member';
    END IF;
    IF TG_TABLE_NAME = 'business_customers' AND TG_OP = 'UPDATE' THEN
        NEW.updated_at := NOW();
    END IF;
    RETURN NEW;
END $$;
DO $$
DECLARE
    t TEXT;
BEGIN
    FOREACH t IN ARRAY ARRAY['business_customers', 'business_customer_notes', 'business_followups', 'business_conversations',
                             'business_services', 'business_appointments', 'business_tasks'] LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS trg_juzzio_business_guard ON public.%I', t);
        EXECUTE format('CREATE TRIGGER trg_juzzio_business_guard BEFORE INSERT OR UPDATE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.juzzio_business_row_guard()', t);
    END LOOP;
END $$;

-- Sorumlu atama (Gelen Kutusu > Sorumlu Ata): yetki + denetim kaydı + atanan kişiye bildirim
CREATE OR REPLACE FUNCTION public.business_assign_conversation(p_conversation UUID, p_assignee UUID, p_reason TEXT DEFAULT '')
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_biz UUID;
BEGIN
    SELECT business_id INTO v_biz FROM public.business_conversations WHERE id = p_conversation FOR UPDATE;
    IF v_biz IS NULL OR NOT public.juzzio_business_can(v_biz, 'inbox.assign') THEN RAISE EXCEPTION 'not_allowed'; END IF;
    IF p_assignee IS NOT NULL AND public.juzzio_business_role(v_biz, p_assignee) IS NULL THEN RAISE EXCEPTION 'assignee_not_member'; END IF;
    UPDATE public.business_conversations SET assignee_id = p_assignee, assign_reason = LEFT(COALESCE(p_reason, ''), 300), last_activity_at = NOW()
     WHERE id = p_conversation;
    INSERT INTO public.business_audit_log (business_id, actor_id, action, target, details)
    VALUES (v_biz, auth.uid(), 'assign', p_conversation::text, jsonb_build_object('assignee', p_assignee, 'reason', p_reason));
    IF p_assignee IS NOT NULL AND p_assignee <> auth.uid() THEN
        INSERT INTO public.notifications (recipient_id, actor_id, actor_username, actor_display_name, event_type, target_id, target_secondary_id, preview_text, dedupe_key)
        SELECT p_assignee, auth.uid(), COALESCE(p.username, ''), COALESCE(NULLIF(p.display_name, ''), p.username, 'Juzzio'),
               'system', v_biz::text, p_conversation::text, 'business_assign|', 'biz_assign_' || p_conversation::text || '_' || extract(epoch FROM NOW())::bigint
        FROM public.profiles p WHERE p.id = auth.uid()
        ON CONFLICT (recipient_id, dedupe_key) DO NOTHING;
    END IF;
    RETURN jsonb_build_object('id', p_conversation, 'assignee_id', p_assignee);
END $$;
REVOKE ALL ON FUNCTION public.business_assign_conversation(UUID, UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.business_assign_conversation(UUID, UUID, TEXT) TO authenticated;

-- Genel Bakış / Analiz: yalnız GERÇEK sayımlar (sahte veri yok; veri yoksa sıfır)
CREATE OR REPLACE FUNCTION public.business_overview(p_business UUID DEFAULT NULL, p_days INTEGER DEFAULT 30)
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_biz UUID := COALESCE(p_business, auth.uid());
    v_days INTEGER := LEAST(GREATEST(COALESCE(p_days, 30), 1), 365);
    v_rooms UUID[];
    v_out JSONB;
BEGIN
    IF NOT public.juzzio_business_can(v_biz, 'analytics.read') AND NOT public.juzzio_business_can(v_biz, 'inbox.read') THEN
        RAISE EXCEPTION 'not_allowed';
    END IF;
    SELECT COALESCE(array_agg(room_id), ARRAY[]::UUID[]) INTO v_rooms FROM public.business_conversations WHERE business_id = v_biz;
    WITH m AS (
        SELECT room_id, sender_id, created_at FROM public.messages
        WHERE room_id = ANY (v_rooms) AND NOT is_deleted AND message_type NOT IN ('system', 'call')
          AND created_at > NOW() - make_interval(days => v_days * 2)
    ),
    staff AS (
        SELECT user_id FROM public.business_members WHERE business_id = v_biz AND status = 'active'
        UNION SELECT v_biz
    ),
    inbound AS (SELECT * FROM m WHERE sender_id NOT IN (SELECT user_id FROM staff)),
    replies AS (
        -- müşteri mesajından sonraki ilk ekip yanıtına kadar geçen süre (dakika)
        SELECT EXTRACT(EPOCH FROM (
            SELECT min(r.created_at) FROM m r WHERE r.room_id = i.room_id AND r.created_at > i.created_at
              AND r.sender_id IN (SELECT user_id FROM staff)) - i.created_at) / 60.0 AS mins, i.created_at
        FROM inbound i
    )
    SELECT jsonb_build_object(
        'period_days', v_days,
        'messages_today', (SELECT count(*) FROM m WHERE created_at >= date_trunc('day', NOW())),
        'messages_period', (SELECT count(*) FROM m WHERE created_at > NOW() - make_interval(days => v_days)),
        'messages_prev_period', (SELECT count(*) FROM m WHERE created_at <= NOW() - make_interval(days => v_days)),
        'awaiting_reply', (SELECT count(*) FROM public.business_conversations c WHERE c.business_id = v_biz AND c.status <> 'resolved'
                           AND (SELECT sender_id FROM m WHERE m.room_id = c.room_id ORDER BY created_at DESC LIMIT 1) NOT IN (SELECT user_id FROM staff)),
        'open_conversations', (SELECT count(*) FROM public.business_conversations WHERE business_id = v_biz AND status <> 'resolved'),
        'resolved_period', (SELECT count(*) FROM public.business_conversations WHERE business_id = v_biz AND status = 'resolved'
                            AND last_activity_at > NOW() - make_interval(days => v_days)),
        'avg_first_reply_min', (SELECT round(avg(mins)::numeric, 1) FROM replies WHERE mins IS NOT NULL AND created_at > NOW() - make_interval(days => v_days)),
        'customers', (SELECT count(*) FROM public.business_customers WHERE business_id = v_biz),
        'customers_new_period', (SELECT count(*) FROM public.business_customers WHERE business_id = v_biz AND created_at > NOW() - make_interval(days => v_days)),
        'appointments_upcoming', (SELECT count(*) FROM public.business_appointments WHERE business_id = v_biz AND status = 'scheduled' AND starts_at > NOW()),
        'appointments_period', (SELECT count(*) FROM public.business_appointments WHERE business_id = v_biz AND starts_at > NOW() - make_interval(days => v_days) AND starts_at <= NOW()),
        'tasks_open', (SELECT count(*) FROM public.business_tasks WHERE business_id = v_biz AND done_at IS NULL),
        'tasks_done_period', (SELECT count(*) FROM public.business_tasks WHERE business_id = v_biz AND done_at > NOW() - make_interval(days => v_days)),
        'followups_due', (SELECT count(*) FROM public.business_followups WHERE business_id = v_biz AND done_at IS NULL AND due_at <= NOW() + INTERVAL '1 day')
    ) INTO v_out;
    RETURN v_out;
END $$;
REVOKE ALL ON FUNCTION public.business_overview(UUID, INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.business_overview(UUID, INTEGER) TO authenticated;

-- Takip ve randevu hatırlatmaları (mevcut hatırlatma işçisine bağlanır; ikinci zamanlayıcı yok)
CREATE OR REPLACE FUNCTION public.juzzio_fire_business_reminders(p_limit INTEGER DEFAULT 500)
RETURNS INTEGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    r RECORD;
    v_n INTEGER := 0;
BEGIN
    FOR r IN
        SELECT f.id, f.business_id, COALESCE(f.assignee_id, f.created_by, f.business_id) AS who, f.title
        FROM public.business_followups f
        WHERE f.done_at IS NULL AND f.reminded_at IS NULL AND f.due_at <= NOW()
        ORDER BY f.due_at LIMIT LEAST(GREATEST(COALESCE(p_limit, 500), 1), 2000)
        FOR UPDATE SKIP LOCKED
    LOOP
        UPDATE public.business_followups SET reminded_at = NOW() WHERE id = r.id;
        CONTINUE WHEN public.juzzio_business_role(r.business_id, r.who) IS NULL;
        INSERT INTO public.notifications (recipient_id, actor_id, actor_username, actor_display_name, event_type, target_id, target_secondary_id, preview_text, dedupe_key)
        VALUES (r.who, NULL, '', 'Juzzio Business', 'reminder', r.business_id::text, r.id::text, 'followup|' || LEFT(r.title, 120), 'biz_followup_' || r.id::text)
        ON CONFLICT (recipient_id, dedupe_key) DO NOTHING;
        v_n := v_n + 1;
    END LOOP;
    FOR r IN
        SELECT a.id, a.business_id, COALESCE(a.assignee_id, a.created_by, a.business_id) AS who, a.starts_at
        FROM public.business_appointments a
        WHERE a.status = 'scheduled' AND a.reminded_at IS NULL AND a.starts_at > NOW()
          AND a.starts_at - make_interval(mins => a.remind_minutes_before) <= NOW()
        ORDER BY a.starts_at LIMIT LEAST(GREATEST(COALESCE(p_limit, 500), 1), 2000)
        FOR UPDATE SKIP LOCKED
    LOOP
        UPDATE public.business_appointments SET reminded_at = NOW() WHERE id = r.id;
        CONTINUE WHEN public.juzzio_business_role(r.business_id, r.who) IS NULL;
        INSERT INTO public.notifications (recipient_id, actor_id, actor_username, actor_display_name, event_type, target_id, target_secondary_id, preview_text, dedupe_key)
        VALUES (r.who, NULL, '', 'Juzzio Business', 'reminder', r.business_id::text, r.id::text,
                'appointment|' || to_char(r.starts_at AT TIME ZONE 'Europe/Istanbul', 'DD.MM HH24:MI'), 'biz_appt_' || r.id::text)
        ON CONFLICT (recipient_id, dedupe_key) DO NOTHING;
        v_n := v_n + 1;
    END LOOP;
    RETURN v_n;
END $$;
REVOKE ALL ON FUNCTION public.juzzio_fire_business_reminders(INTEGER) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.juzzio_fire_business_reminders(INTEGER) TO service_role;
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        BEGIN
            PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'juzzio_fire_business_reminders';
            PERFORM cron.schedule('juzzio_fire_business_reminders', '* * * * *', 'SELECT public.juzzio_fire_business_reminders()');
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'pg_cron görevi (juzzio_fire_business_reminders) oluşturulamadı: %', SQLERRM;
        END;
    END IF;
END $$;

-- Otomatik yanıt (Gelen Kutusu > Ayarlar > Otomatik Yanıtlar): yalnız işletmenin GELEN KUTUSUNA
-- eklenmiş konuşmalarda, müşteri mesajında; karşılama (ilk kez) veya mesai dışı; kişi başına 12 saatte
-- en fazla 1 yanıt (döngü/spam koruması). Yanıt işletmenin kendi hazır metnidir ve açıkça
-- işaretlenir (metadata.security = 'business_auto_reply'); E2EE sohbetlerde şifresiz olduğu
-- kullanıcıya gösterilir. Kayıt: business_auto_reply_log.
CREATE OR REPLACE FUNCTION public.juzzio_business_in_hours(p_hours JSONB, p_tz TEXT, p_at TIMESTAMPTZ)
RETURNS BOOLEAN
LANGUAGE plpgsql STABLE AS $$
DECLARE
    v_local TIMESTAMP := p_at AT TIME ZONE COALESCE(NULLIF(p_tz, ''), 'Europe/Istanbul');
    v_day TEXT := lower(to_char(v_local, 'Dy'));
    v_span JSONB := p_hours -> v_day;
    v_open TIME;
    v_close TIME;
BEGIN
    IF p_hours IS NULL OR p_hours = '{}'::jsonb THEN RETURN true; END IF; -- saat tanımlı değil → mesai içi say
    IF v_span IS NULL OR jsonb_typeof(v_span) <> 'array' OR jsonb_array_length(v_span) <> 2 THEN RETURN false; END IF;
    v_open := (v_span ->> 0)::time;
    v_close := (v_span ->> 1)::time;
    RETURN v_local::time >= v_open AND v_local::time < v_close;
EXCEPTION WHEN OTHERS THEN
    RETURN true;
END $$;

CREATE OR REPLACE FUNCTION public.juzzio_business_auto_reply()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    c RECORD;
    v_kind TEXT;
    v_body TEXT;
    v_msg UUID;
BEGIN
    IF NEW.message_type IN ('system', 'call') OR COALESCE(NEW.metadata ->> 'security', '') = 'business_auto_reply' THEN RETURN NEW; END IF;
    FOR c IN
        SELECT bc.business_id, b.working_hours, b.timezone
        FROM public.business_conversations bc JOIN public.business_accounts b ON b.id = bc.business_id
        WHERE bc.room_id = NEW.room_id AND b.status = 'business_active'
          AND NEW.sender_id <> bc.business_id
          AND public.juzzio_business_role(bc.business_id, NEW.sender_id) IS NULL
    LOOP
        UPDATE public.business_conversations SET last_activity_at = NOW(), status = CASE WHEN status = 'resolved' THEN 'open' ELSE status END
         WHERE business_id = c.business_id AND room_id = NEW.room_id;
        CONTINUE WHEN EXISTS (SELECT 1 FROM public.business_auto_reply_log l WHERE l.business_id = c.business_id
                                AND l.customer_user_id = NEW.sender_id AND l.created_at > NOW() - INTERVAL '12 hours');
        v_kind := CASE
            WHEN NOT EXISTS (SELECT 1 FROM public.business_auto_reply_log l WHERE l.business_id = c.business_id AND l.customer_user_id = NEW.sender_id)
                 AND EXISTS (SELECT 1 FROM public.business_auto_replies r WHERE r.business_id = c.business_id AND r.kind = 'welcome' AND r.enabled AND BTRIM(r.body) <> '')
                THEN 'welcome'
            WHEN NOT public.juzzio_business_in_hours(c.working_hours, c.timezone, NOW())
                 AND EXISTS (SELECT 1 FROM public.business_auto_replies r WHERE r.business_id = c.business_id AND r.kind = 'away' AND r.enabled AND BTRIM(r.body) <> '')
                THEN 'away'
        END;
        CONTINUE WHEN v_kind IS NULL;
        SELECT body INTO v_body FROM public.business_auto_replies WHERE business_id = c.business_id AND kind = v_kind;
        INSERT INTO public.messages (room_id, sender_id, message_type, original_text, metadata)
        VALUES (NEW.room_id, c.business_id, 'text', v_body, jsonb_build_object('security', 'business_auto_reply', 'kind', v_kind))
        RETURNING id INTO v_msg;
        INSERT INTO public.business_auto_reply_log (business_id, room_id, customer_user_id, kind, message_id)
        VALUES (c.business_id, NEW.room_id, NEW.sender_id, v_kind, v_msg);
    END LOOP;
    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    RETURN NEW; -- otomatik yanıt hatası müşterinin mesajını asla engellemez
END $$;
DROP TRIGGER IF EXISTS trg_juzzio_business_auto_reply ON public.messages;
CREATE TRIGGER trg_juzzio_business_auto_reply AFTER INSERT ON public.messages
    FOR EACH ROW EXECUTE FUNCTION public.juzzio_business_auto_reply();

-- =============================================================================
-- 10.22 GÜVENLİK MERKEZİ — doğrulanabilir güvenlik olayları, cihaz listesi
--  * security_events yalnızca sunucu tetikleyicileri/RPC'leri tarafından yazılır
--    (istemci INSERT yetkisi YOK) → kullanıcıya gösterilen her uyarı gerçek bir
--    veritabanı olayına dayanır.
--  * Olaylar: new_device (ilk cihaz hariç), device_removed, e2ee_key_changed.
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.security_events (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    kind TEXT NOT NULL CHECK (kind IN ('new_device', 'device_removed', 'e2ee_key_changed')),
    detail JSONB NOT NULL DEFAULT '{}'::jsonb,
    seen BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_security_events_user ON public.security_events (user_id, created_at DESC);
ALTER TABLE public.security_events ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS security_events_own_select ON public.security_events;
CREATE POLICY security_events_own_select ON public.security_events FOR SELECT TO authenticated USING (user_id = auth.uid());
REVOKE INSERT, UPDATE, DELETE ON public.security_events FROM anon, authenticated;
GRANT SELECT ON public.security_events TO authenticated;

ALTER TABLE public.user_devices ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS user_devices_own_select ON public.user_devices;
CREATE POLICY user_devices_own_select ON public.user_devices FOR SELECT TO authenticated USING (user_id = auth.uid());

CREATE OR REPLACE FUNCTION public.juzzio_security_on_device() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM public.user_devices d WHERE d.user_id = NEW.user_id AND d.device_id <> NEW.device_id) THEN
        INSERT INTO public.security_events (user_id, kind, detail)
        VALUES (NEW.user_id, 'new_device', jsonb_build_object('device', RIGHT(NEW.device_id, 6), 'platform', NEW.platform));
    END IF;
    RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_juzzio_security_on_device ON public.user_devices;
CREATE TRIGGER trg_juzzio_security_on_device AFTER INSERT ON public.user_devices
    FOR EACH ROW EXECUTE FUNCTION public.juzzio_security_on_device();

CREATE OR REPLACE FUNCTION public.juzzio_security_on_key() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF COALESCE(OLD.e2ee_key_id, '') <> '' AND NEW.e2ee_key_id IS DISTINCT FROM OLD.e2ee_key_id THEN
        INSERT INTO public.security_events (user_id, kind, detail)
        VALUES (NEW.id, 'e2ee_key_changed', jsonb_build_object('key', RIGHT(COALESCE(NEW.e2ee_key_id, ''), 8)));
    END IF;
    RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_juzzio_security_on_key ON public.profiles;
CREATE TRIGGER trg_juzzio_security_on_key AFTER UPDATE OF e2ee_key_id ON public.profiles
    FOR EACH ROW EXECUTE FUNCTION public.juzzio_security_on_key();

-- Kendi cihazlarım (kimlik son 6 hane; tam kimlik dönmez)
CREATE OR REPLACE FUNCTION public.list_my_devices(p_current_device TEXT DEFAULT '')
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'device', RIGHT(d.device_id, 6), 'platform', d.platform, 'first_seen', d.first_seen,
        'last_seen', d.last_seen, 'current', d.device_id = COALESCE(p_current_device, ''))
        ORDER BY d.last_seen DESC), '[]'::jsonb)
      FROM public.user_devices d WHERE d.user_id = auth.uid();
$$;
GRANT EXECUTE ON FUNCTION public.list_my_devices(TEXT) TO authenticated;

-- Cihazı listeden çıkar (mevcut cihaz çıkarılamaz). Oturum kapatma istemcide
-- auth.signOut(scope: others) ile yapılır; bu kayıt yalnızca listeyi temizler.
CREATE OR REPLACE FUNCTION public.forget_my_device(p_device_suffix TEXT, p_current_device TEXT)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid UUID := auth.uid(); v_n INT;
BEGIN
    IF v_uid IS NULL OR LENGTH(COALESCE(p_device_suffix, '')) <> 6 THEN RETURN false; END IF;
    DELETE FROM public.user_devices
     WHERE user_id = v_uid AND RIGHT(device_id, 6) = p_device_suffix AND device_id <> COALESCE(p_current_device, '');
    GET DIAGNOSTICS v_n = ROW_COUNT;
    IF v_n > 0 THEN
        INSERT INTO public.security_events (user_id, kind, detail) VALUES (v_uid, 'device_removed', jsonb_build_object('device', p_device_suffix));
    END IF;
    RETURN v_n > 0;
END $$;
GRANT EXECUTE ON FUNCTION public.forget_my_device(TEXT, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.mark_my_security_events_seen()
RETURNS INT LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_n INT;
BEGIN
    UPDATE public.security_events SET seen = true WHERE user_id = auth.uid() AND NOT seen;
    GET DIAGNOSTICS v_n = ROW_COUNT; RETURN v_n;
END $$;
GRANT EXECUTE ON FUNCTION public.mark_my_security_events_seen() TO authenticated;

-- Özet: yalnızca gerçek veriden hesaplanır
CREATE OR REPLACE FUNCTION public.get_my_security_overview()
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT jsonb_build_object(
        'devices', (SELECT COUNT(*) FROM public.user_devices WHERE user_id = auth.uid()),
        'unseen_alerts', (SELECT COUNT(*) FROM public.security_events WHERE user_id = auth.uid() AND NOT seen),
        'e2ee_ready', (SELECT COALESCE(e2ee_public_key, '') <> '' FROM public.profiles WHERE id = auth.uid()));
$$;
GRANT EXECUTE ON FUNCTION public.get_my_security_overview() TO authenticated;

-- =============================================================================
-- 10.23 G26 SOHBET ANKETLERİ + G27 ZAMANLANMIŞ MESAJ
--  Anket: yalnız GRUP sohbetlerinde (gruplar E2EE değildir; birebir sohbette şifresiz anket
--  içeriği oluşturulmaz). Oylar tekil (çoklu seçim izinliyse seçenek başına tekil), kapalı
--  ankete oy verilmez. Gizli ankette kim-neye-oy bilgisi KİMSEYE dönmez (oylar tablosu yalnız
--  sahibine görünür; sonuç yalnız sayım).
--  Zamanlanmış mesaj: birebir sohbette içerik istemcide E2EE ile ŞİFRELENMİŞ olarak saklanır
--  (düz metin REDDEDİLİR); gönderim anında gönderenin yazma hakkı mesaj RLS'iyle aynı kuralla
--  yeniden denetlenir. İşçi idempotenttir (FOR UPDATE SKIP LOCKED + durum).
-- =============================================================================
CREATE OR REPLACE FUNCTION public.juzzio_can_post(p_room UUID, p_user UUID)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT public.is_room_member(p_room, p_user)
       AND NOT public.juzzio_is_banned(p_user)
       AND NOT EXISTS (SELECT 1 FROM public.room_participants me
                        WHERE me.room_id = p_room AND me.user_id = p_user AND me.muted_until > NOW())
       AND NOT EXISTS (SELECT 1 FROM public.room_participants o JOIN public.rooms r ON r.id = o.room_id
                        WHERE o.room_id = p_room AND NOT r.is_group AND o.user_id <> p_user
                          AND public.is_blocked_between(p_user, o.user_id));
$$;
REVOKE ALL ON FUNCTION public.juzzio_can_post(UUID, UUID) FROM PUBLIC, anon, authenticated;

CREATE TABLE IF NOT EXISTS public.polls (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    room_id UUID NOT NULL REFERENCES public.rooms(id) ON DELETE CASCADE,
    created_by UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    message_id UUID,
    question TEXT NOT NULL CHECK (LENGTH(BTRIM(question)) BETWEEN 1 AND 300),
    options JSONB NOT NULL CHECK (jsonb_typeof(options) = 'array' AND jsonb_array_length(options) BETWEEN 2 AND 10),
    multi BOOLEAN NOT NULL DEFAULT false,
    anonymous BOOLEAN NOT NULL DEFAULT false,
    closed BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_polls_room ON public.polls (room_id, created_at DESC);
CREATE TABLE IF NOT EXISTS public.poll_votes (
    poll_id UUID NOT NULL REFERENCES public.polls(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    option_idx SMALLINT NOT NULL CHECK (option_idx BETWEEN 0 AND 9),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (poll_id, user_id, option_idx)
);
ALTER TABLE public.polls ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.poll_votes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS polls_member_select ON public.polls;
CREATE POLICY polls_member_select ON public.polls FOR SELECT TO authenticated USING (public.is_room_member(room_id));
DROP POLICY IF EXISTS poll_votes_own_select ON public.poll_votes;
CREATE POLICY poll_votes_own_select ON public.poll_votes FOR SELECT TO authenticated USING (user_id = auth.uid());
REVOKE INSERT, UPDATE, DELETE ON public.polls, public.poll_votes FROM anon, authenticated;
GRANT SELECT ON public.polls, public.poll_votes TO authenticated;

CREATE OR REPLACE FUNCTION public.create_poll(p_room UUID, p_question TEXT, p_options TEXT[], p_multi BOOLEAN DEFAULT false, p_anonymous BOOLEAN DEFAULT false)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_opts JSONB;
    v_id UUID;
    v_msg UUID;
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
    IF NOT EXISTS (SELECT 1 FROM public.rooms WHERE id = p_room AND is_group) THEN RAISE EXCEPTION 'poll_group_only'; END IF;
    IF NOT public.juzzio_can_post(p_room, v_uid) THEN RAISE EXCEPTION 'not_allowed'; END IF;
    SELECT jsonb_agg(LEFT(BTRIM(o), 100) ORDER BY ord) INTO v_opts
      FROM unnest(p_options) WITH ORDINALITY AS t(o, ord) WHERE LENGTH(BTRIM(COALESCE(o, ''))) > 0;
    IF v_opts IS NULL OR jsonb_array_length(v_opts) < 2 OR jsonb_array_length(v_opts) > 10 THEN RAISE EXCEPTION 'poll_options_invalid'; END IF;
    IF (SELECT COUNT(DISTINCT LOWER(x)) FROM jsonb_array_elements_text(v_opts) x) <> jsonb_array_length(v_opts) THEN
        RAISE EXCEPTION 'poll_options_duplicate';
    END IF;
    INSERT INTO public.polls (room_id, created_by, question, options, multi, anonymous)
    VALUES (p_room, v_uid, LEFT(BTRIM(p_question), 300), v_opts, COALESCE(p_multi, false), COALESCE(p_anonymous, false))
    RETURNING id INTO v_id;
    INSERT INTO public.messages (room_id, sender_id, message_type, original_text, metadata)
    VALUES (p_room, v_uid, 'text', '📊 ' || LEFT(BTRIM(p_question), 300), jsonb_build_object('poll_id', v_id))
    RETURNING id INTO v_msg;
    UPDATE public.polls SET message_id = v_msg WHERE id = v_id;
    RETURN v_id;
END $$;
GRANT EXECUTE ON FUNCTION public.create_poll(UUID, TEXT, TEXT[], BOOLEAN, BOOLEAN) TO authenticated;

-- Oyumu ayarla (boş dizi = oyu geri çek). Tekil seçimde en fazla 1 seçenek.
CREATE OR REPLACE FUNCTION public.vote_poll(p_poll UUID, p_options SMALLINT[])
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid UUID := auth.uid(); p public.polls; v_n INT;
BEGIN
    SELECT * INTO p FROM public.polls WHERE id = p_poll;
    IF p.id IS NULL OR v_uid IS NULL OR NOT public.is_room_member(p.room_id, v_uid) THEN RAISE EXCEPTION 'not_allowed'; END IF;
    IF p.closed THEN RAISE EXCEPTION 'poll_closed'; END IF;
    v_n := COALESCE(array_length(p_options, 1), 0);
    IF NOT p.multi AND v_n > 1 THEN RAISE EXCEPTION 'poll_single_choice'; END IF;
    IF EXISTS (SELECT 1 FROM unnest(COALESCE(p_options, '{}')) o WHERE o < 0 OR o >= jsonb_array_length(p.options)) THEN
        RAISE EXCEPTION 'poll_option_invalid';
    END IF;
    DELETE FROM public.poll_votes WHERE poll_id = p_poll AND user_id = v_uid;
    INSERT INTO public.poll_votes (poll_id, user_id, option_idx)
    SELECT p_poll, v_uid, o FROM (SELECT DISTINCT o FROM unnest(COALESCE(p_options, '{}')) o) d;
    RETURN true;
END $$;
GRANT EXECUTE ON FUNCTION public.vote_poll(UUID, SMALLINT[]) TO authenticated;

CREATE OR REPLACE FUNCTION public.close_poll(p_poll UUID)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_n INT;
BEGIN
    UPDATE public.polls SET closed = true WHERE id = p_poll AND created_by = auth.uid() AND NOT closed;
    GET DIAGNOSTICS v_n = ROW_COUNT; RETURN v_n > 0;
END $$;
GRANT EXECUTE ON FUNCTION public.close_poll(UUID) TO authenticated;

-- Sonuçlar: sayımlar + benim oylarım; seçmen adları yalnız gizli OLMAYAN ankette
CREATE OR REPLACE FUNCTION public.poll_results(p_poll UUID)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE p public.polls;
BEGIN
    SELECT * INTO p FROM public.polls WHERE id = p_poll;
    IF p.id IS NULL OR NOT public.is_room_member(p.room_id) THEN RAISE EXCEPTION 'not_allowed'; END IF;
    RETURN jsonb_build_object(
        'question', p.question, 'options', p.options, 'multi', p.multi, 'anonymous', p.anonymous,
        'closed', p.closed, 'mine_creator', p.created_by = auth.uid(),
        'counts', (SELECT jsonb_agg((SELECT COUNT(*) FROM public.poll_votes v WHERE v.poll_id = p.id AND v.option_idx = i) ORDER BY i)
                     FROM generate_series(0, jsonb_array_length(p.options) - 1) i),
        'voters', (SELECT COUNT(DISTINCT user_id) FROM public.poll_votes WHERE poll_id = p.id),
        'my_votes', COALESCE((SELECT jsonb_agg(option_idx ORDER BY option_idx) FROM public.poll_votes WHERE poll_id = p.id AND user_id = auth.uid()), '[]'::jsonb),
        'by_option', CASE WHEN p.anonymous THEN NULL ELSE
            (SELECT jsonb_object_agg(i::text, COALESCE((SELECT jsonb_agg(COALESCE(NULLIF(pr.display_name, ''), pr.username) ORDER BY v.created_at)
                                                         FROM public.poll_votes v JOIN public.profiles pr ON pr.id = v.user_id
                                                        WHERE v.poll_id = p.id AND v.option_idx = i), '[]'::jsonb))
               FROM generate_series(0, jsonb_array_length(p.options) - 1) i) END);
END $$;
GRANT EXECUTE ON FUNCTION public.poll_results(UUID) TO authenticated;

CREATE TABLE IF NOT EXISTS public.scheduled_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    room_id UUID NOT NULL REFERENCES public.rooms(id) ON DELETE CASCADE,
    sender_id UUID NOT NULL DEFAULT auth.uid() REFERENCES public.profiles(id) ON DELETE CASCADE,
    send_at TIMESTAMPTZ NOT NULL,
    body TEXT NOT NULL DEFAULT '',
    e2ee JSONB,
    preview TEXT NOT NULL DEFAULT '',
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'sent', 'cancelled', 'failed')),
    fail_reason TEXT NOT NULL DEFAULT '',
    message_id UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    sent_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_scheduled_due ON public.scheduled_messages (send_at) WHERE status = 'pending';
ALTER TABLE public.scheduled_messages ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS scheduled_own_select ON public.scheduled_messages;
CREATE POLICY scheduled_own_select ON public.scheduled_messages FOR SELECT TO authenticated USING (sender_id = auth.uid());
REVOKE INSERT, UPDATE, DELETE ON public.scheduled_messages FROM anon, authenticated;
GRANT SELECT ON public.scheduled_messages TO authenticated;

-- p_preview: yalnız GÖNDERENİN kendi listesinde görünen kısa not (birebir sohbette istemci
-- boş bırakır; sunucu birebir sohbette önizlemeyi her durumda boşaltır).
CREATE OR REPLACE FUNCTION public.schedule_message(p_room UUID, p_send_at TIMESTAMPTZ, p_body TEXT DEFAULT '', p_e2ee JSONB DEFAULT NULL, p_preview TEXT DEFAULT '')
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid UUID := auth.uid(); v_group BOOLEAN; v_id UUID;
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
    SELECT is_group INTO v_group FROM public.rooms WHERE id = p_room;
    IF v_group IS NULL OR NOT public.juzzio_can_post(p_room, v_uid) THEN RAISE EXCEPTION 'not_allowed'; END IF;
    IF p_send_at < NOW() + INTERVAL '1 minute' OR p_send_at > NOW() + INTERVAL '365 days' THEN RAISE EXCEPTION 'schedule_time_invalid'; END IF;
    IF (SELECT COUNT(*) FROM public.scheduled_messages WHERE sender_id = v_uid AND status = 'pending') >= 100 THEN
        RAISE EXCEPTION 'schedule_limit';
    END IF;
    IF NOT v_group THEN
        -- Birebir: yalnız şifreli içerik (fail-closed)
        IF p_e2ee IS NULL OR jsonb_typeof(p_e2ee) <> 'object' OR NOT (p_e2ee ? 'c') OR LENGTH(BTRIM(COALESCE(p_body, ''))) > 0 THEN
            RAISE EXCEPTION 'schedule_e2ee_required';
        END IF;
        INSERT INTO public.scheduled_messages (room_id, sender_id, send_at, e2ee) VALUES (p_room, v_uid, p_send_at, p_e2ee) RETURNING id INTO v_id;
    ELSE
        IF p_e2ee IS NOT NULL OR LENGTH(BTRIM(COALESCE(p_body, ''))) NOT BETWEEN 1 AND 4000 THEN RAISE EXCEPTION 'schedule_body_invalid'; END IF;
        INSERT INTO public.scheduled_messages (room_id, sender_id, send_at, body, preview)
        VALUES (p_room, v_uid, p_send_at, BTRIM(p_body), LEFT(BTRIM(p_body), 80)) RETURNING id INTO v_id;
    END IF;
    RETURN v_id;
END $$;
GRANT EXECUTE ON FUNCTION public.schedule_message(UUID, TIMESTAMPTZ, TEXT, JSONB, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.cancel_scheduled_message(p_id UUID)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_n INT;
BEGIN
    UPDATE public.scheduled_messages SET status = 'cancelled' WHERE id = p_id AND sender_id = auth.uid() AND status = 'pending';
    GET DIAGNOSTICS v_n = ROW_COUNT; RETURN v_n > 0;
END $$;
GRANT EXECUTE ON FUNCTION public.cancel_scheduled_message(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.juzzio_send_due_scheduled(p_limit INTEGER DEFAULT 200)
RETURNS INTEGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE s public.scheduled_messages; v_msg UUID; v_n INT := 0;
BEGIN
    FOR s IN SELECT * FROM public.scheduled_messages WHERE status = 'pending' AND send_at <= NOW()
             ORDER BY send_at LIMIT p_limit FOR UPDATE SKIP LOCKED
    LOOP
        IF NOT public.juzzio_can_post(s.room_id, s.sender_id) THEN
            UPDATE public.scheduled_messages SET status = 'failed', fail_reason = 'not_allowed' WHERE id = s.id;
            CONTINUE;
        END IF;
        BEGIN
            INSERT INTO public.messages (room_id, sender_id, message_type, original_text, translated_text, client_msg_id, metadata)
            VALUES (s.room_id, s.sender_id, 'text', CASE WHEN s.e2ee IS NULL THEN s.body ELSE '' END, '',
                    'sch_' || REPLACE(s.id::text, '-', ''),
                    CASE WHEN s.e2ee IS NULL THEN jsonb_build_object('scheduled', true)
                         ELSE jsonb_build_object('e2ee', s.e2ee, 'scheduled', true) END)
            RETURNING id INTO v_msg;
            UPDATE public.scheduled_messages SET status = 'sent', sent_at = NOW(), message_id = v_msg WHERE id = s.id;
            v_n := v_n + 1;
        EXCEPTION WHEN OTHERS THEN
            UPDATE public.scheduled_messages SET status = 'failed', fail_reason = LEFT(SQLERRM, 120) WHERE id = s.id;
        END;
    END LOOP;
    RETURN v_n;
END $$;
REVOKE ALL ON FUNCTION public.juzzio_send_due_scheduled(INTEGER) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.juzzio_send_due_scheduled(INTEGER) TO service_role;
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        BEGIN
            PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'juzzio_send_due_scheduled';
            PERFORM cron.schedule('juzzio_send_due_scheduled', '* * * * *', 'SELECT public.juzzio_send_due_scheduled()');
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'pg_cron görevi (juzzio_send_due_scheduled) oluşturulamadı: %', SQLERRM;
        END;
    END IF;
END $$;

-- =============================================================================
-- 10.24 v0.9.3 YORUM BİLDİRİMLERİ — yanıt, beğeni, @bahsetme
--  * Yanıt bildirimi YANITLANAN kişiye gider (reply_to_username; iç içe yanıtta kök yorum
--    sahibine değil). Önizleme 'reply|<yanıtlanan yorum>|<yanıt>' → istemci
--    "Engin, '…' yorumunuza '…' yanıtını verdi." yazar.
--  * Yorum beğenisi → 'comment_like' bildirimi ("Engin '…' yorumunuzu beğendi.").
--  * Yanıtta yanıtlanan kişi @etiketlenmişse ayrıca "bahsetti" bildirimi gitmez (çift bildirim yok).
--  * Engelleme ve kendi kendine bildirim her yerde atlanır.
-- =============================================================================
ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_event_type_check;
ALTER TABLE public.notifications ADD CONSTRAINT notifications_event_type_check CHECK (event_type = ANY (ARRAY[
    'like', 'comment', 'reply', 'follow', 'follow_request', 'follow_accepted', 'friend_request',
    'friend_accepted', 'story_like', 'story_reply', 'message', 'missed_call', 'incoming_call',
    'group_activity', 'system', 'chick_invite', 'chick_hatched', 'chick_hungry', 'chick_dying',
    'chick_died', 'reaction', 'save', 'mention', 'reminder', 'comment_like'
])) NOT VALID;

-- Yanıtlanan kişi: reply_to_username varsa o, yoksa kök yorumun sahibi
CREATE OR REPLACE FUNCTION public.juzzio_comment_reply_target(p_comment public.post_comments)
RETURNS UUID LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT COALESCE(
        (SELECT pr.id FROM public.profiles pr
          WHERE NULLIF(BTRIM(p_comment.reply_to_username), '') IS NOT NULL
            AND lower(pr.username) = lower(BTRIM(p_comment.reply_to_username)) LIMIT 1),
        (SELECT c.author_id FROM public.post_comments c WHERE c.id = p_comment.parent_comment_id));
$$;
REVOKE ALL ON FUNCTION public.juzzio_comment_reply_target(public.post_comments) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.sync_post_comments_count()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_post UUID := COALESCE(NEW.post_id, OLD.post_id);
    v_target UUID;
    v_parent RECORD;
    v_excerpt TEXT := '';
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
                v_target := public.juzzio_comment_reply_target(NEW);
                SELECT author_id, content INTO v_parent FROM public.post_comments WHERE id = NEW.parent_comment_id;
                -- Yanıtlanan yorumun metni yalnız kök yorum sahibine yanıtta bilinir
                IF v_parent.author_id = v_target THEN
                    v_excerpt := LEFT(REGEXP_REPLACE(COALESCE(v_parent.content, ''), '[\s|]+', ' ', 'g'), 80);
                END IF;
                IF v_target IS NOT NULL AND v_target <> NEW.author_id
                   AND NOT public.is_blocked_between(v_target, NEW.author_id) THEN
                    INSERT INTO public.notifications (recipient_id, actor_id, actor_username, actor_display_name, actor_avatar_url,
                                                      event_type, target_id, target_secondary_id, preview_text, dedupe_key)
                    VALUES (v_target, NEW.author_id, NEW.author_username, NEW.author_display_name, NEW.author_avatar_url,
                            'reply', NEW.post_id::text, NEW.id::text,
                            'reply|' || v_excerpt || '|' || LEFT(REGEXP_REPLACE(NEW.content, '\s+', ' ', 'g'), 100),
                            'reply_' || NEW.id::text)
                    ON CONFLICT (recipient_id, dedupe_key) DO NOTHING;
                END IF;
            END IF;
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
    END IF;
    RETURN COALESCE(NEW, OLD);
END;
$$;

-- Etiket işleyici: atlanacak kullanıcı (yanıt bildirimini zaten alan kişi) desteği
CREATE OR REPLACE FUNCTION public.juzzio_process_mentions(
    p_type TEXT, p_content UUID, p_post UUID, p_author UUID, p_text TEXT, p_visibility_owner UUID, p_visibility TEXT, p_skip UUID
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_name TEXT;
    v_target UUID;
    v_actor RECORD;
    v_n INTEGER := 0;
    v_visible BOOLEAN;
BEGIN
    SELECT username, display_name, avatar_url INTO v_actor FROM public.profiles WHERE id = p_author;
    FOREACH v_name IN ARRAY public.juzzio_extract_mentions(p_text) LOOP
        SELECT id INTO v_target FROM public.profiles WHERE lower(username) = v_name LIMIT 1;
        CONTINUE WHEN v_target IS NULL OR NOT public.juzzio_can_mention(p_author, v_target);
        v_visible := CASE p_type
            WHEN 'story' THEN public.can_view_story(v_target, p_visibility_owner, p_visibility)
            ELSE public.can_view_user_content(v_target, p_visibility_owner, p_visibility) END;
        CONTINUE WHEN NOT COALESCE(v_visible, false);
        INSERT INTO public.content_mentions (content_type, content_id, post_id, author_id, mentioned_user_id)
        VALUES (p_type, p_content, p_post, p_author, v_target)
        ON CONFLICT (content_type, content_id, mentioned_user_id) DO NOTHING;
        CONTINUE WHEN NOT FOUND;
        v_n := v_n + 1;
        CONTINUE WHEN v_target IS NOT DISTINCT FROM p_skip; -- yanıt bildirimi zaten gidiyor
        CONTINUE WHEN NOT public.juzzio_rate_check(p_author, 'mention_notify', 60, 3600);
        INSERT INTO public.notifications (
            recipient_id, actor_id, actor_username, actor_display_name, actor_avatar_url,
            event_type, target_id, target_secondary_id, preview_text, dedupe_key
        ) VALUES (
            v_target, p_author, COALESCE(v_actor.username, ''),
            COALESCE(NULLIF(v_actor.display_name, ''), v_actor.username, 'Juzzio'), v_actor.avatar_url,
            'mention', COALESCE(p_post, p_content)::text, p_content::text,
            p_type || '|' || LEFT(REGEXP_REPLACE(COALESCE(p_text, ''), '\s+', ' ', 'g'), 120),
            'mention_' || p_type || '_' || p_content::text || '_' || v_target::text
        )
        ON CONFLICT (recipient_id, dedupe_key) DO NOTHING;
    END LOOP;
    RETURN v_n;
END;
$$;
REVOKE ALL ON FUNCTION public.juzzio_process_mentions(TEXT, UUID, UUID, UUID, TEXT, UUID, TEXT, UUID) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.juzzio_process_mentions(
    p_type TEXT, p_content UUID, p_post UUID, p_author UUID, p_text TEXT, p_visibility_owner UUID, p_visibility TEXT
)
RETURNS INTEGER LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
    SELECT public.juzzio_process_mentions(p_type, p_content, p_post, p_author, p_text, p_visibility_owner, p_visibility, NULL::uuid);
$$;
REVOKE ALL ON FUNCTION public.juzzio_process_mentions(TEXT, UUID, UUID, UUID, TEXT, UUID, TEXT) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.juzzio_mentions_on_comment()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_post RECORD;
    v_skip UUID;
BEGIN
    IF TG_OP = 'UPDATE' AND NEW.content IS NOT DISTINCT FROM OLD.content THEN RETURN NEW; END IF;
    SELECT author_id, visibility, is_deleted INTO v_post FROM public.posts WHERE id = NEW.post_id;
    IF v_post.author_id IS NULL OR v_post.is_deleted THEN RETURN NEW; END IF;
    IF TG_OP = 'INSERT' AND NEW.parent_comment_id IS NOT NULL THEN
        v_skip := public.juzzio_comment_reply_target(NEW);
    END IF;
    PERFORM public.juzzio_process_mentions('comment', NEW.id, NEW.post_id, NEW.author_id, NEW.content, v_post.author_id, v_post.visibility, v_skip);
    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    RETURN NEW;
END $$;

-- Yorum beğenisi bildirimi (sayaç tetikleyicisinden bağımsız)
CREATE OR REPLACE FUNCTION public.juzzio_notify_comment_like()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    c RECORD;
    a RECORD;
BEGIN
    SELECT id, post_id, author_id, content INTO c FROM public.post_comments WHERE id = NEW.comment_id;
    IF c.author_id IS NULL OR c.author_id = NEW.user_id OR public.is_blocked_between(c.author_id, NEW.user_id) THEN
        RETURN NEW;
    END IF;
    SELECT username, display_name, avatar_url INTO a FROM public.profiles WHERE id = NEW.user_id;
    INSERT INTO public.notifications (recipient_id, actor_id, actor_username, actor_display_name, actor_avatar_url,
                                      event_type, target_id, target_secondary_id, preview_text, dedupe_key)
    VALUES (c.author_id, NEW.user_id, COALESCE(a.username, ''), COALESCE(NULLIF(a.display_name, ''), a.username, 'Juzzio'), a.avatar_url,
            'comment_like', c.post_id::text, c.id::text, LEFT(REGEXP_REPLACE(c.content, '\s+', ' ', 'g'), 100),
            'comment_like_' || c.id::text || '_' || NEW.user_id::text)
    ON CONFLICT (recipient_id, dedupe_key) DO NOTHING;
    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_juzzio_notify_comment_like ON public.comment_likes;
CREATE TRIGGER trg_juzzio_notify_comment_like AFTER INSERT ON public.comment_likes
    FOR EACH ROW EXECUTE FUNCTION public.juzzio_notify_comment_like();

-- =============================================================================
-- 10.25 v0.9.3 — "Juzzio Official" hikâyeleri (Admin → Juzzio Story paneli)
--  • Yalnızca yönetici (@tugkancr) RPC ile paylaşır; visibility='everyone' → arkadaşlık gerekmez.
--  • is_official istemciden doğrudan yazılamaz (tetikleyici zorla false yapar; yalnız RPC içinde true).
-- =============================================================================
ALTER TABLE public.stories ADD COLUMN IF NOT EXISTS is_official BOOLEAN NOT NULL DEFAULT false;
CREATE INDEX IF NOT EXISTS stories_official_idx ON public.stories (created_at DESC) WHERE is_official;

CREATE OR REPLACE FUNCTION public.juzzio_guard_official_story()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
    IF COALESCE(current_setting('juzzio.official_story', true), '') <> '1' THEN
        IF TG_OP = 'INSERT' THEN
            NEW.is_official := false;
        ELSE
            NEW.is_official := OLD.is_official;
        END IF;
    ELSIF TG_OP = 'INSERT' AND NEW.is_official THEN
        -- trg_fill_story_identity (alfabetik olarak önce çalışır) adı ve süreyi profilden ezer; burada geri yazılır
        NEW.display_name := 'Juzzio Official';
        NEW.expires_at := COALESCE(NULLIF(current_setting('juzzio.official_expires', true), '')::timestamptz, NEW.expires_at);
    END IF;
    RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_juzzio_guard_official_story ON public.stories;
CREATE TRIGGER trg_juzzio_guard_official_story BEFORE INSERT OR UPDATE ON public.stories
    FOR EACH ROW EXECUTE FUNCTION public.juzzio_guard_official_story();

CREATE OR REPLACE FUNCTION public.admin_post_official_story(
    p_media_type TEXT, p_media_url TEXT, p_caption TEXT DEFAULT '', p_video_duration_sec INTEGER DEFAULT 15,
    p_hours INTEGER DEFAULT 24)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_id UUID;
    v_p RECORD;
BEGIN
    IF v_uid IS NULL OR NOT public.is_juzzio_admin(v_uid) THEN RAISE EXCEPTION 'not_allowed' USING ERRCODE = '42501'; END IF;
    IF p_media_type NOT IN ('image', 'video') THEN RAISE EXCEPTION 'invalid_media_type' USING ERRCODE = '22023'; END IF;
    IF COALESCE(BTRIM(p_media_url), '') = '' OR p_media_url !~* '^https://' THEN RAISE EXCEPTION 'invalid_media_url' USING ERRCODE = '22023'; END IF;
    SELECT username, avatar_url INTO v_p FROM public.profiles WHERE id = v_uid;
    PERFORM set_config('juzzio.official_story', '1', true);
    PERFORM set_config('juzzio.official_expires', (NOW() + make_interval(hours => LEAST(GREATEST(COALESCE(p_hours, 24), 1), 168)))::text, true);
    INSERT INTO public.stories (user_id, username, display_name, user_avatar, media_type, media_url, caption_original,
                                video_duration_sec, visibility, is_official, expires_at)
    VALUES (v_uid, COALESCE(v_p.username, 'tugkancr'), 'Juzzio Official', v_p.avatar_url, p_media_type, BTRIM(p_media_url),
            LEFT(COALESCE(p_caption, ''), 500), LEAST(GREATEST(COALESCE(p_video_duration_sec, 15), 3), 60), 'everyone', true,
            NOW() + make_interval(hours => LEAST(GREATEST(COALESCE(p_hours, 24), 1), 168)))
    RETURNING id INTO v_id;
    PERFORM set_config('juzzio.official_story', '', true);
    PERFORM set_config('juzzio.official_expires', '', true);
    RETURN v_id;
END $$;
REVOKE ALL ON FUNCTION public.admin_post_official_story(TEXT, TEXT, TEXT, INTEGER, INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_post_official_story(TEXT, TEXT, TEXT, INTEGER, INTEGER) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_delete_official_story(p_story UUID)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF auth.uid() IS NULL OR NOT public.is_juzzio_admin(auth.uid()) THEN RAISE EXCEPTION 'not_allowed' USING ERRCODE = '42501'; END IF;
    DELETE FROM public.stories WHERE id = p_story AND is_official;
    RETURN FOUND;
END $$;
REVOKE ALL ON FUNCTION public.admin_delete_official_story(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_delete_official_story(UUID) TO authenticated;


-- =============================================================================
-- 10.26 v0.9.4 — Canlı veritabanı denetimi düzeltmeleri + yeni modüller
--  A) Mükerrer / kapsanan indeksler (panelden elle eklenmiş kopyalar dahil) kaldırılır.
--  B) blocked_users: engellenen kişi artık engelleyeni ve SEBEBİNİ okuyamaz; istemci iki yönlü
--     engel listesini yalnız kimlik olarak my_block_peer_ids() ile alır.
--  C) Depolama: avatars 5 MB; posts/reels yalnız görsel/video MIME türleri.
--  D) get_server_time(): cihaz saati değiştirilmiş mi denetimi.
--  E) Civciv gardırobu (aksesuar kataloğu, jeton, ortak stil).
--  F) Vardiya planlayıcı (user_shifts) + grup takvimi.
--  G) Sohbet etkinlikleri (room_events + katılım + hatırlatma).
-- =============================================================================
DO $$
DECLARE r RECORD;
BEGIN
    FOR r IN SELECT * FROM (VALUES
        -- friendships_requester_id_receiver_id_key KORUNUR: ON CONFLICT (requester_id, receiver_id) hedefidir
        ('friendships', 'friendships_unique_pair'),
        ('friendships', 'idx_friendships_receiver_status'),
        ('friendships', 'idx_friendships_requester_status'),
        ('call_logs', 'idx_call_logs_caller'),
        ('call_logs', 'idx_call_logs_receiver'),
        ('blocked_users', 'idx_blocked_users_blocker'),
        ('comment_likes', 'idx_comment_likes_comment')) AS t(tbl, idx)
    LOOP
        IF EXISTS (SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid
                    WHERE t.relname = r.tbl AND c.conname = r.idx AND t.relnamespace = 'public'::regnamespace) THEN
            EXECUTE format('ALTER TABLE public.%I DROP CONSTRAINT %I', r.tbl, r.idx);
        ELSE
            EXECUTE format('DROP INDEX IF EXISTS public.%I', r.idx);
        END IF;
    END LOOP;
END $$;
-- Simetrik tekillik (A,B)/(B,A) kalıcı güvence: ters çift indeks her zaman var olmalı
CREATE UNIQUE INDEX IF NOT EXISTS idx_friendships_unique_pair
    ON public.friendships (LEAST(requester_id, receiver_id), GREATEST(requester_id, receiver_id));

-- B) blocked_users gizliliği
DROP POLICY IF EXISTS blocked_users_select_involved ON public.blocked_users;
DROP POLICY IF EXISTS blocked_users_select_own ON public.blocked_users;
CREATE POLICY blocked_users_select_own ON public.blocked_users FOR SELECT TO authenticated
    USING (auth.uid() = blocker_id);
CREATE OR REPLACE FUNCTION public.my_block_peer_ids()
RETURNS SETOF UUID LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT blocked_id FROM public.blocked_users WHERE blocker_id = auth.uid()
    UNION
    SELECT blocker_id FROM public.blocked_users WHERE blocked_id = auth.uid();
$$;
REVOKE ALL ON FUNCTION public.my_block_peer_ids() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.my_block_peer_ids() TO authenticated;

-- C) Depolama sıkılaştırma (istemci avatar/kapak görsellerini yüklemeden önce ≤1600 px JPEG'e sıkıştırır)
DO $$
BEGIN
    IF to_regclass('storage.buckets') IS NOT NULL THEN
        UPDATE storage.buckets SET file_size_limit = 5242880 WHERE id = 'avatars';
        UPDATE storage.buckets SET allowed_mime_types = ARRAY['image/jpeg', 'image/jpg', 'image/png', 'image/webp',
                                                             'video/mp4', 'video/quicktime', 'video/webm']
         WHERE id IN ('posts', 'reels');
    END IF;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'storage.buckets güncellenemedi: %', SQLERRM;
END $$;

-- D) Sunucu saati
CREATE OR REPLACE FUNCTION public.get_server_time()
RETURNS TIMESTAMPTZ LANGUAGE sql STABLE SET search_path = public AS $$ SELECT NOW(); $$;
GRANT EXECUTE ON FUNCTION public.get_server_time() TO anon, authenticated;

-- E) Civciv gardırobu
ALTER TABLE public.chick_pets ADD COLUMN IF NOT EXISTS style JSONB NOT NULL DEFAULT '{}'::jsonb;
CREATE TABLE IF NOT EXISTS public.chick_accessories (
    code TEXT PRIMARY KEY CHECK (code ~ '^[a-z0-9_]{2,40}$'),
    slot TEXT NOT NULL CHECK (slot IN ('hat', 'glasses', 'outfit', 'shoes', 'theme')),
    price INTEGER NOT NULL CHECK (price BETWEEN 0 AND 100000),
    min_stage INTEGER NOT NULL DEFAULT 1 CHECK (min_stage BETWEEN 0 AND 3),
    sort_order INTEGER NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT true
);
ALTER TABLE public.chick_accessories ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS chick_accessories_read ON public.chick_accessories;
CREATE POLICY chick_accessories_read ON public.chick_accessories FOR SELECT TO authenticated USING (is_active);
REVOKE INSERT, UPDATE, DELETE ON public.chick_accessories FROM anon, authenticated;
INSERT INTO public.chick_accessories (code, slot, price, min_stage, sort_order) VALUES
    ('party_hat', 'hat', 30, 1, 1), ('crown', 'hat', 120, 2, 2), ('beanie', 'hat', 50, 1, 3), ('cowboy_hat', 'hat', 90, 2, 4),
    ('round_glasses', 'glasses', 40, 1, 10), ('sunglasses', 'glasses', 70, 1, 11), ('heart_glasses', 'glasses', 90, 2, 12),
    ('bow_tie', 'outfit', 35, 1, 20), ('scarf', 'outfit', 60, 1, 21), ('cape', 'outfit', 140, 2, 22),
    ('sneakers', 'shoes', 45, 2, 30), ('boots', 'shoes', 80, 2, 31),
    ('theme_meadow', 'theme', 0, 0, 40), ('theme_night', 'theme', 60, 0, 41), ('theme_beach', 'theme', 80, 0, 42), ('theme_snow', 'theme', 100, 0, 43)
ON CONFLICT (code) DO UPDATE SET slot = EXCLUDED.slot, price = EXCLUDED.price, min_stage = EXCLUDED.min_stage, sort_order = EXCLUDED.sort_order;

CREATE TABLE IF NOT EXISTS public.chick_owned_accessories (
    chick_id UUID NOT NULL REFERENCES public.chick_pets(id) ON DELETE CASCADE,
    code TEXT NOT NULL REFERENCES public.chick_accessories(code) ON DELETE CASCADE,
    bought_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    price_paid INTEGER NOT NULL DEFAULT 0,
    bought_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (chick_id, code)
);
ALTER TABLE public.chick_owned_accessories ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS chick_owned_read ON public.chick_owned_accessories;
CREATE POLICY chick_owned_read ON public.chick_owned_accessories FOR SELECT TO authenticated
    USING (EXISTS (SELECT 1 FROM public.chick_pets c WHERE c.id = chick_id AND auth.uid() IN (c.owner_a, c.owner_b)));
REVOKE INSERT, UPDATE, DELETE ON public.chick_owned_accessories FROM anon, authenticated;

-- Jeton: her besleme 10 + evre başına 50 bonus; harcamalar düşülür (ortak cüzdan, iki sahip de kullanır)
CREATE OR REPLACE FUNCTION public.juzzio_chick_coins(p_chick UUID)
RETURNS INTEGER LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT GREATEST(0,
        (SELECT COUNT(*)::int * 10 FROM public.chick_feed_log WHERE chick_id = p_chick)
      + (SELECT COALESCE(stage, 0) * 50 FROM public.chick_pets WHERE id = p_chick)
      - (SELECT COALESCE(SUM(price_paid), 0)::int FROM public.chick_owned_accessories WHERE chick_id = p_chick));
$$;
REVOKE ALL ON FUNCTION public.juzzio_chick_coins(UUID) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.chick_wardrobe()
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE c public.chick_pets;
BEGIN
    SELECT * INTO c FROM public.chick_pets WHERE status = 'alive' AND auth.uid() IN (owner_a, owner_b) LIMIT 1;
    IF c.id IS NULL THEN RETURN jsonb_build_object('has_chick', false); END IF;
    RETURN jsonb_build_object(
        'has_chick', true, 'chick_id', c.id, 'stage', c.stage, 'style', c.style,
        'coins', public.juzzio_chick_coins(c.id),
        'owned', COALESCE((SELECT jsonb_agg(code) FROM public.chick_owned_accessories WHERE chick_id = c.id), '[]'::jsonb),
        'catalog', COALESCE((SELECT jsonb_agg(jsonb_build_object('code', code, 'slot', slot, 'price', price, 'min_stage', min_stage) ORDER BY sort_order)
                               FROM public.chick_accessories WHERE is_active), '[]'::jsonb));
END $$;
REVOKE ALL ON FUNCTION public.chick_wardrobe() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.chick_wardrobe() TO authenticated;

CREATE OR REPLACE FUNCTION public.chick_buy_accessory(p_code TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE c public.chick_pets; a public.chick_accessories;
BEGIN
    SELECT * INTO c FROM public.chick_pets WHERE status = 'alive' AND auth.uid() IN (owner_a, owner_b) LIMIT 1 FOR UPDATE;
    IF c.id IS NULL THEN RAISE EXCEPTION 'chick_not_found'; END IF;
    SELECT * INTO a FROM public.chick_accessories WHERE code = p_code AND is_active;
    IF a.code IS NULL THEN RAISE EXCEPTION 'accessory_not_found'; END IF;
    IF c.stage < a.min_stage THEN RAISE EXCEPTION 'chick_stage_too_low'; END IF;
    IF EXISTS (SELECT 1 FROM public.chick_owned_accessories WHERE chick_id = c.id AND code = a.code) THEN
        RETURN public.chick_wardrobe();
    END IF;
    IF public.juzzio_chick_coins(c.id) < a.price THEN RAISE EXCEPTION 'chick_not_enough_coins'; END IF;
    INSERT INTO public.chick_owned_accessories (chick_id, code, bought_by, price_paid) VALUES (c.id, a.code, auth.uid(), a.price);
    RETURN public.chick_wardrobe();
END $$;
REVOKE ALL ON FUNCTION public.chick_buy_accessory(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.chick_buy_accessory(TEXT) TO authenticated;

-- Yuva: p_code NULL → o yuvayı çıkar; p_color: gövde rengi (#RRGGBB) veya '' (varsayılan)
CREATE OR REPLACE FUNCTION public.chick_set_style(p_slot TEXT, p_code TEXT DEFAULT NULL, p_color TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE c public.chick_pets; v JSONB;
BEGIN
    SELECT * INTO c FROM public.chick_pets WHERE status = 'alive' AND auth.uid() IN (owner_a, owner_b) LIMIT 1 FOR UPDATE;
    IF c.id IS NULL THEN RAISE EXCEPTION 'chick_not_found'; END IF;
    v := COALESCE(c.style, '{}'::jsonb);
    IF p_slot = 'color' THEN
        IF COALESCE(p_color, '') = '' THEN v := v - 'color';
        ELSIF p_color ~ '^#[0-9A-Fa-f]{6}$' THEN v := v || jsonb_build_object('color', UPPER(p_color));
        ELSE RAISE EXCEPTION 'invalid_color'; END IF;
    ELSIF p_slot IN ('hat', 'glasses', 'outfit', 'shoes', 'theme') THEN
        IF p_code IS NULL THEN v := v - p_slot;
        ELSE
            IF NOT EXISTS (SELECT 1 FROM public.chick_accessories a
                            WHERE a.code = p_code AND a.slot = p_slot
                              AND (a.price = 0 OR EXISTS (SELECT 1 FROM public.chick_owned_accessories o WHERE o.chick_id = c.id AND o.code = a.code))) THEN
                RAISE EXCEPTION 'accessory_not_owned';
            END IF;
            v := v || jsonb_build_object(p_slot, p_code);
        END IF;
    ELSE
        RAISE EXCEPTION 'invalid_slot';
    END IF;
    UPDATE public.chick_pets SET style = v WHERE id = c.id;
    RETURN public.chick_wardrobe();
END $$;
REVOKE ALL ON FUNCTION public.chick_set_style(TEXT, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.chick_set_style(TEXT, TEXT, TEXT) TO authenticated;

-- F) Vardiya planlayıcı
CREATE TABLE IF NOT EXISTS public.user_shifts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    room_id UUID REFERENCES public.rooms(id) ON DELETE SET NULL,
    shift_date DATE NOT NULL,
    shift_code TEXT NOT NULL CHECK (shift_code IN ('morning_08_16', 'evening_16_00', 'night_00_08', 'custom', 'off_day', 'annual_leave', 'overtime')),
    starts_at TIMESTAMPTZ,
    ends_at TIMESTAMPTZ,
    note TEXT NOT NULL DEFAULT '' CHECK (LENGTH(note) <= 500),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT user_shifts_one_per_day UNIQUE (user_id, shift_date),
    CONSTRAINT user_shifts_range CHECK (ends_at IS NULL OR starts_at IS NULL OR ends_at > starts_at)
);
CREATE INDEX IF NOT EXISTS idx_user_shifts_room_date ON public.user_shifts (room_id, shift_date) WHERE room_id IS NOT NULL;
ALTER TABLE public.user_shifts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS user_shifts_select ON public.user_shifts;
CREATE POLICY user_shifts_select ON public.user_shifts FOR SELECT TO authenticated
    USING (user_id = auth.uid() OR (room_id IS NOT NULL AND public.is_room_member(room_id)));
DROP POLICY IF EXISTS user_shifts_insert_own ON public.user_shifts;
CREATE POLICY user_shifts_insert_own ON public.user_shifts FOR INSERT TO authenticated
    WITH CHECK (user_id = auth.uid() AND (room_id IS NULL OR public.is_room_member(room_id)));
DROP POLICY IF EXISTS user_shifts_update_own ON public.user_shifts;
CREATE POLICY user_shifts_update_own ON public.user_shifts FOR UPDATE TO authenticated
    USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid() AND (room_id IS NULL OR public.is_room_member(room_id)));
DROP POLICY IF EXISTS user_shifts_delete_own ON public.user_shifts;
CREATE POLICY user_shifts_delete_own ON public.user_shifts FOR DELETE TO authenticated USING (user_id = auth.uid());
GRANT SELECT, INSERT, UPDATE, DELETE ON public.user_shifts TO authenticated;

-- G) Sohbet etkinlikleri
CREATE TABLE IF NOT EXISTS public.room_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    room_id UUID NOT NULL REFERENCES public.rooms(id) ON DELETE CASCADE,
    creator_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    message_id UUID REFERENCES public.messages(id) ON DELETE SET NULL,
    title TEXT NOT NULL CHECK (LENGTH(BTRIM(title)) BETWEEN 1 AND 150),
    description TEXT NOT NULL DEFAULT '' CHECK (LENGTH(description) <= 1000),
    starts_at TIMESTAMPTZ NOT NULL,
    remind_minutes INTEGER NOT NULL DEFAULT 15 CHECK (remind_minutes BETWEEN 0 AND 10080),
    reminded_at TIMESTAMPTZ,
    cancelled BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_room_events_due ON public.room_events (starts_at) WHERE reminded_at IS NULL AND NOT cancelled;
CREATE TABLE IF NOT EXISTS public.room_event_rsvps (
    event_id UUID NOT NULL REFERENCES public.room_events(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    status TEXT NOT NULL CHECK (status IN ('going', 'maybe', 'declined')),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (event_id, user_id)
);
ALTER TABLE public.room_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.room_event_rsvps ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS room_events_member_select ON public.room_events;
CREATE POLICY room_events_member_select ON public.room_events FOR SELECT TO authenticated USING (public.is_room_member(room_id));
DROP POLICY IF EXISTS room_event_rsvps_member_select ON public.room_event_rsvps;
CREATE POLICY room_event_rsvps_member_select ON public.room_event_rsvps FOR SELECT TO authenticated
    USING (EXISTS (SELECT 1 FROM public.room_events e WHERE e.id = event_id AND public.is_room_member(e.room_id)));
REVOKE INSERT, UPDATE, DELETE ON public.room_events, public.room_event_rsvps FROM anon, authenticated;
GRANT SELECT ON public.room_events, public.room_event_rsvps TO authenticated;

-- Etkinlik yalnız GRUPLARDA (gruplar E2EE değildir; birebirde şifresiz etkinlik metni oluşturulmaz)
CREATE OR REPLACE FUNCTION public.create_room_event(p_room UUID, p_title TEXT, p_starts_at TIMESTAMPTZ,
                                                    p_description TEXT DEFAULT '', p_remind_minutes INTEGER DEFAULT 15)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid UUID := auth.uid(); v_id UUID; v_msg UUID;
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
    IF NOT EXISTS (SELECT 1 FROM public.rooms WHERE id = p_room AND is_group) THEN RAISE EXCEPTION 'event_group_only'; END IF;
    IF NOT public.juzzio_can_post(p_room, v_uid) THEN RAISE EXCEPTION 'not_allowed'; END IF;
    IF p_starts_at IS NULL OR p_starts_at < NOW() - INTERVAL '5 minutes' THEN RAISE EXCEPTION 'event_in_past'; END IF;
    INSERT INTO public.room_events (room_id, creator_id, title, description, starts_at, remind_minutes)
    VALUES (p_room, v_uid, LEFT(BTRIM(p_title), 150), LEFT(COALESCE(p_description, ''), 1000), p_starts_at,
            LEAST(GREATEST(COALESCE(p_remind_minutes, 15), 0), 10080))
    RETURNING id INTO v_id;
    INSERT INTO public.messages (room_id, sender_id, message_type, original_text, metadata)
    VALUES (p_room, v_uid, 'text', '📅 ' || LEFT(BTRIM(p_title), 150), jsonb_build_object('event_id', v_id))
    RETURNING id INTO v_msg;
    UPDATE public.room_events SET message_id = v_msg WHERE id = v_id;
    INSERT INTO public.room_event_rsvps (event_id, user_id, status) VALUES (v_id, v_uid, 'going');
    RETURN v_id;
END $$;
REVOKE ALL ON FUNCTION public.create_room_event(UUID, TEXT, TIMESTAMPTZ, TEXT, INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_room_event(UUID, TEXT, TIMESTAMPTZ, TEXT, INTEGER) TO authenticated;

CREATE OR REPLACE FUNCTION public.rsvp_room_event(p_event UUID, p_status TEXT)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE e public.room_events;
BEGIN
    SELECT * INTO e FROM public.room_events WHERE id = p_event;
    IF e.id IS NULL OR auth.uid() IS NULL OR NOT public.is_room_member(e.room_id) THEN RAISE EXCEPTION 'not_allowed'; END IF;
    IF p_status NOT IN ('going', 'maybe', 'declined') THEN RAISE EXCEPTION 'invalid_status'; END IF;
    INSERT INTO public.room_event_rsvps (event_id, user_id, status) VALUES (p_event, auth.uid(), p_status)
    ON CONFLICT (event_id, user_id) DO UPDATE SET status = EXCLUDED.status, updated_at = NOW();
    RETURN true;
END $$;
REVOKE ALL ON FUNCTION public.rsvp_room_event(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rsvp_room_event(UUID, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.room_event_details(p_event UUID)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE e public.room_events;
BEGIN
    SELECT * INTO e FROM public.room_events WHERE id = p_event;
    IF e.id IS NULL OR NOT public.is_room_member(e.room_id) THEN RAISE EXCEPTION 'not_allowed'; END IF;
    RETURN jsonb_build_object('id', e.id, 'title', e.title, 'description', e.description, 'starts_at', e.starts_at,
        'cancelled', e.cancelled, 'mine_creator', e.creator_id = auth.uid(),
        'going', (SELECT COUNT(*) FROM public.room_event_rsvps WHERE event_id = e.id AND status = 'going'),
        'maybe', (SELECT COUNT(*) FROM public.room_event_rsvps WHERE event_id = e.id AND status = 'maybe'),
        'declined', (SELECT COUNT(*) FROM public.room_event_rsvps WHERE event_id = e.id AND status = 'declined'),
        'my_status', (SELECT status FROM public.room_event_rsvps WHERE event_id = e.id AND user_id = auth.uid()));
END $$;
REVOKE ALL ON FUNCTION public.room_event_details(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.room_event_details(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.cancel_room_event(p_event UUID)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_n INT;
BEGIN
    UPDATE public.room_events SET cancelled = true WHERE id = p_event AND creator_id = auth.uid() AND NOT cancelled;
    GET DIAGNOSTICS v_n = ROW_COUNT; RETURN v_n > 0;
END $$;
REVOKE ALL ON FUNCTION public.cancel_room_event(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cancel_room_event(UUID) TO authenticated;

-- Hatırlatma: başlangıçtan remind_minutes önce, katılmayacağını söylemeyen tüm üyelere
CREATE OR REPLACE FUNCTION public.juzzio_fire_event_reminders(p_limit INTEGER DEFAULT 200)
RETURNS INTEGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE r RECORD; v_n INTEGER := 0;
BEGIN
    FOR r IN
        SELECT e.* FROM public.room_events e
         WHERE e.reminded_at IS NULL AND NOT e.cancelled
           AND e.starts_at - make_interval(mins => e.remind_minutes) <= NOW()
           AND e.starts_at > NOW() - INTERVAL '1 hour'
         ORDER BY e.starts_at
         LIMIT LEAST(GREATEST(COALESCE(p_limit, 200), 1), 1000)
         FOR UPDATE SKIP LOCKED
    LOOP
        UPDATE public.room_events SET reminded_at = NOW() WHERE id = r.id;
        INSERT INTO public.notifications (recipient_id, actor_id, actor_username, actor_display_name,
                                          event_type, target_id, target_secondary_id, preview_text, dedupe_key)
        SELECT rp.user_id, NULL, '', 'Juzzio', 'reminder', r.room_id::text, COALESCE(r.message_id::text, r.id::text),
               'event|' || LEFT(r.title, 120), 'event_' || r.id::text
          FROM public.room_participants rp
         WHERE rp.room_id = r.room_id
           AND NOT EXISTS (SELECT 1 FROM public.room_event_rsvps v WHERE v.event_id = r.id AND v.user_id = rp.user_id AND v.status = 'declined')
        ON CONFLICT (recipient_id, dedupe_key) DO NOTHING;
        v_n := v_n + 1;
    END LOOP;
    RETURN v_n;
END $$;
REVOKE ALL ON FUNCTION public.juzzio_fire_event_reminders(INTEGER) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.juzzio_fire_event_reminders(INTEGER) TO service_role;
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        BEGIN
            PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'juzzio_fire_event_reminders';
            PERFORM cron.schedule('juzzio_fire_event_reminders', '* * * * *', 'SELECT public.juzzio_fire_event_reminders()');
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'pg_cron görevi (juzzio_fire_event_reminders) oluşturulamadı: %', SQLERRM;
        END;
    END IF;
END $$;

-- =============================================================================
-- 10.27 v0.9.5 — Tek seferlik medya, anket kapanış özeti, anılar, seriler/rozetler,
--   güven puanı, Watch Party, güvenli takip (SOS), anonim soru kutusu
-- =============================================================================
ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_event_type_check;
ALTER TABLE public.notifications ADD CONSTRAINT notifications_event_type_check CHECK (event_type = ANY (ARRAY[
    'like', 'comment', 'reply', 'follow', 'follow_request', 'follow_accepted', 'friend_request',
    'friend_accepted', 'story_like', 'story_reply', 'message', 'missed_call', 'incoming_call',
    'group_activity', 'system', 'chick_invite', 'chick_hatched', 'chick_hungry', 'chick_dying',
    'chick_died', 'reaction', 'save', 'mention', 'reminder', 'comment_like',
    'poll_closed', 'memory', 'sos', 'qa_question', 'qa_answer', 'watch_party'
])) NOT VALID;

-- ---- A) Tek seferlik (view once) medya -------------------------------------------
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS is_view_once BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS view_once_opened_at TIMESTAMPTZ;

-- Alıcı açar: bir kez. Gönderen kendi tek seferlik medyasını açamaz (WhatsApp ile aynı).
CREATE OR REPLACE FUNCTION public.open_view_once(p_message UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE m public.messages;
BEGIN
    SELECT * INTO m FROM public.messages WHERE id = p_message FOR UPDATE;
    IF m.id IS NULL OR auth.uid() IS NULL OR NOT public.is_room_member(m.room_id) THEN RAISE EXCEPTION 'not_allowed'; END IF;
    IF NOT m.is_view_once THEN RAISE EXCEPTION 'not_view_once'; END IF;
    IF m.sender_id = auth.uid() THEN RAISE EXCEPTION 'view_once_sender'; END IF;
    IF m.view_once_opened_at IS NOT NULL OR (m.image_url IS NULL AND m.video_url IS NULL) THEN
        RAISE EXCEPTION 'view_once_already_opened';
    END IF;
    UPDATE public.messages SET view_once_opened_at = NOW() WHERE id = m.id;
    RETURN jsonb_build_object('image_url', m.image_url, 'video_url', m.video_url);
END $$;
REVOKE ALL ON FUNCTION public.open_view_once(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.open_view_once(UUID) TO authenticated;

-- Görüntüleme bitti (veya süre doldu): adres silinir, dosya buluttan kalıcı temizlenir
CREATE OR REPLACE FUNCTION public.juzzio_purge_view_once(p_message UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE m public.messages; r RECORD;
BEGIN
    SELECT * INTO m FROM public.messages WHERE id = p_message FOR UPDATE;
    IF m.id IS NULL OR NOT m.is_view_once THEN RETURN; END IF;
    FOR r IN SELECT * FROM public.juzzio_storage_ref_from_url(m.image_url)
             UNION ALL SELECT * FROM public.juzzio_storage_ref_from_url(m.video_url) LOOP
        PERFORM public.juzzio_enqueue_storage_cleanup(r.bucket, r.object_name, 'view_once');
    END LOOP;
    UPDATE public.messages
       SET image_url = NULL, video_url = NULL,
           metadata = COALESCE(metadata, '{}'::jsonb) - 'media_e2ee',
           view_once_opened_at = COALESCE(view_once_opened_at, NOW())
     WHERE id = m.id;
END $$;
REVOKE ALL ON FUNCTION public.juzzio_purge_view_once(UUID) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.finish_view_once(p_message UUID)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE m public.messages;
BEGIN
    SELECT * INTO m FROM public.messages WHERE id = p_message;
    IF m.id IS NULL OR NOT public.is_room_member(m.room_id) OR m.sender_id = auth.uid() THEN RAISE EXCEPTION 'not_allowed'; END IF;
    IF m.view_once_opened_at IS NULL THEN RAISE EXCEPTION 'view_once_not_opened'; END IF;
    PERFORM public.juzzio_purge_view_once(m.id);
    RETURN true;
END $$;
REVOKE ALL ON FUNCTION public.finish_view_once(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.finish_view_once(UUID) TO authenticated;

-- Açılıp 5 dk içinde kapatılmayan (uygulama kapandı vb.) ya da 14 gün açılmayan medya temizlenir
CREATE OR REPLACE FUNCTION public.juzzio_purge_stale_view_once()
RETURNS INTEGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE r RECORD; v_n INTEGER := 0;
BEGIN
    FOR r IN SELECT id FROM public.messages
              WHERE is_view_once AND (image_url IS NOT NULL OR video_url IS NOT NULL)
                AND ((view_once_opened_at IS NOT NULL AND view_once_opened_at < NOW() - INTERVAL '5 minutes')
                     OR created_at < NOW() - INTERVAL '14 days')
              LIMIT 500 LOOP
        PERFORM public.juzzio_purge_view_once(r.id);
        v_n := v_n + 1;
    END LOOP;
    RETURN v_n;
END $$;
REVOKE ALL ON FUNCTION public.juzzio_purge_stale_view_once() FROM PUBLIC, anon, authenticated;

-- Gönderen dışında kimse is_view_once bayrağını değiştiremez; gönderildikten sonra kaldırılamaz
CREATE OR REPLACE FUNCTION public.juzzio_guard_view_once()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
    IF TG_OP = 'UPDATE' AND public.juzzio_is_client_request() THEN
        NEW.is_view_once := OLD.is_view_once;
        NEW.view_once_opened_at := OLD.view_once_opened_at;
    END IF;
    IF TG_OP = 'INSERT' AND NEW.is_view_once AND NEW.image_url IS NULL AND NEW.video_url IS NULL THEN
        NEW.is_view_once := false;
    END IF;
    RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_juzzio_guard_view_once ON public.messages;
CREATE TRIGGER trg_juzzio_guard_view_once BEFORE INSERT OR UPDATE ON public.messages
    FOR EACH ROW EXECUTE FUNCTION public.juzzio_guard_view_once();

-- ---- B) Anket kapanış özeti + son tarih ------------------------------------------
ALTER TABLE public.polls ADD COLUMN IF NOT EXISTS closes_at TIMESTAMPTZ;
CREATE OR REPLACE FUNCTION public.poll_set_deadline(p_poll UUID, p_closes_at TIMESTAMPTZ)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_n INT;
BEGIN
    IF p_closes_at IS NOT NULL AND p_closes_at < NOW() + INTERVAL '1 minute' THEN RAISE EXCEPTION 'poll_deadline_past'; END IF;
    UPDATE public.polls SET closes_at = p_closes_at WHERE id = p_poll AND created_by = auth.uid() AND NOT closed;
    GET DIAGNOSTICS v_n = ROW_COUNT; RETURN v_n > 0;
END $$;
REVOKE ALL ON FUNCTION public.poll_set_deadline(UUID, TIMESTAMPTZ) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.poll_set_deadline(UUID, TIMESTAMPTZ) TO authenticated;

-- Kazanan: en çok oy (eşitlikte birden çok seçenek ' / ' ile)
CREATE OR REPLACE FUNCTION public.juzzio_poll_summary(p_poll UUID)
RETURNS TEXT LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    WITH p AS (SELECT * FROM public.polls WHERE id = p_poll),
    c AS (SELECT i, (SELECT COUNT(*) FROM public.poll_votes v WHERE v.poll_id = p_poll AND v.option_idx = i) AS n
            FROM p, generate_series(0, jsonb_array_length(p.options) - 1) i),
    mx AS (SELECT MAX(n) AS m, SUM(n) AS t FROM c)
    SELECT CASE WHEN (SELECT m FROM mx) = 0 THEN ''
                ELSE (SELECT string_agg(p.options ->> c.i, ' / ' ORDER BY c.i) FROM p, c, mx WHERE c.n = mx.m)
                     || '|' || (SELECT m FROM mx) || '|' || (SELECT t FROM mx) END;
$$;
REVOKE ALL ON FUNCTION public.juzzio_poll_summary(UUID) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.juzzio_notify_poll_closed()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF NEW.closed AND NOT OLD.closed THEN
        INSERT INTO public.notifications (recipient_id, actor_id, actor_username, actor_display_name,
                                          event_type, target_id, target_secondary_id, preview_text, dedupe_key)
        SELECT rp.user_id, NEW.created_by, '', 'Juzzio', 'poll_closed', NEW.room_id::text, COALESCE(NEW.message_id::text, NEW.id::text),
               'poll|' || LEFT(NEW.question, 120) || '|' || public.juzzio_poll_summary(NEW.id),
               'poll_closed_' || NEW.id::text
          FROM public.room_participants rp
         WHERE rp.room_id = NEW.room_id AND rp.left_at IS NULL
        ON CONFLICT (recipient_id, dedupe_key) DO NOTHING;
    END IF;
    RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_juzzio_notify_poll_closed ON public.polls;
CREATE TRIGGER trg_juzzio_notify_poll_closed AFTER UPDATE OF closed ON public.polls
    FOR EACH ROW EXECUTE FUNCTION public.juzzio_notify_poll_closed();

CREATE OR REPLACE FUNCTION public.juzzio_close_due_polls()
RETURNS INTEGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_n INT;
BEGIN
    UPDATE public.polls SET closed = true WHERE NOT closed AND closes_at IS NOT NULL AND closes_at <= NOW();
    GET DIAGNOSTICS v_n = ROW_COUNT; RETURN v_n;
END $$;
REVOKE ALL ON FUNCTION public.juzzio_close_due_polls() FROM PUBLIC, anon, authenticated;

-- ---- C) Anılar: "Bugün 1 yıl önce" ---------------------------------------------
CREATE OR REPLACE FUNCTION public.juzzio_fire_memories()
RETURNS INTEGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_n INTEGER;
BEGIN
    INSERT INTO public.notifications (recipient_id, actor_id, actor_username, actor_display_name,
                                      event_type, target_id, target_secondary_id, preview_text, dedupe_key)
    SELECT p.author_id, NULL, '', 'Juzzio', 'memory', p.id::text, '',
           'memory|' || (EXTRACT(YEAR FROM NOW()) - EXTRACT(YEAR FROM p.created_at))::int || '|' || LEFT(COALESCE(p.caption, ''), 100),
           'memory_' || p.id::text || '_' || EXTRACT(YEAR FROM NOW())::int
      FROM public.posts p
     WHERE NOT p.is_deleted
       AND EXTRACT(MONTH FROM p.created_at) = EXTRACT(MONTH FROM NOW())
       AND EXTRACT(DAY FROM p.created_at) = EXTRACT(DAY FROM NOW())
       AND p.created_at < date_trunc('day', NOW()) - INTERVAL '300 days'
       AND p.id = (SELECT p2.id FROM public.posts p2 WHERE p2.author_id = p.author_id AND NOT p2.is_deleted
                     AND EXTRACT(MONTH FROM p2.created_at) = EXTRACT(MONTH FROM NOW())
                     AND EXTRACT(DAY FROM p2.created_at) = EXTRACT(DAY FROM NOW())
                     AND p2.created_at < date_trunc('day', NOW()) - INTERVAL '300 days'
                   ORDER BY p2.created_at DESC LIMIT 1)
    ON CONFLICT (recipient_id, dedupe_key) DO NOTHING;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    RETURN v_n;
END $$;
REVOKE ALL ON FUNCTION public.juzzio_fire_memories() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.my_memories()
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT COALESCE(jsonb_agg(jsonb_build_object('post_id', p.id, 'caption', p.caption, 'media_urls', p.media_urls,
                                                 'created_at', p.created_at) ORDER BY p.created_at DESC), '[]'::jsonb)
      FROM public.posts p
     WHERE p.author_id = auth.uid() AND NOT p.is_deleted
       AND EXTRACT(MONTH FROM p.created_at) = EXTRACT(MONTH FROM NOW())
       AND EXTRACT(DAY FROM p.created_at) = EXTRACT(DAY FROM NOW())
       AND p.created_at < date_trunc('day', NOW()) - INTERVAL '300 days';
$$;
REVOKE ALL ON FUNCTION public.my_memories() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.my_memories() TO authenticated;

-- ---- D) Seriler + rozetler -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.user_streaks (
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    kind TEXT NOT NULL CHECK (kind IN ('daily_app', 'chick_care')),
    current_count INTEGER NOT NULL DEFAULT 1 CHECK (current_count >= 0),
    longest_count INTEGER NOT NULL DEFAULT 1 CHECK (longest_count >= 0),
    last_date DATE NOT NULL,
    PRIMARY KEY (user_id, kind)
);
ALTER TABLE public.user_streaks ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS user_streaks_own ON public.user_streaks;
CREATE POLICY user_streaks_own ON public.user_streaks FOR SELECT TO authenticated USING (user_id = auth.uid());
REVOKE INSERT, UPDATE, DELETE ON public.user_streaks FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.juzzio_bump_streak(p_user UUID, p_kind TEXT, p_day DATE)
RETURNS INTEGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE s public.user_streaks;
BEGIN
    SELECT * INTO s FROM public.user_streaks WHERE user_id = p_user AND kind = p_kind FOR UPDATE;
    IF s.user_id IS NULL THEN
        INSERT INTO public.user_streaks (user_id, kind, current_count, longest_count, last_date) VALUES (p_user, p_kind, 1, 1, p_day);
        RETURN 1;
    END IF;
    IF p_day <= s.last_date THEN RETURN s.current_count; END IF;
    IF p_day = s.last_date + 1 THEN s.current_count := s.current_count + 1; ELSE s.current_count := 1; END IF;
    UPDATE public.user_streaks SET current_count = s.current_count, longest_count = GREATEST(longest_count, s.current_count), last_date = p_day
     WHERE user_id = p_user AND kind = p_kind;
    RETURN s.current_count;
END $$;
REVOKE ALL ON FUNCTION public.juzzio_bump_streak(UUID, TEXT, DATE) FROM PUBLIC, anon, authenticated;

-- Gün, kullanıcının saat dilimine göre (geçersiz dilim → Europe/Istanbul); tarih SUNUCU saatinden
CREATE OR REPLACE FUNCTION public.touch_daily_streak(p_tz TEXT DEFAULT 'Europe/Istanbul')
RETURNS INTEGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_tz TEXT := 'Europe/Istanbul';
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
    IF EXISTS (SELECT 1 FROM pg_timezone_names WHERE name = p_tz) THEN v_tz := p_tz; END IF;
    RETURN public.juzzio_bump_streak(auth.uid(), 'daily_app', (NOW() AT TIME ZONE v_tz)::date);
END $$;
REVOKE ALL ON FUNCTION public.touch_daily_streak(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.touch_daily_streak(TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.juzzio_chick_care_streak()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    PERFORM public.juzzio_bump_streak(NEW.fed_by, 'chick_care', (NEW.fed_at AT TIME ZONE 'Europe/Istanbul')::date);
    RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_juzzio_chick_care_streak ON public.chick_feed_log;
CREATE TRIGGER trg_juzzio_chick_care_streak AFTER INSERT ON public.chick_feed_log
    FOR EACH ROW EXECUTE FUNCTION public.juzzio_chick_care_streak();

-- Rozetler veriden hesaplanır (sahte rozet yazılamaz)
CREATE OR REPLACE FUNCTION public.user_badges(p_user UUID DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE u UUID := COALESCE(p_user, auth.uid()); v JSONB := '[]'::jsonb; n INTEGER;
BEGIN
    IF u IS NULL OR public.is_blocked_between(auth.uid(), u) THEN RETURN v; END IF;
    SELECT COALESCE(MAX(longest_count), 0) INTO n FROM public.user_streaks WHERE user_id = u AND kind = 'daily_app';
    IF n >= 7 THEN v := v || '["streak_7"]'; END IF;
    IF n >= 30 THEN v := v || '["streak_30"]'; END IF;
    IF n >= 100 THEN v := v || '["streak_100"]'; END IF;
    SELECT COALESCE(MAX(longest_count), 0) INTO n FROM public.user_streaks WHERE user_id = u AND kind = 'chick_care';
    IF n >= 7 THEN v := v || '["chick_carer"]'; END IF;
    IF EXISTS (SELECT 1 FROM public.chick_pets WHERE u IN (owner_a, owner_b) AND stage >= 3) THEN v := v || '["chick_adult"]'; END IF;
    SELECT COUNT(*) INTO n FROM (SELECT 1 FROM public.friendships WHERE status = 'accepted' AND u IN (requester_id, receiver_id) LIMIT 50) x;
    IF n >= 10 THEN v := v || '["social_10"]'; END IF;
    IF n >= 50 THEN v := v || '["social_50"]'; END IF;
    SELECT COUNT(*) INTO n FROM (SELECT 1 FROM public.posts WHERE author_id = u AND NOT is_deleted LIMIT 25) x;
    IF n >= 1 THEN v := v || '["first_post"]'; END IF;
    IF n >= 25 THEN v := v || '["creator_25"]'; END IF;
    IF EXISTS (SELECT 1 FROM public.profiles WHERE id = u AND created_at < NOW() - INTERVAL '365 days') THEN v := v || '["veteran"]'; END IF;
    RETURN v;
END $$;
REVOKE ALL ON FUNCTION public.user_badges(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.user_badges(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.my_streaks()
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT COALESCE(jsonb_object_agg(kind, jsonb_build_object('current', current_count, 'longest', longest_count, 'last_date', last_date)), '{}'::jsonb)
      FROM public.user_streaks WHERE user_id = auth.uid();
$$;
REVOKE ALL ON FUNCTION public.my_streaks() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.my_streaks() TO authenticated;

-- ---- E) Güven puanı (0-100) --------------------------------------------------------
--  Kurallar (şeffaf): 70 taban + hesap yaşı (≤15) + doğrulanmış e-posta/mavi tik (5)
--  − 30 gün içindeki her ayrı şikâyetçi kişi 8 (≤40) − son 90 gündeki geri alınmamış ihlal başına 20.
CREATE OR REPLACE FUNCTION public.juzzio_trust_score(p_user UUID)
RETURNS INTEGER LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT GREATEST(0, LEAST(100,
        70
      + LEAST(15, (EXTRACT(EPOCH FROM (NOW() - COALESCE((SELECT created_at FROM public.profiles WHERE id = p_user), NOW()))) / 86400 / 12)::int)
      + CASE WHEN COALESCE((SELECT is_verified FROM public.profiles WHERE id = p_user), false) THEN 5 ELSE 0 END
      - LEAST(40, 8 * (SELECT COUNT(DISTINCT reporter_id) FROM public.reports
                        WHERE target_type = 'user' AND target_id = p_user::text AND created_at > NOW() - INTERVAL '30 days'))
      - 20 * (SELECT COUNT(*) FROM public.moderation_strikes WHERE user_id = p_user AND NOT revoked AND created_at > NOW() - INTERVAL '90 days')
    ))::int;
$$;
REVOKE ALL ON FUNCTION public.juzzio_trust_score(UUID) FROM PUBLIC, anon, authenticated;

-- Yönetici: güven puanı en düşük kullanıcılar (moderasyon önceliği)
CREATE OR REPLACE FUNCTION public.admin_trust_list(p_token TEXT, p_limit INTEGER DEFAULT 50)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
    PERFORM public._staff_require(p_token, 'reports');
    RETURN COALESCE((SELECT jsonb_agg(x ORDER BY (x->>'score')::int, x->>'username') FROM (
        SELECT jsonb_build_object('user_id', p.id, 'username', p.username, 'display_name', p.display_name,
                                  'score', public.juzzio_trust_score(p.id)) AS x
          FROM public.profiles p
         WHERE p.id IN (SELECT r.target_id::uuid FROM public.reports r
                         WHERE r.target_type = 'user' AND r.target_id ~ '^[0-9a-f-]{36}$' AND r.created_at > NOW() - INTERVAL '30 days'
                        UNION SELECT user_id FROM public.moderation_strikes WHERE NOT revoked AND created_at > NOW() - INTERVAL '90 days')
         LIMIT LEAST(GREATEST(COALESCE(p_limit, 50), 1), 200)) t), '[]'::jsonb);
END $$;
REVOKE ALL ON FUNCTION public.admin_trust_list(TEXT, INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_trust_list(TEXT, INTEGER) TO authenticated;

-- Düşük güven: puanı < 30 olan hesap günde en fazla 3 gönderi paylaşabilir
CREATE OR REPLACE FUNCTION public.juzzio_is_low_trust(p_user UUID)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT public.juzzio_trust_score(p_user) < 30;
$$;
REVOKE ALL ON FUNCTION public.juzzio_is_low_trust(UUID) FROM PUBLIC, anon, authenticated;
CREATE OR REPLACE FUNCTION public.juzzio_low_trust_post_guard()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF public.juzzio_is_client_request() AND public.juzzio_is_low_trust(NEW.author_id)
       AND (SELECT COUNT(*) FROM public.posts WHERE author_id = NEW.author_id AND created_at > NOW() - INTERVAL '1 day') >= 3 THEN
        RAISE EXCEPTION 'low_trust_limited' USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_juzzio_low_trust_post_guard ON public.posts;
CREATE TRIGGER trg_juzzio_low_trust_post_guard BEFORE INSERT ON public.posts
    FOR EACH ROW EXECUTE FUNCTION public.juzzio_low_trust_post_guard();

-- ---- H) Watch Party (senkron izleme) ------------------------------------------------
CREATE TABLE IF NOT EXISTS public.watch_party_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    room_id UUID NOT NULL REFERENCES public.rooms(id) ON DELETE CASCADE,
    host_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    media_url TEXT NOT NULL CHECK (media_url ~* '^https://' AND char_length(media_url) <= 2000),
    media_title TEXT NOT NULL DEFAULT '' CHECK (char_length(media_title) <= 150),
    source_kind TEXT NOT NULL DEFAULT 'direct' CHECK (source_kind IN ('direct', 'hls', 'web')),
    is_playing BOOLEAN NOT NULL DEFAULT false,
    position_ms BIGINT NOT NULL DEFAULT 0 CHECK (position_ms >= 0),
    playback_rate NUMERIC(3,2) NOT NULL DEFAULT 1.00 CHECK (playback_rate BETWEEN 0.25 AND 2.00),
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'ended')),
    state_changed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_watch_party_active_room ON public.watch_party_sessions (room_id) WHERE status = 'active';
ALTER TABLE public.watch_party_sessions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS watch_party_member_select ON public.watch_party_sessions;
CREATE POLICY watch_party_member_select ON public.watch_party_sessions FOR SELECT TO authenticated USING (public.is_room_member(room_id));
REVOKE INSERT, UPDATE, DELETE ON public.watch_party_sessions FROM anon, authenticated;
GRANT SELECT ON public.watch_party_sessions TO authenticated;
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime')
       AND NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'watch_party_sessions') THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.watch_party_sessions;
    END IF;
END $$;

CREATE OR REPLACE FUNCTION public.start_watch_party(p_room UUID, p_url TEXT, p_title TEXT DEFAULT '')
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid UUID := auth.uid(); v_id UUID; v_url TEXT := BTRIM(COALESCE(p_url, '')); v_kind TEXT;
BEGIN
    IF v_uid IS NULL OR NOT public.juzzio_can_post(p_room, v_uid) THEN RAISE EXCEPTION 'not_allowed'; END IF;
    IF v_url !~* '^https://[^\s/$.?#].[^\s]*$' OR char_length(v_url) > 2000 THEN RAISE EXCEPTION 'watch_party_invalid_url'; END IF;
    v_kind := CASE WHEN v_url ~* '\.m3u8(\?|$)' THEN 'hls'
                   WHEN v_url ~* '\.(mp4|webm|mov|m4v|mkv)(\?|$)' THEN 'direct'
                   ELSE 'web' END;
    UPDATE public.watch_party_sessions SET status = 'ended', state_changed_at = NOW() WHERE room_id = p_room AND status = 'active';
    INSERT INTO public.watch_party_sessions (room_id, host_id, media_url, media_title, source_kind)
    VALUES (p_room, v_uid, v_url, LEFT(COALESCE(BTRIM(p_title), ''), 150), v_kind)
    RETURNING id INTO v_id;
    INSERT INTO public.notifications (recipient_id, actor_id, actor_username, actor_display_name,
                                      event_type, target_id, target_secondary_id, preview_text, dedupe_key)
    SELECT rp.user_id, v_uid, COALESCE(pr.username, ''), COALESCE(pr.display_name, ''), 'watch_party', p_room::text, v_id::text,
           'watch|' || LEFT(COALESCE(NULLIF(BTRIM(p_title), ''), 'Film'), 100), 'watch_' || v_id::text
      FROM public.room_participants rp LEFT JOIN public.profiles pr ON pr.id = v_uid
     WHERE rp.room_id = p_room AND rp.left_at IS NULL AND rp.user_id <> v_uid
    ON CONFLICT (recipient_id, dedupe_key) DO NOTHING;
    RETURN v_id;
END $$;
REVOKE ALL ON FUNCTION public.start_watch_party(UUID, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.start_watch_party(UUID, TEXT, TEXT) TO authenticated;

-- Oynat/duraklat/sar: yalnız ev sahibi (diğerleri sunucu zamanına göre senkron kalır)
CREATE OR REPLACE FUNCTION public.watch_party_control(p_session UUID, p_playing BOOLEAN, p_position_ms BIGINT, p_rate NUMERIC DEFAULT 1.0)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE w public.watch_party_sessions;
BEGIN
    UPDATE public.watch_party_sessions
       SET is_playing = COALESCE(p_playing, is_playing),
           position_ms = GREATEST(0, COALESCE(p_position_ms, position_ms)),
           playback_rate = LEAST(2.0, GREATEST(0.25, COALESCE(p_rate, playback_rate))),
           state_changed_at = NOW()
     WHERE id = p_session AND host_id = auth.uid() AND status = 'active'
    RETURNING * INTO w;
    IF w.id IS NULL THEN RAISE EXCEPTION 'not_allowed'; END IF;
    RETURN jsonb_build_object('server_time', NOW(), 'position_ms', w.position_ms, 'is_playing', w.is_playing);
END $$;
REVOKE ALL ON FUNCTION public.watch_party_control(UUID, BOOLEAN, BIGINT, NUMERIC) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.watch_party_control(UUID, BOOLEAN, BIGINT, NUMERIC) TO authenticated;

CREATE OR REPLACE FUNCTION public.end_watch_party(p_session UUID)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_n INT;
BEGIN
    UPDATE public.watch_party_sessions SET status = 'ended', is_playing = false, state_changed_at = NOW()
     WHERE id = p_session AND status = 'active'
       AND (host_id = auth.uid() OR EXISTS (SELECT 1 FROM public.room_participants rp
                                            WHERE rp.room_id = watch_party_sessions.room_id AND rp.user_id = auth.uid() AND rp.role IN ('owner', 'moderator')));
    GET DIAGNOSTICS v_n = ROW_COUNT; RETURN v_n > 0;
END $$;
REVOKE ALL ON FUNCTION public.end_watch_party(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.end_watch_party(UUID) TO authenticated;

-- ---- I) Güvenli takip / SOS ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.safety_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    room_id UUID NOT NULL REFERENCES public.rooms(id) ON DELETE CASCADE,
    target_name TEXT NOT NULL DEFAULT '' CHECK (char_length(target_name) <= 120),
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'arrived_safe', 'sos_triggered', 'cancelled')),
    inactivity_limit_min INTEGER NOT NULL DEFAULT 15 CHECK (inactivity_limit_min BETWEEN 5 AND 180),
    last_lat DOUBLE PRECISION CHECK (last_lat BETWEEN -90 AND 90),
    last_lng DOUBLE PRECISION CHECK (last_lng BETWEEN -180 AND 180),
    last_battery SMALLINT CHECK (last_battery BETWEEN 0 AND 100),
    last_ping_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL,
    sos_reason TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_safety_active_user ON public.safety_sessions (user_id) WHERE status = 'active';
ALTER TABLE public.safety_sessions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS safety_sessions_visible ON public.safety_sessions;
CREATE POLICY safety_sessions_visible ON public.safety_sessions FOR SELECT TO authenticated
    USING (user_id = auth.uid() OR (status IN ('active', 'sos_triggered') AND public.is_room_member(room_id)));
REVOKE INSERT, UPDATE, DELETE ON public.safety_sessions FROM anon, authenticated;
GRANT SELECT ON public.safety_sessions TO authenticated;

CREATE OR REPLACE FUNCTION public.juzzio_safety_alert(p_session UUID, p_reason TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE s public.safety_sessions; v_link TEXT := ''; pr RECORD;
BEGIN
    UPDATE public.safety_sessions SET status = 'sos_triggered', sos_reason = LEFT(COALESCE(p_reason, ''), 40)
     WHERE id = p_session AND status = 'active' RETURNING * INTO s;
    IF s.id IS NULL THEN RETURN; END IF;
    SELECT username, display_name INTO pr FROM public.profiles WHERE id = s.user_id;
    IF s.last_lat IS NOT NULL THEN
        v_link := 'https://maps.google.com/?q=' || to_char(s.last_lat, 'FM990.000000') || ',' || to_char(s.last_lng, 'FM9990.000000');
    END IF;
    INSERT INTO public.notifications (recipient_id, actor_id, actor_username, actor_display_name,
                                      event_type, target_id, target_secondary_id, preview_text, dedupe_key)
    SELECT rp.user_id, s.user_id, COALESCE(pr.username, ''), COALESCE(pr.display_name, ''), 'sos', s.room_id::text, s.id::text,
           'sos|' || s.sos_reason || '|' || v_link || '|' || COALESCE(s.last_battery::text, ''), 'sos_' || s.id::text
      FROM public.room_participants rp
     WHERE rp.room_id = s.room_id AND rp.left_at IS NULL AND rp.user_id <> s.user_id
    ON CONFLICT (recipient_id, dedupe_key) DO NOTHING;
END $$;
REVOKE ALL ON FUNCTION public.juzzio_safety_alert(UUID, TEXT) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.start_safety_session(p_room UUID, p_minutes INTEGER, p_target TEXT DEFAULT '', p_inactivity_min INTEGER DEFAULT 15)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id UUID;
BEGIN
    IF auth.uid() IS NULL OR NOT public.is_room_member(p_room) THEN RAISE EXCEPTION 'not_allowed'; END IF;
    IF p_minutes IS NULL OR p_minutes NOT BETWEEN 5 AND 720 THEN RAISE EXCEPTION 'safety_invalid_duration'; END IF;
    UPDATE public.safety_sessions SET status = 'cancelled' WHERE user_id = auth.uid() AND status = 'active';
    INSERT INTO public.safety_sessions (user_id, room_id, target_name, inactivity_limit_min, expires_at)
    VALUES (auth.uid(), p_room, LEFT(COALESCE(BTRIM(p_target), ''), 120), LEAST(GREATEST(COALESCE(p_inactivity_min, 15), 5), 180),
            NOW() + make_interval(mins => p_minutes))
    RETURNING id INTO v_id;
    RETURN v_id;
END $$;
REVOKE ALL ON FUNCTION public.start_safety_session(UUID, INTEGER, TEXT, INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.start_safety_session(UUID, INTEGER, TEXT, INTEGER) TO authenticated;

CREATE OR REPLACE FUNCTION public.safety_ping(p_session UUID, p_lat DOUBLE PRECISION, p_lng DOUBLE PRECISION, p_battery INTEGER DEFAULT NULL, p_moved BOOLEAN DEFAULT true)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE s public.safety_sessions;
BEGIN
    IF p_lat NOT BETWEEN -90 AND 90 OR p_lng NOT BETWEEN -180 AND 180 THEN RAISE EXCEPTION 'invalid_location'; END IF;
    UPDATE public.safety_sessions
       SET last_lat = p_lat, last_lng = p_lng,
           last_battery = CASE WHEN p_battery BETWEEN 0 AND 100 THEN p_battery ELSE last_battery END,
           last_ping_at = CASE WHEN COALESCE(p_moved, true) THEN NOW() ELSE last_ping_at END
     WHERE id = p_session AND user_id = auth.uid() AND status = 'active'
    RETURNING * INTO s;
    IF s.id IS NULL THEN RETURN 'inactive'; END IF;
    IF s.last_battery IS NOT NULL AND s.last_battery <= 5 THEN
        PERFORM public.juzzio_safety_alert(s.id, 'battery');
        RETURN 'sos_triggered';
    END IF;
    RETURN 'active';
END $$;
REVOKE ALL ON FUNCTION public.safety_ping(UUID, DOUBLE PRECISION, DOUBLE PRECISION, INTEGER, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.safety_ping(UUID, DOUBLE PRECISION, DOUBLE PRECISION, INTEGER, BOOLEAN) TO authenticated;

CREATE OR REPLACE FUNCTION public.safety_finish(p_session UUID, p_arrived BOOLEAN)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_n INT;
BEGIN
    UPDATE public.safety_sessions SET status = CASE WHEN p_arrived THEN 'arrived_safe' ELSE 'cancelled' END
     WHERE id = p_session AND user_id = auth.uid() AND status IN ('active', 'sos_triggered');
    GET DIAGNOSTICS v_n = ROW_COUNT; RETURN v_n > 0;
END $$;
REVOKE ALL ON FUNCTION public.safety_finish(UUID, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.safety_finish(UUID, BOOLEAN) TO authenticated;

CREATE OR REPLACE FUNCTION public.safety_sos_now(p_session UUID)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.safety_sessions WHERE id = p_session AND user_id = auth.uid() AND status = 'active') THEN
        RAISE EXCEPTION 'not_allowed';
    END IF;
    PERFORM public.juzzio_safety_alert(p_session, 'manual');
    RETURN true;
END $$;
REVOKE ALL ON FUNCTION public.safety_sos_now(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.safety_sos_now(UUID) TO authenticated;

-- Süre doldu ama "vardım" denmedi ya da belirlenen süre boyunca hareket yok → otomatik SOS
CREATE OR REPLACE FUNCTION public.juzzio_check_safety_sessions()
RETURNS INTEGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE r RECORD; v_n INTEGER := 0;
BEGIN
    FOR r IN SELECT id, CASE WHEN expires_at <= NOW() THEN 'overdue' ELSE 'inactive' END AS why
               FROM public.safety_sessions
              WHERE status = 'active'
                AND (expires_at <= NOW() OR last_ping_at < NOW() - make_interval(mins => inactivity_limit_min))
              LIMIT 500 FOR UPDATE SKIP LOCKED LOOP
        PERFORM public.juzzio_safety_alert(r.id, r.why);
        v_n := v_n + 1;
    END LOOP;
    RETURN v_n;
END $$;
REVOKE ALL ON FUNCTION public.juzzio_check_safety_sessions() FROM PUBLIC, anon, authenticated;

-- ---- J) Anonim soru kutusu ---------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.qa_boxes (
    owner_id UUID PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
    title TEXT NOT NULL DEFAULT 'Bana bir şey sor' CHECK (char_length(BTRIM(title)) BETWEEN 1 AND 120),
    allow_anonymous BOOLEAN NOT NULL DEFAULT true,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TABLE IF NOT EXISTS public.qa_submissions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    box_owner UUID NOT NULL REFERENCES public.qa_boxes(owner_id) ON DELETE CASCADE,
    sender_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    is_anonymous BOOLEAN NOT NULL DEFAULT true,
    question_text TEXT NOT NULL CHECK (char_length(BTRIM(question_text)) BETWEEN 1 AND 500),
    answer_text TEXT NOT NULL DEFAULT '' CHECK (char_length(answer_text) <= 1000),
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'answered', 'rejected')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    answered_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_qa_submissions_box ON public.qa_submissions (box_owner, status, created_at DESC);
ALTER TABLE public.qa_boxes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.qa_submissions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS qa_boxes_read ON public.qa_boxes;
CREATE POLICY qa_boxes_read ON public.qa_boxes FOR SELECT TO authenticated
    USING (owner_id = auth.uid() OR (is_active AND NOT public.is_blocked_between(auth.uid(), owner_id)));
-- Gönderen kimliği tablodan HİÇ okunamaz (kutu sahibi dahil); erişim yalnız RPC'lerle
REVOKE ALL ON public.qa_submissions FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.qa_boxes FROM anon, authenticated;
GRANT SELECT ON public.qa_boxes TO authenticated;

CREATE OR REPLACE FUNCTION public.qa_setup_box(p_title TEXT, p_allow_anonymous BOOLEAN DEFAULT true, p_active BOOLEAN DEFAULT true)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
    INSERT INTO public.qa_boxes (owner_id, title, allow_anonymous, is_active)
    VALUES (auth.uid(), LEFT(COALESCE(NULLIF(BTRIM(p_title), ''), 'Bana bir şey sor'), 120), COALESCE(p_allow_anonymous, true), COALESCE(p_active, true))
    ON CONFLICT (owner_id) DO UPDATE SET title = EXCLUDED.title, allow_anonymous = EXCLUDED.allow_anonymous, is_active = EXCLUDED.is_active;
    RETURN true;
END $$;
REVOKE ALL ON FUNCTION public.qa_setup_box(TEXT, BOOLEAN, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.qa_setup_box(TEXT, BOOLEAN, BOOLEAN) TO authenticated;

CREATE OR REPLACE FUNCTION public.qa_ask(p_owner UUID, p_text TEXT, p_anonymous BOOLEAN DEFAULT true)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE b public.qa_boxes; v_id UUID; v_anon BOOLEAN; pr RECORD;
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
    SELECT * INTO b FROM public.qa_boxes WHERE owner_id = p_owner AND is_active;
    IF b.owner_id IS NULL OR p_owner = auth.uid() OR public.is_blocked_between(auth.uid(), p_owner) THEN RAISE EXCEPTION 'not_allowed'; END IF;
    IF char_length(BTRIM(COALESCE(p_text, ''))) NOT BETWEEN 1 AND 500 THEN RAISE EXCEPTION 'qa_invalid_text'; END IF;
    IF (SELECT COUNT(*) FROM public.qa_submissions WHERE sender_id = auth.uid() AND created_at > NOW() - INTERVAL '1 day') >= 20 THEN
        RAISE EXCEPTION 'rate_limited';
    END IF;
    v_anon := COALESCE(p_anonymous, true) AND b.allow_anonymous;
    INSERT INTO public.qa_submissions (box_owner, sender_id, is_anonymous, question_text)
    VALUES (p_owner, auth.uid(), v_anon, BTRIM(p_text)) RETURNING id INTO v_id;
    SELECT username, display_name INTO pr FROM public.profiles WHERE id = auth.uid();
    INSERT INTO public.notifications (recipient_id, actor_id, actor_username, actor_display_name,
                                      event_type, target_id, target_secondary_id, preview_text, dedupe_key)
    VALUES (p_owner, CASE WHEN v_anon THEN NULL ELSE auth.uid() END,
            CASE WHEN v_anon THEN '' ELSE COALESCE(pr.username, '') END,
            CASE WHEN v_anon THEN 'Anonim' ELSE COALESCE(pr.display_name, '') END,
            'qa_question', v_id::text, '', LEFT(BTRIM(p_text), 120), 'qa_q_' || v_id::text)
    ON CONFLICT (recipient_id, dedupe_key) DO NOTHING;
    RETURN v_id;
END $$;
REVOKE ALL ON FUNCTION public.qa_ask(UUID, TEXT, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.qa_ask(UUID, TEXT, BOOLEAN) TO authenticated;

-- Kutu sahibine gelen sorular: anonimse gönderen kimliği NULL döner (güvenli görünüm yerine RPC)
CREATE OR REPLACE FUNCTION public.qa_inbox()
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', s.id, 'question', s.question_text, 'answer', s.answer_text, 'status', s.status,
        'is_anonymous', s.is_anonymous, 'created_at', s.created_at, 'answered_at', s.answered_at,
        'sender_id', CASE WHEN s.is_anonymous THEN NULL ELSE s.sender_id END,
        'sender_name', CASE WHEN s.is_anonymous THEN NULL ELSE (SELECT COALESCE(NULLIF(p.display_name, ''), p.username) FROM public.profiles p WHERE p.id = s.sender_id) END
    ) ORDER BY s.created_at DESC), '[]'::jsonb)
      FROM (SELECT * FROM public.qa_submissions WHERE box_owner = auth.uid() AND status <> 'rejected' ORDER BY created_at DESC LIMIT 200) s;
$$;
REVOKE ALL ON FUNCTION public.qa_inbox() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.qa_inbox() TO authenticated;

CREATE OR REPLACE FUNCTION public.qa_answer(p_id UUID, p_answer TEXT, p_reject BOOLEAN DEFAULT false)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE s public.qa_submissions; pr RECORD;
BEGIN
    UPDATE public.qa_submissions
       SET status = CASE WHEN p_reject THEN 'rejected' ELSE 'answered' END,
           answer_text = CASE WHEN p_reject THEN answer_text ELSE LEFT(BTRIM(COALESCE(p_answer, '')), 1000) END,
           answered_at = NOW()
     WHERE id = p_id AND box_owner = auth.uid()
    RETURNING * INTO s;
    IF s.id IS NULL THEN RAISE EXCEPTION 'not_allowed'; END IF;
    IF NOT p_reject AND char_length(s.answer_text) = 0 THEN RAISE EXCEPTION 'qa_invalid_text'; END IF;
    IF NOT p_reject AND s.sender_id IS NOT NULL THEN
        SELECT username, display_name INTO pr FROM public.profiles WHERE id = auth.uid();
        INSERT INTO public.notifications (recipient_id, actor_id, actor_username, actor_display_name,
                                          event_type, target_id, target_secondary_id, preview_text, dedupe_key)
        VALUES (s.sender_id, auth.uid(), COALESCE(pr.username, ''), COALESCE(pr.display_name, ''), 'qa_answer', auth.uid()::text, '',
                LEFT(s.answer_text, 120), 'qa_a_' || s.id::text)
        ON CONFLICT (recipient_id, dedupe_key) DO NOTHING;
    END IF;
    RETURN true;
END $$;
REVOKE ALL ON FUNCTION public.qa_answer(UUID, TEXT, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.qa_answer(UUID, TEXT, BOOLEAN) TO authenticated;

-- Profilde herkese açık: yalnız YANITLANMIŞ sorular, gönderen kimliği asla yok
CREATE OR REPLACE FUNCTION public.qa_public(p_owner UUID)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT CASE WHEN public.is_blocked_between(auth.uid(), p_owner) THEN '[]'::jsonb ELSE
        COALESCE((SELECT jsonb_agg(jsonb_build_object('id', id, 'question', question_text, 'answer', answer_text, 'answered_at', answered_at)
                                    ORDER BY answered_at DESC)
                    FROM (SELECT * FROM public.qa_submissions WHERE box_owner = p_owner AND status = 'answered'
                           ORDER BY answered_at DESC LIMIT 50) s), '[]'::jsonb) END;
$$;
REVOKE ALL ON FUNCTION public.qa_public(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.qa_public(UUID) TO authenticated;

-- Moderasyon: şikâyet edilen anonim soru için gönderen YALNIZ 'reports.resolve' yetkili personele görünür
CREATE OR REPLACE FUNCTION public.admin_qa_sender(p_token TEXT, p_id UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v UUID;
BEGIN
    PERFORM public._staff_require(p_token, 'reports.resolve');
    SELECT sender_id INTO v FROM public.qa_submissions WHERE id = p_id;
    INSERT INTO public.admin_audit_log (admin_id, action, target, details)
    VALUES (auth.uid(), 'qa_reveal_sender', p_id::text, '{}'::jsonb);
    RETURN v;
END $$;
REVOKE ALL ON FUNCTION public.admin_qa_sender(TEXT, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_qa_sender(TEXT, UUID) TO authenticated;

-- ---- Zamanlanmış görevler -------------------------------------------------------------
DO $$
DECLARE j RECORD;
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        FOR j IN SELECT * FROM (VALUES
            ('juzzio_purge_stale_view_once', '*/5 * * * *', 'SELECT public.juzzio_purge_stale_view_once()'),
            ('juzzio_close_due_polls', '* * * * *', 'SELECT public.juzzio_close_due_polls()'),
            ('juzzio_fire_memories', '7 7 * * *', 'SELECT public.juzzio_fire_memories()'),
            ('juzzio_check_safety_sessions', '* * * * *', 'SELECT public.juzzio_check_safety_sessions()')) AS t(name, sched, cmd)
        LOOP
            BEGIN
                PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = j.name;
                PERFORM cron.schedule(j.name, j.sched, j.cmd);
            EXCEPTION WHEN OTHERS THEN
                RAISE NOTICE 'pg_cron görevi (%) oluşturulamadı: %', j.name, SQLERRM;
            END;
        END LOOP;
    END IF;
END $$;

-- =============================================================================
-- 10.28 v0.9.6 — Sabitlenen mesajlar, düzenlemede çeviri geçersizleme, otomatik hata
--   (çökme) merkezi, Tanrı modu yönetim araçları: sistem sağlığı, depolama kuyruğu,
--   çoklu hesap tespiti, yasal dışa aktarım, genel oturum sonlandırma, AI kotası,
--   ses/medya sınırları, minimum sürüm ve kaba kuvvet eşikleri
-- =============================================================================

-- ---- Mesaj düzenlenince eski (alıcı dili) çeviri önbelleği silinir -----------------------
CREATE OR REPLACE FUNCTION public.juzzio_invalidate_message_translations()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF NEW.original_text IS DISTINCT FROM OLD.original_text
       AND to_regclass('public.message_translations') IS NOT NULL THEN
        BEGIN
            EXECUTE 'DELETE FROM public.message_translations WHERE message_id = $1' USING OLD.id;
        EXCEPTION WHEN undefined_column THEN NULL;
        END;
    END IF;
    RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_juzzio_invalidate_message_translations ON public.messages;
CREATE TRIGGER trg_juzzio_invalidate_message_translations AFTER UPDATE OF original_text ON public.messages
    FOR EACH ROW EXECUTE FUNCTION public.juzzio_invalidate_message_translations();

-- ---- Sabitlenen mesajlar ------------------------------------------------------------------
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS pinned_at TIMESTAMPTZ;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS pinned_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_messages_room_pinned ON public.messages (room_id, pinned_at DESC) WHERE is_pinned;

-- İstemci is_pinned / pinned_* sütunlarını doğrudan değiştiremez; yalnız pin_message RPC'si
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
        IF COALESCE(current_setting('juzzio.pin_rpc', true), '') <> '1' THEN
            NEW.is_pinned := OLD.is_pinned;
            NEW.pinned_at := OLD.pinned_at;
            NEW.pinned_by := OLD.pinned_by;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

-- Birebir: iki taraf da sabitleyebilir. Grup: gönderen veya grup sahibi/yöneticisi/moderatörü.
-- Sohbet başına en fazla 5 sabit mesaj (en eskisi otomatik kalkar).
CREATE OR REPLACE FUNCTION public.pin_message(p_message UUID, p_pinned BOOLEAN)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_uid UUID := auth.uid();
    m RECORD;
    v_group BOOLEAN;
    v_role TEXT;
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
    SELECT id, room_id, sender_id, is_deleted, is_pinned INTO m FROM public.messages WHERE id = p_message;
    IF NOT FOUND OR m.is_deleted THEN RAISE EXCEPTION 'message_not_found'; END IF;
    IF NOT public.is_room_member(m.room_id, v_uid) THEN RAISE EXCEPTION 'not_room_member'; END IF;
    SELECT COALESCE(is_group, false) INTO v_group FROM public.rooms WHERE id = m.room_id;
    IF v_group THEN
        v_role := COALESCE(public.group_role_of(m.room_id, v_uid), '');
        IF m.sender_id IS DISTINCT FROM v_uid AND v_role NOT IN ('owner', 'admin', 'moderator') THEN
            RAISE EXCEPTION 'pin_not_allowed';
        END IF;
    END IF;
    PERFORM set_config('juzzio.pin_rpc', '1', true);
    IF COALESCE(p_pinned, false) THEN
        UPDATE public.messages SET is_pinned = false, pinned_at = NULL, pinned_by = NULL
         WHERE id IN (SELECT id FROM public.messages WHERE room_id = m.room_id AND is_pinned AND id <> m.id
                       ORDER BY pinned_at DESC NULLS LAST OFFSET 4);
        UPDATE public.messages SET is_pinned = true, pinned_at = NOW(), pinned_by = v_uid WHERE id = m.id;
    ELSE
        UPDATE public.messages SET is_pinned = false, pinned_at = NULL, pinned_by = NULL WHERE id = m.id;
    END IF;
    PERFORM set_config('juzzio.pin_rpc', '', true);
    RETURN jsonb_build_object('ok', true, 'pinned', COALESCE(p_pinned, false));
END $$;
REVOKE ALL ON FUNCTION public.pin_message(UUID, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.pin_message(UUID, BOOLEAN) TO authenticated;

CREATE OR REPLACE FUNCTION public.room_pinned_messages(p_room UUID)
RETURNS SETOF public.messages LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT m.* FROM public.messages m
     WHERE m.room_id = p_room AND m.is_pinned AND NOT m.is_deleted
       AND public.is_room_member(p_room, auth.uid())
     ORDER BY m.pinned_at DESC NULLS LAST
     LIMIT 5;
$$;
REVOKE ALL ON FUNCTION public.room_pinned_messages(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.room_pinned_messages(UUID) TO authenticated;

-- ---- Otomatik hata / çökme merkezi -------------------------------------------------------
-- Aynı hata (parmak izi + sürüm) tek satırda toplanır; mesaj içeriği/şifre vb. istemcide
-- temizlenerek gönderilir. Kullanıcı kimliği yalnız "son etkilenen" olarak saklanır.
CREATE TABLE IF NOT EXISTS public.app_error_reports (
    id BIGSERIAL PRIMARY KEY,
    fingerprint TEXT NOT NULL CHECK (char_length(fingerprint) BETWEEN 8 AND 64),
    app_version TEXT NOT NULL DEFAULT '',
    platform TEXT NOT NULL DEFAULT '',
    error_type TEXT NOT NULL DEFAULT '',
    message TEXT NOT NULL DEFAULT '',
    stack TEXT NOT NULL DEFAULT '',
    context TEXT NOT NULL DEFAULT '',
    is_fatal BOOLEAN NOT NULL DEFAULT false,
    occurrences INTEGER NOT NULL DEFAULT 1,
    affected_users INTEGER NOT NULL DEFAULT 1,
    last_user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    device_info TEXT NOT NULL DEFAULT '',
    status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'resolved', 'ignored')),
    first_seen TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_seen TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (fingerprint, app_version)
);
CREATE INDEX IF NOT EXISTS idx_app_error_reports_last ON public.app_error_reports (last_seen DESC);
ALTER TABLE public.app_error_reports ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.app_error_reports FROM anon, authenticated;

CREATE TABLE IF NOT EXISTS public.app_error_reporters (
    report_id BIGINT NOT NULL REFERENCES public.app_error_reports(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    PRIMARY KEY (report_id, user_id)
);
ALTER TABLE public.app_error_reporters ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.app_error_reporters FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.report_app_error(
    p_fingerprint TEXT, p_error_type TEXT, p_message TEXT, p_stack TEXT,
    p_app_version TEXT DEFAULT '', p_platform TEXT DEFAULT '', p_context TEXT DEFAULT '',
    p_fatal BOOLEAN DEFAULT false, p_device_info TEXT DEFAULT '')
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_id BIGINT;
    v_new_user BOOLEAN := false;
BEGIN
    IF v_uid IS NULL THEN RETURN false; END IF;
    IF char_length(COALESCE(p_fingerprint, '')) NOT BETWEEN 8 AND 64 THEN RAISE EXCEPTION 'invalid_fingerprint'; END IF;
    -- Kötüye kullanım: kullanıcı başına saatte en fazla 30 rapor (fazlası sessizce düşer)
    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'juzzio_rate_check') THEN
        IF NOT public.juzzio_rate_check(v_uid, 'app_error', 30, 3600) THEN RETURN false; END IF;
    END IF;
    INSERT INTO public.app_error_reports AS r (fingerprint, app_version, platform, error_type, message, stack, context,
                                               is_fatal, last_user_id, device_info)
    VALUES (p_fingerprint, LEFT(COALESCE(p_app_version, ''), 40), LEFT(COALESCE(p_platform, ''), 20),
            LEFT(COALESCE(p_error_type, ''), 200), LEFT(COALESCE(p_message, ''), 1000), LEFT(COALESCE(p_stack, ''), 8000),
            LEFT(COALESCE(p_context, ''), 200), COALESCE(p_fatal, false), v_uid, LEFT(COALESCE(p_device_info, ''), 300))
    ON CONFLICT (fingerprint, app_version) DO UPDATE
        SET occurrences = r.occurrences + 1, last_seen = NOW(), last_user_id = v_uid,
            is_fatal = r.is_fatal OR EXCLUDED.is_fatal,
            status = CASE WHEN r.status = 'resolved' THEN 'open' ELSE r.status END
    RETURNING id INTO v_id;
    INSERT INTO public.app_error_reporters (report_id, user_id) VALUES (v_id, v_uid)
    ON CONFLICT DO NOTHING;
    GET DIAGNOSTICS v_new_user = ROW_COUNT;
    IF v_new_user THEN
        UPDATE public.app_error_reports SET affected_users = (SELECT COUNT(*) FROM public.app_error_reporters WHERE report_id = v_id)
         WHERE id = v_id;
    END IF;
    RETURN true;
END $$;
REVOKE ALL ON FUNCTION public.report_app_error(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, BOOLEAN, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.report_app_error(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, BOOLEAN, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_list_app_errors(p_token TEXT, p_status TEXT DEFAULT 'open', p_limit INTEGER DEFAULT 100)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
    PERFORM public._staff_require(p_token, 'feedback.manage');
    RETURN COALESCE((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.is_fatal DESC, x.last_seen DESC) FROM (
        SELECT e.id, e.fingerprint, e.app_version, e.platform, e.error_type, e.message, e.stack, e.context, e.is_fatal,
               e.occurrences, e.affected_users, e.device_info, e.status, e.first_seen, e.last_seen,
               p.username AS last_username
          FROM public.app_error_reports e
          LEFT JOIN public.profiles p ON p.id = e.last_user_id
         WHERE COALESCE(p_status, 'all') = 'all' OR e.status = p_status
         ORDER BY e.last_seen DESC
         LIMIT LEAST(GREATEST(COALESCE(p_limit, 100), 1), 500)) x), '[]'::jsonb);
END $$;
REVOKE ALL ON FUNCTION public.admin_list_app_errors(TEXT, TEXT, INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_app_errors(TEXT, TEXT, INTEGER) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_set_app_error_status(p_token TEXT, p_id BIGINT, p_status TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    PERFORM public._staff_require(p_token, 'feedback.manage');
    IF p_status NOT IN ('open', 'resolved', 'ignored') THEN RAISE EXCEPTION 'invalid_status'; END IF;
    UPDATE public.app_error_reports SET status = p_status WHERE id = p_id;
    INSERT INTO public.admin_audit_log (admin_id, action, target, details)
    VALUES (auth.uid(), 'app_error_status', p_id::text, jsonb_build_object('status', p_status));
END $$;
REVOKE ALL ON FUNCTION public.admin_set_app_error_status(TEXT, BIGINT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_app_error_status(TEXT, BIGINT, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.juzzio_purge_old_app_errors()
RETURNS INTEGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE n INTEGER;
BEGIN
    DELETE FROM public.app_error_reports WHERE last_seen < NOW() - INTERVAL '90 days';
    GET DIAGNOSTICS n = ROW_COUNT;
    RETURN n;
END $$;
REVOKE ALL ON FUNCTION public.juzzio_purge_old_app_errors() FROM PUBLIC, anon, authenticated;

-- ---- AI (çeviri/döküm) günlük kullanıcı kotası -------------------------------------------
CREATE TABLE IF NOT EXISTS public.ai_usage_daily (
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    day DATE NOT NULL DEFAULT CURRENT_DATE,
    kind TEXT NOT NULL,
    units INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (user_id, day, kind)
);
CREATE INDEX IF NOT EXISTS idx_ai_usage_daily_day ON public.ai_usage_daily (day, units DESC);
ALTER TABLE public.ai_usage_daily ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.ai_usage_daily FROM anon, authenticated;

-- Edge Function (service_role) çağırır. Kota 0 = sınırsız. Kota aşılırsa false.
CREATE OR REPLACE FUNCTION public.juzzio_ai_quota_take(p_user UUID, p_kind TEXT, p_units INTEGER DEFAULT 1)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_quota INTEGER;
    v_used INTEGER;
BEGIN
    IF p_user IS NULL OR COALESCE(p_kind, '') = '' THEN RETURN false; END IF;
    SELECT CASE WHEN jsonb_typeof(value) = 'number' THEN (value #>> '{}')::numeric::int ELSE 0 END INTO v_quota
      FROM public.app_settings WHERE key = 'ai_daily_quota_per_user';
    v_quota := COALESCE(v_quota, 0);
    IF v_quota > 0 THEN
        SELECT COALESCE(SUM(units), 0) INTO v_used FROM public.ai_usage_daily WHERE user_id = p_user AND day = CURRENT_DATE;
        IF v_used + GREATEST(COALESCE(p_units, 1), 1) > v_quota THEN RETURN false; END IF;
    END IF;
    INSERT INTO public.ai_usage_daily AS u (user_id, day, kind, units)
    VALUES (p_user, CURRENT_DATE, LEFT(p_kind, 40), GREATEST(COALESCE(p_units, 1), 1))
    ON CONFLICT (user_id, day, kind) DO UPDATE SET units = u.units + EXCLUDED.units;
    RETURN true;
END $$;
REVOKE ALL ON FUNCTION public.juzzio_ai_quota_take(UUID, TEXT, INTEGER) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.juzzio_ai_quota_take(UUID, TEXT, INTEGER) TO service_role;

CREATE OR REPLACE FUNCTION public.admin_ai_usage(p_token TEXT, p_days INTEGER DEFAULT 1, p_limit INTEGER DEFAULT 50)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
    PERFORM public._staff_require(p_token, 'stats.read');
    RETURN COALESCE((SELECT jsonb_agg(to_jsonb(x)) FROM (
        SELECT u.user_id, p.username, p.display_name, SUM(u.units)::int AS units,
               jsonb_object_agg(u.kind, u.units) AS by_kind
          FROM (SELECT user_id, kind, SUM(units)::int AS units FROM public.ai_usage_daily
                 WHERE day > CURRENT_DATE - LEAST(GREATEST(COALESCE(p_days, 1), 1), 90)
                 GROUP BY user_id, kind) u
          JOIN public.profiles p ON p.id = u.user_id
         GROUP BY u.user_id, p.username, p.display_name
         ORDER BY SUM(u.units) DESC
         LIMIT LEAST(GREATEST(COALESCE(p_limit, 50), 1), 500)) x), '[]'::jsonb);
END $$;
REVOKE ALL ON FUNCTION public.admin_ai_usage(TEXT, INTEGER, INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_ai_usage(TEXT, INTEGER, INTEGER) TO authenticated;

-- ---- Tanrı modu: genişletilmiş sistem sağlığı ve veritabanı bakımı -----------------------
CREATE OR REPLACE FUNCTION public.admin_god_overview(p_token TEXT)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_catalog AS $$
BEGIN
    PERFORM public._staff_require(p_token, 'stats.read');
    RETURN jsonb_build_object(
        'server_time', NOW(),
        'online_now', (SELECT COUNT(*) FROM public.profiles WHERE is_online AND last_seen > NOW() - INTERVAL '5 minutes'),
        'active_24h', (SELECT COUNT(*) FROM public.profiles WHERE last_seen > NOW() - INTERVAL '24 hours'),
        'active_7d', (SELECT COUNT(*) FROM public.profiles WHERE last_seen > NOW() - INTERVAL '7 days'),
        'total_users', (SELECT COUNT(*) FROM public.profiles),
        'new_users_24h', (SELECT COUNT(*) FROM public.profiles WHERE created_at > NOW() - INTERVAL '24 hours'),
        'messages_24h', (SELECT COUNT(*) FROM public.messages WHERE created_at > NOW() - INTERVAL '24 hours'),
        'errors_open', (SELECT COUNT(*) FROM public.app_error_reports WHERE status = 'open'),
        'errors_fatal_24h', (SELECT COUNT(*) FROM public.app_error_reports WHERE is_fatal AND last_seen > NOW() - INTERVAL '24 hours'),
        'error_events_24h', (SELECT COALESCE(SUM(occurrences), 0) FROM public.app_error_reports WHERE last_seen > NOW() - INTERVAL '24 hours'),
        'security_events_24h', (SELECT COUNT(*) FROM public.security_events WHERE created_at > NOW() - INTERVAL '24 hours'),
        'admin_login_fails_24h', (SELECT COUNT(*) FROM public.admin_login_attempts WHERE NOT success AND created_at > NOW() - INTERVAL '24 hours'),
        'storage_queue_pending', (SELECT COUNT(*) FROM public.juzzio_storage_cleanup_queue WHERE processed_at IS NULL AND attempts < 8),
        'storage_queue_failed', (SELECT COUNT(*) FROM public.juzzio_storage_cleanup_queue WHERE processed_at IS NULL AND attempts >= 8),
        'shared_devices', (SELECT COUNT(*) FROM (SELECT device_id FROM public.user_devices GROUP BY device_id HAVING COUNT(*) > 1) d),
        'ai_units_today', (SELECT COALESCE(SUM(units), 0) FROM public.ai_usage_daily WHERE day = CURRENT_DATE),
        'translation_requests_today', (SELECT COALESCE(SUM(requests), 0) FROM public.translation_usage_daily WHERE day = CURRENT_DATE),
        'admin_actions_24h', (SELECT COUNT(*) FROM public.admin_audit_log WHERE created_at > NOW() - INTERVAL '24 hours'),
        'db_size_bytes', pg_database_size(current_database()),
        'largest_tables', (SELECT COALESCE(jsonb_agg(jsonb_build_object('table', t.relname, 'bytes', t.bytes, 'dead_rows', t.dead,
                                                                        'live_rows', t.live)), '[]'::jsonb)
                             FROM (SELECT s.relname, pg_total_relation_size(s.relid) AS bytes, s.n_dead_tup AS dead, s.n_live_tup AS live
                                     FROM pg_stat_user_tables s WHERE s.schemaname = 'public'
                                    ORDER BY pg_total_relation_size(s.relid) DESC LIMIT 12) t)
    );
END $$;
REVOKE ALL ON FUNCTION public.admin_god_overview(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_god_overview(TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_storage_queue(p_token TEXT, p_failed_only BOOLEAN DEFAULT false, p_limit INTEGER DEFAULT 100)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
    PERFORM public._staff_require(p_token, 'settings');
    RETURN COALESCE((SELECT jsonb_agg(to_jsonb(q) ORDER BY q.enqueued_at DESC) FROM (
        SELECT id, bucket, object_name, is_prefix, reason, enqueued_at, attempts, last_error
          FROM public.juzzio_storage_cleanup_queue
         WHERE processed_at IS NULL AND (NOT COALESCE(p_failed_only, false) OR attempts >= 8)
         ORDER BY enqueued_at DESC
         LIMIT LEAST(GREATEST(COALESCE(p_limit, 100), 1), 500)) q), '[]'::jsonb);
END $$;
REVOKE ALL ON FUNCTION public.admin_storage_queue(TEXT, BOOLEAN, INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_storage_queue(TEXT, BOOLEAN, INTEGER) TO authenticated;

-- Başarısız kalemleri yeniden kuyruğa al (deneme sayacı sıfırlanır)
CREATE OR REPLACE FUNCTION public.admin_storage_queue_retry(p_token TEXT)
RETURNS INTEGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE n INTEGER;
BEGIN
    PERFORM public._staff_require(p_token, 'settings');
    UPDATE public.juzzio_storage_cleanup_queue SET attempts = 0, last_error = ''
     WHERE processed_at IS NULL AND attempts >= 8;
    GET DIAGNOSTICS n = ROW_COUNT;
    INSERT INTO public.admin_audit_log (admin_id, action, target, details)
    VALUES (auth.uid(), 'storage_queue_retry', '', jsonb_build_object('rows', n));
    RETURN n;
END $$;
REVOKE ALL ON FUNCTION public.admin_storage_queue_retry(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_storage_queue_retry(TEXT) TO authenticated;

-- Öksüz medya taraması: silinmiş sohbet odalarına ait, hâlâ depoda duran nesneler
-- (yalnız sayım + kuyruğa ekleme; doğrudan storage silme Edge Function'da yapılır)
CREATE OR REPLACE FUNCTION public.admin_enqueue_orphan_media(p_token TEXT)
RETURNS INTEGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, storage AS $$
DECLARE n INTEGER := 0; r RECORD;
BEGIN
    PERFORM public._staff_require(p_token, 'settings');
    IF to_regclass('storage.objects') IS NULL THEN RETURN 0; END IF;
    FOR r IN
        SELECT o.bucket_id, o.name FROM storage.objects o
         WHERE o.bucket_id IN ('chat-media', 'voice-notes')
           AND o.created_at < NOW() - INTERVAL '2 days'
           -- yol düzeni: <kullanıcı>/<oda>/<dosya>; oda artık yoksa nesne öksüzdür
           AND public.juzzio_try_uuid(split_part(o.name, '/', 2)) IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM public.rooms rm WHERE rm.id = public.juzzio_try_uuid(split_part(o.name, '/', 2)))
         LIMIT 2000
    LOOP
        BEGIN
            PERFORM public.juzzio_enqueue_storage_cleanup(r.bucket_id, r.name, 'orphan_scan');
            n := n + 1;
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
    END LOOP;
    INSERT INTO public.admin_audit_log (admin_id, action, target, details)
    VALUES (auth.uid(), 'orphan_media_scan', '', jsonb_build_object('enqueued', n));
    RETURN n;
END $$;
REVOKE ALL ON FUNCTION public.admin_enqueue_orphan_media(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_enqueue_orphan_media(TEXT) TO authenticated;

-- ---- Çoklu hesap / cihaz tespiti ---------------------------------------------------------
-- (IP adresi saklanmaz; tespit cihaz kimliği üzerinden yapılır. Cihaz kimliği maskelenir.)
CREATE OR REPLACE FUNCTION public.admin_multi_accounts(p_token TEXT, p_limit INTEGER DEFAULT 100)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
    PERFORM public._staff_require(p_token, 'users.read');
    RETURN COALESCE((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.accounts DESC, x.last_seen DESC) FROM (
        SELECT LEFT(d.device_id, 4) || '…' || RIGHT(d.device_id, 4) AS device,
               COUNT(*)::int AS accounts, MAX(d.last_seen) AS last_seen,
               EXISTS (SELECT 1 FROM public.banned_devices b WHERE b.device_id = d.device_id) AS device_banned,
               jsonb_agg(jsonb_build_object('user_id', p.id, 'username', p.username, 'display_name', p.display_name,
                                            'platform', d.platform, 'last_seen', d.last_seen) ORDER BY d.last_seen DESC) AS users
          FROM public.user_devices d JOIN public.profiles p ON p.id = d.user_id
         GROUP BY d.device_id
        HAVING COUNT(*) > 1
         ORDER BY COUNT(*) DESC, MAX(d.last_seen) DESC
         LIMIT LEAST(GREATEST(COALESCE(p_limit, 100), 1), 500)) x), '[]'::jsonb);
END $$;
REVOKE ALL ON FUNCTION public.admin_multi_accounts(TEXT, INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_multi_accounts(TEXT, INTEGER) TO authenticated;

-- ---- Yasal dışa aktarım (Legal Bundle Vault) ---------------------------------------------
-- YALNIZ süper yönetici (şifreli oturum belirteci). Uçtan uca şifreli içerik zaten okunamaz;
-- birebir mesaj içerikleri pakete KONMAZ, yalnız meta veri (sayılar/tarihler). Her dışa aktarım denetim kaydına yazılır.
CREATE OR REPLACE FUNCTION public.admin_legal_export(p_token TEXT, p_user UUID, p_reason TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v JSONB;
BEGIN
    IF NOT public.admin_check_token(p_token) THEN RAISE EXCEPTION 'super_admin_required'; END IF;
    IF char_length(BTRIM(COALESCE(p_reason, ''))) < 5 THEN RAISE EXCEPTION 'reason_required'; END IF;
    IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = p_user) THEN RAISE EXCEPTION 'user_not_found'; END IF;
    SELECT jsonb_build_object(
        'generated_at', NOW(),
        'reason', LEFT(p_reason, 500),
        'profile', (SELECT to_jsonb(p) - 'blocked_users' FROM public.profiles p WHERE p.id = p_user),
        'devices', COALESCE((SELECT jsonb_agg(jsonb_build_object('device', LEFT(device_id, 4) || '…' || RIGHT(device_id, 4),
                                                                 'platform', platform, 'first_seen', first_seen, 'last_seen', last_seen))
                               FROM public.user_devices WHERE user_id = p_user), '[]'::jsonb),
        'posts', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', id, 'created_at', created_at, 'content_type', content_type,
                                                               'is_deleted', is_deleted))
                             FROM public.posts WHERE author_id = p_user), '[]'::jsonb),
        'message_stats', jsonb_build_object(
            'sent_total', (SELECT COUNT(*) FROM public.messages WHERE sender_id = p_user),
            'first_message_at', (SELECT MIN(created_at) FROM public.messages WHERE sender_id = p_user),
            'last_message_at', (SELECT MAX(created_at) FROM public.messages WHERE sender_id = p_user)),
        'reports_filed', COALESCE((SELECT jsonb_agg(to_jsonb(r)) FROM public.reports r WHERE r.reporter_id = p_user), '[]'::jsonb),
        'reports_against', COALESCE((SELECT jsonb_agg(to_jsonb(r)) FROM public.reports r WHERE r.target_owner_id = p_user), '[]'::jsonb),
        'strikes', COALESCE((SELECT jsonb_agg(to_jsonb(s)) FROM public.moderation_strikes s WHERE s.user_id = p_user), '[]'::jsonb),
        'security_events', COALESCE((SELECT jsonb_agg(to_jsonb(e)) FROM public.security_events e WHERE e.user_id = p_user), '[]'::jsonb),
        'admin_actions_on_user', COALESCE((SELECT jsonb_agg(jsonb_build_object('action', action, 'at', created_at, 'details', details))
                                             FROM public.admin_audit_log WHERE target = p_user::text), '[]'::jsonb)
    ) INTO v;
    INSERT INTO public.admin_audit_log (admin_id, action, target, details)
    VALUES (auth.uid(), 'legal_export', p_user::text, jsonb_build_object('reason', LEFT(p_reason, 500)));
    RETURN v;
EXCEPTION WHEN undefined_column OR undefined_table THEN
    -- Eski şema sürümlerinde eksik tablo/sütun: en azından profil ve denetim kaydı
    INSERT INTO public.admin_audit_log (admin_id, action, target, details)
    VALUES (auth.uid(), 'legal_export', p_user::text, jsonb_build_object('reason', LEFT(p_reason, 500), 'partial', true));
    RETURN jsonb_build_object('generated_at', NOW(), 'partial', true,
                              'profile', (SELECT to_jsonb(p) - 'blocked_users' FROM public.profiles p WHERE p.id = p_user));
END $$;
REVOKE ALL ON FUNCTION public.admin_legal_export(TEXT, UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_legal_export(TEXT, UUID, TEXT) TO authenticated;

-- ---- Genel oturum sonlandırma (acil durum) ----------------------------------------------
-- YALNIZ süper yönetici + açık onay metni. Çağıranın kendi oturumları korunur.
CREATE OR REPLACE FUNCTION public.admin_kill_all_sessions(p_token TEXT, p_confirm TEXT)
RETURNS INTEGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_rows INTEGER := 0;
BEGIN
    IF NOT public.admin_check_token(p_token) THEN RAISE EXCEPTION 'super_admin_required'; END IF;
    IF COALESCE(p_confirm, '') <> 'TUM OTURUMLARI KAPAT' THEN RAISE EXCEPTION 'confirmation_required'; END IF;
    BEGIN
        EXECUTE 'DELETE FROM auth.sessions WHERE user_id <> $1' USING auth.uid();
        GET DIAGNOSTICS v_rows = ROW_COUNT;
        EXECUTE 'DELETE FROM auth.refresh_tokens WHERE user_id <> $1::text' USING auth.uid();
    EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION 'session_kill_failed';
    END;
    UPDATE public.profiles SET is_online = false WHERE id <> auth.uid() AND is_online;
    INSERT INTO public.admin_audit_log (admin_id, action, target, details)
    VALUES (auth.uid(), 'kill_all_sessions', '*', jsonb_build_object('sessions', v_rows));
    RETURN v_rows;
END $$;
REVOKE ALL ON FUNCTION public.admin_kill_all_sessions(TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_kill_all_sessions(TEXT, TEXT) TO authenticated;

-- ---- Yeni ayarlar: medya sınırları, minimum sürüm, AI kotası, kaba kuvvet eşikleri ---------
INSERT INTO public.app_settings (key, value) VALUES
    ('voice_max_seconds', '300'::jsonb),
    ('audio_bitrate_kbps', '96'::jsonb),
    ('video_max_seconds', '180'::jsonb),
    ('min_supported_build', '0'::jsonb),
    ('ai_daily_quota_per_user', '0'::jsonb),
    ('admin_bruteforce_max_fails', '5'::jsonb),
    ('admin_bruteforce_window_min', '15'::jsonb),
    ('error_reporting_enabled', 'true'::jsonb)
ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.juzzio_setting_int(p_key TEXT, p_default INTEGER)
RETURNS INTEGER LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT COALESCE((SELECT CASE WHEN jsonb_typeof(value) = 'number' THEN (value #>> '{}')::numeric::int END
                       FROM public.app_settings WHERE key = p_key), p_default);
$$;
REVOKE ALL ON FUNCTION public.juzzio_setting_int(TEXT, INTEGER) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.admin_set_setting(p_token TEXT, p_key TEXT, p_value JSONB)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_num NUMERIC;
BEGIN
    PERFORM public._staff_require(p_token, 'settings');
    IF p_key IN ('maintenance_message', 'announcement_banner') THEN
        IF jsonb_typeof(p_value) <> 'string' THEN RAISE EXCEPTION 'invalid_setting'; END IF;
        p_value := to_jsonb(LEFT(p_value #>> '{}', 500));
    ELSIF p_key = 'default_glass_palette' THEN
        IF jsonb_typeof(p_value) <> 'string'
           OR (p_value #>> '{}') NOT IN ('juzzio_liquid', 'ocean', 'glass_white', 'amethyst', 'emerald', 'lagoon', 'chrome',
                                        'obsidian_oled', 'lavender_mist', 'rose_quartz', 'cyber_neon', 'high_contrast') THEN
            RAISE EXCEPTION 'invalid_setting';
        END IF;
    ELSIF p_key IN ('call_moderation_interval_sec', 'voice_max_seconds', 'audio_bitrate_kbps', 'video_max_seconds',
                    'min_supported_build', 'ai_daily_quota_per_user', 'admin_bruteforce_max_fails', 'admin_bruteforce_window_min') THEN
        IF jsonb_typeof(p_value) <> 'number' THEN RAISE EXCEPTION 'invalid_setting'; END IF;
        v_num := (p_value #>> '{}')::numeric;
        IF v_num <> trunc(v_num) OR NOT (
               (p_key = 'call_moderation_interval_sec' AND v_num BETWEEN 3 AND 60)
            OR (p_key = 'voice_max_seconds' AND v_num BETWEEN 15 AND 900)
            OR (p_key = 'audio_bitrate_kbps' AND v_num BETWEEN 16 AND 256)
            OR (p_key = 'video_max_seconds' AND v_num BETWEEN 10 AND 600)
            OR (p_key = 'min_supported_build' AND v_num BETWEEN 0 AND 100000)
            OR (p_key = 'ai_daily_quota_per_user' AND v_num BETWEEN 0 AND 100000)
            OR (p_key = 'admin_bruteforce_max_fails' AND v_num BETWEEN 3 AND 20)
            OR (p_key = 'admin_bruteforce_window_min' AND v_num BETWEEN 5 AND 1440)) THEN
            RAISE EXCEPTION 'invalid_setting';
        END IF;
        -- Minimum sürüm yalnız süper yönetici tarafından değiştirilebilir (tüm eski istemcileri kilitler)
        IF p_key IN ('min_supported_build', 'admin_bruteforce_max_fails', 'admin_bruteforce_window_min')
           AND NOT public.admin_check_token(p_token) THEN
            RAISE EXCEPTION 'super_admin_required';
        END IF;
    ELSIF p_key IN ('maintenance_mode', 'signups_enabled', 'live_translation_enabled', 'chick_game_enabled',
                    'stories_enabled', 'beauty_filter_enabled', 'call_moderation_enabled',
                    'speech_moderation_enabled', 'avatar_moderation_enabled', 'posts_enabled', 'calls_enabled',
                    'group_creation_enabled', 'global_feed_enabled', 'error_reporting_enabled') THEN
        IF jsonb_typeof(p_value) <> 'boolean' THEN RAISE EXCEPTION 'invalid_setting'; END IF;
        IF p_key = 'maintenance_mode' AND NOT public.admin_check_token(p_token) THEN
            RAISE EXCEPTION 'super_admin_required'; -- bakım modu: yalnız süper yönetici açıp kapatabilir
        END IF;
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

-- Yönetici şifre girişi: kaba kuvvet eşikleri artık ayarlardan okunur (varsayılan 15 dk'da 5)
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
    v_max INTEGER := LEAST(GREATEST(public.juzzio_setting_int('admin_bruteforce_max_fails', 5), 3), 20);
    v_window INTEGER := LEAST(GREATEST(public.juzzio_setting_int('admin_bruteforce_window_min', 15), 5), 1440);
BEGIN
    IF NOT public.is_juzzio_admin(v_uid) THEN RAISE EXCEPTION 'not_allowed'; END IF;
    SELECT COUNT(*) INTO v_fails FROM public.admin_login_attempts
    WHERE user_id = v_uid AND NOT success AND created_at > NOW() - make_interval(mins => v_window);
    IF v_fails >= v_max THEN RAISE EXCEPTION 'too_many_attempts'; END IF;

    SELECT password_hash INTO v_hash FROM public.admin_secret WHERE id = 1;
    IF v_hash IS NULL THEN RAISE EXCEPTION 'admin_password_not_set'; END IF;
    IF crypt(COALESCE(p_password, ''), v_hash) <> v_hash THEN
        INSERT INTO public.admin_login_attempts (user_id, device_id, success) VALUES (v_uid, LEFT(COALESCE(p_device_id, ''), 128), false);
        RETURN jsonb_build_object('ok', false, 'remaining', GREATEST(0, v_max - 1 - v_fails));
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

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        BEGIN
            PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'juzzio_purge_old_app_errors';
            PERFORM cron.schedule('juzzio_purge_old_app_errors', '23 4 * * *', 'SELECT public.juzzio_purge_old_app_errors()');
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'pg_cron görevi (juzzio_purge_old_app_errors) oluşturulamadı: %', SQLERRM;
        END;
    END IF;
END $$;

-- ---- Düzenlenen mesaj bildirimi: "(Düzenlendi)" önekiyle tek seferlik anlık bildirim -------
-- Yalnız düzenleme zamanı (edited_at) değiştiğinde; sessize alınmış/engellenmiş alıcılar atlanır.
-- Şifreli (E2EE) mesajda içerik sunucuda yoktur: önizleme cihazda çözülür ve öneki cihaz ekler.
CREATE OR REPLACE FUNCTION public.juzzio_notify_message_edited()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_room RECORD;
    v_sender RECORD;
    v_preview TEXT;
    rp RECORD;
BEGIN
    IF NEW.edited_at IS NULL OR NEW.edited_at IS NOT DISTINCT FROM OLD.edited_at OR NEW.is_deleted
       OR NEW.message_type IN ('system', 'call') THEN
        RETURN NEW;
    END IF;
    SELECT id, is_group, title INTO v_room FROM public.rooms WHERE id = NEW.room_id;
    SELECT username, display_name, avatar_url INTO v_sender FROM public.profiles WHERE id = NEW.sender_id;
    v_preview := CASE WHEN COALESCE(NEW.metadata, '{}'::jsonb) ? 'e2ee' THEN '✏️ (Düzenlendi) 🔒 Şifreli mesaj'
                      ELSE '✏️ (Düzenlendi) ' || COALESCE(NEW.original_text, '') END;
    FOR rp IN
        SELECT user_id, is_muted, notif_muted_until FROM public.room_participants
         WHERE room_id = NEW.room_id AND user_id <> NEW.sender_id AND left_at IS NULL
    LOOP
        IF rp.is_muted OR COALESCE(rp.notif_muted_until > NOW(), false)
           OR public.is_blocked_between(NEW.sender_id, rp.user_id) THEN
            CONTINUE;
        END IF;
        BEGIN
            INSERT INTO public.notifications (
                recipient_id, actor_id, actor_username, actor_display_name, actor_avatar_url,
                event_type, target_id, target_secondary_id, preview_text, dedupe_key
            ) VALUES (
                rp.user_id, NEW.sender_id, COALESCE(v_sender.username, ''),
                COALESCE(NULLIF(v_sender.display_name, ''), NEW.sender_name, 'Juzzio'), v_sender.avatar_url,
                CASE WHEN COALESCE(v_room.is_group, false) THEN 'group_activity' ELSE 'message' END,
                NEW.room_id::text, NEW.id::text,
                LEFT(CASE WHEN COALESCE(v_room.is_group, false) THEN COALESCE(v_room.title, '') || ': ' || v_preview ELSE v_preview END, 160),
                'msgedit_' || NEW.id::text || '_' || floor(extract(epoch FROM NEW.edited_at))::bigint::text
            )
            ON CONFLICT (recipient_id, dedupe_key) DO NOTHING;
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
    END LOOP;
    RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_juzzio_notify_message_edited ON public.messages;
CREATE TRIGGER trg_juzzio_notify_message_edited AFTER UPDATE OF original_text, metadata ON public.messages
    FOR EACH ROW EXECUTE FUNCTION public.juzzio_notify_message_edited();

-- =============================================================================
-- 10.29 v0.9.7 — 4 yeni cam teması (Kuzey Işıkları, Buzlu İnci, Gece Safiri, Kuzey Buzu)
--   ve yönetici tarafından yönetilen cihaz medya önbelleği sınırları
-- =============================================================================
INSERT INTO public.app_settings (key, value) VALUES
    ('media_cache_max_mb', '300'::jsonb),
    ('media_cache_max_age_days', '60'::jsonb)
ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.admin_set_setting(p_token TEXT, p_key TEXT, p_value JSONB)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_num NUMERIC;
BEGIN
    PERFORM public._staff_require(p_token, 'settings');
    IF p_key IN ('maintenance_message', 'announcement_banner') THEN
        IF jsonb_typeof(p_value) <> 'string' THEN RAISE EXCEPTION 'invalid_setting'; END IF;
        p_value := to_jsonb(LEFT(p_value #>> '{}', 500));
    ELSIF p_key = 'default_glass_palette' THEN
        IF jsonb_typeof(p_value) <> 'string'
           OR (p_value #>> '{}') NOT IN ('juzzio_liquid', 'ocean', 'glass_white', 'amethyst', 'emerald', 'lagoon', 'chrome',
                                        'obsidian_oled', 'lavender_mist', 'rose_quartz', 'cyber_neon', 'high_contrast',
                                        'aurora_borealis', 'frosted_pearl', 'midnight_sapphire', 'nordic_frost') THEN
            RAISE EXCEPTION 'invalid_setting';
        END IF;
    ELSIF p_key IN ('call_moderation_interval_sec', 'voice_max_seconds', 'audio_bitrate_kbps', 'video_max_seconds',
                    'min_supported_build', 'ai_daily_quota_per_user', 'admin_bruteforce_max_fails', 'admin_bruteforce_window_min',
                    'media_cache_max_mb', 'media_cache_max_age_days') THEN
        IF jsonb_typeof(p_value) <> 'number' THEN RAISE EXCEPTION 'invalid_setting'; END IF;
        v_num := (p_value #>> '{}')::numeric;
        IF v_num <> trunc(v_num) OR NOT (
               (p_key = 'call_moderation_interval_sec' AND v_num BETWEEN 3 AND 60)
            OR (p_key = 'voice_max_seconds' AND v_num BETWEEN 15 AND 900)
            OR (p_key = 'audio_bitrate_kbps' AND v_num BETWEEN 16 AND 256)
            OR (p_key = 'video_max_seconds' AND v_num BETWEEN 10 AND 600)
            OR (p_key = 'min_supported_build' AND v_num BETWEEN 0 AND 100000)
            OR (p_key = 'ai_daily_quota_per_user' AND v_num BETWEEN 0 AND 100000)
            OR (p_key = 'admin_bruteforce_max_fails' AND v_num BETWEEN 3 AND 20)
            OR (p_key = 'admin_bruteforce_window_min' AND v_num BETWEEN 5 AND 1440)
            OR (p_key = 'media_cache_max_mb' AND v_num BETWEEN 50 AND 4096)
            OR (p_key = 'media_cache_max_age_days' AND v_num BETWEEN 0 AND 365)) THEN
            RAISE EXCEPTION 'invalid_setting';
        END IF;
        -- Minimum sürüm yalnız süper yönetici tarafından değiştirilebilir (tüm eski istemcileri kilitler)
        IF p_key IN ('min_supported_build', 'admin_bruteforce_max_fails', 'admin_bruteforce_window_min')
           AND NOT public.admin_check_token(p_token) THEN
            RAISE EXCEPTION 'super_admin_required';
        END IF;
    ELSIF p_key IN ('maintenance_mode', 'signups_enabled', 'live_translation_enabled', 'chick_game_enabled',
                    'stories_enabled', 'beauty_filter_enabled', 'call_moderation_enabled',
                    'speech_moderation_enabled', 'avatar_moderation_enabled', 'posts_enabled', 'calls_enabled',
                    'group_creation_enabled', 'global_feed_enabled', 'error_reporting_enabled') THEN
        IF jsonb_typeof(p_value) <> 'boolean' THEN RAISE EXCEPTION 'invalid_setting'; END IF;
        IF p_key = 'maintenance_mode' AND NOT public.admin_check_token(p_token) THEN
            RAISE EXCEPTION 'super_admin_required'; -- bakım modu: yalnız süper yönetici açıp kapatabilir
        END IF;
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

-- =============================================================================
-- 10.30 v1.0.0 — Civciv ekonomisi: kazanmak daha zor, ürünler daha pahalı, yeni
--   özelleştirmeler (prenses tacı, çiçek taç, büyücü şapkası, yıldız gözlük, tütü,
--   inci kolye, bale pabucu, Şato/Uzay/Sakura sahneleri). Yönetici kayıtları okunur
--   hedef adlarıyla (admin_audit → target_username / target_name).
--   Mevcut kullanıcıların BİRİKMİŞ jetonları korunur: 2026-11-10 öncesi beslemeler eski
--   oranla (10), sonrası yeni oranla (4) sayılır; satın alınmış ürünler ellerinde kalır.
-- =============================================================================
CREATE OR REPLACE FUNCTION public.juzzio_chick_coins(p_chick UUID)
RETURNS INTEGER LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT GREATEST(0,
        (SELECT COUNT(*) FILTER (WHERE fed_at < TIMESTAMPTZ '2026-11-10 00:00:00+00')::int * 10
              + COUNT(*) FILTER (WHERE fed_at >= TIMESTAMPTZ '2026-11-10 00:00:00+00')::int * 4
           FROM public.chick_feed_log WHERE chick_id = p_chick)
      + (SELECT COALESCE(stage, 0) * 30 FROM public.chick_pets WHERE id = p_chick)
      - (SELECT COALESCE(SUM(price_paid), 0)::int FROM public.chick_owned_accessories WHERE chick_id = p_chick));
$$;
REVOKE ALL ON FUNCTION public.juzzio_chick_coins(UUID) FROM PUBLIC, anon, authenticated;

INSERT INTO public.chick_accessories (code, slot, price, min_stage, sort_order) VALUES
    ('party_hat', 'hat', 90, 1, 1), ('crown', 'hat', 450, 2, 2), ('beanie', 'hat', 150, 1, 3), ('cowboy_hat', 'hat', 300, 2, 4),
    ('flower_crown', 'hat', 260, 1, 5), ('tiara', 'hat', 620, 2, 6), ('wizard_hat', 'hat', 780, 3, 7),
    ('round_glasses', 'glasses', 120, 1, 10), ('sunglasses', 'glasses', 220, 1, 11), ('heart_glasses', 'glasses', 320, 2, 12),
    ('star_glasses', 'glasses', 380, 2, 13),
    ('bow_tie', 'outfit', 110, 1, 20), ('scarf', 'outfit', 180, 1, 21), ('cape', 'outfit', 520, 2, 22),
    ('necklace', 'outfit', 340, 1, 23), ('tutu', 'outfit', 560, 2, 24),
    ('sneakers', 'shoes', 160, 2, 30), ('boots', 'shoes', 260, 2, 31), ('ballet_shoes', 'shoes', 420, 2, 32),
    ('theme_meadow', 'theme', 0, 0, 40), ('theme_night', 'theme', 200, 0, 41), ('theme_beach', 'theme', 260, 0, 42),
    ('theme_snow', 'theme', 340, 0, 43), ('theme_sakura', 'theme', 480, 0, 44), ('theme_space', 'theme', 640, 0, 45),
    ('theme_castle', 'theme', 900, 0, 46)
ON CONFLICT (code) DO UPDATE SET slot = EXCLUDED.slot, price = EXCLUDED.price, min_stage = EXCLUDED.min_stage, sort_order = EXCLUDED.sort_order;
