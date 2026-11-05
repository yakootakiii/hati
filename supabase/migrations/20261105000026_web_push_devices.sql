-- Hati — web browsers as push devices (DECISIONS D-72).
--
-- The web app registers its FCM token like a phone does, as platform 'web'.

alter table public.device_tokens
  drop constraint device_tokens_platform_check,
  add constraint device_tokens_platform_check
    check (platform in ('ios', 'android', 'web'));
