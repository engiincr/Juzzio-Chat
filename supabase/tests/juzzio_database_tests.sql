-- =============================================================================
-- JUZZIO — veritabanı testleri (yerel PostgreSQL üzerinde, canlıda ÇALIŞTIRMAYIN)
--  1) P0001: canlıdaki eski tetikleyici grup kurulumunu bozar; kanonik dosya
--     uygulanınca grup kurulur ve birebir oda tekrarı yine engellenir.
--  2) v0.5 RLS / bildirim / çeviri önbelleği / yönetici sağlık testleri.
-- Kullanım: psql -d <testdb> -f supabase/tests/juzzio_database_tests.sql
-- =============================================================================
\set ON_ERROR_STOP 0
\set A 'aaaaaaaa-0000-0000-0000-000000000001'
\set B 'bbbbbbbb-0000-0000-0000-000000000002'
-- Canlıdaki ESKİ tetikleyici (birebir kopya)
CREATE OR REPLACE FUNCTION public.check_dm_room_uniqueness() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $f$
BEGIN
    IF (SELECT COUNT(*) FROM public.room_participants WHERE room_id = NEW.room_id AND left_at IS NULL) = 2 THEN
        IF EXISTS (SELECT 1 FROM public.room_participants rp1 JOIN public.room_participants rp2 ON rp1.room_id = rp2.room_id
            WHERE rp1.user_id = (SELECT user_id FROM public.room_participants WHERE room_id = NEW.room_id AND user_id <> NEW.user_id AND left_at IS NULL LIMIT 1)
              AND rp2.user_id = NEW.user_id AND rp1.room_id <> NEW.room_id AND rp1.left_at IS NULL AND rp2.left_at IS NULL) THEN
            RAISE EXCEPTION 'DM room already exists between these two users';
        END IF;
    END IF;
    RETURN NEW;
END; $f$;
DROP TRIGGER IF EXISTS trg_check_dm_room_uniqueness ON public.room_participants;
CREATE TRIGGER trg_check_dm_room_uniqueness AFTER INSERT ON public.room_participants FOR EACH ROW WHEN (new.left_at IS NULL) EXECUTE FUNCTION check_dm_room_uniqueness();
CREATE OR REPLACE FUNCTION pg_temp.as_user(u uuid) RETURNS void LANGUAGE sql AS $$ SELECT set_config('request.jwt.claim.sub', u::text, false) $$;
SET ROLE authenticated;
SELECT pg_temp.as_user(:'A');
SELECT 'ESKI tetikleyici ile' AS asama, create_group_room('P001 deneme', ARRAY[:'B'::uuid], 'off', false, 'group_work', '', '') IS NOT NULL AS olustu;
RESET ROLE;
\ir ../juzzio_database.sql
SET ROLE authenticated;
SELECT pg_temp.as_user(:'A');
SELECT create_group_room('P001 deneme', ARRAY[:'B'::uuid], 'off', false, 'group_work', '', '') AS gid \gset
RESET ROLE;
SELECT 'YENI tetikleyici ile' AS asama, count(*) AS uye_sayisi FROM room_participants WHERE room_id = :'gid';
-- birebir oda koruması hâlâ çalışıyor mu?
SELECT room_id AS dm FROM room_participants rp JOIN rooms r ON r.id=rp.room_id WHERE NOT r.is_group AND rp.user_id=:'A' AND EXISTS(SELECT 1 FROM room_participants x WHERE x.room_id=rp.room_id AND x.user_id=:'B') LIMIT 1 \gset
INSERT INTO rooms (room_code,title,livekit_room_name,is_group,created_by) VALUES ('dmdup_' || md5(random()::text),'x','lk_dmdup_' || md5(random()::text),false,:'A') RETURNING id AS dup \gset
INSERT INTO room_participants (room_id,user_id,role) VALUES (:'dup',:'A','member');
INSERT INTO room_participants (room_id,user_id,role) VALUES (:'dup',:'B','member');

