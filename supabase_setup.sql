-- ============================================================
-- Cricket Fantasy App — Complete Supabase Setup
-- ============================================================
-- Run this ENTIRE file in Supabase SQL Editor (fresh install)
-- Dashboard → SQL Editor → New Query → Paste → Run
--
-- For upgrades from an older version, individual migration
-- blocks are safe to re-run (all use IF NOT EXISTS / ON CONFLICT)
--
-- TABLE OF CONTENTS
--   1.  Core tables
--   2.  Auth & access tables (allowlist, draft_state)
--   3.  Indexes
--   4.  Default rows
--   5.  Row Level Security (RLS)
--   6.  Troubleshooting queries
-- ============================================================


-- ============================================================
-- SECTION 1 — CORE TABLES
-- ============================================================

-- 1a. Participants — one row per fantasy league member
create table if not exists participants (
  id         uuid      primary key default gen_random_uuid(),
  name       text      not null unique,
  team_pick  text,                          -- IPL team drafted for win points (e.g. 'MI', 'CSK')
  mode       text      not null default 'ipl',
  created_at timestamptz default now()
);

-- 1b. Picks — one row per draft pick (is_active=false = swapped out)
create table if not exists picks (
  id             uuid    primary key default gen_random_uuid(),
  participant_id uuid    references participants(id) on delete cascade,
  team_key       text    not null,
  player_name    text    not null,
  is_active      boolean default true,
  swapped_at     timestamptz,
  mode           text    not null default 'ipl',
  created_at     timestamptz default now()
);

-- 1c. Season scores — cumulative totals per player per mode
create table if not exists season_scores (
  player_name text    not null,
  runs        integer not null default 0,
  wickets     integer not null default 0,
  catches     integer not null default 0,
  runouts     integer not null default 0,
  stumpings   integer not null default 0,
  motm        integer not null default 0,   -- Man of the Match count
  mode        text    not null default 'ipl',
  primary key (player_name, mode)
);

-- 1d. Match history — one row per scored match
create table if not exists match_history (
  id         uuid    primary key default gen_random_uuid(),
  title      text,
  match_date text,
  result     text,
  t1_name    text,
  t2_name    text,
  updates    jsonb   default '[]',           -- array of {player, runs, wickets, catches...}
  mode       text    not null default 'ipl',
  created_at timestamptz default now()
);

-- 1e. Swap history — audit log of all mid-season player swaps
create table if not exists swap_history (
  id               uuid    primary key default gen_random_uuid(),
  participant_id   uuid    references participants(id) on delete cascade,
  participant_name text,
  team_key         text,
  team_name        text,
  old_player       text,
  new_player       text,
  frozen_pts       integer default 0,
  swap_date        text,
  mode             text    not null default 'ipl',
  created_at       timestamptz default now()
);

-- 1f. Squads — IPL player roster (auto-seeded by app on first load)
create table if not exists squads (
  id          bigint  generated always as identity primary key,
  team_key    text    not null,
  team_name   text    not null,
  player_name text    not null,
  is_foreign  boolean default false,
  mode        text    not null default 'ipl',
  unique(team_key, player_name, mode)
);

-- 1g. Settings — global app config (single row)
create table if not exists settings (
  id         text primary key default 'global',
  mode       text not null default 'ipl',
  ipl_winner text
);


-- ============================================================
-- SECTION 2 — AUTH & ACCESS TABLES
-- ============================================================

-- 2a. Allowlist — approved Google emails + linked participant name
create table if not exists allowlist (
  email            text    primary key,
  participant_name text,
  is_admin         boolean default false,
  created_at       timestamptz default now()
);

-- 2b. Draft state — tracks live snake draft progress
create table if not exists draft_state (
  id        integer  primary key default 1,
  mode      text     not null default 'ipl',
  active    boolean  not null default false,
  "order"   text,                            -- JSON array of participant names e.g. '["Bandy","Raj"]'
  round     integer  not null default 1,
  pick_idx  integer  not null default 0,
  updated_at timestamptz default now()
);


-- ============================================================
-- SECTION 3 — INDEXES (for fast mode-based filtering)
-- ============================================================

create index if not exists participants_mode_idx   on participants(mode);
create index if not exists picks_mode_idx          on picks(mode);
create index if not exists season_scores_mode_idx  on season_scores(mode);
create index if not exists match_history_mode_idx  on match_history(mode);
create index if not exists swap_history_mode_idx   on swap_history(mode);
create index if not exists squads_mode_idx         on squads(mode);


-- ============================================================
-- SECTION 4 — DEFAULT ROWS
-- ============================================================

-- Insert global settings row (safe to re-run)
insert into settings (id) values ('global') on conflict do nothing;

