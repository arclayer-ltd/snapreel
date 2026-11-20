-- Fixes from the first Supabase advisor run (20 November 2026).

-- The project's "Enable RLS on new tables automatically" option installs public.rls_auto_enable(), an event-trigger
-- function that is SECURITY DEFINER and executable by everyone through /rest/v1/rpc. Event triggers don't need the
-- EXECUTE grant to fire, so only the owner keeps it.
revoke execute on function public.rls_auto_enable() from public, anon, authenticated;

-- Server-only tables: say so explicitly instead of leaving RLS on with no policy. Neither role has a table grant
-- either, so these policies only document the intent.
create policy "reports: server only" on public.reports
  for select to authenticated using (false);
create policy "rate_limits: server only" on private.rate_limits
  for select to authenticated using (false);