\set ON_ERROR_STOP 1
\set ON_ERROR_STOP 1
\set A 'aaaaaaaa-0000-0000-0000-000000000001'
\set B 'bbbbbbbb-0000-0000-0000-000000000002'
CREATE OR REPLACE FUNCTION pg_temp.as_user(u uuid) RETURNS void LANGUAGE sql AS $$ SELECT set_config('request.jwt.claim.sub', u::text, false) $$;
CREATE OR REPLACE FUNCTION pg_temp.check(p_name text, p_ok boolean) RETURNS text LANGUAGE plpgsql AS $$
BEGIN IF p_ok IS NOT TRUE THEN RAISE EXCEPTION 'FAIL %', p_name; END IF; RETURN 'PASS ' || p_name; END $$;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA pg_temp TO authenticated, anon;
-- A ve B arkadaş; aralarında DM var. Grup kurulabilmeli (P0001 düzeltmesi)
SET ROLE authenticated;
SELECT pg_temp.as_user(:'A');
SELECT create_group_room('v050 grup', ARRAY[:'B'::uuid], 'off', false, 'friends', '', '') AS gid \gset
RESET ROLE;
SELECT pg_temp.check('grup iki üyeyle kuruldu', (SELECT count(*) FROM room_participants WHERE room_id = :'gid') = 2);
-- Tepki bildirimi
INSERT INTO messages (room_id, sender_id, original_text) VALUES (:'gid', :'A', 'tepki deneme mesajı') RETURNING id AS mid \gset
SELECT room_id AS mroom FROM messages WHERE id = :'mid' \gset
UPDATE profiles SET active_room_id = NULL WHERE id = :'A';
SET ROLE authenticated;
SELECT pg_temp.as_user(:'B');
SELECT toggle_message_reaction(:'mid', '🌸');
RESET ROLE;
SELECT pg_temp.check('tepki bildirimi oluştu', (SELECT count(*) FROM notifications WHERE recipient_id = :'A' AND event_type = 'reaction' AND target_secondary_id = :'mid') = 1);
SELECT pg_temp.check('tepki önizlemesi emojiyle başlar', (SELECT preview_text FROM notifications WHERE recipient_id = :'A' AND event_type = 'reaction' AND target_secondary_id = :'mid') LIKE '🌸|%');
SET ROLE authenticated;
SELECT pg_temp.as_user(:'B');
SELECT toggle_message_reaction(:'mid', '🌸');  -- kaldır
SELECT toggle_message_reaction(:'mid', '🌸');  -- tekrar ekle → yinelenen bildirim yok
RESET ROLE;
SELECT pg_temp.check('tekrar eden tepki bildirimi yok', (SELECT count(*) FROM notifications WHERE recipient_id = :'A' AND event_type = 'reaction' AND target_secondary_id = :'mid') = 1);
-- Sahip sohbetin içindeyse bildirim gitmez
SET ROLE authenticated;
SELECT pg_temp.as_user(:'A');
SELECT set_my_active_room(:'mroom');
SELECT pg_temp.as_user(:'B');
SELECT toggle_message_reaction(:'mid', '🤩');
RESET ROLE;
UPDATE profiles SET last_seen = NOW() WHERE id = :'A';
SELECT pg_temp.check('sohbet açıkken bildirim yok', (SELECT count(*) FROM notifications WHERE recipient_id = :'A' AND event_type = 'reaction' AND preview_text LIKE '🤩|%') = 0);
-- Sohbete girince ilgili bildirimler okundu
SET ROLE authenticated;
SELECT pg_temp.as_user(:'A');
SELECT mark_room_notifications_read(:'mroom') >= 0 AS ok;
RESET ROLE;
SELECT pg_temp.check('oda bildirimleri okundu', (SELECT count(*) FROM notifications WHERE recipient_id = :'A' AND target_id = :'mroom' AND event_type IN ('message','reaction') AND NOT is_read) = 0);
-- Küresel akış: yalnızca yazı paylaşımı
SET ROLE authenticated;
SELECT pg_temp.as_user(:'A');
INSERT INTO posts (author_id, author_username, content_type, caption) VALUES (:'A', 'a', 'text', 'Merhaba dünya');
RESET ROLE;
SELECT pg_temp.check('yazı paylaşımı oluşturuldu', (SELECT count(*) FROM posts WHERE author_id = :'A' AND content_type = 'text') = 1);
-- Çeviri önbelleği istemciye kapalı (zehirlenemez); yönetici sağlık RPC'si yetkisiz kullanıcıya kapalı
INSERT INTO content_translations (kind, content_id, target_lang, source_hash, translated_text)
VALUES ('post', gen_random_uuid(), 'en', 'h', 'x');
DO $$
DECLARE ok BOOLEAN := false;
BEGIN
    SET LOCAL ROLE authenticated;
    BEGIN
        PERFORM 1 FROM public.content_translations;
    EXCEPTION WHEN insufficient_privilege THEN ok := true;
    END;
    RESET ROLE;
    IF NOT ok THEN RAISE EXCEPTION 'FAIL: content_translations istemciye açık'; END IF;
    RAISE NOTICE 'PASS: çeviri önbelleği istemciye kapalı';
END $$;
SET ROLE authenticated;
SELECT pg_temp.as_user(:'B');
DO $$
BEGIN
    BEGIN
        PERFORM public.admin_system_health('sahte');
        RAISE EXCEPTION 'FAIL: sağlık RPC yetkisiz çalıştı';
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
        RAISE NOTICE 'PASS: sağlık RPC yetkisiz kullanıcıyı reddetti (%)', SQLERRM;
    END;
END $$;
RESET ROLE;
SELECT bump_translation_usage('post', 3, 1, 1);
SELECT pg_temp.check('çeviri ölçümü yazıldı', (SELECT requests FROM translation_usage_daily WHERE day = CURRENT_DATE AND kind = 'post') >= 3);
SELECT 'TÜM v0.5.0 TESTLERİ GEÇTİ';

-- =============================================================================
-- 3) v0.5.1: konferanstan katılımcı çıkarma yetkisi + akış konusu filtresi
-- =============================================================================
\set C 'cccccccc-0000-0000-0000-000000000003'
-- A konferansı başlattı; B ve C katıldı
\set S '99999999-0000-0000-0000-000000000051'
\set R 'lk_test_v051_room'
DELETE FROM call_removals WHERE session_id = :'S';
DELETE FROM call_logs WHERE session_id = :'S';
INSERT INTO call_logs (caller_id, receiver_id, is_video, status, session_id, livekit_room_name, is_group, answered_at)
VALUES (:'A', :'B', true, 'answered', :'S', :'R', true, NOW() - INTERVAL '2 minutes'),
       (:'A', :'C', true, 'answered', :'S', :'R', true, NOW() - INTERVAL '1 minute');
SELECT pg_temp.check('C başta katılabilir', can_join_livekit_room(:'C', :'R'));
-- B (yetkisiz) C'yi çıkaramaz
SELECT pg_temp.check('yetkisiz çıkaramaz', (juzzio_remove_call_participant(:'B', :'R', :'C')->>'error') = 'forbidden');
-- Host çıkarılamaz
SELECT pg_temp.check('host çıkarılamaz', (juzzio_remove_call_participant(:'B', :'R', :'A')->>'error') = 'cannot_remove_host');
-- A (host) C'yi çıkarır
SELECT pg_temp.check('host çıkarır', (juzzio_remove_call_participant(:'A', :'R', :'C')->>'ok')::boolean);
SELECT pg_temp.check('C kaydı kapandı', (SELECT ended_at IS NOT NULL AND status_reason = 'removed' AND duration_sec >= 50 FROM call_logs WHERE session_id = :'S' AND receiver_id = :'C'));
SELECT pg_temp.check('C yeniden token alamaz', NOT can_join_livekit_room(:'C', :'R'));
SELECT pg_temp.check('B hâlâ katılabilir', can_join_livekit_room(:'B', :'R'));
-- İstemci yetki sorgusu
SET ROLE authenticated;
SELECT pg_temp.as_user(:'A');
SELECT pg_temp.check('A yönetebilir', can_manage_call(:'R'));
SELECT pg_temp.check('C kendi çıkarılma kaydını görür (A olarak 1)', (SELECT count(*) FROM call_removals WHERE session_id = :'S') = 1);
SELECT pg_temp.as_user(:'B');
SELECT pg_temp.check('B yönetemez', NOT can_manage_call(:'R'));
SELECT pg_temp.check('B kaydı göremez', (SELECT count(*) FROM call_removals WHERE session_id = :'S') = 0);
RESET ROLE;
-- authenticated rol doğrudan çıkarma fonksiyonunu çağıramaz
SET ROLE authenticated;
DO $$ BEGIN
  PERFORM juzzio_remove_call_participant('aaaaaaaa-0000-0000-0000-000000000001', 'lk_test_v051_room', 'bbbbbbbb-0000-0000-0000-000000000002');
  RAISE EXCEPTION 'FAIL authenticated çağırabildi';
