# NPH REAPER Suite — venture plan (the SWS model, done our way)

**Written 3 Aug 2026.** Grounded in two fresh research passes (full reports in
`docs/research/`): how SWS/ReaPack/ReaTeam distribution actually works in 2026, and
what the live-rig market looks like. This plan supersedes nothing in
`NPH_BUSINESS_BRIEF.md` — it operationalises it.

---

## 1. The model in one paragraph

We do **not** sell the scripts. We give the suite away the way SWS did — free, MIT,
one-click install via ReaPack — because "assumed installed" is the prize: SWS became
the standard because every educator assumed you had it. The suite buys reputation and
distribution; the **course** (learnmusic.nathanielschool.com) and later **StageRig
Pro** carry the margin. That is exactly the proven X-Raym shape (626 free scripts
feeding a paid shop) and the REAPER Blog shape (free content, paid depth) — already
working in this exact market.

## 2. Identity

- **Name on every surface:** NPH REAPER Suite. Script prefix stays `NPH_` — a
  consistent author prefix is how suites get recognised in the Action List.
- **The vertical:** every successful fast-growth suite owned a vertical (Ultraschall =
  podcasts, nvk = game audio). Ours is **the working keyboardist / producer-educator**:
  session speed + live keys. Nobody owns that vertical in REAPER today.
- **The moat (from the business brief, still true):** a decade of released records and
  real gigs. Any page or video that could have been made by someone who never shipped
  a record is off-brand.

## 3. Distribution mechanics (the technical checklist)

1. **Repo goes public** as the free core. License MIT. (Repo exists:
   `jasonzacmusic/nph-reaper-suite`, currently private.)
2. **ReaPack packaging** via cfillion's `reapack-repository-template` — a GitHub
   Action runs `reapack-index` on every push and rebuilds `index.xml`. Headers
   (`@description @author @version @changelog @about @provides @link @donation`) are
   already on every script. Spec authority: **codeberg.org/cfillion/reapack** (the
   GitHub wiki is archived).
3. **Get listed at reapack.com/repos** — one PR editing `config/repos.yml` in
   `cfillion/reapack.com`. Only criterion: packages are free. Ours are.
4. **Submit 2–3 flagship scripts to ReaTeam** via the reapack.com/upload web tool
   (auto-forks, opens the PR, review takes days). ReaTeam is a **default repository**
   in every ReaPack install — this is the single biggest reach lever available and it
   costs one afternoon.
5. `@donation` points at daw.nathanielschool.com/donate — quiet, SWS-style ("keeps the
   free core maintained").

## 4. Launch mechanics (what actually moves installs)

- **One canonical Cockos forum thread** for the suite: GIFs of each app in a real
  session, the ReaPack URL, a changelog post per release, fast replies. Suites live or
  die by this thread.
- **Coverage:** ReaperTips and The REAPER Blog roundups move more installs than
  anything we can buy. When the free core ships, that outreach is a named task, not a
  hope.
- **YouTube per the business brief** — the six-video slate stands. Videos 2 and 3
  ("this is broken and here is why": the custom-action audit, the tempo-marker
  forensics) need no finished software and start now. Video 1 (the session-prep
  ritual) lands the week the free core ships. The StageRig video is played **last and
  once**, after real gigs.
- Every video description carries the ReaPack URL. One destination:
  daw.nathanielschool.com.

## 5. Free / paid line

| Tier | What | Price |
|---|---|---|
| Free (ReaPack + ReaTeam) | 12 speed-layer scripts, Palette & Look, Folders & Flow, Sections & Time, Track Settings Transfer, Stem Print, MIDI Batch Export | ₹0 forever — this is the marketing |
| Course | "How a working producer actually runs a session", modules 1–4 first | $149–299 band (anchor, Jason's call) |
| StageRig Pro | the live rig, once it has survived real gigs | $79–129 anchor; the umbrella is Gig Performer $169 / Camelot $149 / Cantabile $199 — and MainStage at $29.99 is the floor that forces "better", not "cheaper" |
| Donations | daw page | quiet, SWS-style |

Precedent that the premium ceiling is real: **nvk.tools sells vertical REAPER scripts
at $149–159** — and nvk started as a free ReaTeam submission in 2019.

## 6. The StageRig market (why the flagship is worth it)

- MainStage is macOS-only, AU-only, $29.99, visibly neglected ("Has MainStage been
  abandoned?" threads; update-breaks-concert stories). Its biggest user base is
  worship keyboardists fed by patch ecosystems (Sunday Keys — 450+ patches — now
  hedging into Ableton).
- REAPER's existing answers are unproductized: SWS **LiveConfigs** docs frozen since
  **2012** (and half-broken on macOS), cfillion's Song Switcher is the only living
  script, the biggest community live-rig attempt stalled in 2019 on switch dropouts.
- **Playtime 2** (€64, Helgoboss) is the only real clip launcher and has essentially
  no gigging track record; cover bands still pay **$9.99–59.99/month** for Playback by
  MultiTracks.
- The gap in one line: **MainStage-grade patch switching + Ableton-grade clip trust,
  packaged on REAPER, from someone who actually gigs.** Nobody occupies it.
- Where these players live: Keyboard Corner, the MainStage Facebook groups,
  r/mainstage, worship-keys YouTube. The launch video is aimed there.

## 7. Sequencing (nothing runs in parallel that doesn't have to)

1. **Now:** YouTube videos 2 & 3 (no software needed). Engineering finishes Sections &
   Time + the drag-paint retrofit.
2. **Free core ships:** ReaPack repo live → reapack.com/repos PR → ReaTeam submission
   same week → daw.nathanielschool.com home + app pages → forum thread → video 1.
3. **Modules 1–4 verified working:** record and sell the course. Not before.
4. **StageRig survives real gigs:** the live video + capstone module + Pro pricing.
   The claim "MainStage replacement" is earned on stage, not in a demo.

## 8. What we never do

No fake scarcity, no countdown timers, no "10x your workflow" thumbnails, no selling
the free tools hard, no recording a course module for an app that does not exist and
work, and no public claim StageRig replaces MainStage until a working keyboardist has
played paid shows on it and stopped carrying a backup rig.
