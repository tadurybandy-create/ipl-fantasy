# ⚡ IPL 2026 Fantasy League

A season-long fantasy cricket web app for 16 participants across all 10 IPL teams. Built as a single HTML file with Supabase for real-time data sync and Claude AI for automatic scorecard parsing.

---

## 🏏 How It Works

- Each of the **16 participants** drafts **1 player from each of the 10 IPL teams** (10 picks total)
- After every IPL match, the admin pastes a scorecard URL — **Claude AI automatically parses it** and updates all drafted players' season scores
- Points accumulate across the entire season on a live leaderboard

---

## 📊 Scoring

| Action | Points |
|--------|--------|
| 1 Run scored | 1 pt |
| 1 Wicket taken | 25 pts |
| 1 Catch taken | 5 pts |
| 1 Run-out | 5 pts — **both** fielders involved receive full 5 pts each |
| 1 Stumping | 5 pts |

---

## 📋 Draft Rules

- Max **2 fantasy participants** can draft the same cricket player
- Max **4 foreign (overseas) players** per fantasy team — enforced automatically
- Players are flagged 🇮🇳 Indian or 🌍 Overseas in the draft screen
- Mid-season swaps allowed — old player's points stay frozen, new player earns from next match

---

## 🗂️ File Structure

```
ipl-fantasy/
├── index.html                      # Entire app — HTML, CSS, JavaScript
└── netlify/
    └── functions/
        └── anthropic.js            # Serverless proxy for Anthropic API calls
```

> The Anthropic API key is **never stored in any file**. It lives only in Netlify's encrypted environment variables.

---

## 🚀 Deployment

### Prerequisites
- [Supabase](https://supabase.com) account (free)
- [Netlify](https://netlify.com) account (free)
- [Anthropic API](https://console.anthropic.com) key with credits

### Step 1 — Set up Supabase

1. Create a new Supabase project
2. Go to **SQL Editor** and run the contents of `supabase_setup.sql` (available separately)
3. This creates all required tables: `participants`, `picks`, `season_scores`, `match_history`, `swap_history`, `settings`
4. Copy your **Project URL** and **anon public key** from Settings → API

### Step 2 — Configure index.html

Open `index.html` and update the constants at the top of the `<script>` section:

```javascript
const SUPABASE_URL = 'https://your-project.supabase.co';
const SUPABASE_KEY = 'your-anon-public-key';
```

### Step 3 — Deploy to Netlify

1. Push this repository to GitHub
2. Go to [netlify.com](https://netlify.com) → **Add new site → Import from Git**
3. Connect your GitHub repo
4. Leave **build command** and **publish directory** blank
5. Click **Deploy**

### Step 4 — Add the Anthropic API key

1. In Netlify go to **Site Configuration → Environment Variables**
2. Add a variable: `ANTHROPIC_KEY` = your Anthropic API key
3. Go to **Deploys → Trigger deploy → Deploy site** to pick up the new variable

---

## 🔄 Rotating the Anthropic API Key

Since the key is stored only in Netlify environment variables, rotating it requires **no code changes**:

1. Go to [console.anthropic.com](https://console.anthropic.com) → API Keys → revoke old key → create new key
2. Go to Netlify → Site Configuration → Environment Variables → update `ANTHROPIC_KEY`
3. Trigger a redeploy

---

## 🛠️ Tech Stack

| Layer | Technology |
|-------|-----------|
| Frontend | Vanilla HTML/CSS/JavaScript (single file) |
| Database | Supabase (PostgreSQL + REST API) |
| Hosting | Netlify (static site + serverless functions) |
| AI | Anthropic Claude API (`claude-sonnet-4-20250514`) |

---

## ⚙️ Settings Tab

The app includes a Settings tab with two admin tools:

- **📋 Import Squads** — pushes all IPL squad data into Supabase for reference
- **🗑️ Reset Everything** — password-protected wipe of all league data (use before the real season starts)

---

## 🗄️ Database Schema

```sql
participants  — name, created_at
picks         — participant_id, team_key, player_name, is_active, swapped_at
season_scores — player_name, runs, wickets, catches, runouts, stumpings
match_history — title, match_date, result, t1_name, t2_name, updates (jsonb)
swap_history  — participant_name, team_key, old_player, new_player, frozen_pts
settings      — id (global), ipl_winner
```

---

## 📝 License

Private project — not for public distribution.
