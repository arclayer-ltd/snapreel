-- Row-level security checks for Snapreel Pro. Run in the SQL editor, with psql, or through the Supabase MCP
-- (execute_sql). It seeds two users (A and B) with a video each plus activity, then runs every check under the
-- real roles (set local role anon/authenticated/service_role with request.jwt.claims), exactly as PostgREST does.
--
-- The block ALWAYS ends by raising an exception, so everything it seeds is rolled back. The PASS/FAIL report is
-- the exception message; it starts with "RLS CHECKS: n passed, m failed".
do $$
declare
  a uuid := '0a0a0a0a-0000-4000-8000-00000000000a';
  b uuid := '0b0b0b0b-0000-4000-8000-00000000000b';
  va uuid; vb uuid; ca uuid; cb uuid; da text := repeat('a1', 32); db text := repeat('b2', 32);
  r record;
  q text;
  got text;
  ok boolean;
  passed int := 0;
  failed int := 0;
  report text := '';
begin
  -- Seed as the migration owner (bypasses RLS).
  insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
    (a, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'rls-a@example.invalid', '{"full_name":"Alice Test"}', now(), now()),
    (b, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'rls-b@example.invalid', '{}', now(), now());
  insert into public.videos (owner_id, slug, local_id, title, kind, duration_s) values (a, 'AAAAAAAAAA', gen_random_uuid(), 'A video', 'screen', 30) returning id into va;
  insert into public.videos (owner_id, slug, local_id, title, kind, duration_s) values (b, 'BBBBBBBBBB', gen_random_uuid(), 'B video', 'camera', 30) returning id into vb;
  insert into public.comments (video_id, session_id, author_name, body) values (va, 's1', 'Viewer', 'On A') returning id into ca;
  insert into public.comments (video_id, session_id, author_name, body) values (vb, 's1', 'Viewer', 'On B') returning id into cb;
  insert into public.views (video_id, session_id) values (va, 's1'), (vb, 's1');
  insert into public.reactions (video_id, session_id, emoji, at_s) values (va, 's1', '👍', 1), (vb, 's1', '👍', 1);
  insert into public.devices (token, user_id) values (da, a), (db, b);
  insert into public.subscriptions (user_id, product_id, original_transaction_id, status, expires_at, environment)
    values (b, 'co.arclayer.snapreel.pro.monthly', 'rls-test-otid', 'active', now() + interval '30 days', 'Sandbox');
  insert into public.reports (video_id, reason, details, email) values (va, 'spam', 'test', 'reporter@example.invalid');
  insert into public.notification_log (user_id, kind, video_id, dedupe_key) values (b, 'view', vb, 'rls-test-dedupe');
  insert into public.blocks (owner_id, session_id) values (b, 's9');
  insert into storage.objects (bucket_id, name) values ('videos', a::text || '/' || va::text || '/video.mp4'), ('videos', b::text || '/' || vb::text || '/video.mp4');

  for r in
    select * from (values
      -- anon: nothing at all
      ('anon reads profiles',            'anon', null::uuid, 'select count(*) from public.profiles', 'denied'),
      ('anon reads videos',              'anon', null, 'select count(*) from public.videos', 'denied'),
      ('anon reads views',               'anon', null, 'select count(*) from public.views', 'denied'),
      ('anon reads comments',            'anon', null, 'select count(*) from public.comments', 'denied'),
      ('anon reads reactions',           'anon', null, 'select count(*) from public.reactions', 'denied'),
      ('anon reads subscriptions',       'anon', null, 'select count(*) from public.subscriptions', 'denied'),
      ('anon reads reports',             'anon', null, 'select count(*) from public.reports', 'denied'),
      ('anon reads devices',             'anon', null, 'select count(*) from public.devices', 'denied'),
      ('anon reads blocks',              'anon', null, 'select count(*) from public.blocks', 'denied'),
      ('anon reads notification_log',    'anon', null, 'select count(*) from public.notification_log', 'denied'),
      ('anon reads private.rate_limits', 'anon', null, 'select count(*) from private.rate_limits', 'denied'),
      ('anon inserts a video',           'anon', null, 'insert into public.videos (owner_id, slug, local_id, kind, duration_s) values (:a, ''XXXXXXXXXX'', gen_random_uuid(), ''screen'', 1) returning 1', 'denied'),
      ('anon inserts a comment',         'anon', null, 'insert into public.comments (video_id, session_id, author_name, body) values (:va, ''x'', ''x'', ''x'') returning 1', 'denied'),
      ('anon calls is_pro',              'anon', null, 'select public.is_pro(:b)::text', 'denied'),
      ('anon calls active_link_count',   'anon', null, 'select public.active_link_count(:a)', 'denied'),
      ('anon calls rate_limit_hit',      'anon', null, 'select public.rate_limit_hit(''x'', 60, 5)::text', 'denied'),
      ('anon calls video_stats',         'anon', null, 'select count(*) from public.video_stats(array[:va]::uuid[])', 'denied'),
      ('anon calls rls_auto_enable',     'anon', null, 'select public.rls_auto_enable()::text', 'denied'),
      ('anon lists video files',         'anon', null, 'select count(*) from storage.objects where bucket_id = ''videos''', '0'),
      -- user A: own rows only
      ('A sees only own videos',         'authenticated', a, 'select count(*) from public.videos', '1'),
      ('A reads B''s video',             'authenticated', a, 'select count(*) from public.videos where id = :vb', '0'),
      ('A renames B''s video',           'authenticated', a, 'with u as (update public.videos set title = ''pwn'' where id = :vb returning 1) select count(*) from u', '0'),
      ('A deletes B''s video',           'authenticated', a, 'with d as (delete from public.videos where id = :vb returning 1) select count(*) from d', '0'),
      ('A renames own video',            'authenticated', a, 'with u as (update public.videos set title = ''Mine'' where id = :va returning 1) select count(*) from u', '1'),
      ('A sets own password directly',   'authenticated', a, 'with u as (update public.videos set password_hash = ''x'' where id = :va returning 1) select count(*) from u', 'denied'),
      ('A turns on downloads directly',  'authenticated', a, 'with u as (update public.videos set allow_download = true where id = :va returning 1) select count(*) from u', 'denied'),
      ('A marks own video ready directly','authenticated', a, 'with u as (update public.videos set status = ''ready'' where id = :va returning 1) select count(*) from u', 'denied'),
      ('A inserts a video directly',     'authenticated', a, 'insert into public.videos (owner_id, slug, local_id, kind, duration_s) values (:a, ''XXXXXXXXXX'', gen_random_uuid(), ''screen'', 1) returning 1', 'denied'),
      ('A sees comments on own videos',  'authenticated', a, 'select count(*) from public.comments', '1'),
      ('A reads B''s comment',           'authenticated', a, 'select count(*) from public.comments where id = :cb', '0'),
      ('A hides B''s comment',           'authenticated', a, 'with u as (update public.comments set deleted_at = now() where id = :cb returning 1) select count(*) from u', '0'),
      ('A hides comment on own video',   'authenticated', a, 'with u as (update public.comments set deleted_at = now() where id = :ca returning 1) select count(*) from u', '1'),
      ('A edits a comment body',         'authenticated', a, 'with u as (update public.comments set body = ''x'' where id = :ca returning 1) select count(*) from u', 'denied'),
      ('A posts a comment directly',     'authenticated', a, 'insert into public.comments (video_id, session_id, author_name, body) values (:va, ''x'', ''x'', ''x'') returning 1', 'denied'),
      ('A sees views on own videos',     'authenticated', a, 'select count(*) from public.views', '1'),
      ('A deletes views on B''s video',  'authenticated', a, 'with d as (delete from public.views where video_id = :vb returning 1) select count(*) from d', '0'),
      ('A sees reactions on own videos', 'authenticated', a, 'select count(*) from public.reactions', '1'),
      ('A sees only own profile',        'authenticated', a, 'select count(*) from public.profiles', '1'),
      ('A''s profile name from Apple',   'authenticated', a, 'select display_name from public.profiles where id = :a', 'Alice Test'),
      ('A renames B''s profile',         'authenticated', a, 'with u as (update public.profiles set display_name = ''pwn'' where id = :b returning 1) select count(*) from u', '0'),
      ('A sets own brand colour directly','authenticated', a, 'with u as (update public.profiles set brand_color = ''#000000'' where id = :a returning 1) select count(*) from u', 'denied'),
      ('A turns off own email alerts',   'authenticated', a, 'with u as (update public.profiles set email_alerts = false where id = :a returning 1) select count(*) from u', '1'),
      ('A reads subscriptions',          'authenticated', a, 'select count(*) from public.subscriptions', '0'),
      ('A grants itself Pro',            'authenticated', a, 'insert into public.subscriptions (user_id, product_id, original_transaction_id, status, environment) values (:a, ''p'', ''x'', ''active'', ''Sandbox'') returning 1', 'denied'),
      ('A reads reports',                'authenticated', a, 'select count(*) from public.reports', 'denied'),
      ('A sees only own devices',        'authenticated', a, 'select count(*) from public.devices', '1'),
      ('A deletes B''s device',          'authenticated', a, 'with d as (delete from public.devices where user_id = :b returning 1) select count(*) from d', '0'),
      ('A sees B''s blocks',             'authenticated', a, 'select count(*) from public.blocks', '0'),
      ('A sees B''s notification log',   'authenticated', a, 'select count(*) from public.notification_log', '0'),
      ('A reads rate limits',            'authenticated', a, 'select count(*) from private.rate_limits', 'denied'),
      ('A calls is_pro',                 'authenticated', a, 'select public.is_pro(:a)::text', 'denied'),
      ('A calls rate_limit_hit',         'authenticated', a, 'select public.rate_limit_hit(''x'', 60, 5)::text', 'denied'),
      ('A calls record_view',            'authenticated', a, 'select count(*) from public.record_view(:vb, ''s'', ''start'', null, null, null, null, null, null, 0, array[0], 30)', 'denied'),
      ('A lists own files only',         'authenticated', a, 'select count(*) from storage.objects where bucket_id = ''videos''', '1'),
      ('A uploads into B''s folder',     'authenticated', a, 'insert into storage.objects (bucket_id, name) values (''videos'', :b_text || ''/x/video.mp4'') returning 1', 'denied'),
      ('A uploads into own folder',      'authenticated', a, 'with i as (insert into storage.objects (bucket_id, name) values (''videos'', :a_text || ''/x/poster.jpg'') returning 1) select count(*) from i', '1'),
      ('A overwrites B''s file',         'authenticated', a, 'with u as (update storage.objects set metadata = ''{}'' where name like :b_text || ''/%'' returning 1) select count(*) from u', '0'),
      -- user B: the mirror image
      ('B sees only own videos',         'authenticated', b, 'select count(*) from public.videos where id = :va', '0'),
      ('B reads own subscription',       'authenticated', b, 'select count(*) from public.subscriptions', '1'),
      ('B sees views on A''s video',     'authenticated', b, 'select count(*) from public.views where video_id = :va', '0'),
      ('B sees A''s comment',            'authenticated', b, 'select count(*) from public.comments where id = :ca', '0'),
      -- service_role: the API's key bypasses RLS and may call the helpers
      ('server sees every video',        'service_role', null, 'select count(*) from public.videos', '2'),
      ('server: B is Pro',               'service_role', null, 'select public.is_pro(:b)::text', 'true'),
      ('server: A is Free',              'service_role', null, 'select public.is_pro(:a)::text', 'false'),
      ('server: A has 1 active link',    'service_role', null, 'select public.active_link_count(:a)', '1'),
      ('server: rate limit 1 of 2',      'service_role', null, 'select public.rate_limit_hit(''rls-test'', 60, 2)::text', 'true'),
      ('server: rate limit 2 of 2',      'service_role', null, 'select public.rate_limit_hit(''rls-test'', 60, 2)::text', 'true'),
      ('server: rate limit 3 of 2',      'service_role', null, 'select public.rate_limit_hit(''rls-test'', 60, 2)::text', 'false'),
      ('server: short watch not counted','service_role', null, 'select (counted)::text from public.record_view(:va, ''v1'', ''start'', null, null, null, ''GB'', ''phone'', ''example.com'', 1, array[0,1,2], 30)', 'false'),
      ('server: reaching the end counts','service_role', null, 'select (counted and newly_counted and first_for_session)::text from public.record_view(:va, ''v1'', ''end'', null, null, null, null, null, null, 29.5, array[97,98,99], 30)', 'true'),
      ('server: same session, one row',  'service_role', null, 'select count(*) from public.views where session_id = ''v1''', '1'),
      ('server: stats count the view',   'service_role', null, 'select views || ''/'' || unique_viewers || ''/'' || comment_count from public.video_stats(array[:va]::uuid[])', '1/1/0')
    ) as t (name, role, sub, sql, expect)
  loop
    q := replace(replace(replace(replace(replace(replace(replace(replace(r.sql,
           ':a_text', quote_literal(a::text)), ':b_text', quote_literal(b::text)),
           ':va', quote_literal(va)), ':vb', quote_literal(vb)),
           ':ca', quote_literal(ca)), ':cb', quote_literal(cb)),
           ':a', quote_literal(a)), ':b', quote_literal(b));
    begin
      perform set_config('request.jwt.claims',
        coalesce(json_build_object('sub', r.sub, 'role', r.role)::text, '{}'), true);
      perform set_config('request.jwt.claim.sub', coalesce(r.sub::text, ''), true);
      execute format('set local role %I', r.role);
      execute q into got;
      execute 'reset role';
      ok := coalesce(got, 'null') = r.expect;
    exception
      when insufficient_privilege then
        got := 'denied';
        ok := r.expect = 'denied';
      when others then
        got := sqlstate || ' ' || sqlerrm;
        ok := false;
    end;
    if ok then passed := passed + 1; else failed := failed + 1; end if;
    report := report || format(E'\n%s  %s (got %s, want %s)', case when ok then 'PASS' else 'FAIL' end, r.name, got, r.expect);
  end loop;

  raise exception 'RLS CHECKS: % passed, % failed (all seed data rolled back)%', passed, failed, report;
end;
$$;
