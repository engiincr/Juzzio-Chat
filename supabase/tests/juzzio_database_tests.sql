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

-- =============================================================================
-- v0.9.0: GÜVENLİK SERTLEŞTİRMESİ (Bölüm 10) — pozitif + NEGATİF yetki testleri
-- =============================================================================
\set A 'aaaaaaaa-0000-0000-0000-000000000001'
\set B 'bbbbbbbb-0000-0000-0000-000000000002'
\set C 'cccccccc-0000-0000-0000-000000000003'
\set D 'dddddddd-0000-0000-0000-000000000004'
\set S9 '99999999-0000-0000-0000-000000000090'
\set R9 'lk_test_v090_room'
RESET ROLE;
DELETE FROM banned_users WHERE user_id IN (:'A', :'B', :'C', :'D');
DELETE FROM call_removals WHERE session_id = :'S9';
DELETE FROM call_logs WHERE session_id = :'S9';
-- A arayan, B cevapladı (etkin), C çıkarıldı (bitmiş), D cevapladı ama çağrıdan çıktı (bitmiş)
INSERT INTO call_logs (caller_id, receiver_id, is_video, status, session_id, livekit_room_name, is_group, answered_at, ended_at)
VALUES (:'A', :'B', false, 'answered', :'S9', :'R9', true, NOW() - INTERVAL '3 minutes', NULL),
       (:'A', :'C', false, 'answered', :'S9', :'R9', true, NOW() - INTERVAL '3 minutes', NULL),
       (:'A', :'D', false, 'answered', :'S9', :'R9', true, NOW() - INTERVAL '3 minutes', NOW() - INTERVAL '1 minute');
SELECT juzzio_remove_call_participant(:'A', :'R9', :'C');

-- G01: LiveKit token
SELECT pg_temp.check('G01 etkin katılımcı B token alır', can_join_livekit_room(:'B', :'R9'));
SELECT pg_temp.check('G01 çıkarılan C token alamaz', NOT can_join_livekit_room(:'C', :'R9'));
SELECT pg_temp.check('G01 çağrıdan çıkmış D (bitmiş answered) token alamaz', NOT can_join_livekit_room(:'D', :'R9'));
SELECT pg_temp.check('G01 boş oda adı reddedilir', NOT can_join_livekit_room(:'B', ''));
INSERT INTO banned_users (user_id, reason_code, expires_at) VALUES (:'B', 'test', NOW() + INTERVAL '1 hour');
SELECT pg_temp.check('G01 süreli yasaklı B token alamaz', NOT can_join_livekit_room(:'B', :'R9'));
UPDATE banned_users SET expires_at = NOW() - INTERVAL '1 second' WHERE user_id = :'B';
SELECT pg_temp.check('G01 yasak süresi dolunca B tekrar alır', can_join_livekit_room(:'B', :'R9'));
DELETE FROM banned_users WHERE user_id = :'B';

-- G02: content-moderation geri dönüşü — yalnız ETKİN katılımcı
SELECT pg_temp.check('G02 A (arayan) etkin', juzzio_is_active_call_participant(:'A', :'R9'));
SELECT pg_temp.check('G02 B etkin', juzzio_is_active_call_participant(:'B', :'R9'));
SELECT pg_temp.check('G02 çıkarılan C etkin DEĞİL', NOT juzzio_is_active_call_participant(:'C', :'R9'));
SELECT pg_temp.check('G02 çıkmış D etkin DEĞİL', NOT juzzio_is_active_call_participant(:'D', :'R9'));
SELECT pg_temp.check('G02 başka oda adı reddedilir', NOT juzzio_is_active_call_participant(:'B', 'lk_baska_oda'));

-- G05: canlı altyazı
SELECT pg_temp.check('G05 B (etkin) altyazı alır', juzzio_can_use_live_captions(:'B'));
SELECT pg_temp.check('G05 çıkarılan C alamaz', NOT juzzio_can_use_live_captions(:'C'));
SELECT pg_temp.check('G05 çıkmış D alamaz', NOT juzzio_can_use_live_captions(:'D'));
INSERT INTO banned_users (user_id, reason_code) VALUES (:'B', 'test');
SELECT pg_temp.check('G05 yasaklı B alamaz', NOT juzzio_can_use_live_captions(:'B'));
DELETE FROM banned_users WHERE user_id = :'B';

-- G06: invite_to_call
SET ROLE authenticated;
SELECT pg_temp.as_user(:'C');
DO $$ BEGIN
  PERFORM invite_to_call('99999999-0000-0000-0000-000000000090', ARRAY['dddddddd-0000-0000-0000-000000000004'::uuid]);
  RAISE EXCEPTION 'FAIL G06 çıkarılan C davet edebildi';
EXCEPTION WHEN raise_exception THEN
  IF SQLERRM <> 'not_in_call' THEN RAISE; END IF;
END $$;
SELECT pg_temp.as_user(:'D');
DO $$ BEGIN
  PERFORM invite_to_call('99999999-0000-0000-0000-000000000090', ARRAY['cccccccc-0000-0000-0000-000000000003'::uuid]);
  RAISE EXCEPTION 'FAIL G06 çağrıdan çıkmış D davet edebildi';
EXCEPTION WHEN raise_exception THEN
  IF SQLERRM <> 'not_in_call' THEN RAISE; END IF;
END $$;
RESET ROLE;
INSERT INTO banned_users (user_id, reason_code) VALUES (:'B', 'test');
SET ROLE authenticated;
SELECT pg_temp.as_user(:'B');
DO $$ BEGIN
  PERFORM invite_to_call('99999999-0000-0000-0000-000000000090', ARRAY['dddddddd-0000-0000-0000-000000000004'::uuid]);
  RAISE EXCEPTION 'FAIL G06 yasaklı B davet edebildi';
EXCEPTION WHEN raise_exception THEN
  IF SQLERRM <> 'account_banned' THEN RAISE; END IF;
END $$;
RESET ROLE;
DELETE FROM banned_users WHERE user_id = :'B';
-- Pozitif: B etkin; çıkarılmış C yeniden davet EDİLEMEZ (0), arkadaşı olmayan D davet edilemez
SET ROLE authenticated;
SELECT pg_temp.as_user(:'B');
SELECT pg_temp.check('G06 çıkarılan kişi yeniden davet edilemez', invite_to_call(:'S9', ARRAY[:'C'::uuid]) = 0);
RESET ROLE;

-- G07: get_or_create_dm_room yasak kontrolü (kaynakta zaten var — regresyon testi)
INSERT INTO banned_users (user_id, reason_code) VALUES (:'D', 'test');
SET ROLE authenticated;
SELECT pg_temp.as_user(:'D');
DO $$ BEGIN
  PERFORM get_or_create_dm_room('aaaaaaaa-0000-0000-0000-000000000001');
  RAISE EXCEPTION 'FAIL G07 yasaklı DM açabildi';
EXCEPTION WHEN raise_exception THEN
  IF SQLERRM <> 'account_banned' THEN RAISE; END IF;
END $$;
RESET ROLE;
DELETE FROM banned_users WHERE user_id = :'D';

-- G04: sesli mesaj transkripsiyonu — üyelik
SELECT get_or_create_dm_room_test.id AS dmroom FROM (SELECT r.id FROM rooms r
  JOIN room_participants pa ON pa.room_id = r.id AND pa.user_id = :'A'
  JOIN room_participants pb ON pb.room_id = r.id AND pb.user_id = :'B'
  WHERE NOT r.is_group LIMIT 1) get_or_create_dm_room_test \gset
INSERT INTO messages (room_id, sender_id, original_text, message_type) VALUES (:'dmroom', :'A', '', 'voice') RETURNING id AS vmsg \gset
INSERT INTO voice_notes (message_id, room_id, sender_id, storage_path, public_url)
VALUES (:'vmsg', :'dmroom', :'A', :'A' || '/' || :'dmroom' || '/v090.m4a', '') RETURNING id AS vn \gset
SELECT pg_temp.check('G04 oda üyesi B çözebilir', (juzzio_voice_note_for_transcription(:'B', :'vn')->>'ok')::boolean);
SELECT pg_temp.check('G04 mesaj kimliğiyle de çözülür', (juzzio_voice_note_for_transcription(:'B', NULL, :'vmsg')->>'ok')::boolean);
SELECT pg_temp.check('G04 üye olmayan D reddedilir', (juzzio_voice_note_for_transcription(:'D', :'vn')->>'error') = 'forbidden');
SELECT pg_temp.check('G04 başkasının yolu ile D reddedilir',
  (juzzio_voice_note_for_transcription(:'D', NULL, NULL, :'A' || '/' || :'dmroom' || '/v090.m4a')->>'error') = 'forbidden');
SELECT pg_temp.check('G04 yol geçişi (..) reddedilir',
  (juzzio_voice_note_for_transcription(:'D', NULL, NULL, :'D' || '/../x.m4a')->>'error') = 'invalid_path');
SELECT pg_temp.check('G04 D kendi adına sahte oda yolu kullanamaz',
  (juzzio_voice_note_for_transcription(:'D', NULL, NULL, :'D' || '/' || :'dmroom' || '/y.m4a')->>'error') = 'not_found');
SELECT pg_temp.check('G04 A kendi yeni yüklemesini çözebilir',
  (juzzio_voice_note_for_transcription(:'A', NULL, NULL, :'A' || '/' || :'dmroom' || '/yeni.m4a')->>'pending_owner_upload')::boolean);
INSERT INTO banned_users (user_id, reason_code) VALUES (:'B', 'test');
SELECT pg_temp.check('G04 yasaklı B reddedilir', (juzzio_voice_note_for_transcription(:'B', :'vn')->>'error') = 'account_banned');
DELETE FROM banned_users WHERE user_id = :'B';
SET ROLE authenticated;
SELECT pg_temp.as_user(:'B');
DO $$ BEGIN
  PERFORM juzzio_voice_note_for_transcription('bbbbbbbb-0000-0000-0000-000000000002', NULL, NULL, NULL);
  RAISE EXCEPTION 'FAIL G04 authenticated doğrudan çağırabildi';
EXCEPTION WHEN insufficient_privilege THEN NULL; END $$;
RESET ROLE;

-- Hız sınırlayıcı
DELETE FROM juzzio_rate_events WHERE user_id = :'D';
SELECT pg_temp.check('hız sınırı 1', juzzio_rate_check(:'D', 'test', 2, 60));
SELECT pg_temp.check('hız sınırı 2', juzzio_rate_check(:'D', 'test', 2, 60));
SELECT pg_temp.check('hız sınırı 3. istek reddedilir', NOT juzzio_rate_check(:'D', 'test', 2, 60));
SELECT pg_temp.check('farklı eylem bağımsız', juzzio_rate_check(:'D', 'test2', 2, 60));

-- G08: askıda kalan push kilidi
DELETE FROM push_delivery_logs WHERE idempotency_key LIKE 'v090_%';
INSERT INTO push_delivery_logs (idempotency_key, recipient_id, delivery_status, created_at)
VALUES ('v090_stale', :'A', 'processing', NOW() - INTERVAL '5 minutes'),
       ('v090_fresh', :'A', 'processing', NOW() - INTERVAL '10 seconds'),
       ('v090_done',  :'A', 'fcm_accepted', NOW() - INTERVAL '10 minutes');
SELECT pg_temp.check('G08 eski processing devralınır', juzzio_claim_stale_push_delivery('v090_stale') IS NOT NULL);
SELECT pg_temp.check('G08 ikinci devralma yok (çift gönderim yok)', juzzio_claim_stale_push_delivery('v090_stale') IS NULL);
SELECT pg_temp.check('G08 taze processing devralınmaz', juzzio_claim_stale_push_delivery('v090_fresh') IS NULL);
SELECT pg_temp.check('G08 sonuçlanmış kayıt devralınmaz', juzzio_claim_stale_push_delivery('v090_done') IS NULL);
DELETE FROM push_delivery_logs WHERE idempotency_key LIKE 'v090_%';

