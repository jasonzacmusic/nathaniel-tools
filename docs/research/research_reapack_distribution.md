# Distributing a Free REAPER Script Suite: SWS, ReaPack, the Script Economy, and Adoption Playbook

Research date: 2026-08-03. All facts verified against live pages on this date unless marked approximate.

---

## 1. SWS Extension — the reference model for free REAPER tooling

**What it is.** SWS/S&M is a compiled C++ plugin extension (not scripts) that adds hundreds of actions to REAPER. "SWS" = Standing Water Studios, founder Tim Payne's project studio; "S&M" ("Simple & Mighty") is Jeffos's merged extension. Started 2009, community-maintained ever since ([sws-extension.org](https://www.sws-extension.org/)).

**Packaging & install story.**
- Distributed as pre-built binaries per platform from the website: Windows x32/x64 .exe installers, macOS x32/x64/ARM64 disk images, Linux x32/x64/ARM32/ARM64 tar.xz.
- Latest stable: **v2.14.0 #7 (September 7, 2025)**, requires REAPER 5.982+.
- Install = run installer, or drop the plugin into REAPER's `UserPlugins` folder. It is NOT distributed through ReaPack — it predates ReaPack and keeps its own installer/release channel.
- The website is a single landing page that does a few things extremely well: platform-detected download buttons above the fold, a full feature list, a free 300+ page PDF manual ("REAPER Plus! The Power of SWS Extensions" by Geoffrey Francis, [PDF](https://sws-extension.org/download/REAPERPlusSWS171.pdf)), plain install steps including the macOS Gatekeeper "Allow Anyway" note, and a changelog.

**License & governance.** **MIT license**, source at [github.com/reaper-oss/sws](https://github.com/reaper-oss/sws) (567 stars, 105 forks). Today most contributions come from **cfillion** (Christian Fillion, also ReaPack's author) and **nofish**; Tim Payne manages releases and the website. Historic contributors: Jeffos, Breeder, Fingers, Xenakios, IXix, Wol, and others.

**Funding.** Explicitly non-commercial: "make sure we are not making money out of this project: it is only led by passion." A PayPal donation button feeds a **common wallet that covers website costs**; a few contributors (Wol, Breeder, Jeffos) list personal PayPal donation links. That's it — no Patreon, no paid tier.

**Why it became the de-facto standard.**
- First-mover (2009) filling real workflow gaps (snapshots, marker actions, cycle actions, ReaConsole, loudness analysis).
- Free + MIT + open source meant every tutorial author could assume it. Kenny Gioia, The REAPER Blog and virtually all "set up REAPER" guides tell users to install SWS on day one (e.g. [reapertips.com/post/how-to-install-sws](https://reapertips.com/post/how-to-install-sws)).
- Thousands of community scripts declare SWS as a dependency, making it self-reinforcing infrastructure.
- Stable maintainership handoff (founder → community devs) kept it alive 17 years.

**Lesson for Nathaniel Tools:** one clean landing page, per-platform one-click install, a real manual, and being assumed-installed by educators is the endgame. Donations fund hosting, not income.

---

## 2. ReaPack mechanics — 2026 state

### 2.1 Project status (verified August 2026)

- ReaPack client: **v1.2.6, released 2025-09-08**. Site download counter shows **1,120,892 recent downloads** ([reapack.com](https://reapack.com/)).
- The **GitHub repo cfillion/reapack was archived June 3, 2026**; canonical home is now **[codeberg.org/cfillion/reapack](https://codeberg.org/cfillion/reapack)** (issues there too). Release binaries download from Codeberg releases.
- **ReaPack v2 is in development at [codeberg.org/cfillion/reapack2](https://codeberg.org/cfillion/reapack2)** — worth watching, but v1 index format is what ships.
- The old GitHub wiki's user guide moved to **[reapack.com/user-guide](https://reapack.com/user-guide)**; the **Index Format spec lives on the Codeberg wiki** ([codeberg.org/cfillion/reapack/wiki/Index-Format](https://codeberg.org/cfillion/reapack/wiki/Index-Format)).
- The **reapack-index tool is still on GitHub and active** (not archived): [github.com/cfillion/reapack-index](https://github.com/cfillion/reapack-index), Ruby gem (`gem install reapack-index`, Ruby 2.4+, GPL-3.0). Its packaging documentation wiki is the authoritative header spec: [Packaging Documentation](https://github.com/cfillion/reapack-index/wiki/Packaging-Documentation).
- Support channels: [ReaPack user thread](https://forum.cockos.com/showthread.php?t=177978) and [development/packaging thread](https://forum.cockos.com/showthread.php?t=169127) on the Cockos forum.

### 2.2 How a repository works

A ReaPack repository is just **a public URL serving an `index.xml`** file plus downloadable files. The standard pattern is a GitHub repo whose import URL is:

```
https://github.com/<username>/<repo>/raw/master/index.xml
```

Users paste that into REAPER: Extensions > ReaPack > Import repositories.

**index.xml format** (v1 spec, per the [Codeberg Index Format wiki](https://codeberg.org/cfillion/reapack/wiki/Index-Format)):
- `<index version="1" name="...">` root; `name` must be filename-friendly.
- `<category name="Path/With/Slashes">` — the folder tree shown in the ReaPack browser.
- `<reapack name="file name" type="..." desc="Display Name">` — package. Types: `script`, `effect`, `extension`, `data`, `theme`, `langpack`, `webinterface`, `projectpl`, `tracktpl`, `midinotenames`, `autoitem` (v1.2+), `keymap` (v1.2.6+).
- `<version name="1.2.3" author="..." time="ISO8601">` containing optional `<changelog>` and one or more `<source>` elements.
- `<source file="..." platform="..." main="main|midi_editor|midi_inlineeditor|midi_eventlisteditor|mediaexplorer|crossfade_editor" hash="...">URL</source>`. Platforms: `all`, `darwin`, `darwin32/64`, `darwin-arm64`, `linux`, `linux32/64`, `linux-armv7l`, `linux-aarch64`, `windows`, `win32/64`, `windows-arm64ec`. `hash` = SHA-256 multihash (v1.2.2+).
- `<metadata>` with `<description>` (RTF) and `<link rel="website|donation|screenshot" href="...">` — donation links show as a Donate button in ReaPack's package/About window.
- Version names: segments of numbers and letters; must start with a digit; numeric segments ≤ 65535; **any letter makes it a pre-release** (e.g. `1.0beta2`), which ReaPack hides from stable-only users.

**You never write index.xml by hand** — `reapack-index` generates it from git history + file metadata headers.

### 2.3 The metadata header spec (current, per reapack-index wiki)

Every package file starts with a comment header. Two equivalent syntaxes: `@tag value` or `Tag Name: value`. Tag names case-insensitive; **no empty lines between tags**; multi-line values indented by ≥1 space/tab.

Package-wide tags:
- `@description` (aliases: `desc`, `Name`, `ReaScript Name`, `JSFX Name`) — display name. Don't put your author name or file extension here.
- `@author`
- `@about` — full documentation in **CommonMark markdown**, shown in ReaPack's package window.
- `@link` / `@links` (alias `website`) — labelled URLs, e.g. `@link Forum https://forum.cockos.com/...`.
- `@donation` / `@donate` — donation URL(s), same format as @link. **This is how free scripts monetize attention.**
- `@screenshot` / `@screenshots` — image URLs shown in ReaPack.
- `@noindex` — exclude a file from indexing (libraries/requires).
- `@metapackage` — file itself isn't installed, only its @provides list (default ON for themes/data/extensions, OFF for scripts/JSFX).

Version-specific tags:
- `@version` — **mandatory**; bumping it is what triggers a release when reapack-index scans the commit.
- `@changelog` — multi-line; previous versions' changelogs are preserved in the index.
- `@provides` — additional files bundled with the package. Supports globs, renames (`src.lua > Subdir/dest.lua`), platform/type prefixes in brackets, Action-List section control (`main`, `main=midi_editor,main`, `nomain`), and URL templates with `$path`, `$commit`, `$version`, `$package` — e.g. `@provides [windows] reaper_ext.dll https://mysite.com/dl/$version/$path`.

File-type detection is by extension: `.lua`, `.eel`, `.py` → script; `.jsfx` → effect; `.ReaperTheme`/theme zips → theme; `.ReaperLangPack`, `.RPP`/`.RTrackTemplate` (templates), `.ReaperKeyMap`, etc. **Packages must live inside subdirectories (categories); files at repo root are not indexed.**

Minimal working header for an Nathaniel Tools Lua script:

```lua
-- @description Nathaniel Tools Silence Splitter
-- @author Jason Zac (Nathaniel School of Music)
-- @version 1.0
-- @changelog Initial release
-- @about
--   # Nathaniel Tools Silence Splitter
--   Splits items at silence and names regions for lesson editing.
-- @link Forum thread https://forum.cockos.com/showthread.php?t=XXXXXX
-- @donation https://www.nathanielschool.com/support
-- @screenshot https://raw.githubusercontent.com/.../screenshot.png
```

### 2.4 The zero-effort publishing pipeline

**[cfillion/reapack-repository-template](https://github.com/cfillion/reapack-repository-template)** — a GitHub template repo where **GitHub Actions runs reapack-index automatically on every push**:
1. Click "Use this template" to create your repo.
2. Set your repository display name in `index.xml` (the `name` attribute).
3. Replace `README.md` — it becomes ReaPack's "About this repository" text.
4. Put scripts in category subfolders with metadata headers.
5. Commit with a bumped `@version` → the Action regenerates and commits `index.xml`.
6. Your import URL is `https://github.com/<user>/<repo>/raw/master/index.xml`.

### 2.5 Getting listed on reapack.com/repos

[reapack.com/repos](https://reapack.com/repos) is the semi-official directory ("This page lists known **free** third-party ReaPack repositories"). ~75 repositories listed, from ReaTeam (882 scripts) down to single-script repos. Listing process: the page's **"Edit this list" link opens a pull request against `config/repos.yml` in [github.com/cfillion/reapack.com](https://github.com/cfillion/reapack.com)** — you add your repo's name + index URL and cfillion merges. Only criterion in evidence: free packages, working index. There's also a machine-readable [repos.txt](https://reapack.com/repos.txt) users can bulk-import.

### 2.6 Submitting to ReaTeam (the big community collection)

- ReaTeam is a GitHub org of REAPER community devs (cfillion, MPL, and other admins). Repos: [ReaScripts](https://github.com/ReaTeam/ReaScripts) (882 scripts), [JSFX](https://github.com/ReaTeam/JSFX) (143), [Themes](https://github.com/ReaTeam/Themes), [LangPacks](https://github.com/ReaTeam/LangPacks), [Extensions](https://github.com/ReaTeam/Extensions) (12, incl. ReaImGui and js_ReaScriptAPI).
- **Why it matters: ReaTeam's five repos + MPL + X-Raym are ReaPack's DEFAULT repositories** — packages there appear in every ReaPack install's browser with zero import step ([REAPER Blog on ReaPack](https://reaper.blog/2016/06/how-to-use-the-new-reapack-extension-for-reaper/), [X-Raym on ReaPack](https://www.extremraym.com/en/reapack/)). ReaPack ships with 1,300+ packages visible out of the box.
- **Submission process:** the README says simply "Use https://reapack.com/upload/reascript to upload your scripts on this repository." The [Package editor](https://reapack.com/upload) is a web app: you log in with GitHub, it gives you a form (display name, author name, version, changelog, about text, external links, forum thread link, additional/hosted files, Action List placement, platform), validates the header, then **forks the ReaTeam repo and opens a pull request on your behalf** (branches named like `reapack.com_upload-<timestamp>`).
- **Review reality:** lightweight. Example [PR #202](https://github.com/ReaTeam/ReaScripts/pull/202) (nickvonkaenel's SUBPROJECT script, later the founder of nvk.tools): submitted July 7, 2019, merged ~5 days later with no recorded review comments; trusted contributors get org membership and self-merge. Feedback, when it happens, is about metadata headers and file naming, discussed in the [development thread](https://forum.cockos.com/showthread.php?t=169127).
- **Licensing:** no formal MIT/GPL gate is documented in the README or upload flow. Convention: ReaTeam-hosted content is free; many authors put a license line in @about; reapack-index itself is GPL-3.0 but that doesn't bind your scripts. If you want protection, state MIT/GPL in each header — nothing in the process forces one.
- Naming convention in ReaTeam: files are `AuthorName_Script description.lua` (e.g. `Lokasenna_Radial Menu.lua`) — an author prefix is effectively mandatory for a recognizable brand inside the Action List.

**Strategic takeaway:** the highest-reach path is (a) own repo from the template for the full Nathaniel Tools + (b) get listed at reapack.com/repos + (c) optionally push flagship general-purpose scripts into ReaTeam for default-visibility, keeping the suite's home repo as the canonical brand.

---

## 3. How the REAPER script/theme "businesses" actually work

### X-Raym (Raymond Radet) — extremraym.com — the free/paid two-tier master

- **Free:** 626 scripts + 20 JSFX, open source, in ReaPack's default repos ([github.com/X-Raym/REAPER-ReaScripts](https://github.com/X-Raym/REAPER-ReaScripts)). The free catalog IS the marketing funnel.
- **Paid:** "Premium ReaScripts" packs on his own WordPress shop ([extremraym.com/en/reascripts-premium/](https://www.extremraym.com/en/reascripts-premium/)), organized by vertical: Sample Editing, Gaming Audio, Virtual Instrument Creation, Musical Composition, Video Post-Production, Podcast, plus one-offs (Item Manager, DMX light control, Rythmoband ADR, ReaTab Hero).
- **Pricing (verified on the Item Manager product page):** dual honor-system tiers — **Non-Profit 25.00€ / Commercial 65.00€**, per seat, **lifetime license with free public updates**. He openly explains the economics: "most packs have less than 10 active users," so niche scripts must be priced above impulse level; "by purchasing you are supporting my free work."
- **Clever mechanics:**
  - Paid customers get a **private, license-keyed ReaPack repository URL** — paid scripts install and update inside REAPER exactly like free ones.
  - A public **demo ReaPack repo** (`https://www.extremraym.com/cloud/reascripts-premium/demo.php?f=index.xml`) installs stub versions prefixed `X-Raym_demo_` that print a "please purchase" console message — premium scripts are discoverable *inside the Action List itself*.
  - "**Contact me for sponsoring release**" — unreleased private/client scripts listed publicly with a sponsor-this button; clients fund development, everyone later gets the pack.
  - Site subscription (newsletter) + one long-running [Cockos forum thread for Premium packs](https://forum.cockos.com/showthread.php?t=221517) bumped with every release/discount; separate thread for free scripts.
  - Side businesses: custom ReaScript development, REAPER consulting, WordPress plugins.

### ReaperTips (Alejandro Hernandez) — reapertips.com — content brand + pay-what-you-want products

- Free: 120+ written tips, 70+ YouTube videos, 370+ Instagram posts, Discord; publishing since 2016; deliberately **ad-free**, funded by donations + product sales ([reapertips.com](https://reapertips.com/)).
- Paid/PWYW on **Payhip**: the **Reapertips Theme is pay-what-you-want from $0 with 487 reviews** ([payhip.com/b/z7Tur](https://payhip.com/b/z7Tur)); also Essential Icons, 12 Color Palettes + Toolbars, Modern Metal Songwriting Template, "The Perfect Setup" eBook.
- Marketing engine: SEO-friendly listicles ("[Best REAPER 7 Themes (2026)](https://www.reapertips.com/post/best-reaper-7-themes-2026)", "[Best Utility Scripts](https://www.reapertips.com/post/advanced-fx-browsing-in-reaper)") that ALSO make him the discovery hub other developers depend on. Newsletter with monthly recap.
- **Fact-check on the brief:** the **Imperial theme is not ReaperTips' — it's by White Tie** (houseofwhitetie.com), the designer of REAPER 6's default theme; Imperial is a free retro-console theme for dual monitors ([thegearforum.com discussion](https://thegearforum.com/threads/cool-cockos-reaper-theme-white-tie-imperial.5734/)). ReaperTips merely features it in roundups.

### The REAPER Blog (Jon Tidey) — reaper.blog — content + Patreon + courses

- 700+ free video tutorials since 2013; YouTube **~75.9K subscribers** ([SPEAKRJ](https://www.speakrj.com/audit/report/UC39aOXMqg48qpzEz1l_-7tQ/youtube/live)); site with newsletter, Facebook community group.
- Revenue stack ([about page](https://reaper.blog/about/), [Patreon](https://www.patreon.com/cw/thereaperblog)): **Patreon from $2/month** ("$2, $5 or any amount") for equipment/projects; **paid courses** (e.g. [REAPERBLOG Video Tools](https://reaper.blog/course/reaperblog-video-tools/) — video processor presets + training); **1-on-1 REAPER lessons** ([reaper.blog/reaper-lessons](https://reaper.blog/reaper-lessons/)); tip jar; **affiliate links** (Plugin Boutique/Loopmasters, Amazon).
- Important for adoption: his script-roundup videos/articles (e.g. "[9 great JSFX Instruments from Saike and Tilr](https://reaper.blog/2024/11/9-jsfx-instruments/)") are one of the main ways new tools reach non-forum users.

### Kenny Gioia / REAPER Mania — the Cockos-endorsed free channel

- **189K subscribers, 1,239 videos, ~29.9M views** ([Social Blade](https://socialblade.com/youtube/handle/reapermania)) — the biggest REAPER channel.
- Works directly with Cockos: his tutorials are the **official videos on [reaper.fm/videos.php](https://www.reaper.fm/videos.php)** (the financial arrangement isn't public). 99% native-REAPER focus.
- Personal monetization: sells structured courses on **Groove3 at roughly $25–45** ("REAPER Explained", "Mixing in REAPER", "First Song with REAPER" — [groove3.com/browse/author/kenny-gioia](https://www.groove3.com/browse/author/kenny-gioia)).

### nvk (Nick von Kaenel) — nvk.tools — the premium end of the market

- Game-audio/sound-design script products: nvk_WORKFLOW 2, nvk_CREATE, nvk_VARIATIONS, nvk_AUTODOPPLER 2, nvk_LOOPMAKER 2, nvk_SEARCH, nvk_THEME ([nvk.tools](https://nvk.tools/)).
- Prices via Gumroad store: **nvk_WORKFLOW $159**, **nvk_CREATE $149**, **nvk_SEARCH free/pay-what-you-want**; Sound Design / Game Audio / Everything bundles; free trials; license-key + private ReaPack-style delivery with docs at [nvk.tools/docs/install](https://nvk.tools/docs/install/); Discord community; testimonials from Valve/Blizzard sound designers.
- Origin story worth noting: his first public script was a free ReaTeam PR in 2019 ([PR #202](https://github.com/ReaTeam/ReaScripts/pull/202)) — free community work became a five-figure-price-point product line for a professional niche.

### The free-with-donations tier (reputation economy)

- **MPL (Michael Pilyavskiy):** 406 scripts, ReaPack default repo, donation links — one of the two "default repo" script authors alongside X-Raym.
- **Saike (Joep Vanlier):** 47 free JSFX incl. the Yutani synth ([github.com/JoepVanlier/JSFX](https://github.com/JoepVanlier/JSFX)), own ReaPack repo, 36+ page [forum workshop thread](https://forums.cockos.com/showthread.php?p=2774047), donations/sponsors.
- **Sexan (Goran Kovač):** free/open-source, PayPal donations via forum; **Paranormal FX Router** (visual FX-container router) launched alongside REAPER 7's containers feature — [33+ page thread](https://forum.cockos.com/showthread.php?t=283054), plus community "how do you use it" threads spawned by users — the textbook fast launch.
- **BirdBird:** free scripts (Global Sampler — [thread t=266975](https://forum.cockos.com/showthread.php?t=266975)) at [birdsthings.com](https://birdsthings.com); sells a standalone (non-REAPER) version of Global Sampler — free in-REAPER, paid outside.
- **LKC Tools (Nikola Krošnjar):** 25 free scripts + 1 extension via own repo on the reapack.com list.
- **TJF (Tim Farrell / sonictim):** 106 free scripts, own repo.
- **Lokasenna:** wrote the most-used GUI library (Lokasenna_GUI) and Radial Menu; **PayPal donations only — "doesn't have the confidence to charge"**; he eventually drifted away and the library survives via forks (TeamAudio/lokasenna-gui). Cautionary tale: pure-donation infrastructure work burns out; libraries need succession plans.
- **Ultraschall** ([github.com/Ultraschall](https://github.com/Ultraschall/ultraschall-installer)): the podcast-vertical mega-suite — theme + actions + soundboard + SWS bundled in **its own branded installer**, CC0-licensed, with its own website, docs and community. Proof that a vertical suite can build its own identity on top of REAPER rather than living only inside ReaPack.

**Pattern across all of them:** free, open, ReaPack-installed scripts build the audience; money (when wanted) comes from a niche vertical (game audio, ADR, podcasting), from teaching (courses/Patreon), or from honor-system tiers — never from paywalling the general-purpose utilities.

---

## 4. What gets a new script suite adopted

### Where REAPER users discover tools
1. **The ReaPack browser itself** — 1,300+ packages visible by default; being in a default repo (ReaTeam/MPL/X-Raym) = zero-friction discovery; being on [reapack.com/repos](https://reapack.com/repos) = one-click import for power users.
2. **Cockos forum** ([forum.cockos.com](https://forum.cockos.com)) — the center of gravity. Each serious tool has ONE long-running thread in the ReaScript/JSFX sections that serves as changelog, support desk, and social proof (Saike 36+ pages, Paranormal FX 33+ pages, X-Raym Premium thread running since 2019).
3. **YouTube/content amplifiers** — REAPER Mania (189K), The REAPER Blog (76K), ReaperTips; a single roundup video/article moves more installs than months of forum presence.
4. **Curated directories** — [Admiral Bumblebee's Reaper Script Showcase](https://www.admiralbumblebee.com/reaperscripts), [ReaLinks](https://www.realinks.net/), ReaperTips listicles, the KVR "essential ReaScripts" threads.
5. **r/Reaper** — active subreddit (six-figure membership; exact count not verifiable this session — Reddit blocks scraping), best used for GIF-led show-and-tell posts linking back to the forum thread.
6. Legacy: [stash.reaper.fm](https://stash.reaper.fm) still exists but ReaPack has superseded it.

### Anatomy of a successful launch thread (observed patterns)
- **Title convention:** "Script: <Name> — <what it does>" or "V7 Script: ..." when riding a new REAPER version's feature.
- **First post contains everything:** animated GIFs/screenshots of the tool in motion, the ReaPack import URL in a code block, dependency list (SWS / js_ReaScriptAPI / ReaImGui with install instructions), a donation link, and a feature list. The first post is edited forever as the canonical README.
- **Release cadence bumps the thread:** every `@version` bump gets a changelog reply — the thread stays on page 1 of the subforum for months.
- **Author responsiveness:** same-day replies to bug reports in the first weeks decide whether the thread compounds or dies.
- **Timing with REAPER releases:** Paranormal FX Router exploded because it shipped a UI for REAPER 7's brand-new FX containers within days. A suite that makes a new REAPER feature usable inherits that feature's hype cycle.
- **Vertical identity beats "misc utilities":** Ultraschall (podcasting), nvk (game audio), ReaClassical (classical editing), X-Raym packs (ADR/dubbing) all got adopted as *the* toolkit for a workflow, not as loose scripts.
- **Consistent author prefix** (`X-Raym_`, `Sexan_`, `nvk_`) so users can filter the Action List and attribute the brand — an "NPH_" prefix would do the same, with `@about` headers crediting Nathaniel School of Music and `@donation`/`@link` pointing at nathanielschool.com.
- **Dependencies note:** if the suite uses ReaImGui, scripts must runtime-check for it and point users to the default ReaTeam Extensions repo (standard practice; ReaPack has no automatic dependency resolution).

### Fast-adoption case studies
| Suite | Hook | Channel that made it |
|---|---|---|
| Paranormal FX Router (Sexan) | GUI for REAPER 7 containers, launched at v7 release | Forum thread + ReaperTips article |
| Global Sampler (BirdBird) | Novel capability ("sample anything you hear") with GIF demos | Forum + YouTube coverage |
| nvk_WORKFLOW | Complete game-audio vertical workflow | GDC-adjacent word of mouth, Discord, A Sound Effect features |
| Saike JSFX | Pro-grade free synths/filters, constant releases in one thread | Forum workshop thread + REAPER Blog roundups |
| Ultraschall | Whole-vertical branded distribution with installer | Own website/community outside the REAPER bubble |

---

## Sources (primary)
- https://www.sws-extension.org/ · https://github.com/reaper-oss/sws
- https://reapack.com/ · /user-guide · /repos · /upload · https://reapack.com/repos.txt
- https://codeberg.org/cfillion/reapack · /wiki/Index-Format · https://codeberg.org/cfillion/reapack2
- https://github.com/cfillion/reapack-index (+ wiki/Packaging-Documentation) · https://github.com/cfillion/reapack-repository-template · https://github.com/cfillion/reapack.com
- https://github.com/ReaTeam/ReaScripts (+ PR #202) · https://forum.cockos.com/showthread.php?t=169127
- https://www.extremraym.com/en/reascripts-premium/ · /en/my-reaper-scripts/ · /en/download/reascript-item-manager/ · /en/reapack/
- https://reapertips.com/ · https://payhip.com/b/z7Tur · https://www.reapertips.com/post/best-reaper-7-themes-2026
- https://reaper.blog/about/ · https://www.patreon.com/cw/thereaperblog · https://reaper.blog/course/reaperblog-video-tools/
- https://socialblade.com/youtube/handle/reapermania · https://www.groove3.com/browse/author/kenny-gioia · https://www.reaper.fm/videos.php
- https://nvk.tools/ · https://nvktools.gumroad.com/l/nvk_WORKFLOW
- https://github.com/JoepVanlier/JSFX · https://forum.cockos.com/showthread.php?t=283054 · https://forum.cockos.com/showthread.php?t=266975
- https://github.com/Ultraschall/ultraschall-installer · https://www.admiralbumblebee.com/reaperscripts · https://www.realinks.net/
