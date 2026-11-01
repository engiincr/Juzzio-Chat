-- JUZZIO — test kullanıcıları (kanonik SQL uygulandıktan SONRA; profil tetikleyicisi çalışsın)
INSERT INTO auth.users (id, email, raw_user_meta_data) VALUES
    ('aaaaaaaa-0000-0000-0000-000000000001', 'a@test.local', '{"username":"usera","display_name":"User A"}'),
    ('bbbbbbbb-0000-0000-0000-000000000002', 'b@test.local', '{"username":"userb","display_name":"User B"}'),
    ('cccccccc-0000-0000-0000-000000000003', 'c@test.local', '{"username":"userc","display_name":"User C"}'),
    ('dddddddd-0000-0000-0000-000000000004', 'd@test.local', '{"username":"userd","display_name":"User D"}')
ON CONFLICT (id) DO NOTHING;

-- Arkadaşlıklar: A↔B, A↔C, B↔C kabul edilmiş (grup/arama testleri bunu varsayar)
INSERT INTO public.friendships (requester_id, receiver_id, status) VALUES
    ('aaaaaaaa-0000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000002', 'accepted'),
    ('aaaaaaaa-0000-0000-0000-000000000001', 'cccccccc-0000-0000-0000-000000000003', 'accepted'),
    ('bbbbbbbb-0000-0000-0000-000000000002', 'cccccccc-0000-0000-0000-000000000003', 'accepted')
ON CONFLICT (requester_id, receiver_id) DO NOTHING;