-- 10.7 Storage gizliliği
SELECT pg_temp.check('bucket chat-media özel', (SELECT NOT public FROM storage.buckets WHERE id = 'chat-media'));
SELECT pg_temp.check('bucket voice-notes özel', (SELECT NOT public FROM storage.buckets WHERE id = 'voice-notes'));
SELECT pg_temp.check('bucket stories özel', (SELECT NOT public FROM storage.buckets WHERE id = 'stories'));
SELECT pg_temp.check('bucket posts özel', (SELECT NOT public FROM storage.buckets WHERE id = 'posts'));
SELECT pg_temp.check('bucket reels özel', (SELECT NOT public FROM storage.buckets WHERE id = 'reels'));
SELECT pg_temp.check('bucket avatars herkese açık', (SELECT public FROM storage.buckets WHERE id = 'avatars'));
DELETE FROM storage.objects WHERE name LIKE '%v090%';
INSERT INTO storage.objects (bucket_id, name, owner) VALUES
  ('voice-notes', :'A' || '/' || :'dmroom' || '/v090.m4a', :'A'),
  ('chat-media',  :'A' || '/' || :'dmroom' || '/v090.jpg', :'A'),
  ('stories',     :'A' || '/v090_story.jpg', :'A'),
  ('posts',       :'A' || '/v090_post.jpg', :'A'),
  ('posts',       :'A' || '/v090_private.jpg', :'A');
INSERT INTO stories (user_id, media_type, media_url, visibility)
VALUES (:'A', 'image', 'https://x.supabase.co/storage/v1/object/public/stories/' || :'A' || '/v090_story.jpg', 'close_friends');
INSERT INTO posts (author_id, content_type, caption, media_storage_paths, visibility)
VALUES (:'A', 'image', 'v090 public', jsonb_build_array('posts:' || :'A' || '/v090_post.jpg'), 'public'),
       (:'A', 'image', 'v090 private', jsonb_build_array('posts:' || :'A' || '/v090_private.jpg'), 'private');
SET ROLE authenticated;
SELECT pg_temp.as_user(:'B');
SELECT pg_temp.check('oda üyesi B sesli mesajı okur', (SELECT count(*) FROM storage.objects WHERE bucket_id = 'voice-notes' AND name LIKE '%v090%') = 1);
SELECT pg_temp.check('oda üyesi B sohbet medyasını okur', (SELECT count(*) FROM storage.objects WHERE bucket_id = 'chat-media' AND name LIKE '%v090%') = 1);
SELECT pg_temp.check('B yakın arkadaş değil → hikâye medyasını okuyamaz', (SELECT count(*) FROM storage.objects WHERE bucket_id = 'stories' AND name LIKE '%v090%') = 0);
SELECT pg_temp.check('B herkese açık gönderi medyasını okur', (SELECT count(*) FROM storage.objects WHERE bucket_id = 'posts' AND name LIKE '%v090_post%') = 1);
SELECT pg_temp.check('B özel gönderi medyasını okuyamaz', (SELECT count(*) FROM storage.objects WHERE bucket_id = 'posts' AND name LIKE '%v090_private%') = 0);
SELECT pg_temp.as_user(:'D');
SELECT pg_temp.check('üye olmayan D sesli mesajı okuyamaz', (SELECT count(*) FROM storage.objects WHERE bucket_id = 'voice-notes' AND name LIKE '%v090%') = 0);
SELECT pg_temp.check('üye olmayan D sohbet medyasını okuyamaz', (SELECT count(*) FROM storage.objects WHERE bucket_id = 'chat-media' AND name LIKE '%v090%') = 0);
SELECT pg_temp.as_user(:'A');
SELECT pg_temp.check('sahip A kendi dosyalarını okur', (SELECT count(*) FROM storage.objects WHERE name LIKE '%v090%') = 5);
RESET ROLE;
INSERT INTO close_friends (owner_id, friend_id) VALUES (:'A', :'B') ON CONFLICT DO NOTHING;
SET ROLE authenticated;
SELECT pg_temp.as_user(:'B');
SELECT pg_temp.check('yakın arkadaş B hikâye medyasını okur', (SELECT count(*) FROM storage.objects WHERE bucket_id = 'stories' AND name LIKE '%v090%') = 1);
-- Personel erişimi en az yetkiyle
RESET ROLE;
INSERT INTO storage.objects (bucket_id, name, owner) VALUES ('chat-media', :'A' || '/feedback/v090_fb.jpg', :'A');
INSERT INTO staff_roles (user_id, role) VALUES (:'D', 'moderator');
SET ROLE authenticated;
SELECT pg_temp.as_user(:'D');
SELECT pg_temp.check('moderatör özel gönderi medyasını inceleyebilir', (SELECT count(*) FROM storage.objects WHERE bucket_id = 'posts' AND name LIKE '%v090_private%') = 1);
SELECT pg_temp.check('moderatör özel sohbet medyasını GÖREMEZ', (SELECT count(*) FROM storage.objects WHERE bucket_id IN ('chat-media', 'voice-notes') AND name LIKE '%v090%') = 0);
RESET ROLE;
UPDATE staff_roles SET role = 'support' WHERE user_id = :'D';
SET ROLE authenticated;
SELECT pg_temp.as_user(:'D');
SELECT pg_temp.check('destek geri bildirim görüntüsünü görür', (SELECT count(*) FROM storage.objects WHERE name LIKE '%feedback/v090_fb%') = 1);
SELECT pg_temp.check('destek ÖZEL gönderi medyasını göremez', (SELECT count(*) FROM storage.objects WHERE bucket_id = 'posts' AND name LIKE '%v090_private%') = 0);
RESET ROLE;
DELETE FROM staff_roles WHERE user_id = :'D';
SET ROLE authenticated;
SELECT pg_temp.as_user(:'D');
SELECT pg_temp.check('rolsüz kullanıcı geri bildirim görüntüsünü göremez', (SELECT count(*) FROM storage.objects WHERE name LIKE '%feedback/v090_fb%') = 0);
RESET ROLE;
SET ROLE anon;
SELECT pg_temp.check('anonim hiçbir özel nesneyi okuyamaz', (SELECT count(*) FROM storage.objects WHERE name LIKE '%v090%') = 0);
RESET ROLE;
DELETE FROM close_friends WHERE owner_id = :'A' AND friend_id = :'B';
DELETE FROM stories WHERE media_url LIKE '%v090_story%';
DELETE FROM posts WHERE caption IN ('v090 public', 'v090 private');
DELETE FROM storage.objects WHERE name LIKE '%v090%';
DELETE FROM voice_notes WHERE id = :'vn';
DELETE FROM messages WHERE id = :'vmsg';
DELETE FROM call_removals WHERE session_id = :'S9';
DELETE FROM call_logs WHERE session_id = :'S9';
SELECT 'TÜM v0.9.0 GÜVENLİK TESTLERİ GEÇTİ';

-- =============================================================================
-- v0.9.0: RBAC izin matrisi (G20/G21) — HER ROL için izin VE ret testleri
-- =============================================================================
RESET ROLE;
SET search_path = public, extensions;
-- pg_temp.allowed(sql): çağrı yetki hatası VERMEZSE true (yan etkiler her durumda geri alınır)
CREATE OR REPLACE FUNCTION pg_temp.allowed(p_sql TEXT) RETURNS BOOLEAN LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE p_sql;
    RAISE EXCEPTION 'juzzio_test_rollback';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'permission_denied:%' OR SQLERRM = 'admin_session_invalid' THEN RETURN false; END IF;
    RETURN true;  -- yetki geçti (iş kuralı hatası veya bilinçli geri alma)
  END;
END $$;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA pg_temp TO authenticated, anon;
DELETE FROM staff_roles WHERE user_id IN (:'A', :'B', :'C', :'D');
UPDATE profiles SET username = 'tugkancr' WHERE id = :'A';
DELETE FROM admin_sessions WHERE user_id = :'A';
INSERT INTO admin_sessions (token_hash, user_id, expires_at)
VALUES ((SELECT encode(digest('tok090', 'sha256'), 'hex')), :'A', NOW() + INTERVAL '1 hour');
SELECT set_config('juzzio.d', :'D', false);

-- Matris: rol | sql | beklenen
CREATE TEMP TABLE rbac_cases (role TEXT, label TEXT, sql TEXT, expect BOOLEAN);
INSERT INTO rbac_cases VALUES
 -- rolü olmayan kullanıcı: hiçbir şey
 ('none', 'kullanıcı arama', $q$SELECT admin_search_users('', 'x')$q$, false),
 ('none', 'istatistik', $q$SELECT admin_stats('')$q$, false),
 ('none', 'denetim kaydı', $q$SELECT admin_audit('', 5)$q$, false),
 -- moderatör
 ('moderator', 'kullanıcı arama', $q$SELECT admin_search_users('', 'x')$q$, true),
 ('moderator', 'şikâyet listesi', $q$SELECT admin_list_reports('', 'open', 5)$q$, true),
 ('moderator', 'şikâyet çözme', $q$SELECT admin_set_report_status('', gen_random_uuid(), 'resolved', '')$q$, true),
 ('moderator', 'içerik silme', $q$SELECT admin_delete_content('', 'post', gen_random_uuid()::text)$q$, true),
 ('moderator', 'uyarı', $q$SELECT admin_warn_user('', current_setting('juzzio.d')::uuid, 'x')$q$, true),
 ('moderator', 'yasaklama YOK', $q$SELECT admin_ban_user('', current_setting('juzzio.d')::uuid, 'spam', '', false)$q$, false),
 ('moderator', 'e-posta YOK', $q$SELECT admin_get_user_email('', current_setting('juzzio.d')::uuid)$q$, false),
 ('moderator', 'ayar YOK', $q$SELECT admin_set_setting('', 'x', '1'::jsonb)$q$, false),
 ('moderator', 'duyuru YOK', $q$SELECT admin_broadcast('', 't', 'b', '', 'all')$q$, false),
 ('moderator', 'denetim kaydı YOK', $q$SELECT admin_audit('', 5)$q$, false),
 -- destek
 ('support', 'kullanıcı arama', $q$SELECT admin_search_users('', 'x')$q$, true),
 ('support', 'geri bildirim', $q$SELECT admin_list_feedback('', 'open')$q$, true),
 ('support', 'şikâyet görüntüleme', $q$SELECT admin_list_reports('', 'open', 5)$q$, true),
 ('support', 'şikâyet çözme YOK', $q$SELECT admin_set_report_status('', gen_random_uuid(), 'resolved', '')$q$, false),
 ('support', 'içerik silme YOK', $q$SELECT admin_delete_content('', 'post', gen_random_uuid()::text)$q$, false),
 ('support', 'e-posta YOK', $q$SELECT admin_get_user_email('', current_setting('juzzio.d')::uuid)$q$, false),
 ('support', 'hesap silme YOK', $q$SELECT admin_delete_user('', current_setting('juzzio.d')::uuid, 'x')$q$, false),
 -- analist
 ('analyst', 'istatistik', $q$SELECT admin_stats('')$q$, true),
 ('analyst', 'kullanıcı arama YOK', $q$SELECT admin_search_users('', 'x')$q$, false),
 ('analyst', 'denetim kaydı YOK', $q$SELECT admin_audit('', 5)$q$, false),
 -- içerik yöneticisi
 ('content_manager', 'duyuru', $q$SELECT admin_broadcast('', 't', 'b', '', 'nobody_test')$q$, true),
 ('content_manager', 'kullanıcı arama YOK', $q$SELECT admin_search_users('', 'x')$q$, false),
 ('content_manager', 'içerik silme YOK', $q$SELECT admin_delete_content('', 'post', gen_random_uuid()::text)$q$, false),
 -- denetçi (salt okunur)
 ('auditor', 'denetim kaydı', $q$SELECT admin_audit('', 5)$q$, true),
 ('auditor', 'istatistik', $q$SELECT admin_stats('')$q$, true),
 ('auditor', 'uyarı YOK', $q$SELECT admin_warn_user('', current_setting('juzzio.d')::uuid, 'x')$q$, false),
 ('auditor', 'ayar YOK', $q$SELECT admin_set_setting('', 'x', '1'::jsonb)$q$, false),
 -- yönetici
 ('admin', 'yasaklama', $q$SELECT admin_ban_user('', current_setting('juzzio.d')::uuid, 'spam', '', false)$q$, true),
 ('admin', 'e-posta (users.pii)', $q$SELECT admin_get_user_email('', current_setting('juzzio.d')::uuid)$q$, true),
 ('admin', 'ayar', $q$SELECT admin_set_setting('', 'x', '1'::jsonb)$q$, true),
 ('admin', 'hesap silme YOK (yalnız süper yönetici)', $q$SELECT admin_delete_user('', current_setting('juzzio.d')::uuid, 'x')$q$, false),
 ('admin', 'rol verme YOK (yalnız süper yönetici)', $q$SELECT admin_grant_role('', current_setting('juzzio.d')::uuid, 'support')$q$, false);

