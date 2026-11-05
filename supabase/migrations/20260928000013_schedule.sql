-- Hati — the daily job (spec §7.1).
--
-- 06:00 Asia/Manila is 22:00 UTC the previous day, which is the schedule the
-- spec gives. Today the job sends reminders; M9 adds recurring-bill
-- generation to the same function, so there stays one daily job rather than
-- two that can drift apart.
--
-- Guarded twice over: pg_cron is a Supabase fixture that the local test
-- harness does not have, and enabling an extension can be refused. Neither
-- should stop the rest of the migration.

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    execute 'create extension if not exists pg_cron';
  else
    raise notice 'pg_cron is unavailable here; skipping (local harness)';
  end if;
exception when others then
  raise notice 'could not enable pg_cron: %', sqlerrm;
end;
$$;

do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice 'pg_cron not installed; schedule hati-daily by hand';
    return;
  end if;

  -- Re-running the migration re-points the job rather than adding a second.
  if exists (select 1 from cron.job where jobname = 'hati-daily') then
    perform cron.unschedule('hati-daily');
  end if;

  perform cron.schedule(
    'hati-daily',
    '0 22 * * *',
    'select public.run_daily_jobs()'
  );

  raise notice 'scheduled hati-daily at 22:00 UTC (06:00 Asia/Manila)';
exception when others then
  raise notice 'could not schedule hati-daily: %', sqlerrm;
end;
$$;