EXCEPTION WHEN insufficient_privilege THEN NULL; END $$;
RESET ROLE;
-- Konu filtresi
INSERT INTO posts (author_id, content_type, caption, topic) VALUES (:'A', 'text', 'v051 spor', 'sports');
SELECT pg_temp.check('konu kaydedildi', (SELECT count(*) FROM posts WHERE caption = 'v051 spor' AND topic = 'sports') = 1);
DO $$ BEGIN
  INSERT INTO posts (author_id, content_type, caption, topic) VALUES ('aaaaaaaa-0000-0000-0000-000000000001', 'text', 'x', 'nonsense');
  RAISE EXCEPTION 'FAIL geçersiz konu kabul edildi';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DELETE FROM posts WHERE caption = 'v051 spor';
DELETE FROM call_removals WHERE session_id = :'S';
DELETE FROM call_logs WHERE session_id = :'S';
SELECT 'TÜM v0.5.1 TESTLERİ GEÇTİ';

-- =============================================================================
-- 4) v0.6.0: ad/fotoğraf denetimi, ceza basamağı (1 sa / 4 sa / kalıcı), yönetici araçları
-- =============================================================================
\set A 'aaaaaaaa-0000-0000-0000-000000000001'
\set B 'bbbbbbbb-0000-0000-0000-000000000002'
\set C 'cccccccc-0000-0000-0000-000000000003'
\set D 'dddddddd-0000-0000-0000-000000000004'
-- temizlik
DELETE FROM moderation_strikes WHERE user_id IN (:'B', :'C', :'D');
DELETE FROM banned_users WHERE user_id IN (:'B', :'C', :'D');
DELETE FROM banned_identities WHERE user_id IN (:'B', :'C', :'D');
DELETE FROM call_speech_hits WHERE user_id IN (:'B', :'C', :'D');
DELETE FROM media_moderation WHERE user_id IN (:'B', :'C', :'D');
UPDATE profiles SET avatar_url = NULL WHERE id = :'C';
UPDATE profiles SET username = 'ali' WHERE id = :'A';
DELETE FROM banned_devices WHERE device_id = 'and_testdevice_060';
DELETE FROM call_logs WHERE livekit_room_name LIKE 'lk_v060%';
DELETE FROM admin_sessions WHERE user_id = :'A';
DELETE FROM notifications WHERE target_id LIKE 'moderation_%';
-- 1) Ad denetimi: yeni terimler
SELECT pg_temp.check('müstehcen ad reddedilir', NOT juzzio_text_is_clean('Seksi Amcik 34', false));
SELECT pg_temp.check('normal ad geçer', juzzio_text_is_clean('Engin Çelik', false));
SELECT pg_temp.check('İngilizce got geçer', juzzio_text_is_clean('I got it', false));
SET ROLE authenticated;
SELECT pg_temp.as_user(:'C');
DO $$ BEGIN
  UPDATE profiles SET display_name = 'pornhub kral' WHERE id = 'cccccccc-0000-0000-0000-000000000003';
  RAISE EXCEPTION 'FAIL uygunsuz görünen ad kabul edildi';
EXCEPTION WHEN SQLSTATE '22023' THEN NULL; END $$;
-- 2) Profil fotoğrafı: denetimsiz adres reddedilir
DO $$ BEGIN
  UPDATE profiles SET avatar_url = 'https://x.supabase.co/storage/v1/object/public/avatars/c/a1.jpg' WHERE id = 'cccccccc-0000-0000-0000-000000000003';
  RAISE EXCEPTION 'FAIL denetimsiz fotoğraf kabul edildi';
