-- Weekly league seasons for Miko.
-- Lifetime XP remains in public.profiles.xp. Only league_entries.weekly_xp
-- resets when a new UTC week starts.

create table if not exists public.league_seasons (
    id uuid primary key default gen_random_uuid(),
    starts_at timestamptz not null unique,
    ends_at timestamptz not null,
    status text not null default 'active'
        check (status in ('active', 'finalized')),
    finalized_at timestamptz,
    created_at timestamptz not null default now(),
    check (ends_at > starts_at)
);

create unique index if not exists league_seasons_one_active
on public.league_seasons (status)
where status = 'active';

create table if not exists public.league_entries (
    season_id uuid not null references public.league_seasons(id) on delete cascade,
    user_id uuid not null references public.profiles(id) on delete cascade,
    league_key text not null default 'bronze'
        check (league_key in (
            'bronze', 'silver', 'gold', 'turquoise',
            'sapphire', 'ruby', 'obsidian'
        )),
    group_number integer not null default 1 check (group_number > 0),
    weekly_xp integer not null default 0 check (weekly_xp >= 0),
    final_rank integer check (final_rank is null or final_rank > 0),
    outcome text check (outcome is null or outcome in (
        'promoted', 'stayed', 'demoted', 'champion'
    )),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    primary key (season_id, user_id)
);

create index if not exists league_entries_board
on public.league_entries (
    season_id, league_key, group_number,
    weekly_xp desc, updated_at asc, user_id asc
);

alter table public.league_seasons enable row level security;
alter table public.league_entries enable row level security;

revoke all on table public.league_seasons from anon, authenticated;
revoke all on table public.league_entries from anon, authenticated;

-- From this migration onward profile counters and weekly XP must move through
-- one atomic RPC. Leaving the old direct profile UPDATE privilege enabled
-- would let a stale client lower profiles.xp; a later sync would then credit
-- that already-earned difference to the league for a second time.
revoke all on table public.profiles from anon, authenticated;
grant select on table public.profiles to authenticated;

-- League movement helpers. New users begin in Bronze. Existing profiles are
-- backfilled into Turquoise below so the currently shipped league keeps its
-- identity when this migration is first enabled.
create or replace function public.promoted_league(current_league text)
returns text
language sql
immutable
set search_path = ''
as $$
    select case current_league
        when 'bronze' then 'silver'
        when 'silver' then 'gold'
        when 'gold' then 'turquoise'
        when 'turquoise' then 'sapphire'
        when 'sapphire' then 'ruby'
        when 'ruby' then 'obsidian'
        else 'obsidian'
    end
$$;

create or replace function public.demoted_league(current_league text)
returns text
language sql
immutable
set search_path = ''
as $$
    select case current_league
        when 'obsidian' then 'ruby'
        when 'ruby' then 'sapphire'
        when 'sapphire' then 'turquoise'
        when 'turquoise' then 'gold'
        when 'gold' then 'silver'
        else 'bronze'
    end
$$;

-- Finalizes every expired season and creates the current UTC-week season.
-- It is safe to call on every sync/fetch; the unique constraints make it
-- idempotent. Groups smaller than 10 have no demotion zone.
create or replace function public.rollover_league_seasons()
returns uuid
language plpgsql
security definer
set search_path = 'public', 'pg_temp'
as $$
declare
    expired record;
    current_start timestamptz := date_trunc('week', now() at time zone 'UTC') at time zone 'UTC';
    current_id uuid;