-- Insert default draft_state row for IPL (safe to re-run)
insert into draft_state (id, mode) values (1, 'ipl') on conflict do nothing;


-- ============================================================
-- SECTION 5 — ROW LEVEL SECURITY (RLS)
-- ============================================================
-- Blocks all anonymous/public access.
-- Only Google-authenticated users in the allowlist can access data.
-- The anon key alone (visible in HTML source) does nothing without
-- a valid Google JWT from an allowlisted email.
--
-- Permission summary:
--   Action                        Members    Admin
--   ─────────────────────────────────────────────
--   View everything               ✓          ✓
--   Draft picks                   ✓          ✓
--   Import scorecards             ✓          ✓
--   Mid-season swaps              ✗          ✓
--   Add/remove participants       ✗          ✓
--   Reset / manage settings       ✗          ✓
--   Manage access list            ✗          ✓
-- ============================================================

-- Enable RLS on all tables
alter table allowlist       enable row level security;
alter table participants     enable row level security;
alter table picks            enable row level security;
alter table season_scores    enable row level security;
alter table match_history    enable row level security;
alter table swap_history     enable row level security;
alter table squads           enable row level security;
alter table settings         enable row level security;
alter table draft_state      enable row level security;

-- Helper: is calling user in the allowlist?
create or replace function is_league_member()
returns boolean language sql security definer stable as $$
  select exists (
    select 1 from allowlist
    where email = lower(auth.jwt() ->> 'email')
  );
$$;

-- Helper: is calling user an admin?
create or replace function is_league_admin()
returns boolean language sql security definer stable as $$
  select exists (
    select 1 from allowlist
    where email = lower(auth.jwt() ->> 'email')
      and is_admin = true
  );
$$;

-- Drop all old policies before recreating (safe to re-run)
do $$ declare
  r record;
begin
  for r in (
    select policyname, tablename from pg_policies
    where schemaname = 'public'
      and tablename in (
        'allowlist','participants','picks','season_scores',
        'match_history','swap_history','squads','settings','draft_state'
      )
  ) loop
    execute format('drop policy if exists %I on %I', r.policyname, r.tablename);
  end loop;
end $$;

-- ALLOWLIST (any authenticated Google user can read — needed for login check)
create policy "allowlist_read"   on allowlist for select to authenticated using (true);
create policy "allowlist_insert" on allowlist for insert to authenticated with check (is_league_admin());
create policy "allowlist_update" on allowlist for update to authenticated using (is_league_admin());
create policy "allowlist_delete" on allowlist for delete to authenticated using (is_league_admin());

-- PARTICIPANTS (members read + insert; admin update/delete)
create policy "participants_read"   on participants for select to authenticated using (is_league_member());
create policy "participants_insert" on participants for insert to authenticated with check (is_league_member());
create policy "participants_update" on participants for update to authenticated using (is_league_admin());
create policy "participants_delete" on participants for delete to authenticated using (is_league_admin());

-- PICKS (members read + insert for drafting; admin update/delete for swaps)
create policy "picks_read"   on picks for select to authenticated using (is_league_member());
create policy "picks_insert" on picks for insert to authenticated with check (is_league_member());
create policy "picks_update" on picks for update to authenticated using (is_league_admin());
create policy "picks_delete" on picks for delete to authenticated using (is_league_admin());

-- SEASON_SCORES (members read + insert for scorecard import; admin update/delete)
create policy "season_scores_read"   on season_scores for select to authenticated using (is_league_member());
create policy "season_scores_insert" on season_scores for insert to authenticated with check (is_league_member());
create policy "season_scores_update" on season_scores for update to authenticated using (is_league_admin());
create policy "season_scores_delete" on season_scores for delete to authenticated using (is_league_admin());

-- MATCH_HISTORY (members read + insert; admin update/delete)
create policy "match_history_read"   on match_history for select to authenticated using (is_league_member());
create policy "match_history_insert" on match_history for insert to authenticated with check (is_league_member());
create policy "match_history_update" on match_history for update to authenticated using (is_league_admin());
create policy "match_history_delete" on match_history for delete to authenticated using (is_league_admin());

-- SWAP_HISTORY (members read; admin insert/delete — only admin can do swaps)
create policy "swap_history_read"   on swap_history for select to authenticated using (is_league_member());
create policy "swap_history_insert" on swap_history for insert to authenticated with check (is_league_admin());
create policy "swap_history_delete" on swap_history for delete to authenticated using (is_league_admin());

-- SQUADS (members read; admin write)
create policy "squads_read"   on squads for select to authenticated using (is_league_member());
create policy "squads_insert" on squads for insert to authenticated with check (is_league_admin());
create policy "squads_delete" on squads for delete to authenticated using (is_league_admin());