EXCEPTION WHEN SQLSTATE '22023' THEN NULL; END $$;
RESET ROLE;
INSERT INTO media_moderation (user_id, kind, url, verdict, provider) VALUES (:'C', 'avatar', 'https://x.supabase.co/storage/v1/object/public/avatars/c/a1.jpg', 'safe', 'test');
SET ROLE authenticated;
SELECT pg_temp.as_user(:'C');
UPDATE profiles SET avatar_url = 'https://x.supabase.co/storage/v1/object/public/avatars/c/a1.jpg' WHERE id = :'C';
SELECT pg_temp.check('onaylı fotoğraf kaydedildi', (SELECT avatar_url FROM profiles WHERE id = :'C') LIKE '%a1.jpg');
SELECT pg_temp.check('kullanıcı kendi denetim kaydını görür', (SELECT count(*) FROM media_moderation WHERE user_id = :'C') = 1);
SELECT pg_temp.as_user(:'B');
SELECT pg_temp.check('başkasının denetim kaydı görünmez', (SELECT count(*) FROM media_moderation WHERE user_id = :'C') = 0);
RESET ROLE;
-- 3) Ceza basamağı
\set R 'lk_v060_room'
INSERT INTO call_logs (caller_id, receiver_id, is_video, status, session_id, livekit_room_name, answered_at)
VALUES (:'D', :'B', true, 'answered', '99999999-0000-0000-0000-000000000060', :'R', NOW() - INTERVAL '1 minute');
SELECT juzzio_record_violation(:'D', 'call_nudity', 'test', :'R') AS v1 \gset
SELECT pg_temp.check('1. ihlal 1 saat', (:'v1'::jsonb->>'penalty') = 'suspend_1h');
SELECT pg_temp.check('arama kapandı', (SELECT ended_at IS NOT NULL AND status_reason = 'moderation' FROM call_logs WHERE session_id = '99999999-0000-0000-0000-000000000060'));
SELECT pg_temp.check('askıda', juzzio_is_banned(:'D'));
SELECT pg_temp.check('askı ~1 saat', (SELECT expires_at BETWEEN NOW() + INTERVAL '55 minutes' AND NOW() + INTERVAL '65 minutes' FROM banned_users WHERE user_id = :'D'));
SELECT pg_temp.check('uyarı bildirimi', (SELECT count(*) FROM notifications WHERE recipient_id = :'D' AND target_id = 'moderation_suspend_1h') = 1);
SET ROLE authenticated;
SELECT pg_temp.as_user(:'D');
SELECT pg_temp.check('askıdayken erişim kapalı', (check_device_access('and_other_device_1')->>'banned')::boolean);
RESET ROLE;
UPDATE banned_users SET expires_at = NOW() - INTERVAL '1 minute' WHERE user_id = :'D';
SET ROLE authenticated;
SELECT pg_temp.as_user(:'D');
SELECT pg_temp.check('süre dolunca erişim açık', NOT (check_device_access('and_other_device_1')->>'banned')::boolean);
SELECT register_my_device('and_other_device_1', 'android');
RESET ROLE;
SELECT pg_temp.check('süreli cezada yeni cihaz engellenmez', NOT EXISTS (SELECT 1 FROM banned_devices WHERE device_id = 'and_other_device_1'));
DELETE FROM user_devices WHERE device_id = 'and_other_device_1';
SELECT juzzio_record_violation(:'D', 'call_nudity', 'aynı olay', :'R') AS dup \gset
SELECT pg_temp.check('aynı olayda tek ceza', (:'dup'::jsonb->>'duplicate')::boolean);
UPDATE moderation_strikes SET created_at = NOW() - INTERVAL '1 day' WHERE user_id = :'D';
SELECT juzzio_record_violation(:'D', 'call_speech', 'test2', 'lk_v060_room2') AS v2 \gset
SELECT pg_temp.check('2. ihlal 4 saat', (:'v2'::jsonb->>'penalty') = 'suspend_4h');
SELECT pg_temp.check('askı ~4 saat', (SELECT expires_at > NOW() + INTERVAL '3 hours 50 minutes' FROM banned_users WHERE user_id = :'D'));
UPDATE moderation_strikes SET created_at = NOW() - INTERVAL '1 day' WHERE user_id = :'D';
INSERT INTO user_devices (user_id, device_id, platform) VALUES (:'D', 'and_testdevice_060', 'android') ON CONFLICT DO NOTHING;
SELECT juzzio_record_violation(:'D', 'call_nudity', 'test3', 'lk_v060_room3') AS v3 \gset
SELECT pg_temp.check('3. ihlal kalıcı', (:'v3'::jsonb->>'penalty') = 'permanent');
SELECT pg_temp.check('kalıcı engel süresiz', (SELECT expires_at IS NULL FROM banned_users WHERE user_id = :'D'));
SELECT pg_temp.check('cihaz engellendi', EXISTS (SELECT 1 FROM banned_devices WHERE device_id = 'and_testdevice_060'));
SELECT pg_temp.check('cihaz erişimi kapalı', (check_device_access('and_testdevice_060')->>'banned')::boolean);
-- e-posta kaydı (auth.users e-postası varsa)
SELECT pg_temp.check('e-posta özeti (varsa) kaydedildi',
  (SELECT email FROM auth.users WHERE id = :'D') IS NULL OR EXISTS (SELECT 1 FROM banned_identities WHERE user_id = :'D'));
-- 4) Konuşma: v0.7.0'dan itibaren argo/küfür hiçbir zaman ceza değil
SELECT juzzio_record_speech_hit(:'C', 'lk_v060_sp', 'merhaba nasılsın') AS s0 \gset
SELECT pg_temp.check('temiz konuşma', NOT (:'s0'::jsonb->>'explicit')::boolean);
SELECT juzzio_record_speech_hit(:'C', 'lk_v060_sp', 'siktir git') AS s1 \gset
SELECT pg_temp.check('v0.7.0: argo ceza değil', (:'s1'::jsonb->'violation') IS NULL);
SELECT juzzio_record_speech_hit(:'C', 'lk_v060_sp', 'orospu') AS s2 \gset
SELECT pg_temp.check('v0.7.0: tekrar eden argo da ceza değil', (:'s2'::jsonb->'violation') IS NULL AND NOT juzzio_is_banned(:'C'));
-- 5) yetkisiz çağrı
SET ROLE authenticated;
SELECT pg_temp.as_user(:'B');
DO $$ BEGIN
  PERFORM juzzio_record_violation('cccccccc-0000-0000-0000-000000000003', 'admin', 'x', '');
  RAISE EXCEPTION 'FAIL authenticated ceza verebildi';
EXCEPTION WHEN insufficient_privilege THEN NULL; END $$;
DO $$ BEGIN
  PERFORM admin_list_strikes('yanlis-token', NULL);
  RAISE EXCEPTION 'FAIL token olmadan admin';
EXCEPTION WHEN raise_exception THEN
  IF SQLERRM <> 'admin_session_invalid' THEN RAISE; END IF;
END $$;
SELECT pg_temp.check('kendi durumu okunur', (get_my_moderation_status()->>'strikes')::int = 0);
RESET ROLE;
-- 6) Yönetici işlevleri (test için yönetici oturumu)
UPDATE profiles SET username = 'tugkancr' WHERE id = :'A';
INSERT INTO admin_sessions (token_hash, user_id, expires_at)
VALUES (encode(digest('test-admin-token-060', 'sha256'), 'hex'), :'A', NOW() + INTERVAL '1 hour')
ON CONFLICT DO NOTHING;
SET ROLE authenticated;
SELECT pg_temp.as_user(:'A');
SELECT pg_temp.check('admin ihlal listesi', jsonb_array_length(admin_list_strikes('test-admin-token-060', NULL)) >= 3);
SELECT pg_temp.check('admin özet', (admin_moderation_overview('test-admin-token-060')->>'permanent_bans')::int >= 1);
SELECT admin_upsert_banned_term('test-admin-token-060', 'Deneme Küfür', 'contains', true);
SELECT pg_temp.check('admin terim ekledi', EXISTS (SELECT 1 FROM jsonb_array_elements(admin_list_banned_terms('test-admin-token-060')) e WHERE e->>'term' = 'deneme kufur'));
SELECT admin_delete_banned_term('test-admin-token-060', 'deneme kufur');
SELECT pg_temp.check('ad taraması çalışır', jsonb_typeof(admin_scan_names('test-admin-token-060')->'users') = 'array');
SELECT admin_set_setting('test-admin-token-060', 'default_glass_palette', '"emerald"'::jsonb);
SELECT pg_temp.check('cam teması ayarı', (get_app_config()->>'default_glass_palette') = 'emerald');
SELECT admin_set_setting('test-admin-token-060', 'default_glass_palette', '"ocean"'::jsonb);
DO $$ BEGIN
  PERFORM admin_set_setting('test-admin-token-060', 'default_glass_palette', '"orange"'::jsonb);
  RAISE EXCEPTION 'FAIL geçersiz palet kabul edildi';
EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'invalid_setting' THEN RAISE; END IF; END $$;
SELECT pg_temp.check('aktif aramalar listesi', jsonb_typeof(admin_active_calls('test-admin-token-060')) = 'array');
SELECT pg_temp.check('son gönderiler', jsonb_typeof(admin_recent_content('test-admin-token-060', 'post', '')) = 'array');
SELECT pg_temp.check('son yorumlar', jsonb_typeof(admin_recent_content('test-admin-token-060', 'comment', '')) = 'array');
SELECT pg_temp.check('son hikâyeler', jsonb_typeof(admin_recent_content('test-admin-token-060', 'story', '')) = 'array');
SELECT pg_temp.check('grup listesi', jsonb_typeof(admin_list_groups('test-admin-token-060', '')) = 'array');
SELECT admin_update_user_profile('test-admin-token-060', :'C', 'Temiz Ad', NULL, NULL, true);
SELECT pg_temp.check('admin profil düzenledi', (SELECT display_name = 'Temiz Ad' AND avatar_url IS NULL FROM profiles WHERE id = :'C'));
SELECT pg_temp.check('medya kuyruğu', jsonb_typeof(admin_media_queue('test-admin-token-060', 'all')) = 'array');
-- ihlali geri al → engel kalkar
RESET ROLE;
-- v0.7.0: konuşma artık ihlal üretmediği için C'ye test ihlali görüntü kaynaklı verilir
SELECT juzzio_record_violation(:'C', 'call_nudity', 'nsfw', 'lk_v060_test') AS vtest \gset
SELECT id AS sid FROM moderation_strikes WHERE user_id = :'C' ORDER BY id DESC LIMIT 1 \gset
SET ROLE authenticated;
SELECT pg_temp.as_user(:'A');
SELECT admin_revoke_strike('test-admin-token-060', :sid, true);
SELECT pg_temp.check('ihlal geri alındı, engel kalktı', NOT juzzio_is_banned(:'C'));
RESET ROLE;
-- temizlik
UPDATE profiles SET username = 'ali' WHERE id = :'A';
DELETE FROM admin_sessions WHERE user_id = :'A';
DELETE FROM moderation_strikes WHERE user_id IN (:'B', :'C', :'D');
DELETE FROM banned_users WHERE user_id IN (:'B', :'C', :'D');
DELETE FROM banned_devices WHERE device_id = 'and_testdevice_060';
DELETE FROM user_devices WHERE device_id = 'and_testdevice_060';
DELETE FROM banned_identities WHERE user_id IN (:'B', :'C', :'D');
DELETE FROM call_speech_hits WHERE user_id IN (:'B', :'C', :'D');
DELETE FROM media_moderation WHERE user_id IN (:'B', :'C', :'D');
UPDATE profiles SET avatar_url = NULL WHERE id = :'C';
UPDATE profiles SET username = 'ali' WHERE id = :'A';
DELETE FROM banned_devices WHERE device_id = 'and_testdevice_060';
DELETE FROM call_logs WHERE livekit_room_name LIKE 'lk_v060%';
-- 7) Özellik bayrağı sunucuda uygulanır
UPDATE app_settings SET value = 'false'::jsonb WHERE key = 'posts_enabled';
SET ROLE authenticated;
SELECT pg_temp.as_user(:'B');
DO $$ BEGIN
  INSERT INTO posts (author_id, content_type, caption) VALUES ('bbbbbbbb-0000-0000-0000-000000000002', 'text', 'kapalıyken');
  RAISE EXCEPTION 'FAIL kapalı özellikte gönderi açıldı';
EXCEPTION WHEN SQLSTATE '22023' THEN NULL; END $$;
RESET ROLE;
UPDATE app_settings SET value = 'true'::jsonb WHERE key = 'posts_enabled';
SELECT pg_temp.check('bayrak geri açıldı', juzzio_setting_bool('posts_enabled', false));
SELECT 'TÜM v0.6.0 TESTLERİ GEÇTİ';
-- ===================== v0.6.1: şeffaf sürüm notları + depolama listeleme =====================
UPDATE profiles SET username = 'tugkancr' WHERE id = :'A';
INSERT INTO admin_sessions (token_hash, user_id, expires_at)
VALUES (encode(digest('test-admin-token-061', 'sha256'), 'hex'), :'A', NOW() + INTERVAL '1 hour')
ON CONFLICT DO NOTHING;
SET ROLE authenticated;
SELECT pg_temp.as_user(:'A');
DO $$ BEGIN
  PERFORM admin_publish_release('test-admin-token-061', '9.9.1', 99901, 'https://example.com/a.apk', '', '', '', false, '{}'::jsonb);
  RAISE EXCEPTION 'FAIL gerekçesiz sürüm yayınlandı';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM NOT LIKE '%release_reason_required%' THEN RAISE; END IF;
END $$;
SELECT admin_publish_release('test-admin-token-061', '9.9.2', 99902, 'https://example.com/b.apk', 'not', '', '', true,
  '{"tr":{"reason":"test gerekçe","features":["a"],"fixes":["b"],"security":[]}}'::jsonb);
SELECT pg_temp.check('ayrıntılar kaydedildi',
  (SELECT details->'tr'->>'reason' = 'test gerekçe' AND is_mandatory FROM app_releases WHERE version_code = 99902));