begin
    perform pg_advisory_xact_lock(hashtext('miko.league.rollover'));

    for expired in
        select id
        from public.league_seasons
        where status = 'active' and ends_at <= now()
        for update
    loop
        with ranked as (
            select
                season_id,
                user_id,
                league_key,
                row_number() over (
                    partition by season_id, league_key, group_number
                    order by weekly_xp desc, updated_at asc, user_id asc
                )::integer as position,
                count(*) over (
                    partition by season_id, league_key, group_number
                )::integer as participant_count
            from public.league_entries
            where season_id = expired.id
        )
        update public.league_entries entry
        set
            final_rank = ranked.position,
            outcome = case
                when ranked.position <= least(5, ranked.participant_count)
                    and ranked.league_key = 'obsidian' then 'champion'
                when ranked.position <= least(5, ranked.participant_count)
                    then 'promoted'
                when ranked.participant_count >= 10
                    and ranked.position >= ranked.participant_count - 2
                    and ranked.league_key <> 'bronze' then 'demoted'
                else 'stayed'
            end,
            updated_at = now()
        from ranked
        where entry.season_id = ranked.season_id
          and entry.user_id = ranked.user_id;

        update public.league_seasons
        set status = 'finalized', finalized_at = now()
        where id = expired.id;
    end loop;

    insert into public.league_seasons (starts_at, ends_at, status)
    values (current_start, current_start + interval '7 days', 'active')
    on conflict (starts_at) do update
        set ends_at = excluded.ends_at
    returning id into current_id;

    -- Carry players from their latest finalized season into the new one.
    with latest as (
        select distinct on (entry.user_id)
            entry.user_id,
            case entry.outcome
                when 'promoted' then public.promoted_league(entry.league_key)
                when 'demoted' then public.demoted_league(entry.league_key)
                else entry.league_key
            end as next_league
        from public.league_entries entry
        join public.league_seasons season on season.id = entry.season_id
        where season.status = 'finalized'
        order by entry.user_id, season.ends_at desc
    ), grouped as (
        select
            user_id,
            next_league,
            ((row_number() over (
                partition by next_league order by user_id
            ) - 1) / 20 + 1)::integer as next_group
        from latest
    )
    insert into public.league_entries (
        season_id, user_id, league_key, group_number, weekly_xp
    )
    select current_id, user_id, next_league, next_group, 0
    from grouped
    on conflict (season_id, user_id) do nothing;

    return current_id;
end;
$$;

-- Ensures the signed-in user has an entry in the active season.
create or replace function public.ensure_my_league_entry()
returns public.league_entries
language plpgsql
security definer
set search_path = 'public', 'pg_temp'
as $$
declare
    uid uuid := auth.uid();
    active_id uuid;
    selected_league text := 'bronze';
    selected_group integer;
    result public.league_entries;
begin
    if uid is null then
        raise exception 'Authentication required' using errcode = '42501';
    end if;

    active_id := public.rollover_league_seasons();

    select * into result
    from public.league_entries
    where season_id = active_id and user_id = uid;
    if found then return result; end if;

    perform pg_advisory_xact_lock(hashtext('miko.league.assign.' || selected_league));
    select (count(*) / 20 + 1)::integer into selected_group
    from public.league_entries
    where season_id = active_id and league_key = selected_league;

    insert into public.league_entries (
        season_id, user_id, league_key, group_number, weekly_xp
    ) values (active_id, uid, selected_league, selected_group, 0)
    returning * into result;
    return result;
end;
$$;

-- Replaces the old direct profile upsert. The positive delta between the
-- device's lifetime XP and the last cloud total is credited to this week.
create or replace function public.sync_progress_and_league(
    p_username text,
    p_xp integer,
    p_streak_days integer,
    p_lessons_completed integer
)
returns void
language plpgsql
security definer
set search_path = 'public', 'pg_temp'
as $$
declare
    uid uuid := auth.uid();
    previous_xp integer := 0;
    xp_delta integer := 0;
    membership public.league_entries;