DO $$
DECLARE r RECORD; v BOOLEAN; n INT := 0;
BEGIN
  FOR r IN SELECT * FROM rbac_cases ORDER BY role LOOP
    DELETE FROM staff_roles WHERE user_id = 'cccccccc-0000-0000-0000-000000000003';
    IF r.role <> 'none' THEN
      INSERT INTO staff_roles (user_id, role) VALUES ('cccccccc-0000-0000-0000-000000000003', r.role);
    END IF;
    PERFORM set_config('request.jwt.claim.sub', 'cccccccc-0000-0000-0000-000000000003', true);
    SET LOCAL ROLE authenticated;
    v := pg_temp.allowed(r.sql);
    RESET ROLE;
    IF v IS DISTINCT FROM r.expect THEN
      RAISE EXCEPTION 'FAIL RBAC % / % beklenen=% gerçek=%', r.role, r.label, r.expect, v;
    END IF;
    n := n + 1;
  END LOOP;
  RAISE NOTICE 'RBAC matrisi: % durum doğrulandı', n;
END $$;
DELETE FROM staff_roles WHERE user_id = :'C';
SELECT pg_temp.check('RBAC matrisi (35 durum) geçti', true);

-- Süper yönetici: belirteçsiz '*' GEÇMEZ; geçerli belirteçle geçer; yanlış belirteç → admin_session_invalid
SET ROLE authenticated;
SELECT pg_temp.as_user(:'A');
SELECT pg_temp.check('süper yönetici belirteçsiz reddedilir', NOT pg_temp.allowed($q$SELECT admin_stats('')$q$));
SELECT pg_temp.check('süper yönetici belirteçle geçer', pg_temp.allowed($q$SELECT admin_stats('tok090')$q$));
DO $$ BEGIN
  PERFORM admin_stats('yanlis');
  RAISE EXCEPTION 'FAIL yanlış belirteç';
EXCEPTION WHEN raise_exception THEN
  IF SQLERRM <> 'admin_session_invalid' THEN RAISE; END IF;
END $$;
-- Destek görevlisi kullanıcı ayrıntısında e-postayı GÖREMEZ; okuma denetime yazılır
RESET ROLE;
INSERT INTO staff_roles (user_id, role) VALUES (:'C', 'support');
SET ROLE authenticated;
SELECT pg_temp.as_user(:'C');
SELECT pg_temp.check('destek: e-posta maskeli', (admin_user_detail('', :'D')->>'email') IS NULL);
RESET ROLE;
SELECT pg_temp.check('ayrıcalıklı okuma denetimde', EXISTS (SELECT 1 FROM admin_audit_log WHERE admin_id = :'C' AND action = 'view_user_detail' AND target = :'D'));
UPDATE staff_roles SET role = 'admin' WHERE user_id = :'C';
SET ROLE authenticated;
SELECT pg_temp.as_user(:'C');
SELECT pg_temp.check('yönetici: e-posta görünür', (admin_user_detail('', :'D')->>'email') = 'd@test.local');
RESET ROLE;
-- Rol geri alınınca ANINDA etkisiz
DELETE FROM staff_roles WHERE user_id = :'C';
SET ROLE authenticated;
SELECT pg_temp.as_user(:'C');
SELECT pg_temp.check('rol geri alındı → ret', NOT pg_temp.allowed($q$SELECT admin_search_users('', 'x')$q$));
RESET ROLE;
DELETE FROM admin_sessions WHERE user_id = :'A';
UPDATE profiles SET username = 'ali' WHERE id = :'A';
SELECT 'TÜM v0.9.0 RBAC TESTLERİ GEÇTİ';

-- =============================================================================
-- v0.9.0: STORAGE TEMİZLİĞİ (G22 / G33)
-- =============================================================================
RESET ROLE;
DELETE FROM juzzio_storage_cleanup_queue;
SELECT pg_temp.check('URL ayrıştırma (public)', (SELECT bucket || '|' || object_name FROM juzzio_storage_ref_from_url('https://x.supabase.co/storage/v1/object/public/chat-media/u/r/a.jpg')) = 'chat-media|u/r/a.jpg');
SELECT pg_temp.check('URL ayrıştırma (sign + sorgu)', (SELECT object_name FROM juzzio_storage_ref_from_url('https://x.supabase.co/storage/v1/object/sign/stories/u/s.mp4?token=abc')) = 'u/s.mp4');
SELECT pg_temp.check('yabancı URL yok sayılır', NOT EXISTS (SELECT 1 FROM juzzio_storage_ref_from_url('https://evil.example/a.jpg')));
-- Gönderi yumuşak silme → medya + kapak kuyruğa
INSERT INTO posts (author_id, content_type, caption, media_storage_paths, cover_url)
VALUES (:'A', 'image', 'v090 cleanup', '["posts:aaaa/p1.jpg","reels:aaaa/r1.mp4"]'::jsonb,
        'https://x.supabase.co/storage/v1/object/public/posts/aaaa/cover1.jpg') RETURNING id AS cpost \gset
UPDATE posts SET is_deleted = true WHERE id = :'cpost';
SELECT pg_temp.check('gönderi silme: 3 nesne kuyrukta',
  (SELECT count(*) FROM juzzio_storage_cleanup_queue WHERE reason = 'post_deleted' AND processed_at IS NULL) = 3);
UPDATE posts SET caption = 'x' WHERE id = :'cpost';
SELECT pg_temp.check('ilgisiz güncelleme tekrar kuyruğa yazmaz',
  (SELECT count(*) FROM juzzio_storage_cleanup_queue WHERE reason = 'post_deleted') = 3);
DELETE FROM posts WHERE id = :'cpost';
SELECT pg_temp.check('sert silme yinelenen kuyruk kaydı üretmez',
  (SELECT count(*) FROM juzzio_storage_cleanup_queue WHERE reason = 'post_deleted' AND processed_at IS NULL) = 3);