RESET ROLE;
DELETE FROM app_releases WHERE version_code IN (99901, 99902);
DO $$ BEGIN
  IF to_regclass('storage.objects') IS NOT NULL THEN
    IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='storage' AND tablename='objects'
               AND policyname IN ('juzzio_v2_storage_read','juzzio_storage_public_read')) THEN
      RAISE EXCEPTION 'FAIL eski herkese açık listeleme politikası duruyor';
    END IF;
  END IF;
END $$;
SET ROLE authenticated;
SELECT pg_temp.as_user(:'A');
SELECT admin_publish_release('test-admin-token-061', '9.9.3', 99903, 'https://example.com/c.apk', 'kısa not', '', '', false, '{}'::jsonb);
SELECT pg_temp.check('v0.7.0: gerekçe kısa nottan dolduruldu',
  (SELECT details->'tr'->>'reason' = 'kısa not' FROM app_releases WHERE version_code = 99903));
RESET ROLE;
DELETE FROM app_releases WHERE version_code = 99903;
DELETE FROM admin_sessions WHERE user_id = :'A';
UPDATE profiles SET username = 'ali' WHERE id = :'A';
SELECT 'TÜM v0.6.1 TESTLERİ GEÇTİ';
-- ===================== v0.7.0 =====================
\set C 'cccccccc-0000-0000-0000-000000000003'
-- 1) Yakın arkadaşlar: hikâyeyi yalnızca listedeki kişi görür
INSERT INTO stories (user_id, media_url, media_type, visibility, expires_at)
VALUES (:'A', 'https://x.supabase.co/storage/v1/object/public/stories/a/s.jpg', 'image', 'close_friends', NOW() + INTERVAL '1 day')
RETURNING id AS cfs \gset
SET ROLE authenticated;
SELECT pg_temp.as_user(:'A');
INSERT INTO close_friends (owner_id, friend_id) VALUES (:'A', :'C');
SELECT pg_temp.check('sahip yakın arkadaş listesini görür', (SELECT count(*) FROM close_friends) = 1);
SELECT pg_temp.as_user(:'C');
SELECT pg_temp.check('listedeki kişi hikâyeyi görür', EXISTS (SELECT 1 FROM stories WHERE id = :'cfs'));
SELECT pg_temp.check('listedeki kişi listeyi göremez', (SELECT count(*) FROM close_friends) = 0);
SELECT pg_temp.as_user(:'B');
SELECT pg_temp.check('arkadaş olsa da listede olmayan göremez', NOT EXISTS (SELECT 1 FROM stories WHERE id = :'cfs'));
DO $$ BEGIN
  INSERT INTO close_friends (owner_id, friend_id) VALUES ('aaaaaaaa-0000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000002');
  RAISE EXCEPTION 'FAIL başkası adına yakın arkadaş eklendi';
EXCEPTION WHEN insufficient_privilege THEN NULL; END $$;
RESET ROLE;
DELETE FROM stories WHERE id = :'cfs';
DELETE FROM close_friends WHERE owner_id = :'A';
-- 2) Uçtan uca şifreli mesaj: sunucu içeriği görmez, önizleme kilitli
SELECT room_id AS dmroom FROM room_participants rp JOIN rooms r ON r.id = rp.room_id
 WHERE NOT r.is_group AND rp.user_id = :'A' AND rp.left_at IS NULL
   AND EXISTS (SELECT 1 FROM room_participants x WHERE x.room_id = rp.room_id AND x.user_id = :'B' AND x.left_at IS NULL)
 ORDER BY r.created_at LIMIT 1 \gset
SET ROLE authenticated;
SELECT pg_temp.as_user(:'A');
INSERT INTO messages (room_id, sender_id, message_type, original_text, translated_text, metadata)
VALUES (:'dmroom', :'A', 'text', '', '', '{"e2ee": {"v": 1, "spk": "x", "rpk": "y", "c": "zz"}}'::jsonb);
RESET ROLE;
SELECT pg_temp.check('şifreli mesaj önizlemesi kilitli', (SELECT last_message_preview FROM rooms WHERE id = :'dmroom') = '🔒 Şifreli mesaj');
UPDATE profiles SET e2ee_public_key = 'geçersiz' WHERE id = :'A';
SELECT pg_temp.check('geçersiz açık anahtar reddedildi', (SELECT e2ee_public_key FROM profiles WHERE id = :'A') = '');
UPDATE profiles SET e2ee_public_key = 'QUJDREVGR0hJSktMTU5PUFFSU1RVVldYWVphYmNkZWY=' WHERE id = :'A';
SELECT pg_temp.check('geçerli açık anahtar kaydedildi', (SELECT length(e2ee_public_key) FROM profiles WHERE id = :'A') = 44);
-- 3) Arama sonu: ended_by + sohbet içi arama kaydı (yalnızca bir kez)
INSERT INTO call_logs (session_id, room_id, caller_id, caller_name, receiver_id, receiver_name, is_video, status, answered_at, livekit_room_name)
VALUES ('11111111-2222-3333-4444-555555555555', :'dmroom', :'A', 'Ali', :'B', 'Bora', false, 'answered', NOW() - INTERVAL '2 minutes', 'lk_v070_call');
SET ROLE authenticated;
SELECT pg_temp.as_user(:'B');
SELECT end_call_session('11111111-2222-3333-4444-555555555555', 95, false);
SELECT end_call_session('11111111-2222-3333-4444-555555555555', 95, false);
RESET ROLE;
SELECT pg_temp.check('ilk kapatan kaydedildi', (SELECT ended_by FROM call_logs WHERE session_id = '11111111-2222-3333-4444-555555555555') = :'B');
SELECT pg_temp.check('sohbette tek arama kaydı', (SELECT count(*) FROM messages WHERE room_id = :'dmroom' AND message_type = 'call'
   AND metadata->'call'->>'session_id' = '11111111-2222-3333-4444-555555555555') = 1);
SELECT pg_temp.check('arama kaydı mesaj bildirimi üretmez', NOT EXISTS (SELECT 1 FROM notifications WHERE recipient_id = :'A'
   AND event_type = 'message' AND created_at > NOW() - INTERVAL '5 seconds' AND preview_text LIKE '%Arama%'));