-- SETTINGS (members read; admin update)
create policy "settings_read"   on settings for select to authenticated using (is_league_member());
create policy "settings_update" on settings for update to authenticated using (is_league_admin());

-- DRAFT_STATE (members read + update for turn advancing; admin insert/delete)
create policy "draft_state_read"   on draft_state for select to authenticated using (is_league_member());
create policy "draft_state_insert" on draft_state for insert to authenticated with check (is_league_admin());
create policy "draft_state_update" on draft_state for update to authenticated using (is_league_member());
create policy "draft_state_delete" on draft_state for delete to authenticated using (is_league_admin());


-- ============================================================
-- SECTION 6 — TROUBLESHOOTING QUERIES
-- ============================================================
-- Uncomment and run individual blocks when diagnosing issues.
-- NEVER run these on production data without reading first.
-- ============================================================

-- ── CHECK 1: Verify RLS is enabled on all tables ──────────────
-- select tablename, rowsecurity
-- from pg_tables
-- where schemaname = 'public'
-- order by tablename;
-- Expected: rowsecurity = true for all 9 tables

-- ── CHECK 2: List all active RLS policies ─────────────────────
-- select tablename, policyname, cmd, roles
-- from pg_policies
-- where schemaname = 'public'
-- order by tablename, policyname;

-- ── CHECK 3: View all allowlisted users ───────────────────────
-- select email, participant_name, is_admin, created_at
-- from allowlist
-- order by is_admin desc, participant_name;

-- ── CHECK 4: View all participants ────────────────────────────
-- select id, name, mode, team_pick, created_at
-- from participants
-- order by mode, created_at;

-- ── CHECK 5: View current draft state ─────────────────────────
-- select id, mode, active, "order", round, pick_idx, updated_at
-- from draft_state;

-- ── CHECK 6: Count picks per participant ──────────────────────
-- select p.name, count(pk.id) as picks, pk.mode
-- from participants p
-- left join picks pk on pk.participant_id = p.id and pk.is_active = true
-- group by p.name, pk.mode
-- order by pk.mode, p.name;

-- ── CHECK 7: View season leaderboard (raw scores) ─────────────
-- select player_name, runs, wickets, catches, runouts, stumpings, motm,
--        (runs + wickets*25 + catches*5 + runouts*5 + stumpings*5 + motm*5) as total_pts,
--        mode
-- from season_scores
-- where mode = 'ipl'
-- order by total_pts desc;

-- ── CHECK 8: View match history ───────────────────────────────
-- select id, title, match_date, result, t1_name, t2_name, mode, created_at
-- from match_history
-- order by created_at desc
-- limit 20;

-- ── CHECK 9: View swap history ────────────────────────────────
-- select participant_name, team_key, old_player, new_player,
--        frozen_pts, swap_date, mode
-- from swap_history
-- order by created_at desc;

-- ── FIX 1: Manually reset draft state (e.g. round got corrupted) ──
-- update draft_state
-- set active = false, round = 1, pick_idx = 0, "order" = null
-- where id = 1;

-- ── FIX 2: Remove a specific participant by name ──────────────
-- delete from participants where name = 'ParticipantName';
-- (cascades to picks and swap_history automatically)

-- ── FIX 3: Re-add yourself to allowlist if locked out ─────────
-- insert into allowlist (email, participant_name, is_admin)
-- values ('your@email.com', 'YourName', true)
-- on conflict (email) do update set is_admin = true;

-- ── FIX 4: Wipe all picks for one mode (re-draft) ─────────────
-- delete from picks where mode = 'ipl';
-- update participants set team_pick = null where mode = 'ipl';

-- ── FIX 5: Wipe all scores and match history for one mode ─────
-- delete from season_scores where mode = 'ipl';
-- delete from match_history where mode = 'ipl';
-- delete from swap_history where mode = 'ipl';

-- ── FIX 6: Temporarily disable RLS on a table for debugging ───
-- alter table picks disable row level security;
-- (remember to re-enable after: alter table picks enable row level security;)

-- ── FIX 7: Check what JWT email Supabase sees for current user ─
-- select auth.jwt() ->> 'email' as my_email;
-- (run this while authenticated to verify your email matches allowlist)

-- ── FIX 8: Sync draft state round to match actual picks made ──
-- update draft_state
-- set round = (
--   select coalesce(max(pick_count), 0) + 1
--   from (
--     select count(*) as pick_count
--     from picks
--     where is_active = true and mode = 'ipl'
--     group by participant_id
--   ) t
-- )
-- where mode = 'ipl';
