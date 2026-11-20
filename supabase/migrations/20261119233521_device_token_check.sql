-- Postgres regular expressions allow repeat counts up to 255, so the original devices.token check
-- ('^[0-9a-f]{32,400}$') failed on every insert. Check the alphabet and the length separately.
alter table public.devices drop constraint devices_token_check;
alter table public.devices add constraint devices_token_check
  check (token ~ '^[0-9a-f]+$' and char_length(token) between 32 and 400);