DELETE FROM messages WHERE room_id = :'dmroom' AND message_type = 'call';
DELETE FROM call_logs WHERE livekit_room_name = 'lk_v070_call';
-- 4) Süreli mesaj ayarı (1'e 1)
SET ROLE authenticated;
SELECT pg_temp.as_user(:'B');
SELECT set_room_disappearing_timer(:'dmroom', '7d');
RESET ROLE;
SELECT pg_temp.check('süreli mesaj 7 gün', (SELECT disappearing_timer FROM rooms WHERE id = :'dmroom') = '7d');
UPDATE rooms SET disappearing_timer = 'off' WHERE id = :'dmroom';
-- 5) Ses tercihleri: yalnızca kendi satırı, geçersiz değer düzeltilir
SET ROLE authenticated;
SELECT pg_temp.as_user(:'A');
INSERT INTO user_sound_prefs (user_id, message_tone, ringtone, contact_prefs)
VALUES (:'A', 'juzzio_tone_pop', 'bozuk; DROP', '{"bbbbbbbb-0000-0000-0000-000000000002": {"ring": "juzzio_ring_pulse"}}'::jsonb);
SELECT pg_temp.check('geçersiz zil sesi varsayılana döndü', (SELECT ringtone FROM user_sound_prefs WHERE user_id = :'A') = 'juzzio_ring_aurora');
SELECT pg_temp.as_user(:'B');
SELECT pg_temp.check('başkasının ses tercihleri görünmez', (SELECT count(*) FROM user_sound_prefs) = 0);
-- 6) Hata bildirimi: kendi adına eklenir, başkası göremez
INSERT INTO app_feedback (user_id, kind, message) VALUES (:'B', 'bug', 'Arama ekranında düğme taşıyor');
SELECT pg_temp.check('kendi bildirimini görür', (SELECT count(*) FROM app_feedback) = 1);
SELECT pg_temp.as_user(:'A');
SELECT pg_temp.check('başkasının bildirimini göremez', (SELECT count(*) FROM app_feedback) = 0);
RESET ROLE;
DELETE FROM app_feedback WHERE user_id = :'B';
DELETE FROM user_sound_prefs WHERE user_id = :'A';
-- 7) Konuşma hiçbir zaman ceza değil
SELECT pg_temp.check('konuşma ceza üretmez', (juzzio_record_speech_hit(:'C', 'lk_v070', 'siktir git orospu')->'violation') IS NULL);
-- 8) Müzik: YouTube reddedilir, önizleme kabul edilir
SET ROLE authenticated;
SELECT pg_temp.as_user(:'A');
DO $$ BEGIN
  UPDATE profiles SET music_url = 'https://youtu.be/dQw4w9WgXcQ' WHERE id = 'aaaaaaaa-0000-0000-0000-000000000001';
  RAISE EXCEPTION 'FAIL YouTube bağlantısı kabul edildi';
EXCEPTION WHEN SQLSTATE '22023' THEN NULL; END $$;
UPDATE profiles SET music_url = 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview/x/y.m4a', music_title = 'Şarkı' WHERE id = :'A';
RESET ROLE;
SELECT pg_temp.check('önizleme müziği kaydedildi', (SELECT music_url LIKE 'https://audio-ssl.itunes.apple.com/%' AND music_title = 'Şarkı' FROM profiles WHERE id = :'A'));
UPDATE profiles SET music_url = '', music_title = '' WHERE id = :'A';
SELECT 'TÜM v0.7.0 TESTLERİ GEÇTİ';

-- =============================================================================
-- v0.8.3: RBAC + KÜRESEL TEMA STÜDYOSU TESTLERİ
-- =============================================================================
RESET ROLE;
\set A 'aaaaaaaa-0000-0000-0000-000000000001'
\set B 'bbbbbbbb-0000-0000-0000-000000000002'
\set C 'cccccccc-0000-0000-0000-000000000003'
\set TP '{"schema":"juzzio-theme","version":1,"name":"Test","mode":"dark","gradient":true,"colors":{"background":"#050A12","gradientA":"#20D9F2","gradientB":"#397BFF","gradientC":"#925CFF","text":"#F5F9FF","heading":"#FFFFFF","button":"#20D9F2","buttonText":"#041018","card":"#101B2A","bubbleOut":"#1E6FD9","bubbleIn":"#172536","icon":"#DDE7F5","border":"#40FFFFFF"},"glass":{"blur":18,"opacity":0.3,"intensity":1.0}}'
SELECT set_config('juzzio.tp', :'TP', false);
DELETE FROM global_themes;
DELETE FROM staff_roles WHERE user_id IN (:'A', :'B', :'C');
UPDATE profiles SET username = 'tugkancr' WHERE id = :'A';
SET search_path = public, extensions;
DELETE FROM admin_sessions WHERE user_id = :'A';
INSERT INTO admin_sessions (token_hash, user_id, expires_at)
VALUES ((SELECT encode(digest('tok083', 'sha256'), 'hex')), :'A', NOW() + INTERVAL '1 hour');

SET ROLE authenticated;
-- 1) Rolü olmayan kullanıcı taslak kaydedemez
SELECT pg_temp.as_user(:'C');
DO $$ BEGIN
  PERFORM admin_theme_save_draft('', 'x', '{"schema":"juzzio-theme"}'::jsonb);
  RAISE EXCEPTION 'FAIL yetkisiz taslak kaydı';
EXCEPTION WHEN raise_exception THEN
  IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
  IF SQLERRM NOT LIKE 'permission_denied%' THEN RAISE EXCEPTION 'FAIL beklenmeyen hata: %', SQLERRM; END IF;
END $$;
SELECT pg_temp.check('rolsüz kullanıcı yetki almaz', NOT juzzio_has_permission('theme.publish'));
-- 2) Süper yönetici rol verir; kendine rol veremez
SELECT pg_temp.as_user(:'A');
SELECT pg_temp.check('süper yönetici rolü', juzzio_staff_role() = 'super_admin');
SELECT admin_grant_role('tok083', :'B', 'content_manager');
DO $$ BEGIN
  PERFORM admin_grant_role('tok083', 'aaaaaaaa-0000-0000-0000-000000000001', 'admin');
  RAISE EXCEPTION 'FAIL kendine rol verildi';
EXCEPTION WHEN raise_exception THEN
  IF SQLERRM NOT LIKE 'cannot_change_own_role%' THEN RAISE EXCEPTION 'FAIL: %', SQLERRM; END IF;
