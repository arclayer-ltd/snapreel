-- The daily cron clears old rate-limit windows. private.rate_limits isn't exposed through the Data API, so the
-- API calls this helper instead (service_role only).
create or replace function public.prune_rate_limits(p_before timestamptz)
returns integer
language sql
set search_path = ''
as $$
  with gone as (delete from private.rate_limits r where r.window_start < p_before returning 1)
  select count(*)::integer from gone;
$$;
revoke execute on function public.prune_rate_limits(timestamptz) from public, anon, authenticated;
grant execute on function public.prune_rate_limits(timestamptz) to service_role;
