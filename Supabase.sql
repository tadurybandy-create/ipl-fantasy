-- IPL 2026 Fantasy League — Supabase Table Setup
-- Run this entire script in Supabase SQL Editor

-- 1. Participants
create table if not exists participants (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  win_pick text,
  created_at timestamptz default now()
);

-- 2. Picks (one row per player pick; is_active=false means swapped out)
create table if not exists picks (
  id uuid primary key default gen_random_uuid(),
  participant_id uuid references participants(id) on delete cascade,
  team_key text not null,
  player_name text not null,
  is_active boolean default true,
  swapped_at timestamptz,
  created_at timestamptz default now()
);

-- 3. Season scores (one row per player, cumulative totals)
create table if not exists season_scores (
  player_name text primary key,
  runs integer default 0,
  wickets integer default 0,
  catches integer default 0
);

-- 4. Match history
create table if not exists match_history (
  id uuid primary key default gen_random_uuid(),
  title text,
  match_date text,
  result text,
  t1_name text,
  t2_name text,
  updates jsonb default '[]',
  created_at timestamptz default now()
);

-- 5. Swap history log
create table if not exists swap_history (
  id uuid primary key default gen_random_uuid(),
  participant_id uuid references participants(id) on delete cascade,
  participant_name text,
  team_key text,
  team_name text,
  old_player text,
  new_player text,
  frozen_pts integer default 0,
  swap_date text,
  created_at timestamptz default now()
);

-- 6. Global settings (IPL winner etc.)
create table if not exists settings (
  id text primary key default 'global',
  ipl_winner text
);

insert into settings (id) values ('global') on conflict do nothing;

-- 7. Enable Row Level Security but allow public access (anon key)
alter table participants enable row level security;
alter table picks enable row level security;
alter table season_scores enable row level security;
alter table match_history enable row level security;
alter table swap_history enable row level security;
alter table settings enable row level security;

create policy "public read" on participants for select using (true);
create policy "public write" on participants for insert with check (true);
create policy "public update" on participants for update using (true);
create policy "public delete" on participants for delete using (true);

create policy "public read" on picks for select using (true);
create policy "public write" on picks for insert with check (true);
create policy "public update" on picks for update using (true);
create policy "public delete" on picks for delete using (true);

create policy "public read" on season_scores for select using (true);
create policy "public write" on season_scores for insert with check (true);
create policy "public update" on season_scores for update using (true);
create policy "public delete" on season_scores for delete using (true);

create policy "public read" on match_history for select using (true);
create policy "public write" on match_history for insert with check (true);
create policy "public update" on match_history for update using (true);
create policy "public delete" on match_history for delete using (true);

create policy "public read" on swap_history for select using (true);
create policy "public write" on swap_history for insert with check (true);
create policy "public update" on swap_history for update using (true);
create policy "public delete" on swap_history for delete using (true);

create policy "public read" on settings for select using (true);
create policy "public write" on settings for insert with check (true);
create policy "public update" on settings for update using (true);



select * from participants


alter table season_scores add column if not exists runouts integer default 0;



truncate table match_history cascade;
truncate table season_scores cascade;
truncate table swap_history cascade;
truncate table picks cascade;
truncate table participants cascade;
truncate table settings cascade;

-- Re-insert the default settings row
insert into settings (id) values ('global') on conflict do nothing;

alter table season_scores add column if not exists stumpings integer default 0;