END $$;
DO $$ BEGIN
  PERFORM admin_grant_role('tok083', 'cccccccc-0000-0000-0000-000000000003', 'god');
  RAISE EXCEPTION 'FAIL geçersiz rol kabul edildi';
EXCEPTION WHEN raise_exception THEN
  IF SQLERRM NOT LIKE 'invalid_role%' THEN RAISE EXCEPTION 'FAIL: %', SQLERRM; END IF;
END $$;
-- 3) İçerik yöneticisi (B): token olmadan, yalnızca izinle
SELECT pg_temp.as_user(:'B');
SELECT pg_temp.check('B içerik yöneticisi', juzzio_staff_role() = 'content_manager' AND juzzio_has_permission('theme.publish'));
SELECT pg_temp.check('B rol yönetemez', NOT juzzio_has_permission('roles.read'));
DO $$ BEGIN
  PERFORM admin_grant_role('', 'cccccccc-0000-0000-0000-000000000003', 'admin');
  RAISE EXCEPTION 'FAIL içerik yöneticisi rol verdi';
EXCEPTION WHEN raise_exception THEN
  IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
END $$;
SELECT pg_temp.check('v1 taslak', admin_theme_save_draft('', 'Okyanus', :'TP'::jsonb, 'ilk') = 1);
DO $$ BEGIN
  PERFORM admin_theme_save_draft('', 'Bozuk', jsonb_set(current_setting('juzzio.tp')::jsonb, '{colors,text}', '"#GGGGGG"'));
  RAISE EXCEPTION 'FAIL geçersiz renk kabul edildi';
EXCEPTION WHEN raise_exception THEN
  IF SQLERRM NOT LIKE 'theme_invalid_color:text%' THEN RAISE EXCEPTION 'FAIL: %', SQLERRM; END IF;
END $$;
DO $$ BEGIN
  PERFORM admin_theme_save_draft('', 'Bozuk', jsonb_set(current_setting('juzzio.tp')::jsonb, '{glass,blur}', '99'));
  RAISE EXCEPTION 'FAIL sınır dışı blur kabul edildi';
EXCEPTION WHEN raise_exception THEN
  IF SQLERRM NOT LIKE 'theme_invalid_blur%' THEN RAISE EXCEPTION 'FAIL: %', SQLERRM; END IF;
END $$;
-- 4) Taslak herkese görünmez
SELECT pg_temp.as_user(:'C');
SELECT pg_temp.check('taslak C için görünmez', (SELECT COUNT(*) FROM global_themes) = 0);
SELECT pg_temp.check('yayın yokken aktif tema yok', get_active_global_theme() IS NULL);
-- 5) Yayın → herkes görür
SELECT pg_temp.as_user(:'B');
SELECT admin_theme_publish('', 1, NULL);
SELECT pg_temp.as_user(:'C');
SELECT pg_temp.check('v1 yayında', (get_active_global_theme()->>'version')::int = 1);
-- 6) İleri tarihli zamanlama: henüz geçerli değil
SELECT pg_temp.as_user(:'B');
SELECT pg_temp.check('v2 taslak', admin_theme_save_draft('', 'Gece', :'TP'::jsonb) = 2);
SELECT admin_theme_publish('', 2, NOW() + INTERVAL '2 days');
SELECT pg_temp.as_user(:'C');
SELECT pg_temp.check('zamanlanmış v2 henüz aktif değil', (get_active_global_theme()->>'version')::int = 1);
SELECT pg_temp.check('zamanlanmış v2 C için görünmez', NOT EXISTS (SELECT 1 FROM global_themes WHERE version = 2));
-- 7) Geri alma: v1 yeni sürüm (v3) olarak yayınlanır, geçmiş korunur
SELECT pg_temp.as_user(:'B');
SELECT pg_temp.check('geri alma v3', admin_theme_rollback('', 1) = 3);
SELECT pg_temp.as_user(:'C');
SELECT pg_temp.check('v3 aktif', (get_active_global_theme()->>'version')::int = 3);
-- 8) Arşiv: aktif kaldırılınca önceki kararlı yayın (v1) geçerli olur
SELECT pg_temp.as_user(:'B');
SELECT admin_theme_archive('', 3);
SELECT pg_temp.as_user(:'C');
SELECT pg_temp.check('arşivden sonra v1 aktif', (get_active_global_theme()->>'version')::int = 1);
-- 9) Doğrudan tablo yazımı engelli
DO $$ BEGIN
  INSERT INTO global_themes (version, name, payload) VALUES (99, 'hack', '{}'::jsonb);
  RAISE EXCEPTION 'FAIL doğrudan yazım';
EXCEPTION WHEN insufficient_privilege THEN NULL; END $$;
DO $$ BEGIN
  INSERT INTO staff_roles (user_id, role) VALUES ('cccccccc-0000-0000-0000-000000000003', 'admin');
  RAISE EXCEPTION 'FAIL kendine rol yazımı';
EXCEPTION WHEN insufficient_privilege THEN NULL; END $$;
SELECT pg_temp.check('C rol tablosunu göremez', (SELECT COUNT(*) FROM staff_roles) = 0);
SELECT pg_temp.as_user(:'B');
SELECT pg_temp.check('B yalnız kendi rolünü görür', (SELECT COUNT(*) FROM staff_roles) = 1);
-- 10) Denetim kayıtları ve rol geri alma
RESET ROLE;
SELECT pg_temp.check('denetim kayıtları yazıldı',
  (SELECT COUNT(*) FROM admin_audit_log WHERE action IN ('grant_role','theme_save_draft','theme_publish','theme_rollback','theme_archive')) >= 6);
SET ROLE authenticated;
SELECT pg_temp.as_user(:'A');
SELECT admin_revoke_role('tok083', :'B');
SELECT pg_temp.as_user(:'B');
SELECT pg_temp.check('rol geri alındı', NOT juzzio_has_permission('theme.publish'));
RESET ROLE;
DELETE FROM admin_sessions WHERE user_id = :'A';
DELETE FROM global_themes;
UPDATE profiles SET username = 'ali' WHERE id = :'A';
SELECT 'TÜM v0.8.3 TESTLERİ GEÇTİ';
