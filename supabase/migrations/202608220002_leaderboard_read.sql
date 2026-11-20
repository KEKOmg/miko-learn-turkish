-- Leaderboard support: signed-in users may read every profile so the app can
-- rank players by XP. Writes remain limited to the owner via the policies from
-- 202608220001_create_profiles.sql.

drop policy if exists "Users can read their own profile" on public.profiles;

create policy "Authenticated users can read all profiles"
on public.profiles for select
to authenticated
using (true);