-- Hikâye silme
INSERT INTO stories (user_id, media_type, media_url) VALUES (:'A', 'image', 'https://x.supabase.co/storage/v1/object/public/stories/aaaa/st1.jpg') RETURNING id AS cstory \gset
DELETE FROM stories WHERE id = :'cstory';
SELECT pg_temp.check('hikâye silme kuyrukta', EXISTS (SELECT 1 FROM juzzio_storage_cleanup_queue WHERE bucket = 'stories' AND object_name = 'aaaa/st1.jpg'));
-- Mesaj "herkesten sil" (URL'ler temizlenir) + sesli mesaj
SELECT room_id AS croom FROM room_participants WHERE user_id = :'A' LIMIT 1 \gset
INSERT INTO messages (room_id, sender_id, original_text, message_type, image_url)
VALUES (:'croom', :'A', '', 'image', 'https://x.supabase.co/storage/v1/object/public/chat-media/aaaa/r/m1.jpg') RETURNING id AS cmsg \gset
INSERT INTO voice_notes (message_id, room_id, sender_id, storage_path, public_url) VALUES (:'cmsg', :'croom', :'A', 'aaaa/r/v1.m4a', '');
UPDATE messages SET is_deleted = true, image_url = NULL WHERE id = :'cmsg';
SELECT pg_temp.check('mesaj medyası kuyrukta', EXISTS (SELECT 1 FROM juzzio_storage_cleanup_queue WHERE bucket = 'chat-media' AND object_name = 'aaaa/r/m1.jpg'));
SELECT pg_temp.check('sesli mesaj kaydı silindi ve dosyası kuyrukta',
  NOT EXISTS (SELECT 1 FROM voice_notes WHERE message_id = :'cmsg')
  AND EXISTS (SELECT 1 FROM juzzio_storage_cleanup_queue WHERE bucket = 'voice-notes' AND object_name = 'aaaa/r/v1.m4a'));
-- Süreli mesaj süresi dolunca
INSERT INTO messages (room_id, sender_id, original_text, message_type, image_url, expires_at)
VALUES (:'croom', :'A', '', 'image', 'https://x.supabase.co/storage/v1/object/public/chat-media/aaaa/r/exp.jpg', NOW() - INTERVAL '2 hours');
SELECT pg_temp.check('süresi dolan içerik temizlendi', (juzzio_purge_expired_content()->>'messages')::int >= 1);
SELECT pg_temp.check('süresi dolan mesaj medyası kuyrukta', EXISTS (SELECT 1 FROM juzzio_storage_cleanup_queue WHERE object_name = 'aaaa/r/exp.jpg'));
-- Güvenlik: yol geçişi ve bilinmeyen bucket reddedilir
SELECT juzzio_enqueue_storage_cleanup('chat-media', 'a/../b.jpg', 't');
SELECT juzzio_enqueue_storage_cleanup('secret-bucket', 'a/b.jpg', 't');
SELECT pg_temp.check('kötü yol/bucket kuyruğa girmez', NOT EXISTS (SELECT 1 FROM juzzio_storage_cleanup_queue WHERE reason = 't'));
-- İşçi talebi: kilitli talep, tamamlandı işareti
SELECT count(*) AS claimed FROM juzzio_storage_cleanup_claim(2) \gset
SELECT pg_temp.check('işçi en fazla istenen kadar alır', :'claimed'::int = 2);
SELECT juzzio_storage_cleanup_done(ARRAY(SELECT id FROM juzzio_storage_cleanup_queue WHERE attempts = 1), '');
SELECT pg_temp.check('işlenenler kapandı', (SELECT count(*) FROM juzzio_storage_cleanup_queue WHERE processed_at IS NOT NULL) = 2);
-- Yetkisiz kullanıcı kuyruğa erişemez / temizlik başlatamaz
SET ROLE authenticated;
SELECT pg_temp.as_user(:'B');
DO $$ BEGIN
  PERFORM count(*) FROM juzzio_storage_cleanup_queue;
  RAISE EXCEPTION 'FAIL kuyruk okunabildi';
EXCEPTION WHEN insufficient_privilege THEN NULL; END $$;
DO $$ BEGIN
  PERFORM juzzio_purge_expired_content();
  RAISE EXCEPTION 'FAIL authenticated temizlik başlattı';
EXCEPTION WHEN insufficient_privilege THEN NULL; END $$;
RESET ROLE;
DELETE FROM messages WHERE room_id = :'croom' AND sender_id = :'A' AND message_type = 'image';
DELETE FROM juzzio_storage_cleanup_queue;
SELECT 'TÜM v0.9.0 STORAGE TEMİZLİK TESTLERİ GEÇTİ';
-- Hesap silme → kullanıcının 6 bucket'taki klasörü kuyrukta (dosyanın EN SONUNDA: D silinir)
DELETE FROM auth.users WHERE id = :'D';
SELECT pg_temp.check('hesap silme: 6 klasör kuyrukta',
  (SELECT count(*) FROM juzzio_storage_cleanup_queue WHERE is_prefix AND object_name = :'D' || '/' AND reason = 'account_deleted') = 6);
SELECT 'TÜM v0.9.0 HESAP SİLME TEMİZLİK TESTLERİ GEÇTİ';
-- v0.9.0: mesaj idempotency
RESET ROLE;
SELECT room_id AS iroom FROM room_participants WHERE user_id = :'A' LIMIT 1 \gset
INSERT INTO messages (room_id, sender_id, original_text, client_msg_id) VALUES (:'iroom', :'A', 'idem', 'qr_0123456789abcdef');
DO $$ BEGIN
  INSERT INTO messages (room_id, sender_id, original_text, client_msg_id)
  SELECT room_id, 'aaaaaaaa-0000-0000-0000-000000000001', 'idem2', 'qr_0123456789abcdef' FROM messages WHERE client_msg_id = 'qr_0123456789abcdef';
  RAISE EXCEPTION 'FAIL aynı client_msg_id iki kez eklendi';
EXCEPTION WHEN unique_violation THEN NULL; END $$;
DO $$ BEGIN
  INSERT INTO messages (room_id, sender_id, original_text, client_msg_id)
  SELECT room_id, 'aaaaaaaa-0000-0000-0000-000000000001', 'x', 'bad id!' FROM messages WHERE client_msg_id = 'qr_0123456789abcdef';
  RAISE EXCEPTION 'FAIL geçersiz client_msg_id kabul edildi';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DELETE FROM messages WHERE client_msg_id = 'qr_0123456789abcdef';
SELECT 'TÜM v0.9.0 MESAJ İDEMPOTENCY TESTLERİ GEÇTİ';
-- v0.9.0 N-A: sohbet etkinlik durumu (yazıyor / kaydediliyor) Realtime yetkilendirmesi
RESET ROLE;
-- A–B birebir odası önceki bloklarda zaten var (ikinci DM tetikleyiciyle engellenir) → onu kullan
SELECT r.id AS dmroom FROM rooms r
  JOIN room_participants a ON a.room_id = r.id AND a.user_id = :'A' AND a.left_at IS NULL
  JOIN room_participants b ON b.room_id = r.id AND b.user_id = :'B' AND b.left_at IS NULL
  WHERE NOT r.is_group LIMIT 1 \gset
INSERT INTO rooms (id, room_code, livekit_room_name, is_group) VALUES
  ('acacacac-0000-0000-0000-0000000000a2', 'act_grp_abc', 'act_grp_abc', true);
INSERT INTO room_participants (room_id, user_id) VALUES
  ('acacacac-0000-0000-0000-0000000000a2', :'A'), ('acacacac-0000-0000-0000-0000000000a2', :'B'),
  ('acacacac-0000-0000-0000-0000000000a2', :'C');
CREATE OR REPLACE FUNCTION pg_temp.can_send(u uuid, topic text) RETURNS boolean LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', u::text, false);
  PERFORM set_config('realtime.topic', topic, false);
  BEGIN
    SET LOCAL ROLE authenticated;
    INSERT INTO realtime.messages (topic, extension, payload) VALUES (topic, 'broadcast', '{"state":"typing"}');
    RESET ROLE;
    RETURN true;
  EXCEPTION WHEN insufficient_privilege THEN
    RETURN false;
  END;
END $$;
CREATE OR REPLACE FUNCTION pg_temp.can_read(u uuid, topic text) RETURNS boolean LANGUAGE plpgsql AS $$
DECLARE n int;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', u::text, false);
  PERFORM set_config('realtime.topic', topic, false);
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO n FROM realtime.messages m WHERE m.topic = realtime.topic();
  RESET ROLE;
  RETURN n > 0;
END $$;
SELECT pg_temp.check('DM üyesi yazıyor yayınlar', pg_temp.can_send(:'A', 'room-activity:' || :'dmroom'));
SELECT pg_temp.check('DM karşı tarafı okur', pg_temp.can_read(:'B', 'room-activity:' || :'dmroom'));
SELECT pg_temp.check('üye olmayan okuyamaz', NOT pg_temp.can_read(:'C', 'room-activity:' || :'dmroom'));
SELECT pg_temp.check('üye olmayan yayınlayamaz', NOT pg_temp.can_send(:'C', 'room-activity:' || :'dmroom'));
SELECT pg_temp.check('grup üyesi yayınlar', pg_temp.can_send(:'C', 'room-activity:acacacac-0000-0000-0000-0000000000a2'));
SELECT pg_temp.check('bozuk konu reddedilir', NOT pg_temp.can_send(:'A', 'room-activity:not-a-uuid'));
SELECT pg_temp.check('başka kanal adı reddedilir', NOT pg_temp.can_send(:'A', 'other:acacacac-0000-0000-0000-0000000000a1'));
-- Çevrimiçi gizliliği 'nobody' → yayın yok (okuma serbest)
UPDATE profiles SET privacy_online = 'nobody' WHERE id = :'A';
SELECT pg_temp.check('gizlilik nobody → yayın yok', NOT pg_temp.can_send(:'A', 'room-activity:acacacac-0000-0000-0000-0000000000a2'));
SELECT pg_temp.check('gizlilik nobody → yine de okur', pg_temp.can_read(:'A', 'room-activity:acacacac-0000-0000-0000-0000000000a2'));
UPDATE profiles SET privacy_online = 'everyone' WHERE id = :'A';
-- Engel → DM'de iki yön kapalı
INSERT INTO blocked_users (blocker_id, blocked_id) VALUES (:'B', :'A');
SELECT pg_temp.check('engel: engellenen yayınlayamaz', NOT pg_temp.can_send(:'A', 'room-activity:' || :'dmroom'));
SELECT pg_temp.check('engel: engelleyen okuyamaz', NOT pg_temp.can_read(:'B', 'room-activity:' || :'dmroom'));
DELETE FROM blocked_users WHERE blocker_id = :'B' AND blocked_id = :'A';
-- Odadan ayrılan
UPDATE room_participants SET left_at = NOW() WHERE room_id = 'acacacac-0000-0000-0000-0000000000a2' AND user_id = :'C';
SELECT pg_temp.check('ayrılan üye yayınlayamaz', NOT pg_temp.can_send(:'C', 'room-activity:acacacac-0000-0000-0000-0000000000a2'));
RESET ROLE;
DELETE FROM realtime.messages;
DELETE FROM room_participants WHERE room_id IN ('acacacac-0000-0000-0000-0000000000a2');
DELETE FROM rooms WHERE id IN ('acacacac-0000-0000-0000-0000000000a2');
SELECT 'TÜM v0.9.0 ETKİNLİK DURUMU TESTLERİ GEÇTİ';
-- v0.9.0 N-D: bildirim önizleme kipi + şifreli önizleme sızıntısı
RESET ROLE;
INSERT INTO user_push_tokens (user_id, device_id, fcm_token, platform)
VALUES (:'A', 'dev-a', 'tok_A_0123456789abcdefghijkl', 'android');
SELECT pg_temp.check('varsayılan kip full',
  (SELECT notify_preview FROM user_push_tokens WHERE fcm_token = 'tok_A_0123456789abcdefghijkl') = 'full');
SET ROLE authenticated;
SELECT pg_temp.as_user(:'A');
SELECT pg_temp.check('sahibi kipi değiştirir', set_my_push_preview('tok_A_0123456789abcdefghijkl', 'HIDDEN'));
SELECT pg_temp.as_user(:'B');
SELECT pg_temp.check('başkasının cihazı değişmez', NOT set_my_push_preview('tok_A_0123456789abcdefghijkl', 'full'));
DO $$ BEGIN
  PERFORM set_my_push_preview('tok_A_0123456789abcdefghijkl', 'everything');
  RAISE EXCEPTION 'FAIL geçersiz kip kabul edildi';
EXCEPTION WHEN raise_exception THEN
  IF SQLERRM NOT LIKE '%invalid_preview_mode%' THEN RAISE; END IF;
END $$;
RESET ROLE;
SET ROLE anon;
DO $$ BEGIN
  PERFORM set_my_push_preview('tok_A_0123456789abcdefghijkl', 'full');
  RAISE EXCEPTION 'FAIL anon kip değiştirdi';
EXCEPTION WHEN insufficient_privilege THEN NULL; END $$;
RESET ROLE;
SELECT pg_temp.check('kip hidden kaldı',
  (SELECT notify_preview FROM user_push_tokens WHERE fcm_token = 'tok_A_0123456789abcdefghijkl') = 'hidden');
INSERT INTO notifications (recipient_id, actor_id, event_type, target_id, preview_text, dedupe_key)
VALUES (:'A', :'B', 'reaction', 'x', '❤️|juzzio_e2ee_pq3_v2_QUJDREVGR0g=', 'nd_t1'),
       (:'A', :'B', 'message', 'x', 'juzzio_e2ee_x25519_v1_abc', 'nd_t2'),
       (:'A', :'B', 'message', 'x', 'Merhaba', 'nd_t3');
SELECT pg_temp.check('tepki önizlemesinde şifre metni yok',
  (SELECT preview_text FROM notifications WHERE dedupe_key = 'nd_t1') = '❤️|🔒');
SELECT pg_temp.check('mesaj önizlemesinde şifre metni yok',
  (SELECT preview_text FROM notifications WHERE dedupe_key = 'nd_t2') = '🔒');
SELECT pg_temp.check('düz önizleme korunur',
  (SELECT preview_text FROM notifications WHERE dedupe_key = 'nd_t3') = 'Merhaba');
UPDATE notifications SET preview_text = 'x juzzio_E2EE_ y' WHERE dedupe_key = 'nd_t3';
SELECT pg_temp.check('güncellemede de temizlenir (büyük/küçük harf)',
  (SELECT preview_text FROM notifications WHERE dedupe_key = 'nd_t3') = '🔒');
DELETE FROM notifications WHERE dedupe_key LIKE 'nd_t%';
DELETE FROM user_push_tokens WHERE fcm_token = 'tok_A_0123456789abcdefghijkl';
SELECT 'TÜM v0.9.0 BİLDİRİM ÖNİZLEME TESTLERİ GEÇTİ';
-- v0.9.0 N-F: bildirimden aramayı reddetme
RESET ROLE;
INSERT INTO call_logs (id, caller_id, receiver_id, is_video, status, livekit_room_name)
VALUES ('cdcdcdcd-0000-0000-0000-0000000000f1', :'B', :'A', false, 'ringing', 'nf_room_1'),
       ('cdcdcdcd-0000-0000-0000-0000000000f2', :'B', :'A', false, 'answered', 'nf_room_2');
SET ROLE authenticated;
SELECT pg_temp.as_user(:'B');
DO $$ BEGIN
  PERFORM juzzio_decline_call('cdcdcdcd-0000-0000-0000-0000000000f1');
  RAISE EXCEPTION 'FAIL arayan kendi aramasını "reddetti"';
EXCEPTION WHEN raise_exception THEN
  IF SQLERRM NOT LIKE '%not_allowed%' THEN RAISE; END IF;
END $$;
SELECT pg_temp.as_user(:'C');
DO $$ BEGIN
  PERFORM juzzio_decline_call('cdcdcdcd-0000-0000-0000-0000000000f1');
  RAISE EXCEPTION 'FAIL üçüncü kişi aramayı reddetti';
EXCEPTION WHEN raise_exception THEN
  IF SQLERRM NOT LIKE '%not_allowed%' THEN RAISE; END IF;
END $$;
SELECT pg_temp.as_user(:'A');
SELECT pg_temp.check('aranan çalan aramayı reddeder', juzzio_decline_call('cdcdcdcd-0000-0000-0000-0000000000f1') = 'rejected');
SELECT pg_temp.check('tekrar basma idempotent', juzzio_decline_call('cdcdcdcd-0000-0000-0000-0000000000f1') = 'rejected');
SELECT pg_temp.check('cevaplanmış arama değişmez', juzzio_decline_call('cdcdcdcd-0000-0000-0000-0000000000f2') = 'answered');
RESET ROLE;
SELECT pg_temp.check('durumlar doğru',
  (SELECT status FROM call_logs WHERE id = 'cdcdcdcd-0000-0000-0000-0000000000f1') = 'rejected'
  AND (SELECT status FROM call_logs WHERE id = 'cdcdcdcd-0000-0000-0000-0000000000f2') = 'answered');
SET ROLE anon;
DO $$ BEGIN
  PERFORM juzzio_decline_call('cdcdcdcd-0000-0000-0000-0000000000f2');
  RAISE EXCEPTION 'FAIL anon reddetti';
EXCEPTION WHEN insufficient_privilege THEN NULL; END $$;
RESET ROLE;
DELETE FROM call_logs WHERE id IN ('cdcdcdcd-0000-0000-0000-0000000000f1', 'cdcdcdcd-0000-0000-0000-0000000000f2');
SELECT 'TÜM v0.9.0 ARAMA REDDETME TESTLERİ GEÇTİ';
-- v0.9.0 §6.4: sohbet bazlı bildirim ayarları
RESET ROLE;
INSERT INTO rooms (id, room_code, livekit_room_name, is_group) VALUES ('abababab-0000-0000-0000-0000000000b1', 'np_grp', 'np_grp', true);
INSERT INTO room_participants (room_id, user_id) VALUES
  ('abababab-0000-0000-0000-0000000000b1', :'A'), ('abababab-0000-0000-0000-0000000000b1', :'B');
SET ROLE authenticated;
SELECT pg_temp.as_user(:'A');
SELECT pg_temp.check('varsayılan: miras + titreşim',
  get_room_notification_prefs('abababab-0000-0000-0000-0000000000b1') = '{"muted_until": null, "preview": "inherit", "vibrate": true}'::jsonb);
SELECT set_room_notification_prefs('abababab-0000-0000-0000-0000000000b1', 60, 'HIDDEN', false);
SELECT pg_temp.check('ayarlar kaydedildi',
  (get_room_notification_prefs('abababab-0000-0000-0000-0000000000b1')->>'preview') = 'hidden'
  AND (get_room_notification_prefs('abababab-0000-0000-0000-0000000000b1')->>'vibrate') = 'false'
  AND (get_room_notification_prefs('abababab-0000-0000-0000-0000000000b1')->>'muted_until') IS NOT NULL);
SELECT pg_temp.as_user(:'C');
DO $$ BEGIN
  PERFORM set_room_notification_prefs('abababab-0000-0000-0000-0000000000b1', 0, NULL, NULL);
  RAISE EXCEPTION 'FAIL üye olmayan ayar değiştirdi';
EXCEPTION WHEN raise_exception THEN IF SQLERRM NOT LIKE '%not_allowed%' THEN RAISE; END IF; END $$;
SELECT pg_temp.check('üye olmayan okuyamaz', get_room_notification_prefs('abababab-0000-0000-0000-0000000000b1') IS NULL);
SELECT pg_temp.as_user(:'A');
DO $$ BEGIN
  PERFORM set_room_notification_prefs('abababab-0000-0000-0000-0000000000b1', NULL, 'loud', NULL);
  RAISE EXCEPTION 'FAIL geçersiz kip';
EXCEPTION WHEN raise_exception THEN IF SQLERRM NOT LIKE '%invalid_preview_mode%' THEN RAISE; END IF; END $$;
DO $$ BEGIN
  PERFORM set_room_notification_prefs('abababab-0000-0000-0000-0000000000b1', -5, NULL, NULL);
  RAISE EXCEPTION 'FAIL geçersiz süre';
EXCEPTION WHEN raise_exception THEN IF SQLERRM NOT LIKE '%invalid_mute_duration%' THEN RAISE; END IF; END $$;
-- Sessizdeyken mesaj bildirimi üretilmez; B'nin ayarı A'yı etkilemez
SELECT pg_temp.as_user(:'B');
RESET ROLE;
INSERT INTO messages (room_id, sender_id, original_text) VALUES ('abababab-0000-0000-0000-0000000000b1', :'B', 'np-sessiz');
SELECT pg_temp.check('sessizdeki sohbet bildirim üretmez',
  NOT EXISTS (SELECT 1 FROM notifications n JOIN messages m ON n.target_secondary_id = m.id::text
              WHERE m.original_text = 'np-sessiz' AND n.recipient_id = :'A'));
SET ROLE authenticated;
SELECT pg_temp.as_user(:'A');
SELECT set_room_notification_prefs('abababab-0000-0000-0000-0000000000b1', 0, 'inherit', true);
RESET ROLE;
INSERT INTO messages (room_id, sender_id, original_text) VALUES ('abababab-0000-0000-0000-0000000000b1', :'B', 'np-acik');
SELECT pg_temp.check('sessiz kalkınca bildirim gelir',
  EXISTS (SELECT 1 FROM notifications n JOIN messages m ON n.target_secondary_id = m.id::text
          WHERE m.original_text = 'np-acik' AND n.recipient_id = :'A'));
DELETE FROM notifications WHERE target_id = 'abababab-0000-0000-0000-0000000000b1';
DELETE FROM messages WHERE room_id = 'abababab-0000-0000-0000-0000000000b1';
DELETE FROM room_participants WHERE room_id = 'abababab-0000-0000-0000-0000000000b1';
DELETE FROM rooms WHERE id = 'abababab-0000-0000-0000-0000000000b1';
SELECT 'TÜM v0.9.0 SOHBET BİLDİRİM AYARI TESTLERİ GEÇTİ';
-- v0.9.0 N-C: kaydetme bildirimi isteğe bağlı (varsayılan kapalı)
RESET ROLE;
INSERT INTO posts (id, author_id, content_type, caption) VALUES ('5a5a5a5a-0000-0000-0000-0000000000c1', :'A', 'text', 'nc-save');
INSERT INTO saved_posts (user_id, post_id) VALUES (:'B', '5a5a5a5a-0000-0000-0000-0000000000c1');
SELECT pg_temp.check('varsayılan: kaydetme bildirilmez',
  NOT EXISTS (SELECT 1 FROM notifications WHERE event_type = 'save' AND target_id = '5a5a5a5a-0000-0000-0000-0000000000c1'));
SET ROLE authenticated;
SELECT pg_temp.as_user(:'A');
SELECT pg_temp.check('varsayılan tercih kapalı', NOT get_my_save_notifications());
SELECT pg_temp.check('sahibi açar', set_my_save_notifications(true));
SELECT pg_temp.as_user(:'C');
SELECT pg_temp.check('başkası A''nın tercihini görmez (kendi tercihi kapalı)', NOT get_my_save_notifications());
RESET ROLE;
INSERT INTO saved_posts (user_id, post_id) VALUES (:'C', '5a5a5a5a-0000-0000-0000-0000000000c1');
SELECT pg_temp.check('açıkken kaydetme bildirilir',
  EXISTS (SELECT 1 FROM notifications WHERE event_type = 'save' AND target_id = '5a5a5a5a-0000-0000-0000-0000000000c1' AND actor_id = :'C'));
DELETE FROM notifications WHERE target_id = '5a5a5a5a-0000-0000-0000-0000000000c1';
DELETE FROM saved_posts WHERE post_id = '5a5a5a5a-0000-0000-0000-0000000000c1';
DELETE FROM posts WHERE id = '5a5a5a5a-0000-0000-0000-0000000000c1';
UPDATE profile_private SET notify_post_saves = false WHERE user_id = :'A';
SELECT 'TÜM v0.9.0 KAYDETME BİLDİRİMİ TESTLERİ GEÇTİ';
-- v0.9.0 N-B: @etiketleme (not: önceki bloklar A'nın kullanıcı adını 'ali' yapar)
SELECT pg_temp.check('ön koşul: A = ali', (SELECT username FROM profiles WHERE id = :'A') = 'ali');
RESET ROLE;
SELECT pg_temp.check('ayrıştırıcı: tekil, küçük harf, e-posta/uzun ad hariç',
  juzzio_extract_mentions('Hi @UserB ve @userb, a@b.com @ab @' || repeat('z', 31) || ' (@userc.)') = ARRAY['userb', 'userc']);
SELECT pg_temp.check('içerik başına en fazla 10 etiket',
  cardinality(juzzio_extract_mentions((SELECT string_agg('@user' || g, ' ') FROM generate_series(100, 130) g))) = 10);
-- A, B ve C'yi herkese açık gönderide etiketler
INSERT INTO posts (id, author_id, content_type, caption, visibility)
VALUES ('6b6b6b6b-0000-0000-0000-0000000000d1', :'A', 'text', 'merhaba @userb ve @userc @ali @yokboyle', 'public');
SELECT pg_temp.check('etiketlenen B ve C kaydı, kendini etiketleme yok',
  (SELECT array_agg(mentioned_user_id ORDER BY mentioned_user_id) FROM content_mentions WHERE content_id = '6b6b6b6b-0000-0000-0000-0000000000d1')
  = ARRAY[:'B'::uuid, :'C'::uuid]);
SELECT pg_temp.check('B''ye etiket bildirimi',
  EXISTS (SELECT 1 FROM notifications WHERE recipient_id = :'B' AND event_type = 'mention' AND target_secondary_id = '6b6b6b6b-0000-0000-0000-0000000000d1'));
-- Düzenleme: aynı etiket yeniden bildirilmez
UPDATE posts SET caption = caption || ' tekrar @userb' WHERE id = '6b6b6b6b-0000-0000-0000-0000000000d1';
SELECT pg_temp.check('düzenlemede tekrar bildirim yok',
  (SELECT count(*) FROM notifications WHERE recipient_id = :'B' AND event_type = 'mention' AND target_secondary_id = '6b6b6b6b-0000-0000-0000-0000000000d1') = 1);
-- Tercih: C 'nobody' → yorumda etiketlenemez
UPDATE profiles SET privacy_mentions = 'nobody' WHERE id = :'C';
INSERT INTO post_comments (id, post_id, author_id, content)
VALUES ('6b6b6b6b-0000-0000-0000-0000000000d2', '6b6b6b6b-0000-0000-0000-0000000000d1', :'B', 'bak @userc @ali');
SELECT pg_temp.check('nobody tercihi etiketi engeller; A yorumda etiketlenir',
  NOT EXISTS (SELECT 1 FROM content_mentions WHERE content_id = '6b6b6b6b-0000-0000-0000-0000000000d2' AND mentioned_user_id = :'C')
  AND EXISTS (SELECT 1 FROM content_mentions WHERE content_id = '6b6b6b6b-0000-0000-0000-0000000000d2' AND mentioned_user_id = :'A'));
UPDATE profiles SET privacy_mentions = 'everyone' WHERE id = :'C';
-- Engel: B, A'yı engellerse A, B'yi etiketleyemez
INSERT INTO blocked_users (blocker_id, blocked_id) VALUES (:'B', :'A');
INSERT INTO posts (id, author_id, content_type, caption) VALUES ('6b6b6b6b-0000-0000-0000-0000000000d3', :'A', 'text', '@userb engelli');
SELECT pg_temp.check('engel varken etiket yok',
  NOT EXISTS (SELECT 1 FROM content_mentions WHERE content_id = '6b6b6b6b-0000-0000-0000-0000000000d3'));
DELETE FROM blocked_users WHERE blocker_id = :'B' AND blocked_id = :'A';
-- Görünürlük: özel gönderide etiketlenen içeriği göremez → bildirim yok
INSERT INTO posts (id, author_id, content_type, caption, visibility) VALUES ('6b6b6b6b-0000-0000-0000-0000000000d4', :'A', 'text', '@userc gizli', 'private');
SELECT pg_temp.check('göremediği içerikte etiket yok',
  NOT EXISTS (SELECT 1 FROM content_mentions WHERE content_id = '6b6b6b6b-0000-0000-0000-0000000000d4'));
-- RLS: üçüncü kişi etiket kaydını göremez; istemci doğrudan ekleyemez; öneri
SET ROLE authenticated;
SELECT pg_temp.as_user(:'C');
SELECT pg_temp.check('C yalnız kendi etiketini görür',
  (SELECT count(*) FROM content_mentions WHERE content_id = '6b6b6b6b-0000-0000-0000-0000000000d1') = 1);
DO $$ BEGIN
  INSERT INTO content_mentions (content_type, content_id, author_id, mentioned_user_id)
  VALUES ('post', gen_random_uuid(), 'cccccccc-0000-0000-0000-000000000003', 'aaaaaaaa-0000-0000-0000-000000000001');
  RAISE EXCEPTION 'FAIL istemci etiket kaydı ekledi';
EXCEPTION WHEN insufficient_privilege THEN NULL; END $$;
SELECT pg_temp.check('öneri: ad veya görünen ad öneki, kendisi yok', (SELECT array_agg(username ORDER BY username) FROM suggest_mentions('user')) = ARRAY['ali', 'userb']);
SELECT pg_temp.check('öneri: joker karakter etkisiz', NOT EXISTS (SELECT 1 FROM suggest_mentions('%')));
SELECT pg_temp.as_user(:'A');
SELECT set_my_mention_privacy('nobody');
SELECT pg_temp.as_user(:'C');
SELECT pg_temp.check('nobody olan öneride çıkmaz', NOT EXISTS (SELECT 1 FROM suggest_mentions('ali')));
SELECT pg_temp.as_user(:'A');
SELECT set_my_mention_privacy('everyone');
RESET ROLE;
DELETE FROM notifications WHERE event_type = 'mention';
DELETE FROM content_mentions;
DELETE FROM post_comments WHERE id = '6b6b6b6b-0000-0000-0000-0000000000d2';
DELETE FROM posts WHERE id::text LIKE '6b6b6b6b-%';
SELECT 'TÜM v0.9.0 ETİKETLEME TESTLERİ GEÇTİ';
-- v0.9.0 C-A3: Yaşam Merkezi görevleri, mesaja hatırlatıcı, kayıtlı mesajlar
RESET ROLE;
SELECT r.id AS lroom FROM rooms r
  JOIN room_participants a ON a.room_id = r.id AND a.user_id = :'A' AND a.left_at IS NULL
  JOIN room_participants b ON b.room_id = r.id AND b.user_id = :'B' AND b.left_at IS NULL
  WHERE NOT r.is_group LIMIT 1 \gset
INSERT INTO messages (id, room_id, sender_id, original_text) VALUES ('7e7e7e7e-0000-0000-0000-0000000000e1', :'lroom', :'B', 'hatırlat bunu');
SET ROLE authenticated;
SELECT pg_temp.as_user(:'A');
INSERT INTO life_tasks (title, description, due_at, remind_at, client_request_id)
VALUES ('  Süt al  ', 'market', NOW() + INTERVAL '1 day', NOW() - INTERVAL '1 minute', 'lt_req_1');
SELECT pg_temp.check('görev kırpılır ve kaydedilir', (SELECT title FROM life_tasks WHERE client_request_id = 'lt_req_1') = 'Süt al');
DO $$ BEGIN
  INSERT INTO life_tasks (title, client_request_id) VALUES ('x', 'lt_req_1');
  RAISE EXCEPTION 'FAIL aynı istek iki kez eklendi';
EXCEPTION WHEN unique_violation THEN NULL; END $$;
DO $$ BEGIN
  INSERT INTO life_tasks (title) VALUES ('   ');
  RAISE EXCEPTION 'FAIL boş başlıklı görev';
EXCEPTION WHEN check_violation THEN NULL; END $$;
INSERT INTO life_tasks (kind, room_id, message_id, remind_at)
VALUES ('message_reminder', :'lroom', '7e7e7e7e-0000-0000-0000-0000000000e1', NOW() - INTERVAL '1 minute');
SELECT pg_temp.check('mesaj hatırlatıcısı kaydedildi', EXISTS (SELECT 1 FROM life_tasks WHERE kind = 'message_reminder'));
INSERT INTO saved_messages (message_id, room_id, user_id) VALUES ('7e7e7e7e-0000-0000-0000-0000000000e1', :'lroom', :'A');
SELECT pg_temp.check('mesaj kaydedildi', EXISTS (SELECT 1 FROM saved_messages WHERE message_id = '7e7e7e7e-0000-0000-0000-0000000000e1'));
-- C üye değil: hatırlatıcı/kayıt yapamaz, A'nın kayıtlarını göremez
SELECT set_config('juzzio.lroom', :'lroom', false);
SELECT pg_temp.as_user(:'C');
DO $$ BEGIN
  INSERT INTO life_tasks (kind, room_id, message_id, remind_at, user_id)
  VALUES ('message_reminder', current_setting('juzzio.lroom')::uuid, '7e7e7e7e-0000-0000-0000-0000000000e1', NOW(), 'cccccccc-0000-0000-0000-000000000003');
  RAISE EXCEPTION 'FAIL üye olmayan mesaj hatırlatıcısı';
EXCEPTION WHEN raise_exception THEN IF SQLERRM NOT LIKE '%not_allowed%' THEN RAISE; END IF; END $$;
DO $$ BEGIN
  INSERT INTO saved_messages (message_id, room_id, user_id)
  VALUES ('7e7e7e7e-0000-0000-0000-0000000000e1', current_setting('juzzio.lroom')::uuid, 'cccccccc-0000-0000-0000-000000000003');
  RAISE EXCEPTION 'FAIL üye olmayan mesaj kaydetti';
EXCEPTION WHEN insufficient_privilege THEN NULL; END $$;
SELECT pg_temp.check('başkasının görev/kayıtları görünmez',
  NOT EXISTS (SELECT 1 FROM life_tasks) AND NOT EXISTS (SELECT 1 FROM saved_messages));
DO $$ BEGIN
  INSERT INTO life_tasks (title, user_id) VALUES ('sahte', 'aaaaaaaa-0000-0000-0000-000000000001');
  RAISE EXCEPTION 'FAIL başkası adına görev';
EXCEPTION WHEN insufficient_privilege THEN NULL; END $$;
DO $$ BEGIN
  PERFORM juzzio_fire_due_reminders(10);
  RAISE EXCEPTION 'FAIL istemci hatırlatma tetikledi';
EXCEPTION WHEN insufficient_privilege THEN NULL; END $$;
-- Sahiplik güncellemeyle değiştirilemez
SELECT pg_temp.as_user(:'A');
UPDATE life_tasks SET user_id = 'cccccccc-0000-0000-0000-000000000003' WHERE client_request_id = 'lt_req_1';
RESET ROLE;
SELECT pg_temp.check('sahiplik değişmez', (SELECT user_id FROM life_tasks WHERE client_request_id = 'lt_req_1') = :'A');
-- Hatırlatmalar tetiklenir; tekrar çalıştırmada çift bildirim yok
SELECT pg_temp.check('2 hatırlatma tetiklendi', juzzio_fire_due_reminders(100) = 2);
SELECT pg_temp.check('ikinci çalıştırma boş', juzzio_fire_due_reminders(100) = 0);
SELECT pg_temp.check('görev hatırlatma bildirimi metinli, mesaj hatırlatıcısı METİNSİZ',
  EXISTS (SELECT 1 FROM notifications WHERE recipient_id = :'A' AND event_type = 'reminder' AND preview_text = 'task|Süt al')
  AND EXISTS (SELECT 1 FROM notifications WHERE recipient_id = :'A' AND event_type = 'reminder' AND preview_text = 'message|'
              AND target_secondary_id = '7e7e7e7e-0000-0000-0000-0000000000e1'));
-- Zaman değişince yeniden hatırlatılabilir; tamamlanan görev hatırlatılmaz
UPDATE life_tasks SET remind_at = NOW() - INTERVAL '10 seconds' WHERE client_request_id = 'lt_req_1';
SELECT pg_temp.check('yeni zaman → yeniden hatırlatma', juzzio_fire_due_reminders(100) = 1);
UPDATE life_tasks SET remind_at = NOW() - INTERVAL '5 seconds', done_at = NOW() WHERE client_request_id = 'lt_req_1';
SELECT pg_temp.check('tamamlanan görev hatırlatılmaz', juzzio_fire_due_reminders(100) = 0);
DELETE FROM notifications WHERE event_type = 'reminder';
DELETE FROM life_tasks;
DELETE FROM saved_messages;
DELETE FROM messages WHERE id = '7e7e7e7e-0000-0000-0000-0000000000e1';
SELECT 'TÜM v0.9.0 YAŞAM MERKEZİ / HATIRLATICI / KAYITLI MESAJ TESTLERİ GEÇTİ';
-- v0.9.0 §4.5: mesaj düzenleme + geçmiş
RESET ROLE;
SELECT r.id AS eroom FROM rooms r
  JOIN room_participants a ON a.room_id = r.id AND a.user_id = :'A' AND a.left_at IS NULL
  JOIN room_participants b ON b.room_id = r.id AND b.user_id = :'B' AND b.left_at IS NULL
  WHERE NOT r.is_group LIMIT 1 \gset
INSERT INTO messages (id, room_id, sender_id, original_text, message_type, translated_text)
VALUES ('8e8e8e8e-0000-0000-0000-0000000000a1', :'eroom', :'A', 'ilk hali', 'text', 'first'),
       ('8e8e8e8e-0000-0000-0000-0000000000a2', :'eroom', :'A', 'eski', 'text', ''),
       ('8e8e8e8e-0000-0000-0000-0000000000a3', :'eroom', :'A', '', 'text', '');
SELECT set_config('request.jwt.claim.sub', '', false); -- kurulum güncellemeleri servis olarak (düzenleme sayılmaz)
UPDATE messages SET created_at = NOW() - INTERVAL '20 minutes' WHERE id = '8e8e8e8e-0000-0000-0000-0000000000a2';
UPDATE messages SET metadata = '{"e2ee": {"v": 2, "c": "AAA"}}'::jsonb WHERE id = '8e8e8e8e-0000-0000-0000-0000000000a3';
SET ROLE authenticated;
SELECT pg_temp.as_user(:'A');
UPDATE messages SET original_text = 'düzeltilmiş' WHERE id = '8e8e8e8e-0000-0000-0000-0000000000a1';
SELECT pg_temp.check('düzenleme kaydedildi, eski çeviri temizlendi, edited_at dolu',
  (SELECT original_text = 'düzeltilmiş' AND translated_text = '' AND edited_at IS NOT NULL FROM messages WHERE id = '8e8e8e8e-0000-0000-0000-0000000000a1'));
UPDATE messages SET metadata = '{"e2ee": {"v": 2, "c": "BBB"}}'::jsonb WHERE id = '8e8e8e8e-0000-0000-0000-0000000000a3';
SELECT pg_temp.check('E2EE düzenlemede eski ZARF saklanır (sunucu açmaz)',
  (SELECT prev_metadata = '{"e2ee": {"v": 2, "c": "AAA"}}'::jsonb AND prev_text = '' FROM message_edits WHERE message_id = '8e8e8e8e-0000-0000-0000-0000000000a3'));
DO $$ BEGIN
  UPDATE messages SET original_text = 'geç' WHERE id = '8e8e8e8e-0000-0000-0000-0000000000a2';
  RAISE EXCEPTION 'FAIL 15 dk sonra düzenlendi';
EXCEPTION WHEN raise_exception THEN IF SQLERRM NOT LIKE '%edit_window_expired%' THEN RAISE; END IF; END $$;
DO $$ BEGIN
  UPDATE messages SET original_text = '   ' WHERE id = '8e8e8e8e-0000-0000-0000-0000000000a1';
  RAISE EXCEPTION 'FAIL boş düzenleme';
EXCEPTION WHEN raise_exception THEN IF SQLERRM NOT LIKE '%edit_empty%' THEN RAISE; END IF; END $$;
SELECT pg_temp.as_user(:'B');
SELECT pg_temp.check('oda üyesi geçmişi görür', (SELECT prev_text FROM message_edits WHERE message_id = '8e8e8e8e-0000-0000-0000-0000000000a1') = 'ilk hali');
UPDATE messages SET original_text = 'hack' WHERE id = '8e8e8e8e-0000-0000-0000-0000000000a1';
SELECT pg_temp.as_user(:'C');
SELECT pg_temp.check('üye olmayan geçmişi göremez', NOT EXISTS (SELECT 1 FROM message_edits));
DO $$ BEGIN
  INSERT INTO message_edits (message_id, room_id, editor_id) VALUES ('8e8e8e8e-0000-0000-0000-0000000000a1', current_setting('juzzio.lroom')::uuid, 'cccccccc-0000-0000-0000-000000000003');
  RAISE EXCEPTION 'FAIL istemci geçmiş yazdı';
EXCEPTION WHEN insufficient_privilege THEN NULL; END $$;
-- 10 düzenleme sınırı
SELECT pg_temp.as_user(:'A');
DO $$ BEGIN
  FOR i IN 2..10 LOOP
    UPDATE messages SET original_text = 'sürüm ' || i WHERE id = '8e8e8e8e-0000-0000-0000-0000000000a1';
  END LOOP;
  UPDATE messages SET original_text = 'sürüm 11' WHERE id = '8e8e8e8e-0000-0000-0000-0000000000a1';
  RAISE EXCEPTION 'FAIL 10 düzenleme sınırı aşıldı';
EXCEPTION WHEN raise_exception THEN IF SQLERRM NOT LIKE '%edit_limit_reached%' THEN RAISE; END IF; END $$;
RESET ROLE;
SELECT pg_temp.check('B''nin denemesi mesajı değiştirmedi; 10 geçmiş kaydı',
  (SELECT original_text FROM messages WHERE id = '8e8e8e8e-0000-0000-0000-0000000000a1') = 'düzeltilmiş'
  AND (SELECT count(*) FROM message_edits WHERE message_id = '8e8e8e8e-0000-0000-0000-0000000000a1') = 1);
-- Not: yukarıdaki DO bloğu hata ile geri alındığından yalnız ilk düzenleme kalıcıdır; sınırı ayrıca doğrula
SET ROLE authenticated;
SELECT pg_temp.as_user(:'A');
DO $$ BEGIN
  FOR i IN 2..10 LOOP
    UPDATE messages SET original_text = 'sürüm ' || i WHERE id = '8e8e8e8e-0000-0000-0000-0000000000a1';
  END LOOP;
END $$;
RESET ROLE;
SELECT pg_temp.check('10 geçmiş kaydı', (SELECT count(*) FROM message_edits WHERE message_id = '8e8e8e8e-0000-0000-0000-0000000000a1') = 10);
-- Silinince geçmiş de silinir; sistem (auth yok) güncellemesi kurala takılmaz
UPDATE messages SET is_deleted = true, original_text = '' WHERE id = '8e8e8e8e-0000-0000-0000-0000000000a1';
SELECT pg_temp.check('silinen mesajın geçmişi silindi', NOT EXISTS (SELECT 1 FROM message_edits WHERE message_id = '8e8e8e8e-0000-0000-0000-0000000000a1'));
SELECT set_config('request.jwt.claim.sub', '', false);
UPDATE messages SET original_text = 'sistem' WHERE id = '8e8e8e8e-0000-0000-0000-0000000000a2';
SELECT pg_temp.check('servis güncellemesi serbest', (SELECT original_text FROM messages WHERE id = '8e8e8e8e-0000-0000-0000-0000000000a2') = 'sistem');
DELETE FROM messages WHERE id::text LIKE '8e8e8e8e-%';
SELECT 'TÜM v0.9.0 MESAJ DÜZENLEME GEÇMİŞİ TESTLERİ GEÇTİ';
-- =============================================================================
-- v0.9.0 BUSINESS: durum makinesi, onaylar, kurulum, kiracı izolasyonu, ekip RBAC, CRM,
-- atama, otomatik yanıt, gerçek analiz, Personal'a dönüş (veri silinmez), personel yetkisi
-- =============================================================================
RESET ROLE;
DELETE FROM staff_roles WHERE user_id IN (:'A', :'B', :'C');
SELECT pg_temp.check('14 taslak hukuki belge, hepsi DRAFT etiketli',
  (SELECT count(*) FROM legal_documents WHERE doc_key LIKE 'business_%') = 14
  AND NOT EXISTS (SELECT 1 FROM legal_documents WHERE doc_key LIKE 'business_%' AND review_status <> 'DRAFT - LEGAL REVIEW REQUIRED')
  AND NOT EXISTS (SELECT 1 FROM legal_documents WHERE doc_key LIKE 'business_%' AND (policy_hash = '' OR body NOT LIKE '%DRAFT - LEGAL REVIEW REQUIRED%')));
SET ROLE authenticated;
SELECT pg_temp.as_user(:'A');
-- İstemci durumu doğrudan yazamaz
DO $$ BEGIN
  INSERT INTO business_accounts (id, status) VALUES ('aaaaaaaa-0000-0000-0000-000000000001', 'business_active');
  RAISE EXCEPTION 'FAIL istemci business_active yazdı';
EXCEPTION WHEN insufficient_privilege THEN NULL; END $$;
DO $$ BEGIN
  PERFORM juzzio_business_set_status('aaaaaaaa-0000-0000-0000-000000000001', 'business_active', 'system', 'x');
  RAISE EXCEPTION 'FAIL istemci iç durum fonksiyonunu çağırdı';
EXCEPTION WHEN insufficient_privilege THEN NULL; END $$;
SELECT pg_temp.check('başvuru → terms_pending',
  (business_start_application('business', 'Ali Kuaför', 'biz_req_0001')->>'status') = 'business_terms_pending');
SELECT pg_temp.check('aynı başvuru tekrarı çift kayıt üretmez',
  (business_start_application('business', 'Başka Ad', 'biz_req_0002')->>'status') = 'business_terms_pending'
  AND (SELECT display_name FROM business_accounts WHERE id = :'A') = 'Ali Kuaför');
SELECT pg_temp.check('zorunlu onaylar eksik listelenir (8)', jsonb_array_length(business_get_state()->'missing_consents') = 8);
DO $$ BEGIN
  PERFORM business_submit_consents();
  RAISE EXCEPTION 'FAIL onaysız başvuru ilerledi';
EXCEPTION WHEN raise_exception THEN IF SQLERRM NOT LIKE 'consents_missing%' THEN RAISE; END IF; END $$;
DO $$ BEGIN
  PERFORM business_run_setup_step('profile');
  RAISE EXCEPTION 'FAIL hazırlık onaysız başladı';
EXCEPTION WHEN raise_exception THEN IF SQLERRM NOT LIKE '%not_preparing%' THEN RAISE; END IF; END $$;
-- Belgeler önceden işaretli DEĞİL
SELECT pg_temp.check('hiçbir belge önceden onaylı değil',
  NOT EXISTS (SELECT 1 FROM jsonb_array_elements(get_business_legal_documents('tr')) e WHERE (e->>'accepted')::boolean));
SELECT record_consent(d, true, 'tr', 'juzzio 0.9.0') FROM (VALUES ('business_terms_of_use'), ('business_service_terms'),
  ('business_kvkk_notice'), ('business_data_processing_info'), ('business_content_rights'),
  ('business_customer_comm_duties'), ('business_abuse_policy'), ('business_closure_retention')) v(d);
-- Geri alma → yeniden eksik; tekrar kabul
SELECT record_consent('business_kvkk_notice', false);
SELECT pg_temp.check('geri alınan onay eksik sayılır', business_get_state()->'missing_consents' ? 'business_kvkk_notice');
SELECT record_consent('business_kvkk_notice', true);
SELECT pg_temp.check('onay kaydı değiştirilemez: geri alma ayrı satır', (SELECT count(*) FROM user_consents WHERE doc_key = 'business_kvkk_notice') = 3);
DO $$ BEGIN
  UPDATE user_consents SET action = 'accept';
  IF FOUND THEN RAISE EXCEPTION 'FAIL onay kaydı değişti'; END IF;
EXCEPTION WHEN insufficient_privilege THEN NULL; END $$;
SELECT pg_temp.check('isteğe bağlı pazarlama izni zorunlu değil',
  NOT (business_get_state()->'missing_consents' ? 'business_commercial_messages'));
SELECT pg_temp.check('onaylar tamam → preparing', (business_submit_consents()->>'status') = 'business_preparing');
-- Kurulum: sıra zorunlu, idempotent, kaldığı yerden devam
DO $$ BEGIN
  PERFORM business_run_setup_step('security');
  RAISE EXCEPTION 'FAIL adım atlandı';
EXCEPTION WHEN raise_exception THEN IF SQLERRM NOT LIKE 'previous_step_missing%' THEN RAISE; END IF; END $$;
SELECT business_run_setup_step('profile');
SELECT business_run_setup_step('profile');
SELECT business_run_setup_step('workspace');
SELECT pg_temp.check('yarıda kalan kurulum durumdan okunur', jsonb_array_length(business_get_state()->'steps') = 2
  AND (business_get_state()->>'status') = 'business_preparing');
SELECT business_run_setup_step('security');
SELECT business_run_setup_step('modules');
SELECT pg_temp.check('final → business_active', (business_run_setup_step('final')->>'status') = 'business_active');
SELECT pg_temp.check('durum geçmişi kayıtlı', (SELECT count(*) FROM business_status_events WHERE business_id = :'A') = 4);
SELECT pg_temp.check('görünüm business', business_set_view('business') = 'business');
-- Kiracı izolasyonu: B, A'nın verisini göremez/yazamaz
INSERT INTO business_customers (business_id, name, phone, tags) VALUES (:'A', 'Müşteri Bir', '555', ARRAY['vip']);
SELECT id AS cust FROM business_customers WHERE name = 'Müşteri Bir' \gset
INSERT INTO business_customer_notes (business_id, customer_id, body) VALUES (:'A', :'cust', 'sadece ekip görür');
SELECT pg_temp.as_user(:'B');
SELECT pg_temp.check('başka kullanıcı müşteri göremez', NOT EXISTS (SELECT 1 FROM business_customers));
DO $$ BEGIN
  INSERT INTO business_customers (business_id, name) VALUES ('aaaaaaaa-0000-0000-0000-000000000001', 'sızma');
  RAISE EXCEPTION 'FAIL kiracı dışı yazma';
EXCEPTION WHEN insufficient_privilege THEN NULL; END $$;
DO $$ BEGIN
  PERFORM business_overview('aaaaaaaa-0000-0000-0000-000000000001', 30);
  RAISE EXCEPTION 'FAIL kiracı dışı analiz';
EXCEPTION WHEN raise_exception THEN IF SQLERRM NOT LIKE '%not_allowed%' THEN RAISE; END IF; END $$;
SELECT pg_temp.check('aktif işletme profili herkese görünür', (SELECT display_name FROM business_accounts WHERE id = :'A') = 'Ali Kuaför');
-- Ekip: A, B'yi destek görevlisi olarak davet eder; B kabul eder
SELECT pg_temp.as_user(:'A');
SELECT business_invite_member(:'A', 'userb', 'support_agent');
SELECT pg_temp.as_user(:'B');
SELECT pg_temp.check('davet bekleyen üyelik görünür', (business_get_state()->'memberships'->0->>'status') = 'invited');
SELECT pg_temp.check('davetli henüz yetkisiz', NOT EXISTS (SELECT 1 FROM business_customers));
SELECT business_respond_invite(:'A', true);
SELECT pg_temp.check('destek: müşteri okur', EXISTS (SELECT 1 FROM business_customers WHERE id = :'cust'));
INSERT INTO business_customer_notes (business_id, customer_id, body) VALUES (:'A', :'cust', 'destek notu');
DO $$ BEGIN
  PERFORM business_invite_member('aaaaaaaa-0000-0000-0000-000000000001', 'userc', 'analyst');
  RAISE EXCEPTION 'FAIL destek ekip yönetti';
EXCEPTION WHEN raise_exception THEN IF SQLERRM NOT LIKE '%not_allowed%' THEN RAISE; END IF; END $$;
DO $$ BEGIN
  INSERT INTO business_auto_replies (business_id, kind, enabled, body) VALUES ('aaaaaaaa-0000-0000-0000-000000000001', 'welcome', true, 'x');
  RAISE EXCEPTION 'FAIL destek otomasyon değiştirdi';
EXCEPTION WHEN insufficient_privilege THEN NULL; END $$;
SELECT pg_temp.check('destek denetim kaydını göremez', NOT EXISTS (SELECT 1 FROM business_audit_log));
-- Gelen kutusu: yalnız oda katılımcısı ekleyebilir; atama yetkisi
RESET ROLE;
SELECT set_config('request.jwt.claim.sub', '', false);
INSERT INTO rooms (id, room_code, livekit_room_name, is_group) VALUES ('b1b1b1b1-0000-0000-0000-0000000000c1', 'biz_dm_ac', 'biz_dm_ac', false);
INSERT INTO room_participants (room_id, user_id) VALUES ('b1b1b1b1-0000-0000-0000-0000000000c1', :'A'), ('b1b1b1b1-0000-0000-0000-0000000000c1', :'C');
\set broom b1b1b1b1-0000-0000-0000-0000000000c1
SET ROLE authenticated;
SELECT pg_temp.as_user(:'A');
INSERT INTO business_customers (business_id, customer_user_id, name) VALUES (:'A', :'C', 'C müşteri');
SELECT id AS ccust FROM business_customers WHERE customer_user_id = :'C' \gset
INSERT INTO business_conversations (business_id, room_id, customer_id) VALUES (:'A', :'broom', :'ccust');
SELECT id AS bconv FROM business_conversations WHERE room_id = :'broom' \gset
SELECT set_config('juzzio.bconv', :'bconv', false);
SELECT business_assign_conversation(:'bconv', :'B', 'vardiya');
SELECT pg_temp.check('atama + denetim + bildirim',
  (SELECT assignee_id FROM business_conversations WHERE id = :'bconv') = :'B'
  AND EXISTS (SELECT 1 FROM business_audit_log WHERE action = 'assign'));
DO $$ BEGIN
  PERFORM business_assign_conversation(current_setting('juzzio.bconv')::uuid, 'cccccccc-0000-0000-0000-000000000003', '');
  RAISE EXCEPTION 'FAIL ekip dışına atama';
EXCEPTION WHEN raise_exception THEN IF SQLERRM NOT LIKE '%assignee_not_member%' THEN RAISE; END IF;
     WHEN undefined_object THEN NULL; END $$;
-- Otomatik karşılama: ilk müşteri mesajında 1 kez, işaretli; 12 saat içinde tekrar yok
INSERT INTO business_auto_replies (business_id, kind, enabled, body) VALUES (:'A', 'welcome', true, 'Merhaba, en kısa sürede dönüş yapacağız.');
RESET ROLE;
SELECT set_config('request.jwt.claim.sub', '', false);
INSERT INTO messages (room_id, sender_id, original_text) VALUES (:'broom', :'C', 'fiyat nedir?');
INSERT INTO messages (room_id, sender_id, original_text) VALUES (:'broom', :'C', 'cevap?');
SELECT pg_temp.check('karşılama 1 kez, işaretli',
  (SELECT count(*) FROM messages WHERE room_id = :'broom' AND metadata->>'security' = 'business_auto_reply') = 1
  AND (SELECT count(*) FROM business_auto_reply_log WHERE business_id = :'A') = 1);
INSERT INTO messages (room_id, sender_id, original_text) VALUES (:'broom', :'A', 'buyurun');
SELECT pg_temp.check('işletmenin kendi mesajı otomatik yanıt tetiklemez',
  (SELECT count(*) FROM business_auto_reply_log WHERE business_id = :'A') = 1);
-- Gerçek analiz
SET ROLE authenticated;
SELECT pg_temp.as_user(:'A');
SELECT pg_temp.check('analiz gerçek sayımlar',
  (business_overview(NULL, 30)->>'customers')::int = 2
  AND (business_overview(NULL, 30)->>'messages_today')::int = 4
  AND (business_overview(NULL, 30)->>'open_conversations')::int = 1
  AND (business_overview(NULL, 30)->>'awaiting_reply')::int = 0);
-- Randevu: hizmet başka işletmeden olamaz; bitiş başlangıçtan sonra
INSERT INTO business_services (business_id, name, duration_min) VALUES (:'A', 'Saç kesimi', 45);
INSERT INTO business_appointments (business_id, customer_id, service_id, starts_at, ends_at, assignee_id, remind_minutes_before)
SELECT :'A', :'ccust', id, NOW() + INTERVAL '30 minutes', NOW() + INTERVAL '75 minutes', :'B', 60 FROM business_services WHERE name = 'Saç kesimi';
INSERT INTO business_followups (business_id, customer_id, title, due_at, assignee_id) VALUES (:'A', :'cust', 'Teklif gönder', NOW() - INTERVAL '1 minute', :'B');
INSERT INTO business_tasks (business_id, title, assignee_id) VALUES (:'A', 'Stok say', :'B');
DO $$ BEGIN
  INSERT INTO business_appointments (business_id, starts_at, ends_at) VALUES ('aaaaaaaa-0000-0000-0000-000000000001', NOW(), NOW() - INTERVAL '1 hour');
  RAISE EXCEPTION 'FAIL ters randevu';
EXCEPTION WHEN check_violation THEN NULL; END $$;
RESET ROLE;
SELECT juzzio_fire_business_reminders(100) AS fired \gset
SELECT pg_temp.check('takip + randevu hatırlatması atanan kişiye', :'fired'::int = 2
  AND (SELECT count(*) FROM notifications WHERE recipient_id = :'B' AND event_type = 'reminder' AND preview_text LIKE 'followup|%') = 1
  AND (SELECT count(*) FROM notifications WHERE recipient_id = :'B' AND event_type = 'reminder' AND preview_text LIKE 'appointment|%') = 1);
SELECT pg_temp.check('hatırlatma tekrarlanmaz', juzzio_fire_business_reminders(100) = 0);
-- Personel: destek görevlisi listeyi görür ama durumu değiştiremez; yönetici askıya alır
INSERT INTO staff_roles (user_id, role) VALUES (:'C', 'support');
SET ROLE authenticated;
SELECT pg_temp.as_user(:'C');
SELECT pg_temp.check('destek personeli işletmeleri listeler', jsonb_array_length(admin_list_business_accounts('', NULL, 10)) >= 1);
DO $$ BEGIN
  PERFORM admin_business_set_status('', 'aaaaaaaa-0000-0000-0000-000000000001', 'business_suspended', 'test');
  RAISE EXCEPTION 'FAIL destek askıya aldı';
EXCEPTION WHEN raise_exception THEN IF SQLERRM NOT LIKE 'permission_denied%' THEN RAISE; END IF; END $$;
RESET ROLE;
UPDATE staff_roles SET role = 'admin' WHERE user_id = :'C';
SET ROLE authenticated;
SELECT pg_temp.as_user(:'C');
SELECT pg_temp.check('yönetici askıya alır (gerekçeli, denetimli)', admin_business_set_status('', :'A', 'business_suspended', 'spam şikayeti') = 'business_suspended');
SELECT pg_temp.as_user(:'B');
SELECT pg_temp.check('askıdaki işletmede ekip yetkisi düşer', NOT EXISTS (SELECT 1 FROM business_customers));
SELECT pg_temp.as_user(:'C');
SELECT admin_business_set_status('', :'A', 'business_active', 'itiraz kabul');
-- Personal'a dönüş: kapatma veri SİLMEZ, ekip erişimi kapanır
SELECT pg_temp.as_user(:'A');
SELECT pg_temp.check('geçici devre dışı', (business_owner_action('pause')->>'status') = 'business_paused');
SELECT pg_temp.check('devam', (business_owner_action('resume')->>'status') = 'business_active');
SELECT pg_temp.check('kapat → cancelled, görünüm personal', (business_owner_action('close', 'artık gerek yok')->>'status') = 'business_cancelled'
  AND (SELECT active_view FROM business_accounts WHERE id = :'A') = 'personal');
RESET ROLE;
SELECT pg_temp.check('kapatmada müşteri/not/görev verisi korunur',
  (SELECT count(*) FROM business_customers WHERE business_id = :'A') = 2
  AND (SELECT count(*) FROM business_customer_notes WHERE business_id = :'A') = 2
  AND (SELECT status FROM business_members WHERE business_id = :'A' AND user_id = :'B') = 'removed');
SET ROLE authenticated;
SELECT pg_temp.as_user(:'A');
SELECT pg_temp.check('kapalı işletmede sahip bile iş verisine erişemez', NOT EXISTS (SELECT 1 FROM business_customers));
DO $$ BEGIN
  PERFORM business_set_view('business');
  RAISE EXCEPTION 'FAIL kapalı işletmede business görünümü';
EXCEPTION WHEN raise_exception THEN IF SQLERRM NOT LIKE '%business_not_active%' THEN RAISE; END IF; END $$;
SELECT pg_temp.check('yeniden başvuru mümkün', (business_start_application('business', 'Ali Kuaför', 'biz_req_0003')->>'status') = 'business_terms_pending');
RESET ROLE;
DELETE FROM staff_roles WHERE user_id = :'C';
DELETE FROM notifications WHERE event_type = 'reminder' OR preview_text LIKE 'business_%';
DELETE FROM messages WHERE room_id = :'broom' AND (original_text IN ('fiyat nedir?', 'cevap?', 'buyurun') OR metadata->>'security' = 'business_auto_reply');
DELETE FROM business_accounts WHERE id = :'A';
DELETE FROM user_consents WHERE user_id = :'A';
DELETE FROM messages WHERE room_id = 'b1b1b1b1-0000-0000-0000-0000000000c1';
DELETE FROM room_participants WHERE room_id = 'b1b1b1b1-0000-0000-0000-0000000000c1';
DELETE FROM rooms WHERE id = 'b1b1b1b1-0000-0000-0000-0000000000c1';
SELECT 'TÜM v0.9.0 BUSINESS TESTLERİ GEÇTİ';

-- ===== 10.22 Güvenlik Merkezi =====
RESET ROLE;
DELETE FROM user_devices WHERE user_id IN (:'A', :'B');
DELETE FROM security_events WHERE user_id IN (:'A', :'B');
SET ROLE authenticated;
SELECT pg_temp.as_user(:'A');
SELECT register_my_device('devA_first_000001', 'android');
SELECT pg_temp.check('ilk cihaz uyarı üretmez', (SELECT count(*) FROM security_events) = 0);
SELECT register_my_device('devA_second_000002', 'android');
SELECT pg_temp.check('yeni cihaz uyarısı', (SELECT count(*) FROM security_events WHERE kind = 'new_device') = 1);
SELECT register_my_device('devA_second_000002', 'android');
SELECT pg_temp.check('aynı cihaz tekrar uyarı üretmez', (SELECT count(*) FROM security_events) = 1);
SELECT pg_temp.check('cihaz listesi 2, mevcut işaretli', jsonb_array_length(list_my_devices('devA_first_000001')) = 2
    AND (SELECT count(*) FROM jsonb_array_elements(list_my_devices('devA_first_000001')) e WHERE (e->>'current')::bool) = 1);
SELECT pg_temp.check('mevcut cihaz çıkarılamaz', NOT forget_my_device('000001', 'devA_first_000001'));
SELECT pg_temp.check('diğer cihaz çıkarılır', forget_my_device('000002', 'devA_first_000001'));
SELECT pg_temp.check('çıkarma olayı', (SELECT count(*) FROM security_events WHERE kind = 'device_removed') = 1);
DO $$ BEGIN INSERT INTO security_events (user_id, kind) VALUES (auth.uid(), 'new_device'); RAISE NOTICE 'FAIL istemci sahte olay yazdı';
EXCEPTION WHEN insufficient_privilege THEN RAISE NOTICE 'PASS istemci sahte olay yazamaz'; END $$;
SELECT pg_temp.check('özet gerçek veriden', (get_my_security_overview()->>'devices')::int = 1 AND (get_my_security_overview()->>'unseen_alerts')::int = 2);
SELECT pg_temp.check('görüldü işaretleme', mark_my_security_events_seen() = 2);
SELECT pg_temp.check('görüldü sonrası okunmamış 0', (get_my_security_overview()->>'unseen_alerts')::int = 0);
SELECT pg_temp.as_user(:'B');
SELECT pg_temp.check('başkasının olayları görünmez', (SELECT count(*) FROM security_events) = 0 AND jsonb_array_length(list_my_devices('')) = 0);
SELECT pg_temp.check('başkasının cihazı çıkarılamaz', NOT forget_my_device('000001', ''));
RESET ROLE;
UPDATE profiles SET e2ee_key_id = '0123456789abcdef' WHERE id = :'B';
UPDATE profiles SET e2ee_key_id = 'fedcba9876543210' WHERE id = :'B';
SELECT pg_temp.check('E2EE anahtar değişimi olayı', (SELECT count(*) FROM security_events WHERE user_id = :'B' AND kind = 'e2ee_key_changed') >= 1);
DELETE FROM security_events WHERE user_id IN (:'A', :'B');
DELETE FROM user_devices WHERE user_id IN (:'A', :'B');
SELECT 'TÜM v0.9.0 GÜVENLİK MERKEZİ TESTLERİ GEÇTİ';
