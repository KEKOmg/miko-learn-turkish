-- Minimal cross-device course restoration. Only completed lesson identities
-- and the already-used best-accuracy display value are synchronized. Unlock
-- state remains derived by the app from the ordered completed lesson keys.

create table if not exists public.user_lesson_progress (
    user_id uuid not null references public.profiles(id) on delete cascade,
    lesson_key text not null,
    best_accuracy double precision not null default 0,
    completed_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    primary key (user_id, lesson_key),
    constraint user_lesson_progress_lesson_key_check
        check (lesson_key ~ '^[a-z0-9]+([._-][a-z0-9]+)*$' and length(lesson_key) <= 120),
    constraint user_lesson_progress_best_accuracy_check
        check (best_accuracy >= 0 and best_accuracy <= 1)
);

create index if not exists user_lesson_progress_user_updated_idx
    on public.user_lesson_progress (user_id, updated_at desc);

alter table public.user_lesson_progress enable row level security;

drop policy if exists "lesson progress select own" on public.user_lesson_progress;
create policy "lesson progress select own"
    on public.user_lesson_progress
    for select
    to authenticated
    using ((select auth.uid()) = user_id);

drop policy if exists "lesson progress insert own" on public.user_lesson_progress;
create policy "lesson progress insert own"
    on public.user_lesson_progress
    for insert
    to authenticated
    with check ((select auth.uid()) = user_id);

drop policy if exists "lesson progress update own" on public.user_lesson_progress;
create policy "lesson progress update own"
    on public.user_lesson_progress
    for update
    to authenticated
    using ((select auth.uid()) = user_id)
    with check ((select auth.uid()) = user_id);

-- A client may improve its own accuracy/timestamp, but an UPDATE cannot move
-- or erase a completion identity and an old client cannot lower best accuracy.
create or replace function public.preserve_completed_lesson_progress()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    if new.user_id <> old.user_id or new.lesson_key <> old.lesson_key then
        raise exception 'completed lesson identity is immutable' using errcode = '42501';
    end if;
    new.best_accuracy := greatest(old.best_accuracy, new.best_accuracy);
    new.completed_at := greatest(old.completed_at, new.completed_at);
    new.updated_at := now();
    return new;
end;
$$;

drop trigger if exists preserve_completed_lesson_progress
    on public.user_lesson_progress;
create trigger preserve_completed_lesson_progress
before update on public.user_lesson_progress
for each row execute function public.preserve_completed_lesson_progress();

-- Atomic monotonic batch upsert. The caller never supplies a user UUID;
-- ownership is always derived from auth.uid().
create or replace function public.sync_my_lesson_progress(p_rows jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_user_id uuid := auth.uid();
    v_row jsonb;
    v_lesson_key text;
    v_best_accuracy double precision;
    v_completed_at timestamptz;
begin
    if v_user_id is null then
        raise exception 'authentication required' using errcode = '42501';
    end if;
    if p_rows is null or jsonb_typeof(p_rows) <> 'array' then
        raise exception 'p_rows must be a JSON array' using errcode = '22023';
    end if;

    for v_row in select value from jsonb_array_elements(p_rows)
    loop
        v_lesson_key := btrim(coalesce(v_row ->> 'lesson_key', ''));
        v_best_accuracy := coalesce((v_row ->> 'best_accuracy')::double precision, 0);
        v_completed_at := coalesce((v_row ->> 'completed_at')::timestamptz, now());

        if v_lesson_key !~ '^[a-z0-9]+([._-][a-z0-9]+)*$'
            or length(v_lesson_key) > 120 then
            raise exception 'invalid lesson_key' using errcode = '22023';
        end if;
        if v_best_accuracy < 0 or v_best_accuracy > 1 then
            raise exception 'best_accuracy must be between 0 and 1' using errcode = '22023';
        end if;

        insert into public.user_lesson_progress (
            user_id,
            lesson_key,
            best_accuracy,
            completed_at,
            updated_at
        ) values (
            v_user_id,
            v_lesson_key,
            v_best_accuracy,
            v_completed_at,
            now()
        )
        on conflict (user_id, lesson_key) do update
        set best_accuracy = greatest(
                public.user_lesson_progress.best_accuracy,
                excluded.best_accuracy
            ),
            completed_at = greatest(
                public.user_lesson_progress.completed_at,
                excluded.completed_at
            ),
            updated_at = now();
    end loop;
end;
$$;

revoke all on table public.user_lesson_progress from public, anon, authenticated;
grant select, insert, update on table public.user_lesson_progress to authenticated;

revoke all on function public.preserve_completed_lesson_progress() from public, anon, authenticated;
revoke all on function public.sync_my_lesson_progress(jsonb) from public, anon, authenticated;
grant execute on function public.sync_my_lesson_progress(jsonb) to authenticated;
