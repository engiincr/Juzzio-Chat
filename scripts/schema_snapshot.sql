-- Juzzio — dağıtım öncesi şema anlık görüntüsü (yalnızca okuma, VERİ İÇERMEZ).
-- CI supabase-sync işinde psql -At ile çalışır; çıktı 90 gün artefakt olarak saklanır.
-- Bir dağıtım sonrası fonksiyon/politika davranışı geri alınmak istenirse eski
-- tanımlar buradan alınıp ileri yönlü düzeltme (forward-fix) olarak uygulanır.
SELECT '## functions';
SELECT format('-- %s.%s(%s)', n.nspname, p.proname, pg_get_function_identity_arguments(p.oid))
       || E'\n' || pg_get_functiondef(p.oid) || ';'
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.prokind IN ('f', 'p')
ORDER BY p.proname, pg_get_function_identity_arguments(p.oid);

SELECT '## policies';
SELECT format('%s.%s | %s | %s | %s | USING (%s) | CHECK (%s)', schemaname, tablename, policyname,
              cmd, array_to_string(roles, ','), qual, with_check)
FROM pg_policies WHERE schemaname IN ('public', 'storage') ORDER BY schemaname, tablename, policyname;

SELECT '## columns';
SELECT format('%s.%s | %s | %s | null=%s | default=%s', table_schema, table_name, column_name,
              data_type, is_nullable, column_default)
FROM information_schema.columns WHERE table_schema = 'public' ORDER BY table_name, ordinal_position;

SELECT '## buckets';
SELECT format('%s | public=%s | limit=%s', id, public, file_size_limit) FROM storage.buckets ORDER BY id;