begin
    if uid is null then
        raise exception 'Authentication required' using errcode = '42501';
    end if;

    -- Serialize by user even when the profile row does not exist yet. A row
    -- lock alone cannot protect that first sync, so two concurrent requests
    -- could otherwise both observe previous_xp = 0 and credit the same XP.
    perform pg_advisory_xact_lock(hashtext('miko.league.sync.' || uid::text));

    select xp into previous_xp
    from public.profiles
    where id = uid
    for update;
    previous_xp := coalesce(previous_xp, 0);
    xp_delta := greatest(coalesce(p_xp, 0) - previous_xp, 0);

    insert into public.profiles (
        id, username, xp, streak_days, lessons_completed, updated_at
    ) values (
        uid,
        left(coalesce(nullif(trim(p_username), ''), 'Ученик'), 30),
        greatest(coalesce(p_xp, 0), 0),
        greatest(coalesce(p_streak_days, 0), 0),
        greatest(coalesce(p_lessons_completed, 0), 0),
        now()
    )
    on conflict (id) do update set
        username = excluded.username,
        xp = greatest(public.profiles.xp, excluded.xp),
        streak_days = greatest(public.profiles.streak_days, excluded.streak_days),
        lessons_completed = greatest(public.profiles.lessons_completed, excluded.lessons_completed),
        updated_at = now();

    membership := public.ensure_my_league_entry();
    update public.league_entries
    set
        weekly_xp = weekly_xp + xp_delta,
        -- `updated_at` is the tie-break timestamp for equal weekly scores.
        -- A metadata-only/idempotent sync must not move the player backwards.
        updated_at = case when xp_delta > 0 then now() else updated_at end
    where season_id = membership.season_id and user_id = uid;
end;
$$;

-- Returns only the caller's 20-person group plus season metadata.
create or replace function public.get_my_leaderboard()
returns table (
    id uuid,
    username text,
    weekly_xp integer,
    streak_days integer,
    league_key text,
    group_number integer,
    "position" integer,
    season_starts_at timestamptz,
    season_ends_at timestamptz,
    promotion_count integer,
    demotion_start integer
)
language plpgsql
security definer
set search_path = 'public', 'pg_temp'
as $$
declare
    membership public.league_entries;
begin
    membership := public.ensure_my_league_entry();

    return query
    with board as (
        select
            entry.user_id,
            profile.username,
            entry.weekly_xp,
            profile.streak_days,
            entry.league_key,
            entry.group_number,
            row_number() over (
                order by entry.weekly_xp desc, entry.updated_at asc, entry.user_id asc
            )::integer as board_position,
            count(*) over ()::integer as participant_count
        from public.league_entries entry
        join public.profiles profile on profile.id = entry.user_id
        where entry.season_id = membership.season_id
          and entry.league_key = membership.league_key
          and entry.group_number = membership.group_number
    )
    select
        board.user_id,
        board.username,
        board.weekly_xp,
        board.streak_days,
        board.league_key,
        board.group_number,
        board.board_position,
        season.starts_at,
        season.ends_at,
        least(5, board.participant_count),
        case when board.league_key <> 'bronze' and board.participant_count >= 10
            then board.participant_count - 2
            else null
        end
    from board
    join public.league_seasons season on season.id = membership.season_id
    order by board.board_position;
end;
$$;

revoke all on function public.rollover_league_seasons() from public, anon, authenticated;
revoke all on function public.ensure_my_league_entry() from public, anon, authenticated;
revoke all on function public.sync_progress_and_league(text, integer, integer, integer) from public, anon, authenticated;
revoke all on function public.get_my_leaderboard() from public, anon, authenticated;

grant execute on function public.sync_progress_and_league(text, integer, integer, integer) to authenticated;
grant execute on function public.get_my_leaderboard() to authenticated;

-- Initialize this week's season and keep already registered players in the
-- Turquoise league for the first rollout.
do $$
declare
    active_id uuid;
begin
    active_id := public.rollover_league_seasons();
    insert into public.league_entries (
        season_id, user_id, league_key, group_number, weekly_xp
    )
    select
        active_id,
        profile.id,
        'turquoise',
        ((row_number() over (order by profile.id) - 1) / 20 + 1)::integer,
        0
    from public.profiles profile
    on conflict (season_id, user_id) do nothing;
end;
$$;
